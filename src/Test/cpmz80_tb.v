`timescale 1ns / 1ns

module cpmz80_tb();

   // This is used to simulate the ARM downloaded the initial set of ROM images
   parameter   BOOT_INIT_FILE    = "../mem/CPM_BASIC.mem";
   parameter   BOOT_START_ADDR   = 'h00000;
   parameter   BOOT_END_ADDR     = 'h01FFF;

   reg [23:0]  boot_start = BOOT_START_ADDR;
   reg [23:0]  boot_end   = BOOT_END_ADDR;
   reg [7:0]   boot [ 0 : BOOT_END_ADDR - BOOT_START_ADDR ];

   reg [17:0]  mem [ 0:262143 ];

   reg         clk;
   reg         reset_b;
   wire [17:0] addr;
   wire [7:0]  data;
   reg [7:0]   data_out;
   wire        ramwe_b;
   wire        ramoe_b;
   wire        ramcs_b;
   wire        ps2Clk;
   wire        ps2Data;
   
   reg         arm_ss_r;
   reg         arm_sclk_r;
   reg         arm_mosi_r;

   reg         booting;

   wire        arm_ss;
   wire        arm_sclk;
   wire        arm_mosi;

   integer     i, j;

   assign arm_ss   = booting ? arm_ss_r   : 1'bZ;
   assign arm_sclk = booting ? arm_sclk_r : 1'bZ;
   assign arm_mosi = booting ? arm_mosi_r : 1'bZ;
   
   // send a byte over SPI (MSB first)
   // data changes on falling edge of clock and is samples on rising edges
   task spi_send_byte;
      input [7:0] byte;
      for (j = 7; j >= 0; j = j - 1)
        begin
           #25 arm_sclk_r = 1'b0;
           arm_mosi_r = byte[j];
           #25 arm_sclk_r = 1'b1;
        end
   endtask // for
   
Microcomputer
   DUT
     (
      .clk100(clk),
      .n_reset(reset_b),
      .arm_ss(arm_ss),
      .arm_sclk(arm_sclk),
      .arm_mosi(arm_mosi),
      .sramData(data),
      .sramAddress(addr),
      .n_sRamWE(ramwe_b),
      .n_sRamCS(ramcs_b),
      .n_sRamOE(ramoe_b),
      .rxd1(1'b1),
      .txd1(),
      .sdCS(),
      .sdMOSI(),
      .sdMISO(1'b1),
      .sdSCLK(),
      .ps2Clk(ps2Clk),
      .ps2Data(ps2Data)
      );

   
   assign ps2Clk = 1'b1;
   assign ps2Data = 1'b1;
   

   initial begin
      $dumpvars;
      // Initialize, otherwise it messes up when probing for roms
      for (i = 0; i < 262144; i = i + 1)
        mem[i] = 0;
      
      // initialize 10MHz clock
      clk = 1'b0;

      // load the boot image at 20MHz (should take 6ms for 16KB)
      $readmemh(BOOT_INIT_FILE, boot);
      booting    = 1'b1;
      arm_ss_r   = 1'b1;
      arm_sclk_r = 1'b1;
      arm_mosi_r = 1'b1;
      // start the boot spi transfer by lowering ss
      #1000 arm_ss_r = 1'b0;
      // wait ~1us longer (as this is what the arm does)
      #1000;

      // send the ROM image start address
      spi_send_byte(boot_start[ 7: 0]);
      spi_send_byte(boot_start[15: 8]);
      spi_send_byte(boot_start[23:16]);
      // send the ROM image end address
      spi_send_byte(boot_end[ 7: 0]);
      spi_send_byte(boot_end[15: 8]);
      spi_send_byte(boot_end[23:16]);
      // send the ROM image data
      for (i = 0; i <= BOOT_END_ADDR - BOOT_START_ADDR; i = i + 1)
        spi_send_byte(boot[i]);

      #1000 arm_ss_r = 1'b1;

      #1000 booting  = 1'b0;
      
      // external
      reset_b  = 1'b1;
      #1000
      reset_b  = 1'b0;
      #1000
      reset_b  = 1'b1;
              
      #20000000 ; // 20ms

      $finish;

   end

   always
     #5 clk = !clk;

   always @(posedge DUT.cpuClock) begin
      if (!DUT.n_RD && !DUT.cpu1.m1_n)
        $display("Fetch: %04x = %02x", DUT.cpuAddress, DUT.cpuDataIn);
//      if (!DUT.n_RD)
//        $display("Rd: %04x = %02x", DUT.cpuAddress, DUT.cpuDataIn);
//      if (!DUT.n_WR)      
//        $display("Wr: %04x = %02x", DUT.cpuAddress, DUT.cpuDataOut);
   end
   
   assign data = (!ramcs_b && !ramoe_b && ramwe_b) ? data_out : 8'hZZ;


   // This seem a bit of a hack, but the memory write
   // was getting lost because the data was being tristated instantly
   wire [7:0] #(1)  data_in = data;
   
   always @(posedge ramwe_b)
     if (ramcs_b == 1'b0) begin
        mem[addr] <= data_in;
        $display("Ram Wr: %04x = %02x",addr, data_in);       
     end


   always @(addr)
     data_out <= mem[addr];

endmodule
