`timescale 1ns / 1ps
`default_nettype none

// a component to limit the sampling to a given sampling interval 
module Sampler
#(
	parameter integer DataWidth = 24,	// data width in number of bits
	parameter integer SamplingInterval = 2500,	// sampling interval
)
(
	input aclk,
	input aresetn,		
	
	input in_tvalid,
	output in_tready,
	input [DataWidth-1:0] in_tdata,
		
	output out_tvalid,
	input out_tready,
	output [DataWidth-1:0] out_tdata
);	

reg out_tvalid_reg; 
reg [13:0] systemClockCounter;
reg allowSampleReg;

assign out_tdata = in_tdata;
assign out_tvalid = in_tvalid & allowSampleReg;

wire systemClockCounterLimit;
assign systemClockCounterLimit = systemClockCounter == SamplingInterval-1;

always @(posedge aclk) begin
	systemClockCounter <= ~aresetn | systemClockCounterLimit ? 14'b0 : systemClockCounter + 1;
	allowSampleReg <= ~aresetn | out_tvalid & out_tready ? 1'b0 : systemClockCounterLimit ? 1'b1 : allowSampleReg;
end

endmodule
