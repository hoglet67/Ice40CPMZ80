// Verilog translation (C) 2017 David Banks
//
// 6850 ACIA COMPATIBLE UART WITH HARDWARE INPUT BUFFER AND HANDSHAKE
// This file is copyright by Grant Searle 2013
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

module bufferedUART
  (
   input            clk,
   input            n_wr,
   input            n_rd,
   input            regSel,
   input [7:0]      dataIn,
   output reg [7:0] dataOut,
   output           n_int,
   input            rxClock,
   // 16 x baud rate
   input            txClock,
   // 16 x baud rate
   input            rxd,
   output reg       txd,
   output reg       n_rts,
   input            n_cts,
   input            n_dcd
);

   wire             n_int_internal;
   wire [7:0]       statusReg;
   reg [7:0]        controlReg = 8'b00000000;
   reg [3:0]        rxBitCount = 4'b0000;
   reg [3:0]        txBitCount = 4'b0000;
   reg [5:0]        rxClockCount = 6'b0000;
   reg [5:0]        txClockCount = 6'b0000;
   reg [7:0]        rxCurrentByteBuffer;
   reg [7:0]        txBuffer;
   reg [7:0]        txByteLatch;
   // Use bit toggling to determine change of state
   // If byte sent over serial, change "txByteSent" flag from 0//>1, or from 1//>0
   // If byte written to tx buffer, change "txByteWritten" flag from 0//>1, or from 1//>0
   // So, if "txByteSent" = "txByteWritten" then no new data to be sent
   // otherwise (if "txByteSent" /= "txByteWritten") then new data available ready to be sent
   reg              txByteWritten = 1'b0;
   reg              txByteSent = 1'b0;
   parameter [1:0]
     idle = 0,
     dataBit = 1,
     stopBit = 2;   
   reg [1:0]        rxState = idle;
   reg [1:0]        txState = idle;        
   wire             reset;   
   reg [7:0]        rxBuffer[0:15];
   reg [31:0]       rxInPointer = 0;
   reg [31:0]       rxReadPointer = 0;
   wire [31:0]      rxBuffCount;
   reg [31:0]       rxFilter;
   reg              rxdFiltered = 1'b1;

   // minimal 6850 compatibility
   assign statusReg[0] = rxInPointer == rxReadPointer ? 1'b0 : 1'b1;
   assign statusReg[1] = txByteWritten == txByteSent ? 1'b1 : 1'b0;
   assign statusReg[2] = n_dcd;
   assign statusReg[3] = n_cts;
   assign statusReg[6:4] = 3'b000;   
   assign statusReg[7] =  ~((n_int_internal));
   // interrupt mask
   assign n_int = n_int_internal;
   assign n_int_internal = (rxInPointer != rxReadPointer) && controlReg[7] == 1'b1 ? 1'b0 : (txByteWritten == txByteSent) && controlReg[6] == 1'b0 && controlReg[5] == 1'b1 ? 1'b0 : 1'b1;
   // raise (inhibit) n_rts when buffer over half-full
   // 6850 implementatit = n_rts <= '1' when controlReg(6)='1' and controlReg(5)='0' else '0';
   assign rxBuffCount = rxInPointer >= rxReadPointer ? 0 + rxInPointer - rxReadPointer : 16 + rxInPointer - rxReadPointer;
   // RTS with hysteresis
   // enable flow if less than 2 characters in buffer
   // stop flow if greater that 8 chars in buffer (to allow 8 byte overflow)
   always @(negedge clk) begin
      if(rxBuffCount < 2) begin
         n_rts <= 1'b0;
      end
      if(rxBuffCount > 8) begin
         n_rts <= 1'b1;
      end
   end
   
   // n_rts <= '1' when rxBuffCount > 24 else '0';
   // control reg
   //     7               6                     5              4          3        2         1         0
   // Rx int en | Tx control (INT/RTS) | Tx control (RTS) | ignored | ignored | ignored | reset A | reset B
   //             [        0                   1         ] = RTS LOW
   //                                                                             RESET = [  1         1  ]
   // status reg
   //     7              6                5         4          3        2         1         0
   //    irq   |   parity error      | overrun | frame err | n_cts  | n_dcd |  tx empty | rx full
   //            always 0 (no parity)    n/a        n/a
   // write of xxxxxx11 to control reg will reset

   // DMB: changed data in pattern, as 0x95 is written to reset
   assign reset = n_wr == 1'b0 && dataIn[2:0] == 3'b101 && regSel == 1'b0 ? 1'b1 : 1'b0;

   // RX de-glitcher - important because the FPGA is very sensistive
   // Filtered RX will not switch low to high until there is 50 more high samples than lows
   // hysteresis will then not switch high to low until there is 50 more low samples than highs.
   // Introduces a minor (1uS) delay with 50MHz clock
   // However, then makes serial comms 100% reliable
   always @(negedge clk) begin
      if(rxd == 1'b1 && rxFilter == 50) begin
         rxdFiltered <= 1'b1;
      end
      if(rxd == 1'b1 && rxFilter != 50) begin
         rxFilter <= rxFilter + 1;
      end
      if(rxd == 1'b0 && rxFilter == 0) begin
         rxdFiltered <= 1'b0;
      end
      if(rxd == 1'b0 && rxFilter != 0) begin
         rxFilter <= rxFilter - 1;
      end
   end
   
   always @(negedge n_rd) begin
      // Standard CPU - present data on leading edge of rd
      if(regSel == 1'b1) begin
         dataOut <= rxBuffer[rxReadPointer];
         if(rxInPointer != rxReadPointer) begin
            if(rxReadPointer < 15) begin
               rxReadPointer <= rxReadPointer + 1;
            end
            else begin
               rxReadPointer <= 0;
            end
         end
      end
      else begin
         dataOut <= statusReg;
      end
   end
   
   always @(posedge n_wr) begin
      // Standard CPU - capture data on trailing edge of wr
      if(regSel == 1'b1) begin
         if(txByteWritten == txByteSent) begin
            txByteWritten <=  ~txByteWritten;
         end
         txByteLatch <= dataIn;
      end
      else begin
         controlReg <= dataIn;
      end
   end
   
   always @(negedge rxClock or posedge reset) begin
      if(reset == 1'b1) begin
         rxState <= idle;
         rxBitCount <= {4{1'b0}};
         rxClockCount <= {6{1'b0}};
      end else begin
         case(rxState)
           idle : begin
              if(rxdFiltered == 1'b1) begin
                 // high so idle
                 rxBitCount <= {4{1'b0}};
                 rxClockCount <= {6{1'b0}};
              end
              else begin
                 // low so in start bit
                 if(rxClockCount == 7) begin
                    // wait to half way through bit
                    rxClockCount <= {6{1'b0}};
                    rxState <= dataBit;
                 end
                 else begin
                    rxClockCount <= rxClockCount + 1;
                 end
              end
           end
           dataBit : begin
              if(rxClockCount == 15) begin
                 // 1 bit later - sample
                 rxClockCount <= {6{1'b0}};
                 rxBitCount <= rxBitCount + 1;
                 rxCurrentByteBuffer <= {rxdFiltered,rxCurrentByteBuffer[7:1]};
                 if(rxBitCount == 7) begin
                    // 8 bits read - handle stop bit
                    rxState <= stopBit;
                 end
              end
              else begin
                 rxClockCount <= rxClockCount + 1;
              end
           end
           stopBit : begin
              if(rxClockCount == 15) begin
                 rxBuffer[rxInPointer] <= rxCurrentByteBuffer;
                 if(rxInPointer < 15) begin
                    rxInPointer <= rxInPointer + 1;
                 end
                 else begin
                    rxInPointer <= 0;
                 end
                 rxClockCount <= {6{1'b0}};
                 rxState <= idle;
              end
              else begin
                 rxClockCount <= rxClockCount + 1;
              end
           end
         endcase
      end
   end
   
   always @(negedge txClock or posedge reset) begin
      if(reset == 1'b1) begin
         txState <= idle;
         txBitCount <= {4{1'b0}};
         txClockCount <= {6{1'b0}};
         txByteSent <= 1'b0;
         txd <= 1'b1;         
      end else begin
         case(txState)
           idle : begin
              txd <= 1'b1;
              if((txByteWritten != txByteSent) && n_cts == 1'b0 && n_dcd == 1'b0) begin
                 txBuffer <= txByteLatch;
                 txByteSent <=  ~txByteSent;
                 txState <= dataBit;
                 txd <= 1'b0;
                 // start bit
                 txBitCount <= {4{1'b0}};
                 txClockCount <= {6{1'b0}};
              end
           end
           dataBit : begin
              if(txClockCount == 15) begin
                 // 1 bit later
                 txClockCount <= {6{1'b0}};
                 if(txBitCount == 8) begin
                    // 8 bits read - handle stop bit
                    txd <= 1'b1;
                    txState <= stopBit;
                 end
                 else begin
                    txd <= txBuffer[0];
                    txBuffer <= {1'b0,txBuffer[7:1]};
                    txBitCount <= txBitCount + 1;
                 end
              end
              else begin
                 txClockCount <= txClockCount + 1;
              end
           end
           stopBit : begin
              if(txClockCount == 15) begin
                 txState <= idle;
              end
              else begin
                 txClockCount <= txClockCount + 1;
              end
           end
         endcase
      end
   end
   
   
endmodule
