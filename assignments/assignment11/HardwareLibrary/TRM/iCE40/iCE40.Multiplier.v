`timescale 1ns / 1ps  // PDR 30.9.19
`default_nettype none  // based on TRM NW Aug 2010

module Multiplier #(parameter DW = 32)
(input wire clk, mul, output wire stall,
  input wire [DW-1:0] A, B, output wire [DW*2-1:0] mulRes);

reg [5:0] S; // state  // if DW == 32
reg [DW-1:0] Hi, Lo; // high and low parts of partial product
wire [DW:0] p, Hix, Bx;

assign stall = mul & ~S[5];
assign Hix = {Hi[DW-1], Hi};
assign Bx = {B[DW-1], B};
assign p = (S == 0) ? (A[0] ? Bx : 0) :
  Lo[0] ? ((S == DW-1) ? (Hix - Bx) : (Hix + Bx)) : Hix;
assign mulRes = {Hi, Lo};

always @ (posedge(clk)) begin
  if (mul & stall) begin
    Hi <= p[DW:1];
    Lo <= (S == 0) ? {p[0], A[DW-1:1]} : {p[0], Lo[DW-1:1]}; S <= S + 1;
  end
  else if (mul) S <= 0;
  end
endmodule


