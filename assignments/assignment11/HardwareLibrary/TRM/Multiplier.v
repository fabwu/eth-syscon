`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    17:12:48 04/21/2013 
// Design Name: 
// Module Name:    Multiplier
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module Multiplier
	#(
		parameter integer NumStages = 4
	)
	(
		input CLK, RST,
		input signed [31:0] A, B,
		output stall,
		output [63:0] mulRes
    );

reg S1, S2, S3, S4;  // state machine

assign stall = ~RST & ~S4;
assign S0 = ~RST & ~S1 & ~S2 & ~S3 & ~S4;

reg [63:0] result[NumStages-1:0];
assign mulRes = result[NumStages-1];

integer i;

always @(posedge CLK) begin	
	
	result[0] <= A * B;
	for(i = 1; i < NumStages; i = i+1)
		result[i] <= result[i-1];

	S1 <= S0; S2 <= S1; S3 <= S2; S4 <= S3;
end



endmodule
