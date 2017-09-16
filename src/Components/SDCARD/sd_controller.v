// Verilog translation (C) 2017 David Banks
//
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
   // twice the spi clk
   output reg   driveLED
   );
   
   parameter [4:0]
     rst = 0,
     init = 1,
     cmd0 = 2,
     cmd55 = 3,
     cmd41 = 4,
     poll_cmd = 5,
     idle = 6,
     read_block_cmd = 7,
     read_block_wait = 8,
     read_block_data = 9,
     send_cmd = 10,
     receive_byte_wait = 11,
     receive_byte = 12,
     write_block_cmd = 13,
     write_block_init = 14,
     write_block_data = 15,
     write_block_byte = 16,
     write_block_wait = 17;
     
   // one start byte, plus 512 bytes of data, plus two ff end bytes (crc)
   parameter write_data_size = 515;
   
   reg [4:0]    state;
   reg [4:0]    return_state;
   reg          sclk_sig = 1'b0;
   reg [55:0]   cmd_out;
   reg [7:0]    recv_data;
   wire [7:0]   status;
   reg          block_read = 1'b0;
   reg          block_write = 1'b0;
   reg          block_start_ack = 1'b0;
   reg          cmd_mode = 1'b1;
   reg          response_mode = 1'b1;
   reg [7:0]    data_sig = 8'h 00;
   reg [7:0]    din_latched = 8'h 00;
   reg [7:0]    dout = 8'h 00;
   reg          sd_read_flag = 1'b0;
   reg          host_read_flag = 1'b0;
   reg          sd_write_flag = 1'b0;
   reg          host_write_flag = 1'b0;
   reg          init_busy = 1'b0;
   reg          block_busy = 1'b0;
   reg [31:0]   address = 32'h 00000000;
   reg [31:0]   led_on_count;
   
   assign status[3:0] = 4'b0;
   
   always @(posedge n_wr) begin
      // sd address 0..8 (first 9 bits) always zero because each sector is 512 bytes
      if(regAddr == 3'b010) begin
         address[16:9] <= dataIn;
      end
      else if(regAddr == 3'b011) begin
         address[24:17] <= dataIn;
      end
      else if(regAddr == 3'b100) begin
         address[31:25] <= dataIn[6:0];
      end
   end
   
   assign dataOut = regAddr == 3'b000 ? dout : regAddr == 3'b001 ? status : 8'b00000000;
   always @(posedge n_wr) begin
      if((regAddr == 3'b000) && (sd_write_flag == host_write_flag)) begin
         din_latched <= dataIn;
         host_write_flag <=  ~host_write_flag;
      end
   end
   
   always @(posedge n_rd) begin
      if((regAddr == 3'b000) && (sd_read_flag != host_read_flag)) begin
         host_read_flag <=  ~host_read_flag;
      end
   end

   always @(posedge n_wr or posedge block_start_ack or posedge init_busy) begin
      if (init_busy == 1'b1)
        block_read <= 1'b0;
      else if (block_start_ack == 1'b1)
        block_read <= 1'b0;
      else begin
         if (regAddr == 3'b001 && dataIn == 8'b00000000)
           block_read <= 1'b1;
      end
   end
   
   always @(posedge n_wr or posedge block_start_ack or posedge init_busy) begin
      if (init_busy == 1'b1)
        block_write <= 1'b0;
      else if (block_start_ack == 1'b1)
        block_write <= 1'b0;
      else begin
         if (regAddr == 3'b001 && dataIn == 8'b00000001)
           block_write <= 1'b1;
      end
   end

   always @(posedge clk or negedge n_reset) begin : P1
      reg [31:0] byte_counter;
      reg [31:0] bit_counter;
      
      if((n_reset == 1'b0)) begin
         state <= rst;
         sclk_sig <= 1'b0;
         sdCS <= 1'b1;
      end else begin
         case(state)
           rst : begin
              sd_read_flag <= host_read_flag;
              sd_write_flag <= host_write_flag;
              sclk_sig <= 1'b0;
              cmd_out <= {56{1'b1}};
              byte_counter = 0;
              cmd_mode <= 1'b1;
              // 0=data, 1=command
              response_mode <= 1'b1;
              // 0=data, 1=command
              bit_counter = 160;
              sdCS <= 1'b1;
              state <= init;
           end
           init : begin
              // cs=1, send 80 clocks, cs=0
              init_busy <= 1'b1;
              if((bit_counter == 0)) begin
                 sdCS <= 1'b0;
                 state <= cmd0;
              end
              else begin
                 bit_counter = bit_counter - 1;
                 sclk_sig <=  ~sclk_sig;
              end
           end
           cmd0 : begin
              cmd_out <= 56'h ff400000000095;
              bit_counter = 55;
              return_state <= cmd55;
              state <= send_cmd;
           end
           cmd55 : begin
              cmd_out <= 56'h ff770000000001;
              // 55d or 40h = 77h
              bit_counter = 55;
              return_state <= cmd41;
              state <= send_cmd;
           end
           cmd41 : begin
              cmd_out <= 56'h ff690000000001;
              // 41d or 40h = 69h
              bit_counter = 55;
              return_state <= poll_cmd;
              state <= send_cmd;
           end
           poll_cmd : begin
              if((recv_data[0] == 1'b0)) begin
                 state <= idle;
              end
              else begin
                 state <= cmd55;
              end
           end
           idle : begin
              sd_read_flag <= host_read_flag;
              sd_write_flag <= host_write_flag;
              sclk_sig <= 1'b0;
              cmd_out <= {56{1'b1}};
              data_sig <= {8{1'b1}};
              byte_counter = 0;
              cmd_mode <= 1'b1;
              // 0=data, 1=command
              response_mode <= 1'b1;
              // 0=data, 1=command
              block_busy <= 1'b0;
              init_busy <= 1'b0;
              dout <= {8{1'b0}};
              if((block_read == 1'b1)) begin
                 state <= read_block_cmd;
                 block_start_ack <= 1'b1;
              end
              else if((block_write == 1'b1)) begin
                 state <= write_block_cmd;
                 block_start_ack <= 1'b1;
              end
              else begin
                 state <= idle;
              end
           end
           read_block_cmd : begin
              block_busy <= 1'b1;
              block_start_ack <= 1'b0;
              cmd_out <= {8'h ff,8'h 51,address,8'h ff};
              bit_counter = 55;
              return_state <= read_block_wait;
              state <= send_cmd;
              // wait until data token read (= 11111110)
           end
           read_block_wait : begin
              if((sclk_sig == 1'b0 && sdMISO == 1'b0)) begin
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
              if((sclk_sig == 1'b1)) begin
                 if((bit_counter == 0)) begin
                    state <= receive_byte_wait;
                 end
                 else begin
                    bit_counter = bit_counter - 1;
                    cmd_out <= {cmd_out[54:0],1'b1};
                 end
              end
              sclk_sig <=  ~sclk_sig;
           end
           receive_byte_wait : begin
              if((sclk_sig == 1'b0)) begin
                 if((sdMISO == 1'b0)) begin
                    recv_data <= {8{1'b0}};
                    if((response_mode == 1'b0)) begin
                       bit_counter = 3;
                       // already read bits 7..4
                    end
                    else begin
                       bit_counter = 6;
                       // already read bit 7
                    end
                    state <= receive_byte;
                 end
              end
              sclk_sig <=  ~sclk_sig;
           end
           receive_byte : begin
              if((sclk_sig == 1'b0)) begin
                 recv_data <= {recv_data[6:0],sdMISO};
                 if((bit_counter == 0)) begin
                    state <= return_state;
                    // if real data received then flag it (byte counter = 0 for both crc bytes)
                    if(return_state == read_block_data && byte_counter > 0) begin
                       sd_read_flag <=  ~sd_read_flag;
                       dout <= recv_data;
                    end
                 end
                 else begin
                    bit_counter = bit_counter - 1;
                 end
              end
              sclk_sig <=  ~sclk_sig;
           end
           write_block_cmd : begin
              block_busy <= 1'b1;
              block_start_ack <= 1'b0;
              cmd_mode <= 1'b1;
              cmd_out <= {8'h ff,8'h 58,address,8'h ff};
              // single block
              bit_counter = 55;
              return_state <= write_block_init;
              state <= send_cmd;
           end
           write_block_init : begin
              cmd_mode <= 1'b0;
              byte_counter = write_data_size;
              state <= write_block_data;
           end
           write_block_data : begin
              if(byte_counter == 0) begin
                 state <= receive_byte_wait;
                 return_state <= write_block_wait;
                 response_mode <= 1'b0;
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
              if((sclk_sig == 1'b1)) begin
                 if(bit_counter == 0) begin
                    state <= write_block_data;
                 end
                 else begin
                    data_sig <= {data_sig[6:0],1'b1};
                    bit_counter = bit_counter - 1;
                 end
              end
              sclk_sig <=  ~sclk_sig;
           end
           write_block_wait : begin
              cmd_mode <= 1'b1;
              response_mode <= 1'b1;
              if(sclk_sig == 1'b0) begin
                 if(sdMISO == 1'b1) begin
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
   assign sdMOSI = cmd_mode == 1'b1 ? cmd_out[55] : data_sig[7];
   assign status[7] = host_write_flag == sd_write_flag ? 1'b1 : 1'b0;
   // tx byte empty when equal
   assign status[6] = host_read_flag == sd_read_flag ? 1'b0 : 1'b1;
   // rx byte ready when not equal
   assign status[5] = block_busy;
   assign status[4] = init_busy;
   // Make sure the drive LED is on for a visible amount of time
   wire reset_led = block_busy | init_busy;   
   always @(posedge clk or posedge reset_led) begin
      if(reset_led == 1'b1) begin
         led_on_count <= 200;
         // ensure on for at least 200ms (assuming 1MHz clk)
         driveLED <= 1'b0;
      end else begin
         if(led_on_count > 0) begin
            led_on_count <= led_on_count - 1;
            driveLED <= 1'b0;
         end
         else begin
            driveLED <= 1'b1;
         end
      end
   end
   
   
endmodule
