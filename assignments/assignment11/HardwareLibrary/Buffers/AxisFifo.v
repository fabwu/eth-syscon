`timescale 1ns / 1ps

`include "UtilityMacros.vh"

/*
	This FIFO implementation has the latency of 2 cycles
	
	Supported commands:
	
	SetEnableInputOutput	(0)
	SetWrPos				(1)
	SetRdPos				(2)
	SetFullFlag				(3)
	SetLength				(4)
	GetEnableInputOutput	(5)
	GetWrPos				(6)
	GetRdPos				(7)
	GetFullFlag				(8)
	GetLength				(9)
*/

`define CmdWidth 4 // width of a command

module AxisFifo
(
	aclk,
	aresetn,
	
	// FIFO input
	i_tvalid,
	i_tready,
	i_tdata,

	// FIFO output
	o_tvalid,
	o_tready,
	o_tdata,
	
	// FIFO command input
	cmd_tvalid,
	cmd_tready,
	cmd_tdata,
	
	// FIFO status output
	status_tvalid,
	status_tready,
	status_tdata
);

`include "UtilityFunctions.vh"

parameter integer DataWidth = 32; // FIFO data width in number of bits
parameter integer Length = 8; // FIFO buffer length
parameter integer InitEnableInput = 1; // initial value of EnableInput flag
parameter integer InitEnableOutput = 1; // initial value of EnableOutput flag
parameter integer InitFullFlag = 0; // initial value of FullFlag flag
parameter integer InitWrPos = 0; // initial value of write position pointer
parameter integer InitRdPos = 0; // initial value of read position pointer
parameter integer CmdPortUnused = 0; // non-zero if the command port is unused

localparam integer PosWidth = NumBits(Length); // number of bits used for buffer position pointers
localparam integer CmdDataWidth = `MAX(PosWidth,2);

localparam SetEnableInputOutput		= `CmdWidth'd0;
localparam SetWrPos					= `CmdWidth'd1;
localparam SetRdPos					= `CmdWidth'd2;
localparam SetFullFlag				= `CmdWidth'd3;
localparam SetLength				= `CmdWidth'd4;
localparam GetEnableInputOutput		= `CmdWidth'd5;
localparam GetWrPos					= `CmdWidth'd6;
localparam GetRdPos					= `CmdWidth'd7;
localparam GetFullFlag				= `CmdWidth'd8;
localparam GetLength				= `CmdWidth'd9;

input aclk;
input aresetn;

// FIFO input
input i_tvalid;
output i_tready;
input [DataWidth-1:0] i_tdata;

// FIFO output
output o_tvalid;
input o_tready;
output [DataWidth-1:0] o_tdata;

// FIFO command input
input cmd_tvalid;
output cmd_tready;
input [CmdDataWidth+`CmdWidth-1:0] cmd_tdata;

// FIFO status output
output reg status_tvalid;
input status_tready;
output reg [CmdDataWidth-1:0] status_tdata;

reg enableInput;
reg enableOutput;

generate

