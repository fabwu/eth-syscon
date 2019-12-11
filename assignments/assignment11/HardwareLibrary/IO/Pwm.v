`timescale 1ns / 1ps
`default_nettype none

// extremely simple PWM components: out is on for given amount of cycles

module Pwm
(
aclk,
aresetn,
	
inp_tdata,
inp_tvalid,
inp_tready,
	
out);

parameter integer DW = 16; // number of counter bits
input aclk;
input aresetn;
	
input [DW-1:0] inp_tdata;
input inp_tvalid;
output inp_tready;
	
output [2:0] out;

/////////////////////////////////////////

reg [DW-1:0] counter;
reg [DW-1:0] duration [2:0];
reg [2:0] target;
reg state; 

wire assignTargets; 
assign assignTargets = inp_tvalid & (state == 0);
wire assignDuration; 
assign assignDuration = inp_tvalid & (state == 1);

assign out[0] = counter < duration[0];
assign out[1] = counter < duration[1];
assign out[2] = counter < duration[2];


assign inp_tready = 1'b1;  // always ready

always @(posedge aclk) begin
	state <= inp_tvalid ? ~state : state;
	target <= assignTargets ? inp_tdata[2:0] : target;
	duration[0] <= ~aresetn ? 0 : assignDuration & target[0] ? inp_tdata : duration[0]; 
	duration[1] <= ~aresetn ? 0 : assignDuration & target[1] ? inp_tdata : duration[1]; 
	duration[2] <= ~aresetn ? 0 : assignDuration & target[2] ? inp_tdata : duration[2]; 
	counter <= ~aresetn ? 0 : counter + 1;
end

endmodule
