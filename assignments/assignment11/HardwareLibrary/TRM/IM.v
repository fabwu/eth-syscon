`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    23:28:44 04/19/2013 
// Design Name: 
// Module Name:    IM
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
module IM
	#(
		parameter integer DW = 36,
		parameter integer Size = 1024 // size in words
	)
	(
		input clk,
		input [31:0] pmadr,
		output reg [DW-1:0] pmout
    );

	reg [DW-1:0] mem[0:Size-1];
	
	initial
	begin
		$readmemh("Test0controller0code0.mem",mem);
	end
	
	always @(posedge clk)
	begin
		pmout <= mem[pmadr];
	end

endmodule
