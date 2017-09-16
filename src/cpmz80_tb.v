`timescale 1ns / 1ns

module cpmz80_tb();

   reg [17:0]  mem [ 0:262143 ];
   reg         clk;
   reg         reset_b;
   wire [17:0] addr;
   wire [7:0]  data;
   reg [7:0]   data_out;
   wire        ramwe_b;
   wire        ramoe_b;
   wire        ramcs_b;
   integer     i;
   
Microcomputer
   DUT
     (
      .clk100(clk),
      .n_reset(reset_b),
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
      .sdSCLK()      
      );
   

   initial begin
      $dumpvars;
      // Initialize, otherwise it messes up when probing for roms
      for (i = 0; i < 262144; i = i + 1)
        mem[i] = 0;
      
      // initialize 10MHz clock
      clk = 1'b0;
      
      // external
      reset_b  = 1'b1;
      #1000
      reset_b  = 1'b0;
      #1000
      reset_b  = 1'b1;
              
      #10000000 ; // 1ms

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
