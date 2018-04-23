// Verilog translation (C) 2017 David Banks
//
// This file is copyright by Grant Searle 2014
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

`define include_video

// The IceStorm sythesis scripts defines use_sb_io to force
// the instantaion of SB_IO (as inferrence broken)
// `define use_sb_io

module Microcomputer
  (
   input         clk100,
    // ARM SPI slave, to bootstrap load the ROMS
   inout         arm_ss,
   inout         arm_sclk,
   inout         arm_mosi,
   output        arm_miso,
   input         n_reset,
   inout [7:0]   sramData,
   output [17:0] sramAddress,
   output        n_sRamWE,
   output        n_sRamCS,
   output        n_sRamOE,
`ifdef blackice2
   output        n_sRamLB,
   output        n_sRamUB,
`endif
   input         rxd1,
   output        txd1,
`ifdef include_video
   output        videoSync,
   output        video,
   output        videoR0,
   output        videoG0,
   output        videoB0,
   output        videoR1,
   output        videoG1,
   output        videoB1,
   output        hSync,
   output        vSync,
   inout         ps2Clk,
   inout         ps2Data,
`endif
   output        sdCS,
   output        sdMOSI,
   input         sdMISO,
   output        sdSCLK
   );

   wire          n_WR;
   wire          n_RD;
   wire [15:0]   cpuAddress;
   wire [7:0]    cpuDataOut;
   wire [7:0]    cpuDataIn;
   wire          n_memWR;
   wire          n_memRD;
   wire          n_ioWR;
   wire          n_ioRD;
   wire          n_MREQ;
   wire          n_IORQ;
   wire          n_int1;
   wire          n_int2;
   wire          n_externalRamCS;
   wire          n_basRomCS;
   wire [7:0]    basRomData;
   wire          n_interface1CS;
   wire [7:0]    interface1DataOut;
   wire          n_interface2CS;
   wire [7:0]    interface2DataOut;
   wire          n_sdCardCS;
   wire [7:0]    sdCardDataOut;

   reg [15:0]    serialClkCount = 0;
   reg [5:0]     cpuClkCount = 0;
   reg           cpuClock;
   wire          serialClock;
   reg           sdClock;
   reg           clk = 0;
   wire          driveLED;

