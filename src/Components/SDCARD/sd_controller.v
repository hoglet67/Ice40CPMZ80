// SD card interface
// Reads and writes a single block of data as a data stream
// Adapted from design by Steven J. Merrifield, June 2008
// Read states are derived from the Apple II emulator by Stephen Edwards
// This version of the code contains modifications copyright by Grant Searle 2013
// You are free to use this file in your own projects but must never charge for it nor use it without
// acknowledgement.
// Please ask permission from Grant Searle before republishing elsewhere.
// If you use this file or any part of it, please add an acknowledgement to myself and
// a link back to my main web site http://searle.hostei.com/grant/
// and to the "multicomp" page at http://searle.hostei.com/grant/Multicomp/index.html
//
// Please check on the above web pages to see if there are any updates before using this file.
// If for some reason the page is no longer available, please search for "Grant Searle"
// on the internet to see if I have moved to another web hosting service.
//
// Grant Searle
// eMail address available on my main web page link above.
// Minor changes by foofoobedoo@gmail.com
// Additional functionality to provide SDHC support by RHKoolaap.
//
// This design uses the SPI interface and supports "standard capacity" (SDSC) and
// "high capacity" (SDHC) cards.
// Address Register
//    0    SDDATA        read/write data
//    1    SDSTATUS      read
//    1    SDCONTROL     write
//    2    SDLBA0        write-only
//    3    SDLBA1        write-only
//    4    SDLBA2        write-only (only bits 6:0 are valid)
//
// For both SDSC and SDHC (high capacity) cards, the block size is 512bytes (9-bit value) and the
// SDLBA registers select the block number. SDLBA2 is most significant, SDLBA0 is least significant.
//
// For SDSC, the read/write address parameter is a 512-byte aligned byte address. ie, it has 9 low
// address bits explicitly set to 0. 23 of the 24 programmable address bits select the 512-byte block.
// This gives an address capacity of 2^23 * 512 = 4GB .. BUT maximum SDSC capacity is 2GByte.
//
// The SDLBA registers are used like this:
//
// 31 30 29 28.27 26 25 24.23 22 21 20.19 18 17 16.15 14 13 12.11 10 09 08.07 06 05 04.03 02 01 00
//+------- SDLBA2 -----+------- SDLBA1 --------+------- SDLBA0 --------+ 0  0  0  0  0  0  0  0  0
//
// For SDHC cards, the read/write address parameter is the ordinal number of 512-byte block ie, the
// 9 low address bits are implicity 0. The 24 programmable address bits select the 512-byte block.
// This gives an address capacity of 2^24 * 512 = 8GByte. SDHC can be upto 32GByte but this design
// can only access the low 8GByte (could add SDLBA3 to get the extra address lines if required).
//
// The SDLBA registers are used like this:
//
// 31 30 29 28.27 26 25 24.23 22 21 20.19 18 17 16.15 14 13 12.11 10 09 08.07 06 05 04.03 02 01 00
//  0  0  0  0  0  0  0  0+---------- SDLBA2 -----+------- SDLBA1 --------+------- SDLBA0 --------+
//
// The end result of all this is that the addressing looks the same for SDSC and SDHC cards.
//
// SDSTATUS (RO)
//    b7     Write Data Byte can be accepted
//    b6     Read Data Byte available
//    b5     Block Busy
//    b4     Init Busy
//    b3     Unused. Read 0
//    b2     Unused. Read 0
//    b1     Unused. Read 0
//    b0     Unused. Read 0
//
// SDCONTROL (WO)
//    b7:0   0x00 Read block
//           0x01 Write block
//
//
// To read a 512-byte block from the SDCARD:
// Wait until SDSTATUS=0x80 (ensures previous cmd has completed)
// Write SDLBA0, SDLBA1 SDLBA2 to select block index to read from
// Write 0 to SDCONTROL to issue read command
// Loop 512 times:
//     Wait until SDSTATUS=0xE0 (read byte ready, block busy)
//     Read byte from SDDATA
//
// To write a 512-byte block to the SDCARD:
// Wait until SDSTATUS=0x80 (ensures previous cmd has completed)
// Write SDLBA0, SDLBA1 SDLBA2 to select block index to write to
// Write 1 to SDCONTROL to issue write command
// Loop 512 times:
//     Wait until SDSTATUS=0xA0 (block busy)
//     Write byte to SDDATA
//
// At HW level each data transfer is 515 bytes: a start byte, 512 data bytes,
// 2 CRC bytes. CRC need not be valid in SPI mode, *except* for CMD0.
//
// SDCARD specification can be downloaded from
// https://www.sdcard.org/downloads/pls/
// All you need is the "Part 1 Physical Layer Simplified Specification"
// no timescale needed

