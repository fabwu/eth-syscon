`timescale 1ns / 1ps

//
//	Asynchronous (with separate write and read clock) AXI4Stream FIFO 
// with parameterizable data width and length
//
module AxisAsyncFifo
#(
parameter integer DW = 8,		// FIFO data width
parameter integer Length = 32	// FIFO length
)
(
input aresetn,
						
input i_aclk,
input i_tvalid,
output i_tready,
input [DW-1:0] i_tdata,
						
input o_aclk,					
output reg o_tvalid,
input o_tready,
output [DW-1:0] o_tdata
);

`include "UtilityFunctions.vh"

localparam integer AW = NumBits(Length);
localparam integer Length1 = (1 << AW); // internally the length can be only of power of 2; this limitation comes due to the nature of the Gray code
	
wire wr_req;
wire rd_req;

wire full;
wire empty;

wire i_resetn, o_resetn;
ResetSync #(.InputPolarity(0),.OutputPolarity(0))i_resetSync(.clk(i_aclk),.inp(aresetn),.out(i_resetn));
ResetSync #(.InputPolarity(0),.OutputPolarity(0))o_resetSync(.clk(o_aclk),.inp(aresetn),.out(o_resetn));

AsyncFifo
#(
.DW(DW),
.AW(AW)
)
fifo
(
.rdata(o_tdata),
.wfull(full),
.rempty(empty),
.wdata(i_tdata),
.wen(wr_req), 
.wclk(i_aclk), 
.wrst_n(i_resetn),
.ren(rd_req),
.rclk(o_aclk), 
.rrst_n(o_resetn)
);

/*
	Input clock domain
*/
assign wr_req = i_tvalid & ~full;
assign i_tready = ~full;

/*
	Output clock domain
*/
assign rd_req = (~o_tvalid || o_tready) & ~empty;

always @(posedge o_aclk) begin

	if(o_resetn) begin
		
		if( (~o_tvalid || o_tready) & ~empty )
			o_tvalid <= 1'b1;
		else if(o_tvalid & o_tready)
			o_tvalid <= 1'b0;
		
	end
	else
		o_tvalid <= 1'b0;
	
end

endmodule
