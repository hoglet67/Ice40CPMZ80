
module DisplayRam
  (
   input [A_WIDTH-1:0]      address_a,
   input [A_WIDTH-1:0]      address_b,
   input                    clock,
   input [D_WIDTH-1:0]      data_a,
   input [D_WIDTH-1:0]      data_b,
   input                    wren_a,
   input                    wren_b,
   output reg [D_WIDTH-1:0] q_a,
   output reg [D_WIDTH-1:0] q_b
);

   parameter A_WIDTH = 11;
   parameter D_WIDTH = 8;

   reg [D_WIDTH-1:0] mem[0:2**A_WIDTH-1];
   
   always @(posedge clock) begin
      if (wren_a)
        mem[address_a] <= data_a;
      q_a <= mem[address_a];
   end
   
   always @(posedge clock) begin
      if (wren_b)
        mem[address_b] <= data_b;
      q_b <= mem[address_b];
   end     
     
endmodule
