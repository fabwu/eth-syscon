`timescale 1ns / 1ps    // PDR 30.9.19
`default_nettype none   // based on TRM NW Aug 2010

module Divider #(parameter DW = 32)
(input clk, div, output stall,
  input [DW-1:0] x, y, output [DW-1:0] quot, rem);

reg [5:0] S; // state // if DW == 32
reg [DW-1:0] R, Q; // remainder, quotient
wire [DW-1:0] xa, rsh, qsh, d;

assign stall = div & ~S[5];  // if DW == 32
assign xa = (x[DW-1]) ? -x : x;
assign rsh = (S == 0) ? 0 : {R[DW-2:0], Q[DW-1]};
assign qsh = (S == 0) ? {xa[DW-2:0], ~d[DW-1]} : {Q[DW-2:0], ~d[DW-1]};
assign d = rsh - y;
assign quot = (~x[DW-1]) ? Q : (R == 0) ? -Q : -Q-1;
assign rem = (~x[DW-1]) ? R : (R==0) ? 0 : y-R;
always @ (posedge clk) begin
  if (div & stall) begin
    R <= (~d[DW-1]) ? d : rsh;
    Q <= qsh;
    S <= S + 1;
  end else if (div) S <= 0;
end
endmodule

