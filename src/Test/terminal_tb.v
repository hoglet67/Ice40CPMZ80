`timescale 1ns / 1ns

module terminal_tb();

   reg         clk = 1'b0;
   reg         n_reset = 1'b1;

   wire        ps2Clk = 1'b1;
   wire        ps2Data = 1'b1;
   reg         n_wr = 1'b1;
   reg         n_rd = 1'b1;
   reg         regSel = 1'b0;
   reg [7:0]   dataIn;
   wire [7:0]  dataOut;
      
   wire        videoR0;
   wire        videoR1;
   wire        videoG0;
   wire        videoG1;
   wire        videoB0;
   wire        videoB1;
   wire        hSync;
   wire        vSync;
   integer     i;
   

   task send_byte;
      input [7:0] byte;
      begin
         // Select the control/status register
         @(posedge clk)
           regSel <= 1'b0;
         // Loop until the not-busy bit is set
         @(posedge clk)     
           n_rd <= 1'b0;
         @(posedge clk)     
           n_rd <= 1'b1;
         while (!dataOut[1]) begin
            @(posedge clk)     
              n_rd <= 1'b0;
            @(posedge clk)     
              n_rd <= 1'b1;
         end
         // Select the display
         @(posedge clk)
           regSel <= 1'b1;
           dataIn <= byte;
           n_wr <= 1'b0;
         @(posedge clk)      
           n_wr <= 1'b1;
         @(posedge clk)
           dataIn <= 8'hZZ;
      end
   endtask // for
   
   
SBCTextDisplayRGB DUT
  (
   .n_reset(n_reset),
   .clk(clk),
   .n_wr(n_wr),
   .n_rd(n_rd),
   .regSel(regSel),
   .dataIn(dataIn),
   .dataOut(dataOut),
   .n_int(),
   .n_rts(),
   // RGB video signals
   .videoR0(videoR0),
   .videoR1(videoR1),
   .videoG0(videoG0),
   .videoG1(videoG1),
   .videoB0(videoB0),
   .videoB1(videoB1),
   .hSync(hSync),
   .vSync(vSync),
   // Monochrome video signals
   .video(),
   .sync(),
   // Keyboard signals
   .ps2Clk(ps2Clk),
   .ps2Data(ps2Data),
   // FN keys passed out as general signals (momentary and toggled versions)
   .FNkeys(),
   .FNtoggledKeys()
   );
   
   initial begin
      $dumpvars;
      
      #1000
      n_reset  = 1'b0;
      #1000
      n_reset  = 1'b1;
      #1000
      send_byte(8'h0c);
      send_byte(8'h0a);
      send_byte(8'h0d);

      for (i = 0; i < 8; i = i + 1) begin

         // Bold off: <ESC>[22m
         send_byte(8'h1b);
         send_byte(8'h5b);
         send_byte(8'h32);
         send_byte(8'h32);
         send_byte(8'h6d);

         // Normal color: <ESC>[3<i>m
         send_byte(8'h1b);
         send_byte(8'h5b);
         send_byte(8'h33);
         send_byte(8'h30 + i);
         send_byte(8'h6d);

         // ABCDE
         send_byte(8'h41);
         send_byte(8'h42);
         send_byte(8'h43);
         send_byte(8'h44);
         send_byte(8'h45);

         // <spc><spc><spc>
         send_byte(8'h20);
         send_byte(8'h20);
         send_byte(8'h20);

         // Bright color: <ESC>[9<i>m
         send_byte(8'h1b);
         send_byte(8'h5b);
         send_byte(8'h39);
         send_byte(8'h30 + i);
         send_byte(8'h6d);
         
         // ABCDE
         send_byte(8'h41);
         send_byte(8'h42);
         send_byte(8'h43);
         send_byte(8'h44);
         send_byte(8'h45);
         
         // <lf><cr>
         send_byte(8'h0a);
         send_byte(8'h0d);

         end

         
      
        
      #20000000 ; // 20ms

      $finish;

   end

   always
     #10 clk = !clk;

endmodule
