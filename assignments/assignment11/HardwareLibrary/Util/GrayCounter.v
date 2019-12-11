//
//	Gray code counter with parameterizable counter data width
//
`timescale 1ns / 1ps

module GrayCounter
#(
parameter integer CW = 5 // counter data width
)
(
input clk,
input resetn,	// counter reset (active low)
input enable,	// enable counting
output reg  [CW-1:0] out	// Gray code counter output.
);
					
reg [CW-1:0] binCount; // binary counter
	
always @(posedge clk) begin
	if (~resetn) begin
		binCount <= {CW{1'b 0}} + 1; // Gray count begins with '1'
		out <= {CW{1'b 0}};
	end
	else if(enable) begin
		binCount <= binCount + 1;
		out <= {binCount[CW-1], binCount[CW-2:0] ^ binCount[CW-1:1]};
	end
end
	
endmodule
