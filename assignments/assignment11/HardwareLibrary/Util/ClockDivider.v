/*
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: clock divider with integer division ratio
*/

`timescale 1ns / 1ps

module ClockDivider
(
	iclk,
	oclk,
	resetn,
	period_1,
	pulsewidth,
	init_phase
);

parameter integer PeriodWidth = 16; // bit width of the integer period value

input iclk; // input clock to divide
output oclk; // output clock after division
input resetn; // active low reset signal synchronous with input clock
input [PeriodWidth-1:0] period_1; // current period value minus 1, in number of input clock cycles
input [PeriodWidth-1:0] pulsewidth; // pulsewidth value, in number of input clock cycles (pulsewidth > 0) && (pulsewidth <= period_1)
input [PeriodWidth-1:0] init_phase; // initial phase of the division counter, in input clock cycles (init_phase >= 0) && (init_phase <= divisor_1)

reg [PeriodWidth-1:0] counter;

assign oclk = counter < pulsewidth;

always @(posedge iclk) begin
	if(resetn) begin
		
		if(counter == period_1) begin
			counter <= {PeriodWidth{1'b0}};
		end
		else begin
			counter <= counter + 1'b1;
		end
			
	end
	else begin
		counter <= init_phase;
	end
end

endmodule
