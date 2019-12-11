`timescale 1ns / 1ps  // NW 15.7.2010

module Multiplier(  // not done for negative multipliers
  input CLK, mul,
  output stall,
  input [31:0] A, B,
  output [63:0] mulRes);

reg [5:0] S;    // state
reg [31:0] Hi, Lo;  // high and low parts of partial product
wire [32:0] p, Hix, Bx;

assign stall = mul & ~S[5];
assign Hix = {Hi[31], Hi};
assign Bx = {B[31], B};
assign p = (S == 0) ? (A[0] ? Bx : 0) :
    Lo[0] ? ((S == 31) ? (Hix - Bx) : (Hix + Bx)) : Hix;
assign mulRes = {Hi, Lo};

always @ (posedge(CLK)) begin
  if (mul & stall) begin
    Hi <= p[32:1];
    Lo <= (S == 0) ? {p[0], A[31:1]} : {p[0], Lo[31:1]};
    S <= S + 1; end
  else if (mul) S <= 0;
end

endmodule
