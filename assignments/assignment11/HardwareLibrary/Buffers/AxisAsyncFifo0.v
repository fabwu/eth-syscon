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
output [DW-1:0] o_tdata,
					
output full,
output empty
);
	
wire wr_req;
wire rd_req;	

AsyncFifo #(.DW(DW),.Length(Length))
fifo
(
.wr_clk(i_aclk),
.wr_req(wr_req),
.wr_data(i_tdata),
.full(full),
			
.rd_clk(o_aclk),
.rd_req(rd_req),
.rd_data(o_tdata),
.empty(empty),
			
.resetn(aresetn)
);

assign wr_req = i_tvalid & ~full;
assign i_tready = ~full;
assign rd_req = (~o_tvalid || o_tready) & ~empty;

always @(posedge o_aclk) begin

	if(aresetn) begin
		
		if( (~o_tvalid || o_tready) & ~empty ) begin				
			o_tvalid <= 1'b1;
		end
		else begin
			if(o_tvalid & o_tready)
				o_tvalid <= 1'b0;
		end
		
	end
	else begin
		o_tvalid <= 1'b0;
	end
end

endmodule
