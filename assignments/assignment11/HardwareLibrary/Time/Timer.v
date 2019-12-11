`timescale 1ns / 1ps
/*
	Timer with incrementing or decrementing counter of configurable width
*/
module Timer	
(
	aclk,
	aresetn,
		
	// command input channel
	cmd_tvalid,
	cmd_tready,
	cmd_tdata,
		
	// counter output channel
	out_tvalid,
	out_tready,
	out_tdata
);
	
	parameter integer CW = 32; // timer counter width in number of bits
	parameter integer Inc = 1; // non-zero for incrementing counter, 0 for decrementing counter
	
	input aclk;
	input aresetn;
		
	// command input channel
	input cmd_tvalid;
	output cmd_tready;
	input [1:0] cmd_tdata;
		
	// counter output channel
	output reg out_tvalid;
	input out_tready;
	output reg [CW-1:0] out_tdata;
	
	////////////////////////////////////////
	 
	localparam CmdReset = 2'b00; // command for resetting the timer counter
	localparam CmdSample = 2'b01; // command for sampling the counter
	
	// command signals
	wire cmdReset, cmdSample;
	assign cmdReset = cmd_tvalid && (cmd_tdata == CmdReset);
	assign cmdSample = cmd_tvalid && (cmd_tdata == CmdSample);
	
	reg [CW-1:0] counter;
	
	assign cmd_tready = 1'b1; // always ready for a command
	
	wire [CW-1:0] counter_next;
	generate
	if(Inc != 0)
		assign counter_next = counter + 1'b1;
	else
		assign counter_next = counter - 1'b1;
	endgenerate

	always @(posedge aclk)
	begin
		if(aresetn)
		begin

			if(cmdSample) // sampling of the timer counter - assert tvalid
			begin
				out_tdata <= counter; // sample the counter at the sample command issue time
				out_tvalid <= 1'b1;
			end
			else if(out_tvalid & out_tready) // if not sampling and previous sample was already read - deassert tvalid
				out_tvalid <= 1'b0;
				
			if(cmdReset) // reset the counter
				counter <= {CW{1'b0}};
			else
				counter <= counter_next;
				
		end
		else
		begin
			counter <= {CW{1'b0}};
			out_tdata <= {CW{1'b0}};
			out_tvalid <= 1'b0;
		end
	end

endmodule
