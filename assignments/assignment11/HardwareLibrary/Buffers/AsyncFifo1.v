/*
	Based on the code originally provided in the article 
	"Simulation and Synthesis Techniques for Asynchronous FIFO Design"
	by Clifford E. Cummings
*/

module fifomem
#(
	parameter integer DW = 8,	// Memory data word width
	parameter integer AW = 4	// Number of mem address bits
) 
(
	input rclk,
	input [AW-1:0] raddr,
	output reg [DW-1:0] rdata,
	
	input wclk,
	input wen,
	input [AW-1:0] waddr,
	input [DW-1:0] wdata
);

// RTL Verilog memory model
localparam integer DEPTH = 1 << AW;	
reg [DW-1:0] mem[0:DEPTH-1];

//assign rdata = mem[raddr];
always @(posedge rclk) begin
	rdata <= mem[raddr];
end

always @(posedge wclk) begin
	if(wen)
		mem[waddr] <= wdata;
end

endmodule

//////////////////////////////////////////////////////////////

module sync_r2w
#(
	parameter integer AW = 4
)
(
	output reg [AW:0] wq2_rptr,
	input [AW:0] rptr,
	input wclk,
	input wrst_n
);

reg [AW:0] wq1_rptr;

always @(posedge wclk or negedge wrst_n) begin
	if (!wrst_n) 
		{wq2_rptr,wq1_rptr} <= 0;
	else 
		{wq2_rptr,wq1_rptr} <= {wq1_rptr,rptr};
end
	
endmodule

//////////////////////////////////////////////////////////////

module sync_w2r 
#(
	parameter integer AW = 4
)
(
	output reg [AW:0] rq2_wptr,
	input [AW:0] wptr,
	input rclk, 
	input rrst_n
);

reg [AW:0] rq1_wptr;

always @(posedge rclk or negedge rrst_n) begin
	if (!rrst_n) 
		{rq2_wptr,rq1_wptr} <= 0;
	else 
		{rq2_wptr,rq1_wptr} <= {rq1_wptr,wptr};
end

endmodule

//////////////////////////////////////////////////////////////

module rptr_empty 
#(
	parameter integer AW = 4
)
(
	output reg rempty,
	output [AW-1:0] raddr,
	output reg [AW:0] rptr,
	input [AW:0] rq2_wptr,
	input ren,
	input rclk,
	input rrst_n
);

reg [AW:0] rbin;
wire [AW:0] rgraynext, rbinnext;

//-------------------
// GRAYSTYLE2 pointer
//-------------------
always @(posedge rclk or negedge rrst_n) begin
	if (!rrst_n) 
		{rbin, rptr} <= 0;
	else 
		{rbin, rptr} <= {rbinnext, rgraynext};
end

// Memory read-address pointer (okay to use binary to address memory)
assign raddr = rbin[AW-1:0];
assign rbinnext = rbin + (ren & ~rempty);
assign rgraynext = (rbinnext>>1) ^ rbinnext;

//---------------------------------------------------------------
// FIFO empty when the next rptr == synchronized wptr or on reset
//---------------------------------------------------------------
assign rempty_val = (rgraynext == rq2_wptr);
always @(posedge rclk or negedge rrst_n) begin
	if (!rrst_n) 
		rempty <= 1'b1;
	else 
		rempty <= rempty_val;
end

endmodule

//////////////////////////////////////////////////////////////

module wptr_full 
#(
	parameter integer AW = 4
)
(
	output reg wfull,
	output [AW-1:0] waddr,
	output reg [AW :0] wptr,
	input [AW :0] wq2_rptr,
	input wen, 
	input wclk,
	input wrst_n
);

reg [AW:0] wbin;
wire [AW:0] wgraynext, wbinnext;

// GRAYSTYLE2 pointer
always @(posedge wclk or negedge wrst_n) begin
	if (!wrst_n) 
		{wbin, wptr} <= 0;
	else 
		{wbin, wptr} <= {wbinnext, wgraynext};
end

// Memory write-address pointer (okay to use binary to address memory)
assign waddr = wbin[AW-1:0];
assign wbinnext = wbin + (wen & ~wfull);
assign wgraynext = (wbinnext>>1) ^ wbinnext;

//------------------------------------------------------------------
// Simplified version of the three necessary full-tests:
// assign wfull_val=((wgnext[AW] !=wq2_rptr[AW] ) &&
// (wgnext[AW-1] !=wq2_rptr[AW-1]) &&
// (wgnext[AW-2:0]==wq2_rptr[AW-2:0]));
//------------------------------------------------------------------
assign wfull_val = (wgraynext=={~wq2_rptr[AW:AW-1],wq2_rptr[AW-2:0]});
always @(posedge wclk or negedge wrst_n) begin
	if (!wrst_n) 
		wfull <= 1'b0;
	else 
		wfull <= wfull_val;
end

endmodule

//////////////////////////////////////////////////////////////

module AsyncFifo
#(
	parameter integer DW = 8,
	parameter integer AW = 4
)
(
	output [DW-1:0] rdata,
	output wfull,
	output rempty,
	input [DW-1:0] wdata,
	input wen, 
	input wclk,
	input wrst_n,
	input ren, 
	input rclk,
	input rrst_n
);

wire [AW-1:0] waddr, raddr;
wire [AW:0] wptr, rptr, wq2_rptr, rq2_wptr;

sync_r2w #(.AW(AW)) sync_r2w (.wq2_rptr(wq2_rptr),.rptr(rptr),.wclk(wclk),.wrst_n(wrst_n));
sync_w2r #(.AW(AW)) sync_w2r (.rq2_wptr(rq2_wptr),.wptr(wptr),.rclk(rclk),.rrst_n(rrst_n));

fifomem #(.DW(DW),.AW(AW)) fifomem
(
	.rdata(rdata), 
	.wdata(wdata),
	.waddr(waddr), 
	.raddr(raddr),
	.wen(wen && !wfull), 
	.wclk(wclk),
	.rclk(rclk)
);

rptr_empty #(.AW(AW)) rptr_empty
(
	.rempty(rempty),
	.raddr(raddr),
	.rptr(rptr), 
	.rq2_wptr(rq2_wptr),
	.ren(ren), 
	.rclk(rclk),
	.rrst_n(rrst_n)
);

wptr_full #(.AW(AW)) wptr_full
(
	.wfull(wfull), 
	.waddr(waddr),
	.wptr(wptr), 
	.wq2_rptr(wq2_rptr),
	.wen(wen), 
	.wclk(wclk),
	.wrst_n(wrst_n)
);

endmodule
