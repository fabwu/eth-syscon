`timescale 1ns / 1ps

module Gpi
(
aclk,
aresetn,
	
out_tdata,
out_tvalid,
out_tready,
	
gpi
);

parameter integer DW = 8; // number of GPI bits

input aclk;
input aresetn;
	
output reg [DW-1:0] out_tdata;
output out_tvalid;
input out_tready;
	
input [DW-1:0] gpi;

/////////////////////////////////////////
	
assign out_tvalid = 1'b1;  // always valid

always @(posedge aclk)
begin
	out_tdata <= gpi;
	/*
	if(aresetn)
		out_tdata <= gpi;
	else // reset event	
		out_tdata <= {DW{1'b0}};
	*/
end

endmodule
