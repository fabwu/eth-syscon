`timescale 1ns / 1ps
`default_nettype none

// a component to correct data to bias (bias considered constant over time)
module BiasCorrector
#(
	parameter integer DataWidth = 24,	// data width in number of bits
	parameter integer SampleBits = 12,	// 2^SampleBits samples
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
assign out_tvalid = out_tvalid_reg;
assign in_tready = 1'b1; // can always accept data

reg[DataWidth-1:0] biasRegister; 
assign out_tdata = in_tdata - biasRegister;

reg[SampleBits-1:0] sampleCount;

always @(posedge aclk) begin
	out_tvalid_reg <= ~aresetn | out_tvalid & out_tready ? 1'b0 : in_tvalid ? 1'b1: out_tvalid;
	biasRegister <= ~aresetn ? DataWidth'b0 
		: biasRegister;
	sampleCount <= ~aresetn ? SampleBits'b0 : in_tvalid ? sampleCount + 1 : sampleCount; 
end

endmodule
