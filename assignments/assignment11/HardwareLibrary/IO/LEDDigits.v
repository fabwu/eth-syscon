`timescale 1ns / 1ps
/*
	LED digits on the spartan3 starter board
*/
module LEDDigits	
(
	input aclk,
	input aresetn,
		
	// command input channel
	input inp_tvalid,
	output inp_tready,
	input [31:0 ]inp_tdata,  //bits 11:8 mapped to digit register,  bits 7:0 mapped to segment register

	//outputs to pins
	//digit selection
	output reg [3:0] ds,
	//segment selection
	output reg [7:0] ss
);
	
assign inp_tready = 1'b1;
reg [7:0] ledSegReg;
reg [3:0] ledDigReg;

always @(posedge aclk) begin
	if(aresetn) begin
		if(inp_tvalid) begin
			ds <= ~inp_tdata[11:8];
			ss <= ~inp_tdata[7:0];
		end
	end else begin // reset event
		ds<=4'hF;
		ss<=8'hFF;
	end	
end


endmodule