if(Length > 1) begin

	reg o_tvalid_reg;
	reg [DataWidth-1:0] o_tdata_reg;	
	assign o_tvalid = o_tvalid_reg & enableOutput;
	assign o_tdata = o_tdata_reg;

	reg [DataWidth-1:0] data[Length-1:0]; // FIFO buffer

	reg [PosWidth-1:0] wrPos; // write buffer position
	reg [PosWidth-1:0] rdPos; // read buffer position

	reg [PosWidth-1:0] length_1; // Length-1	

	// next values of write and read position pointers
	wire [PosWidth-1:0] wrPosNext;
	wire [PosWidth-1:0] rdPosNext;

	if((CmdPortUnused != 0) && ((1 << PosWidth) == Length)) begin
		assign wrPosNext = wrPos + 1'b1;
		assign rdPosNext = rdPos + 1'b1;
	end
	else begin
		assign wrPosNext = (wrPos < length_1) ? (wrPos + 1'b1) : {PosWidth{1'b0}};
		assign rdPosNext = (rdPos < length_1) ? (rdPos + 1'b1) : {PosWidth{1'b0}};
	end

	// FIFO full/empty condition logic
	reg fullFlag;
	wire full = (wrPos == rdPos) & fullFlag;
	wire empty = (wrPos == rdPos) & ~fullFlag;

	assign i_tready = ~full & enableInput;
	wire writeRequest = i_tvalid & i_tready;
	wire readRequest = ~empty & (~o_tvalid | o_tready) & enableOutput;
	
	// command input
	assign cmd_tready = 1'b1; // always ready to process commands
	wire [`CmdWidth-1:0] cmd = cmd_tdata[`CmdWidth-1:0];
	wire [CmdDataWidth-1:0] cmdData = cmd_tdata[CmdDataWidth+`CmdWidth-1:`CmdWidth];

	always @(posedge aclk) begin

		if(aresetn) begin
		
			// process a command
			if(cmd_tvalid & cmd_tready) begin
				case(cmd)
					SetEnableInputOutput: begin
						enableInput <= cmdData[0];
						enableOutput <= cmdData[1];
					end
					SetWrPos: wrPos <= cmdData;
					SetRdPos: rdPos <= cmdData;
					SetFullFlag: fullFlag <= cmdData[0];
					SetLength: length_1 <= cmdData;
					GetEnableInputOutput: begin 
						status_tdata[1:0] <= {enableOutput,enableInput};
						status_tvalid <= 1'b1;
					end
					GetWrPos: begin
						status_tdata <= wrPos; 
						status_tvalid <= 1'b1;
					end
					GetRdPos: begin
						status_tdata <= rdPos; 
						status_tvalid <= 1'b1;
					end
					GetFullFlag: begin
						status_tdata[0] <= fullFlag; 
						status_tvalid <= 1'b1;
					end
					GetLength: begin
						status_tdata <= length_1; 
						status_tvalid <= 1'b1;
					end
					default: begin
						status_tdata <= {CmdDataWidth{1'b0}};
						status_tvalid <= 1'b1;
					end
				endcase
			end
			else if(status_tvalid & status_tready)
				status_tvalid <= 1'b0;
			
			// process write request
			if(writeRequest) begin
				data[wrPos] <= i_tdata;
				wrPos <= wrPosNext;
			end
			
			// process read request
			if(readRequest) begin
				o_tdata_reg <= data[rdPos];
				o_tvalid_reg <= 1'b1;
				rdPos <= rdPosNext;
			end
			else if(o_tvalid & o_tready) begin
				o_tvalid_reg <= 1'b0;
			end
			
			if(writeRequest & ~readRequest)
				fullFlag <= 1'b1;
			else if(readRequest)
				fullFlag <= 1'b0;
			
		end
		else begin
			o_tvalid_reg <= 1'b0;
			
			wrPos <= InitWrPos;
			rdPos <= InitRdPos;
			fullFlag <= InitFullFlag;
			
			length_1 <= Length-1;
			
			enableInput <= InitEnableInput;
			enableOutput <= InitEnableOutput;
			
			status_tvalid <= 1'b0;
		end
		
	end

end
else if(Length == 1) begin // a single register
	
	reg o_tvalid_reg;
	reg [DataWidth-1:0] o_tdata_reg;
	assign o_tvalid = o_tvalid_reg & enableOutput;
	assign o_tdata = o_tdata_reg;
	
	assign i_tready = (~o_tvalid | o_tready) & enableInput; // ready for new data the data has been or is being consumed by the sink
	
	// command input
	assign cmd_tready = 1'b1; // always ready to process commands
	wire [`CmdWidth-1:0] cmd = cmd_tdata[`CmdWidth-1:0];
	wire [CmdDataWidth-1:0] cmdData = cmd_tdata[CmdDataWidth+`CmdWidth-1:`CmdWidth];
	
	always @(posedge aclk) begin
	
		if(aresetn) begin
		
			// process a command
			if(cmd_tvalid & cmd_tready) begin
				if(cmd == SetEnableInputOutput) begin
					enableInput <= cmdData[0];
					enableOutput <= cmdData[1];
				end
				if(cmd == SetFullFlag) begin
					o_tvalid_reg <= cmdData[0];
				end
				else if(cmd == GetEnableInputOutput) begin 
					status_tdata[1:0] <= {enableOutput,enableInput};
					status_tvalid <= 1'b1;
				end				
				else if(cmd == GetFullFlag) begin
					status_tdata[0] <= o_tvalid_reg; 
					status_tvalid <= 1'b1;
				end
				else begin
					status_tdata <= {CmdDataWidth{1'b0}};
					status_tvalid <= 1'b1;
				end
			end
			else if(status_tvalid & status_tready)
				status_tvalid <= 1'b0;
			
			if(i_tvalid & i_tready) begin // there is new data
				o_tdata_reg <= i_tdata;
				o_tvalid_reg <= 1'b1;
			end
			else if(o_tvalid & o_tready) begin // deassert o_tvalid if the data is being consumed by the sink
				o_tvalid_reg <= 1'b0;
			end
			
		end
		else begin
			o_tvalid_reg <= InitFullFlag;
			
			enableInput <= InitEnableInput;
			enableOutput <= InitEnableOutput;
			
			status_tvalid <= 1'b0;			
		end
	end

end	
else begin
	assign o_tvalid = i_tvalid;
	assign i_tready = o_tready;
	assign o_tdata = i_tdata;
end

endgenerate

endmodule
