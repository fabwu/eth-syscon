/*
	Based on the code originally provided in the article 
	"Simulation and Synthesis Techniques for Asynchronous FIFO Design with Asynchronous Pointer Comparisons" 
	by Clifford E. Cummings and Peter Alfke
*/

module fifomem
(
	rclk,
	raddr,
	rdata,
	
	wclk,
	waddr,
	wen,
	wdata
);

parameter integer DW = 8; // Memory data word width
parameter integer AW = 4; // Number of memory address bits

localparam integer DEPTH = 1 << AW; // DEPTH = 2**AW

input rclk;
input [AW-1:0] raddr;
output reg [DW-1:0] rdata;

input wclk;
input wen;
input [AW-1:0] waddr;
input [DW-1:0] wdata;

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

module async_cmp 
(
	aempty_n, 
	afull_n, 
	wptr, 
	rptr, 
	wrst_n
);

parameter integer AW = 4;

localparam integer N = AW-1;

output aempty_n;
output afull_n;
input [N:0] wptr;
input [N:0] rptr;
input wrst_n;

reg direction;
wire high = 1'b1;
wire dirset_n = ~( (wptr[N]^rptr[N-1]) & ~(wptr[N-1]^rptr[N]));
wire dirclr_n = ~((~(wptr[N]^rptr[N-1]) & (wptr[N-1]^rptr[N])) | ~wrst_n);

always @(posedge high or negedge dirset_n or negedge dirclr_n) begin
	if (!dirclr_n) 
		direction <= 1'b0;
	else if (!dirset_n) 
		direction <= 1'b1;
	else 
		direction <= high;
end

//always @(negedge dirset_n or negedge dirclr_n)
//if (!dirclr_n) direction <= 1'b0;
//else direction <= 1'b1;

assign aempty_n = ~((wptr == rptr) && !direction);
assign afull_n = ~((wptr == rptr) && direction);

endmodule

//////////////////////////////////////////////////////////////

module rptr_empty
(
	rempty, 
	rptr, 
	aempty_n, 
	ren, 
	rclk, 
	rrst_n
);

parameter integer AW = 4;

output rempty;
output [AW-1:0] rptr;
input aempty_n;
input ren;
input rclk;
input rrst_n;

reg [AW-1:0] rptr, rbin;
reg rempty, rempty2;
wire [AW-1:0] rgnext, rbnext;

//---------------------------------------------------------------
// GRAYSTYLE2 pointer
//---------------------------------------------------------------
always @(posedge rclk or negedge rrst_n) begin
	if (!rrst_n) begin
		rbin <= 0;
		rptr <= 0;
	end
	else begin
		rbin <= rbnext;
		rptr <= rgnext;
	end
end

//---------------------------------------------------------------
// increment the binary count if not empty
//---------------------------------------------------------------
assign rbnext = !rempty ? rbin + ren : rbin;
assign rgnext = (rbnext >> 1) ^ rbnext; // binary-to-gray conversion

always @(posedge rclk or negedge aempty_n) begin
	if (!aempty_n) 
		{rempty,rempty2} <= 2'b11;
	else 
		{rempty,rempty2} <= {rempty2,~aempty_n};
end

endmodule

//////////////////////////////////////////////////////////////

module wptr_full
(
	wfull, 
	wptr, 
	afull_n, 
	wen, 
	wclk, 
	wrst_n
);

parameter integer AW = 4;

output wfull;
output [AW-1:0] wptr;
input afull_n;
input wen;
input wclk;
input wrst_n;

reg [AW-1:0] wptr, wbin;
reg wfull, wfull2;
wire [AW-1:0] wgnext, wbnext;

//---------------------------------------------------------------
// GRAYSTYLE2 pointer
//---------------------------------------------------------------
always @(posedge wclk or negedge wrst_n) begin
	if (!wrst_n) begin
		wbin <= 0;
		wptr <= 0;
	end
	else begin
		wbin <= wbnext;
		wptr <= wgnext;
	end
end

//---------------------------------------------------------------
// increment the binary count if not full
//---------------------------------------------------------------
assign wbnext = !wfull ? wbin + wen : wbin;
assign wgnext = (wbnext>>1) ^ wbnext; // binary-to-gray conversion

always @(posedge wclk or negedge wrst_n or negedge afull_n) begin
	if (!wrst_n ) 
		{wfull,wfull2} <= 2'b00;
	else if (!afull_n) 
		{wfull,wfull2} <= 2'b11;
	else 
		{wfull,wfull2} <= {wfull2,~afull_n};
end

endmodule

//////////////////////////////////////////////////////////////

module AsyncFifo
(
	rdata, 
	wfull, 
	rempty, 
	wdata,
	wen, 
	wclk, 
	wrst_n, 
	ren, 
	rclk,
	rrst_n
);

parameter integer DW = 8;
parameter integer AW = 4;

output [DW-1:0] rdata;
output wfull;
output rempty;
input [DW-1:0] wdata;
input wen;
input wclk;
input wrst_n;
input ren;
input rclk;
input rrst_n;

wire [AW-1:0] wptr, rptr;
wire [AW-1:0] waddr, raddr;

async_cmp #(.AW(AW)) async_cmp
(
	.aempty_n(aempty_n), 
	.afull_n(afull_n),
	.wptr(wptr), 
	.rptr(rptr), 
	.wrst_n(wrst_n)
);

fifomem #(.DW(DW),.AW(AW)) fifomem
(
	.rclk(rclk),
	.raddr(rptr),
	.rdata(rdata),
	.wclk(wclk),
	.wen(wen),
	.waddr(wptr),
	.wdata(wdata)
);

rptr_empty #(.AW(AW)) rptr_empty
(
	.rempty(rempty),
	.rptr(rptr),
	.aempty_n(aempty_n), 
	.ren(ren),
	.rclk(rclk), 
	.rrst_n(rrst_n)
);

wptr_full #(.AW(AW)) wptr_full
(
	.wfull(wfull),
	.wptr(wptr),
	.afull_n(afull_n),
	.wen(wen),
	.wclk(wclk),
	.wrst_n(wrst_n)
);

endmodule
