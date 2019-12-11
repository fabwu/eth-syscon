`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    23:58:08 04/19/2013 
// Design Name: 
// Module Name:    DM
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
module DM
	#(
		parameter integer DW = 32,
		parameter integer Size = 1024 // size in words
	)
	(
		input clk,
		
		input [31:0] wrAdr, 
		input [DW-1:0] wrDat,
		input wrEnb,
		
		input [31:0] rdAdr,
		output reg [DW-1:0] rdDat
    );

	reg [DW-1:0] mem[0:Size-1];
	
	initial
	begin
		$readmemh("Test0controller0data0.mem",mem);
	end
	
	always @(posedge clk)
	begin
	
		if(wrEnb)
			mem[wrAdr] <= wrDat;
		else
			rdDat <= mem[rdAdr];
			
	end

endmodule