module sd_controller
  (
   output reg   sdCS,
   output       sdMOSI,
   input        sdMISO,
   output       sdSCLK,
   input        n_reset,
   input        n_rd,
   input        n_wr,
   input [7:0]  dataIn,
   output [7:0] dataOut,
   input [2:0]  regAddr,
   input        clk,
   output reg   driveLED
   );
   
   parameter [31:0] CLKEDGE_DIVIDER=50;
   // 50MHz / 50 gives edges at 1MHz ie output
   // sdSCLK of 500kHz.
   
   parameter [4:0]
     rst = 0,
     init = 1,
     cmd0 = 2,
     cmd8 = 3,
     cmd55 = 4,
     acmd41 = 5,
     poll_cmd = 6,
     cmd58 = 7,
     cardsel = 8,
     idle = 9,
     read_block_cmd = 10,
     read_block_wait = 11,
     read_block_data = 12,
     send_cmd = 13,
     send_regreq = 14,
     receive_ocr_wait = 15,
     receive_byte_wait = 16,
     receive_byte = 17,
     write_block_cmd = 18,
     write_block_init = 19,
     write_block_data = 20,
     write_block_byte = 21,
     write_block_wait = 22;
   // one start byte, plus 512 bytes of data, plus two ff end bytes (crc)
   parameter write_data_size = 515;
   reg [4:0]    state; reg [4:0] return_state;
   reg          sclk_sig = 1'b 0;
   reg [55:0]   cmd_out;  // at different times holds 8-bit data, 8-bit R1 response or 40-bit R7 response
   reg [39:0]   recv_data;
   reg [5:0]    clkCount;
   wire         clkEn;
   wire [7:0]   status;
   reg          block_read = 1'b 0;
   reg          block_write = 1'b 0;
   reg          block_start_ack = 1'b 0;
   reg          cmd_mode = 1'b 1;
   reg          response_mode = 1'b 1;
   reg [7:0]    data_sig = 8'h 00;
   reg [7:0]    din_latched = 8'h 00;
   reg [7:0]    dout = 8'h 00;
   reg          sdhc = 1'b 0;
   reg          sd_read_flag = 1'b 0;
   reg          host_read_flag = 1'b 0;
   reg          sd_write_flag = 1'b 0;
   reg          host_write_flag = 1'b 0;
   reg          init_busy = 1'b 1;
   reg          block_busy = 1'b 0;
   reg [31:0]   address = 32'h 00000000;
   reg [31:0]   led_on_count;
   
   always @(posedge clk) begin
      if(clkCount < ((CLKEDGE_DIVIDER - 1))) begin
         clkCount <= clkCount + 1;
      end
      else begin
         clkCount <= {6{1'b0}};
      end
   end
   
   assign clkEn = clkCount == 0 ? 1'b 1 : 1'b 0;
   always @(posedge n_wr) begin
      // sdsc address 0..8 (first 9 bits) always zero because each sector is 512 bytes
      if(sdhc == 1'b 0) begin
         // SDSC card
         if(regAddr == 3'b 010) begin
            address[16:9] <= dataIn;
         end
         else if(regAddr == 3'b 011) begin
            address[24:17] <= dataIn;
         end
         else if(regAddr == 3'b 100) begin
            address[31:25] <= dataIn[6:0];
         end
      end
      else begin
         // SDHC card
         // SDHC address is the 512 bytes block address. starts at bit 0
         if(regAddr == 3'b 010) begin
            address[7:0] <= dataIn;
            // 128 k
         end
         else if(regAddr == 3'b 011) begin
            address[15:8] <= dataIn;
            // 32 M
         end
         else if(regAddr == 3'b 100) begin
            address[23:16] <= dataIn;
            // addresses upto 8 G
         end
      end
   end
   
   // output data is MUXed externally based on CS so only need to
   // drive 0 by default if dataOut is being ORed externally
   assign dataOut = regAddr == 3'b 000 ? dout : regAddr == 3'b 001 ? status : 8'h 00;
   always @(posedge n_wr) begin
      if((regAddr == 3'b 000) && (sd_write_flag == host_write_flag)) begin
         din_latched <= dataIn;
         host_write_flag <=  ~host_write_flag;
      end
   end
   
   always @(posedge n_rd) begin
      if((regAddr == 3'b 000) && (sd_read_flag != host_read_flag)) begin
         host_read_flag <=  ~host_read_flag;
      end
   end

   wire reset_block = init_busy | block_start_ack;   
   always @(posedge n_wr or posedge reset_block) begin
      if(reset_block == 1'b 1) begin
         block_read <= 1'b 0;
         block_write <= 1'b 0;
      end else begin
         if(regAddr == 3'b 001 && dataIn == 8'b 00000000) begin
            block_read <= 1'b 1;
         end
         if(regAddr == 3'b 001 && dataIn == 8'b 00000001) begin
            block_write <= 1'b 1;
         end
      end
   end
   
   always @(posedge clk or negedge n_reset) begin : P1
      reg [31:0] byte_counter;
      reg [31:0] bit_counter;
      
      if((n_reset == 1'b 0)) begin
         state <= rst;
         sclk_sig <= 1'b 0;
         sdCS <= 1'b 1;
      end else if (clkEn == 1'b1) begin
         case(state)
           rst : begin
              sd_read_flag <= host_read_flag;
              sd_write_flag <= host_write_flag;
              sclk_sig <= 1'b 0;
              cmd_out <= {56{1'b1}};
              byte_counter = 0;
              cmd_mode <= 1'b 1;
              // 0=data, 1=command
              response_mode <= 1'b 1;
              // 0=data, 1=command
              bit_counter = 160;
              sdCS <= 1'b 1;
              state <= init;
              init_busy <= 1'b 1;
              block_start_ack <= 1'b 0;
           end
           init : begin
              // cs=1, send 80 clocks, cs=0
              if((bit_counter == 0)) begin
                 sdCS <= 1'b 0;
                 state <= cmd0;
              end
              else begin
                 bit_counter = bit_counter - 1;
                 sclk_sig <=  ~sclk_sig;
              end
           end
           cmd0 : begin
              cmd_out <= 56'h ff400000000095;
              // GO_IDLE_STATE here, Select SPI
              bit_counter = 55;
              return_state <= cmd8;
              state <= send_cmd;
           end
           cmd8 : begin
              cmd_out <= 56'h ff48000001aa87;
              // SEND_IF_COND
              bit_counter = 55;
              return_state <= cmd55;
              state <= send_regreq;
              // cmd55 is the "prefix" command for ACMDs
           end
           cmd55 : begin
              cmd_out <= 56'h ff770000000001;
              // APP_CMD
              bit_counter = 55;
              return_state <= acmd41;
              state <= send_cmd;
           end
           acmd41 : begin
              cmd_out <= 56'h ff694000000077;
              // SD_SEND_OP_COND
              bit_counter = 55;
              return_state <= poll_cmd;
              state <= send_cmd;
           end
           poll_cmd : begin
              if((recv_data[0] == 1'b 0)) begin
                 state <= cmd58;
              end
              else begin
                 // still busy; go round and do it again
                 state <= cmd55;
              end
           end
           cmd58 : begin
              cmd_out <= 56'h ff7a00000000fd;
              // READ_OCR
              bit_counter = 55;
              return_state <= cardsel;
              state <= send_regreq;
           end
           cardsel : begin
              if((recv_data[31] == 1'b 0)) begin
                 // power up not completed
                 state <= cmd58;
              end
              else begin
                 sdhc <= recv_data[30];
                 // CCS bit
                 state <= idle;
              end
           end
           idle : begin
              sd_read_flag <= host_read_flag;
              sd_write_flag <= host_write_flag;
              sclk_sig <= 1'b 0;
              cmd_out <= {56{1'b1}};
              data_sig <= {8{1'b1}};
              byte_counter = 0;
              cmd_mode <= 1'b 1;
              // 0=data, 1=command
              response_mode <= 1'b 1;
              // 0=data, 1=command
              block_busy <= 1'b 0;
              init_busy <= 1'b 0;
              dout <= {8{1'b0}};
              if((block_read == 1'b 1)) begin
                 state <= read_block_cmd;
                 block_start_ack <= 1'b 1;
              end
              else if((block_write == 1'b 1)) begin
                 state <= write_block_cmd;
                 block_start_ack <= 1'b 1;
              end
              else begin
                 state <= idle;
              end
           end
           read_block_cmd : begin
              block_busy <= 1'b 1;
              block_start_ack <= 1'b 0;
              cmd_out <= {8'h ff,8'h 51,address,8'h ff};
              // CMD17 read single block
              bit_counter = 55;
              return_state <= read_block_wait;
              state <= send_cmd;
              // wait until data token read (= 11111110)
           end
           read_block_wait : begin
              if((sclk_sig == 1'b 0 && sdMISO == 1'b 0)) begin
                 state <= receive_byte;
                 byte_counter = 513;
                 // data plus crc
                 bit_counter = 8;
                 // ???????????????????????????????
                 return_state <= read_block_data;
              end
              sclk_sig <=  ~sclk_sig;
           end
           read_block_data : begin
              if((byte_counter == 1)) begin
                 // crc byte 1 - ignore
                 byte_counter = byte_counter - 1;
                 return_state <= read_block_data;
                 bit_counter = 7;
                 state <= receive_byte;
              end
              else if((byte_counter == 0)) begin
                 // crc byte 2 - ignore
                 bit_counter = 7;
                 return_state <= idle;
                 state <= receive_byte;
              end
              else if((sd_read_flag != host_read_flag)) begin
                 state <= read_block_data;
                 // stay here until previous byte read
              end
              else begin
                 byte_counter = byte_counter - 1;
                 return_state <= read_block_data;
                 bit_counter = 7;
                 state <= receive_byte;
              end
           end
           send_cmd : begin
              if((sclk_sig == 1'b 1)) begin
                 // sending command
                 if((bit_counter == 0)) begin
                    // command sent
                    state <= receive_byte_wait;
                 end
                 else begin
                    bit_counter = bit_counter - 1;
                    cmd_out <= {cmd_out[54:0],1'b 1};
                 end
              end
              sclk_sig <=  ~sclk_sig;
           end
           send_regreq : begin
              if((sclk_sig == 1'b 1)) begin
                 // sending command
                 if((bit_counter == 0)) begin
                    // command sent
                    state <= receive_ocr_wait;
                 end
                 else begin
                    bit_counter = bit_counter - 1;
                    cmd_out <= {cmd_out[54:0],1'b 1};
                 end
              end
              sclk_sig <=  ~sclk_sig;
           end
           receive_ocr_wait : begin
              if((sclk_sig == 1'b 0)) begin
                 if((sdMISO == 1'b 0)) begin
                    // wait for zero bit
                    recv_data <= {40{1'b0}};
                    bit_counter = 38;
                    // already read bit 39
                    state <= receive_byte;
                 end
              end
              sclk_sig <=  ~sclk_sig;
           end
           receive_byte_wait : begin
              if((sclk_sig == 1'b 0)) begin
                 if((sdMISO == 1'b 0)) begin
                    // wait for start bit
                    recv_data <= {40{1'b0}};
                    if((response_mode == 1'b 0)) begin
                       // data mode
                       bit_counter = 3;
                       // already read bits 7..4
                    end
                    else begin
                       // command mode
                       bit_counter = 6;
                       // already read bit 7 (start bit)
                    end
                    state <= receive_byte;
                 end
              end
              sclk_sig <=  ~sclk_sig;
              // read 8-bit data or 8-bit R1 response or 40-bit R7 response
           end
           receive_byte : begin
              if((sclk_sig == 1'b 0)) begin
                 recv_data <= {recv_data[38:0],sdMISO};
                 // read next bit
                 if((bit_counter == 0)) begin
                    state <= return_state;
                    // if real data received then flag it (byte counter = 0 for both crc bytes)
                    if(return_state == read_block_data && byte_counter > 0) begin
                       sd_read_flag <=  ~sd_read_flag;
                       dout <= recv_data[7:0];
                    end
                 end
                 else begin
                    bit_counter = bit_counter - 1;
                 end
              end
              sclk_sig <=  ~sclk_sig;
           end
           write_block_cmd : begin
              block_busy <= 1'b 1;
              block_start_ack <= 1'b 0;
              cmd_mode <= 1'b 1;
              cmd_out <= {8'h ff,8'h 58,address,8'h ff};
              // CMD24 write single block
              bit_counter = 55;
              return_state <= write_block_init;
              state <= send_cmd;
           end
           write_block_init : begin
              cmd_mode <= 1'b 0;
              byte_counter = write_data_size;
              state <= write_block_data;
           end
           write_block_data : begin
              if(byte_counter == 0) begin
                 state <= receive_byte_wait;
                 return_state <= write_block_wait;
                 response_mode <= 1'b 0;
              end
              else begin
                 if(((byte_counter == 2) || (byte_counter == 1))) begin
                    data_sig <= 8'h ff;
                    // two crc bytes
                    bit_counter = 7;
                    state <= write_block_byte;
                    byte_counter = byte_counter - 1;
                 end
                 else if(byte_counter == write_data_size) begin
                    data_sig <= 8'h fe;
                    // start byte, single block
                    bit_counter = 7;
                    state <= write_block_byte;
                    byte_counter = byte_counter - 1;
                 end
                 else if(host_write_flag != sd_write_flag) begin
                    // only send if flag set
                    data_sig <= din_latched;
                    bit_counter = 7;
                    state <= write_block_byte;
                    byte_counter = byte_counter - 1;
                    sd_write_flag <=  ~sd_write_flag;
                 end
              end
           end
           write_block_byte : begin
              if((sclk_sig == 1'b 1)) begin
                 if(bit_counter == 0) begin
                    state <= write_block_data;
                 end
                 else begin
                    data_sig <= {data_sig[6:0],1'b 1};
                    bit_counter = bit_counter - 1;
                 end
              end
              sclk_sig <=  ~sclk_sig;
           end
           write_block_wait : begin
              cmd_mode <= 1'b 1;
              response_mode <= 1'b 1;
              if(sclk_sig == 1'b 0) begin
                 if(sdMISO == 1'b 1) begin
                    state <= idle;
                 end
              end
              sclk_sig <=  ~sclk_sig;
           end
           default : begin
              state <= idle;
           end
         endcase
      end
   end
   
   assign sdSCLK = sclk_sig;
   assign sdMOSI = cmd_mode == 1'b 1 ? cmd_out[55] : data_sig[7];
   assign status[7] = host_write_flag == sd_write_flag ? 1'b 1 : 1'b 0;
   // tx byte empty when equal
   assign status[6] = host_read_flag == sd_read_flag ? 1'b 0 : 1'b 1;
   // rx byte ready when not equal
   assign status[5] = block_busy;
   assign status[4] = init_busy;
   assign status[3:0] = 4'b0;
   // Make sure the drive LED is on for a visible amount of time
   wire reset_led = block_busy | init_busy;   
   always @(posedge clk or posedge reset_led) begin
      if(reset_led) begin
         led_on_count <= 200;
         // ensure on for at least 200ms (assuming 1MHz clk)
         driveLED <= 1'b 0;
      end else begin
         if(led_on_count > 0) begin
            led_on_count <= led_on_count - 1;
            driveLED <= 1'b 0;
         end
         else begin
            driveLED <= 1'b 1;
         end
      end
   end
   
   
endmodule
