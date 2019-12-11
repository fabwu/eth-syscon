`timescale 1ns / 1ps
/*
	simple I2S driver
*/
module I2S	
(
	input aclk,
	input aresetn,
		
	// output channel
	output out_tvalid,
	input out_tready,
	output reg [23:0] out_tdata,

	output clk, // I2S bus clock
	input data, // I2S bus data
	output ws,  
	output enable 
	
);
	
assign enable = aresetn; // always on
assign out_tvalid = 1'b1; // always available

reg dataRegister;
reg [4:0] systemClockCounter; // 5 bit (0..31) system clock counter
reg [5:0] busClockCounter; // 6 bit (0..63) bus clock counter
reg [31:0] shiftRegister; // shift register for the data

wire systemClockCounterLimit;

assign clk = systemClockCounter [4]; // 50 --> 50/32 MHz
assign systemClockCounterLimit = (systemClockCounter == 31);
assign ws = busClockCounter [5]; // 32 cycles low / high

always @(posedge aclk) begin

	if (aresetn) begin
		systemClockCounter <= systemClockCounter + 1;
	end else begin // reset event
		systemClockCounter <= 5'b0;
		busClockCounter <= 6'b0;
	end
	if (systemClockCounterLimit) begin
		busClockCounter <= busClockCounter + 1;
		dataRegister <= data;		
		shiftRegister <= {shiftRegister[30:0], dataRegister};
		if (busClockCounter == 6'd31) begin // valid data are now in bits [29:5]
			out_tdata <= shiftRegister[29:5];
		end
	end
end

/*
always @(posedge busClock) begin
	if (aresetn) begin
		busClockCounter <= busClockCounter + 1;
	end
end

always @(negedge busClock) begin
	if (aresetn) begin
		shiftRegister <= {shiftRegister[30:0], data};
	end
end

always @(negedge ws) begin
	if (aresetn) begin
		data <= {8'b0, shreg[23:0]};
		out_tvalid = 1'b1;
	end
end
*/


endmodule









