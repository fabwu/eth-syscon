`timescale 1ns / 1ps

module Gpo
(
aclk,
aresetn,
	
inp_tdata,
inp_tvalid,
inp_tready,
	
gpo
);

parameter integer DW = 8; // number of GPO bits
parameter InitState = {DW{1'b0}}; // Initial state of all GPO pins

input aclk;
input aresetn;
	
input [DW-1:0] inp_tdata;
input inp_tvalid;
output inp_tready;
	
output [DW-1:0] gpo;

/////////////////////////////////////////

reg [DW-1:0] gpo_reg;
assign gpo = gpo_reg;

assign inp_tready = 1'b1;  // always ready

always @(posedge aclk) begin
	if(aresetn) begin
		if(inp_tvalid)
			gpo_reg <= inp_tdata;			
	end
	else begin // reset event
		gpo_reg <= InitState;
	end	
end

endmodule
