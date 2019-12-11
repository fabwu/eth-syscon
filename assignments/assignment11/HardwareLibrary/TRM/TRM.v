`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    11:28:34 09/19/2012 
// Design Name: 
// Module Name:    TRM
// Project Name: 
// Target Devices: XC6S
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module TRM(	
	input aclk,
	input aresetn,
	
	// input
	input [31:0] inp_tdata,
	input inp_tvalid,
	output inp_tready,
	output [3:0] inp_tdest,
	
	// output
	output [31:0] out_tdata,
	output out_tvalid,
	input out_tready,
	output [3:0] out_tdest
    );

parameter integer IMB = 2;
parameter integer DMB = 2;
parameter integer FloatingPoint = 0; // non-zero for FPU support
parameter integer Inst=0; // TRM instance number
parameter integer CodeMemorySize=256;
parameter integer DataMemorySize=256;
parameter integer IAW = 8;
parameter integer DAW = 8;
//#####################################
reg stop;
//#####################################

// destination selection from TRM
wire [5:0] ioadr;
// inp_tdest and out_tdest share same ioadr; currently it is not a problem because reading and writing are done sequentially
assign inp_tdest = ioadr[3:0];
assign out_tdest = ioadr[3:0];

// input to TRM
wire [31:0] inbus;
assign inbus[31:1] = inp_tdata[31:1];
// 4-th and 5-th bits of ioadr are used as flags for reading inp_tvalid and out_tready signals correspondingly; inp_tvalid and out_tready are written to 0-th bit of inbus
assign inbus[0] = (ioadr[4]) ? inp_tvalid : (ioadr[5]) ? out_tready : inp_tdata[0];
wire iord;
//assign inp_tready = (~ioadr[4] & ~ioadr[5]) ? iord : 1'b0; // assure that inp_tready is not asserted in case if inp_tvalid and out_tready are to be read

//#############################################################
  assign inp_tready = (~ioadr[4] & ~ioadr[5]) ? (iord & stop) : 1'b0; 
//#############################################################

// output from TRM
wire [31:0] outbus;
assign out_tdata = outbus;
wire iowr;
assign out_tvalid = iowr;

//###############################################
always@(posedge aclk) begin

	if(~aresetn) begin
		stop <= 1'b1;
	end
	else begin
	
		if(iord & inp_tvalid) begin
			stop <= 1'b0;
		end
		
		if(~stop) begin
			stop <= 1'b1;
		end
	
	end
	
end
//###############################################

TRM0#(.CodeMemorySize(CodeMemorySize),.DataMemorySize(DataMemorySize),.IAW(IAW),.DAW(DAW),.Inst(Inst))trm(.clk(aclk),.rst(aresetn),.irq0(1'b0),.irq1(1'b0),.stall(1'b0),.inbus(inbus),.ioadr(ioadr),.iowr(iowr),.iord(iord),.outbus(outbus));

endmodule
