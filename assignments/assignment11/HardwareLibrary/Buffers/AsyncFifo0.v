//
//	Asynchronous (with separate write and read clock) FIFO with parameterizable data width and length
//
`timescale 1ns / 1ps

module AsyncFifo
#(
parameter integer DW = 8,		// FIFO data width
parameter integer Length = 32	// FIFO length
)
(
input wr_clk,
input wr_req,
input [DW-1:0] wr_data,
output reg full,
				
input rd_clk,
input rd_req,
output reg [DW-1:0] rd_data,
output reg empty,
				
input resetn
);

`include "UtilityFunctions.vh"
 
localparam integer AW = NumBits(Length);
localparam integer Length1 = (1 << AW); // internally the length can be only of power of 2; this limitation comes due to the nature of Gray code

reg [DW-1:0] mem[Length1-1:0];
wire [AW-1:0] wrPos, rdPos;
wire wrPos_eq_rdPos;
wire enableWrite, enableRead;
wire setStatus, rstStatus;
reg status;
wire preFull, preEmpty;

// signals for enabling/disabling the write and read t/from the FIFO
assign enableWrite = wr_req & ~full;
assign enableRead  = rd_req  & ~empty;

// reading from the memory
always @(posedge rd_clk) begin
	if(enableRead)
		rd_data <= mem[rdPos];
end

// writing to the memory
always @(posedge wr_clk) begin
	if(enableWrite)
		mem[wrPos] <= wr_data;
end

// write counter
GrayCounter #(.CW(AW))wr_counter
(
.out(wrPos),
.enable(enableWrite),
.resetn(resetn),
.clk(wr_clk)
);

GrayCounter #(.CW( AW ))rd_counter
(
.out(rdPos),
.enable(enableRead),
.resetn(resetn),
.clk(rd_clk)
);

assign wrPos_eq_rdPos = (wrPos == rdPos);

// Quadrant selection logic
assign setStatus = (wrPos[AW-2] ~^ rdPos[AW-1]) & (wrPos[AW-1] ^  rdPos[AW-2]);
assign rstStatus = (wrPos[AW-2] ^  rdPos[AW-1]) & (wrPos[AW-1] ~^ rdPos[AW-2]);

always @(setStatus,rstStatus,resetn) begin // D Latch with asynchronous reset and preset.
	if(rstStatus | ~resetn)
		status = 0;  // Going empty
	else if (setStatus)
		status = 1;  // Going full
end

// FIFO full logic
assign preFull = status & wrPos_eq_rdPos;
always @(posedge wr_clk, posedge preFull) begin // D Flip-Flop with asynchronous preset.
	if(preFull)
		full <= 1;
	else
		full <= 0;
end

// FIFO empty logic
assign preEmpty = ~status & wrPos_eq_rdPos;
always @(posedge rd_clk, posedge preEmpty) begin  // D Flip-Flop with asynchronous preset.
	if(preEmpty)
		empty <= 1;
	else
		empty <= 0;
end	
            
endmodule
