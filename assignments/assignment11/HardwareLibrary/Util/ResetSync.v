/*
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: synchronization of a reset signal with a given clock	
	
	Remark: the output reset signal is asserted asynchronously but deasserted synchronously with the input clock
*/
`timescale 1ns / 1ps
module ResetSync
(
	clk,	// input clock signal
	inp,	// input reset signal
	out	// output reset signal 
);

parameter integer InputPolarity = 1; // polarity of the input reset signal, 0 for active low, non-zero for active high
parameter integer OutputPolarity = 1; // polarity of the output reset signal, 0 for active low, non-zero for active high
parameter integer ClockEdge = 1; // non-zero for synchronizing to positive clock edge, zero - to negative clock edge

input clk;	// input clock signal
input inp;	// input reset signal
output out;	// output reset signal 

////////////////////////////////////////////

reg r0, r1;

assign out = r1;

generate

if(ClockEdge != 0) begin // sync to positive clock edge

	if(InputPolarity == 1) begin // active high input

		always @(posedge clk or posedge inp) begin
			if(inp) begin
				r0 <= OutputPolarity;
				r1 <= OutputPolarity;
			end
			else begin
				r1 <= r0;
				r0 <= !OutputPolarity;
			end
		end
		
	end
	else begin // active low input

		always @(posedge clk or negedge inp) begin
			if(~inp) begin
				r0 <= OutputPolarity;
				r1 <= OutputPolarity;
			end
			else begin
				r1 <= r0;
				r0 <= !OutputPolarity;
			end
		end

	end
	
end
else begin // sync to negative clock edge

	if(InputPolarity == 1) begin // active high input

		always @(negedge clk or posedge inp) begin
			if(inp) begin
				r0 <= OutputPolarity;
				r1 <= OutputPolarity;
			end
			else begin
				r1 <= r0;
				r0 <= !OutputPolarity;
			end
		end
		
	end
	else begin // active low input

		always @(negedge clk or negedge inp) begin
			if(~inp) begin
				r0 <= OutputPolarity;
				r1 <= OutputPolarity;
			end
			else begin
				r1 <= r0;
				r0 <= !OutputPolarity;
			end
		end

	end
	
end

endgenerate

endmodule