`ifdef blackice2
   assign n_sRamUB  = 0;
   assign n_sRamLB  = 0;
`endif

   // High during the initial ROM bootstrap phase
   wire          booting;
   
   // Hold everything in reset during ROM bootstrap
   wire          n_hard_reset = n_reset & !booting;

   // ____________________________________________________________________________________
   // CPU CHOICE GOES HERE
   tv80n
     #(
       .Mode(1),
       .T2Write(1),
       .IOWait(0)
       )
   cpu1
     (
      .reset_n(n_hard_reset),
      .clk(cpuClock),
      .wait_n(1'b 1),
      .int_n(1'b 1),
      .nmi_n(1'b 1),
      .busrq_n(1'b 1),
      .mreq_n(n_MREQ),
      .iorq_n(n_IORQ),
      .rd_n(n_RD),
      .wr_n(n_WR),
      .A(cpuAddress),
      .di(cpuDataIn),
      .do(cpuDataOut));

   // ____________________________________________________________________________________
   // ROM GOES HERE
   //
   // Bootstrap (of ROM content from ARM into RAM )
   wire        cpm_RAMCS_b = n_externalRamCS;
   wire        cpm_RAMOE_b = n_memRD | n_externalRamCS;
   wire        cpm_RAMWE_b = n_memWR | n_externalRamCS;
   wire [17:0] cpm_RAMA    = {2'b00, cpuAddress[15:0]};


   wire [7:0]  cpm_RAMDin = cpuDataOut;
   wire [7:0]  cpm_RAMDout = data_pins_in;

   wire        ext_RAMCS_b;
   wire        ext_RAMOE_b;
   wire        ext_RAMWE_b;
   wire [17:0] ext_RAMA;
   wire [7:0]  ext_RAMDin;

   wire        arm_ss_int;
   wire        arm_mosi_int;
   wire        arm_miso_int;
   wire        arm_sclk_int;

   // TODO: not (yet) had any problems without this, but Z80 onlt running at 10MHz currently
   wire        wegate_b = 1'b0;   
   
   bootstrap BS
     (
      .clk(clk100),
      .booting(booting),
      .progress(),
      // SPI Slave Interface (runs at 20MHz)
      .SCK(arm_sclk_int),
      .SSEL(arm_ss_int),
      .MOSI(arm_mosi_int),
      .MISO(arm_miso_int),
      // RAM from Beeb
      .cpm_RAMCS_b(cpm_RAMCS_b),
      .cpm_RAMOE_b(cpm_RAMOE_b),
      .cpm_RAMWE_b(cpm_RAMWE_b | wegate_b),
      .cpm_RAMA(cpm_RAMA),
      .cpm_RAMDin(cpm_RAMDin),
      // RAM to external SRAM
      .ext_RAMCS_b(ext_RAMCS_b),
      .ext_RAMOE_b(ext_RAMOE_b),
      .ext_RAMWE_b(ext_RAMWE_b),
      .ext_RAMA(ext_RAMA),
      .ext_RAMDin(ext_RAMDin)
   );
   
   // ____________________________________________________________________________________
   // RAM GOES HERE

   assign sramAddress = ext_RAMA;
   assign n_sRamWE    = ext_RAMWE_b;
   assign n_sRamOE    = ext_RAMOE_b; 
   assign n_sRamCS    = ext_RAMCS_b; 

`ifdef use_sb_io
   // IceStorm cannot infer bidirectional I/Os
   wire [7:0] data_pins_in;
   wire [7:0] data_pins_out = ext_RAMDin;
   wire       data_pins_out_en = !ext_RAMWE_b;
   SB_IO
     #(
       .PIN_TYPE(6'b 1010_01)
       )
   sram_data_pins [7:0]
     (
      .PACKAGE_PIN(sramData),
      .OUTPUT_ENABLE(data_pins_out_en),
      .D_OUT_0(data_pins_out),
      .D_IN_0(data_pins_in)
      );
`else
   assign sramData = (ext_RAMWE_b) ? 8'bz : ext_RAMDin;
   wire [7:0] data_pins_in = sramData;
`endif

   // ____________________________________________________________________________________
   // INPUT/OUTPUT DEVICES GO HERE

   bufferedUART io1
     (
      .clk(clk),
      .n_wr(n_interface1CS | n_ioWR),
      .n_rd(n_interface1CS | n_ioRD),
      .n_int(n_int1),
      .regSel(cpuAddress[0]),
      .dataIn(cpuDataOut),
      .dataOut(interface1DataOut),
      .rxClock(serialClock),
      .txClock(serialClock),
      .rxd(rxd1),
      .txd(txd1),
      .n_cts(1'b 0),
      .n_dcd(1'b 0),
      .n_rts()
      );

`ifdef include_video
   SBCTextDisplayRGB io2
     (
      .n_reset(n_hard_reset),
      .clk(clk),
      // RGB video signals
      .hSync(hSync),
      .vSync(vSync),
      .videoR0(videoR0),
      .videoR1(videoR1),
      .videoG0(videoG0),
      .videoG1(videoG1),
      .videoB0(videoB0),
      .videoB1(videoB1),
      // Monochrome video signals (when using TV timings only)
      .sync(videoSync),
      .video(video),
      .n_wr(n_interface2CS | n_ioWR),
      .n_rd(n_interface2CS | n_ioRD),
      .n_int(n_int2),
      .regSel(cpuAddress[0]),
      .dataIn(cpuDataOut),
      .dataOut(interface2DataOut),
      .ps2Clk(ps2Clk),
      .ps2Data(ps2Data)
      );
`else
   assign interface2DataOut = 8'hff;
`endif

   sd_controller sd1
     (
      .sdCS(sdCS),
      .sdMOSI(sdMOSI),
      .sdMISO(sdMISO),
      .sdSCLK(sdSCLK),
      .n_wr(n_sdCardCS | n_ioWR),
      .n_rd(n_sdCardCS | n_ioRD),
      .n_reset(n_hard_reset),
      .dataIn(cpuDataOut),
      .dataOut(sdCardDataOut),
      .regAddr(cpuAddress[2:0]),
      .driveLED(driveLED),
      .clk(clk)
      );
   

   // ____________________________________________________________________________________
   // MEMORY READ/WRITE LOGIC GOES HERE

   assign n_ioWR = n_WR | n_IORQ;
   assign n_memWR = n_WR | n_MREQ;
   assign n_ioRD = n_RD | n_IORQ;
   assign n_memRD = n_RD | n_MREQ;

   // ____________________________________________________________________________________
   // CHIP SELECTS GO HERE

   // 2 Bytes $80-$81
   assign n_interface1CS = cpuAddress[7:1] == 7'b 1000000 && (n_ioWR == 1'b 0 || n_ioRD == 1'b 0) ? 1'b 0 : 1'b 1;

   // 2 Bytes $82-$83
   assign n_interface2CS = cpuAddress[7:1] == 7'b 1000001 && (n_ioWR == 1'b 0 || n_ioRD == 1'b 0) ? 1'b 0 : 1'b 1;

   // 8 Bytes $88-$8F
   assign n_sdCardCS = cpuAddress[7:3] == 5'b 10001 && (n_ioWR == 1'b 0 || n_ioRD == 1'b 0) ? 1'b 0 : 1'b 1;

   // Always enabled
   assign n_externalRamCS = 1'b0;

   // ____________________________________________________________________________________
   // BUS ISOLATION GOES HERE

   assign cpuDataIn =   n_interface1CS == 1'b 0 ? interface1DataOut   :
                        n_interface2CS == 1'b 0 ? interface2DataOut   :
                            n_sdCardCS == 1'b 0 ? sdCardDataOut       :
                       n_externalRamCS == 1'b 0 ? data_pins_in        :
                                                  8'h FF;
  // ____________________________________________________________________________________
  // SYSTEM CLOCKS GO HERE
  // SUB-CIRCUIT CLOCK SIGNALS

   assign serialClock = serialClkCount[15];

   always @(posedge clk100)
      clk = !clk;

   always @(posedge clk) begin
      if(cpuClkCount < 4) begin
         // 4 = 10MHz, 3 = 12.5MHz, 2=16.6MHz, 1=25MHz
         cpuClkCount <= cpuClkCount + 1;
      end
      else begin
         cpuClkCount <= {6{1'b0}};
      end
      if(cpuClkCount < 2) begin
         // 2 when 10MHz, 2 when 12.5MHz, 2 when 16.6MHz, 1 when 25MHz
         cpuClock <= 1'b 0;
      end
      else begin
         cpuClock <= 1'b 1;
      end
      // Serial clock DDS
      // 50MHz master input clock:
      // Baud Increment
      // 115200 2416
      // 38400 805
      // 19200 403
      // 9600 201
      // 4800 101
      // 2400 50
      serialClkCount <= serialClkCount + 2416;
   end

   // ===============================================================
   // ARM SPI Port / LED multiplexor
   // ===============================================================

   wire led1 = 0;
   wire led2 = !driveLED;
   wire led3 = n_WR;
   wire led4 = !n_hard_reset;
   
   // FPGA -> ARM signals
   assign arm_miso = booting ? arm_miso_int : led2;

   // ARM -> FPGA signals
`ifdef use_sb_io
   SB_IO
     #(
       .PIN_TYPE(6'b 1010_01)
       )
   arm_spi_pins [2:0]
     (
      .PACKAGE_PIN({arm_ss, arm_mosi, arm_sclk}),
      .OUTPUT_ENABLE(!booting),
      .D_OUT_0({led1, led3, led4}),
      .D_IN_0({arm_ss_int, arm_mosi_int, arm_sclk_int})
      );
`else
   assign {arm_ss, arm_mosi, arm_sclk} = booting ? 3'bZ : {led1, led3, led4};
   assign {arm_ss_int, arm_mosi_int, arm_sclk_int} = {arm_ss, arm_mosi, arm_sclk};
`endif
   
endmodule
