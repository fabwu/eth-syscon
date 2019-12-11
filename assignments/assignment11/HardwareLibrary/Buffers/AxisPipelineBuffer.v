`timescale 1ns / 1ps

module AxisPipelineBuffer
#(
	parameter integer DataWidth = 32,	// data width in number of bits
	parameter integer NumStages = 1		// number of pipeline stages
)
(
	input aclk,
	input aresetn,		
	
	input i_tvalid,
	output i_tready,
	input [DataWidth-1:0] i_tdata,
		
	output o_tvalid,
	input o_tready,
	output [DataWidth-1:0] o_tdata
);	
	
	generate
	
	if(NumStages > 1) begin
	
		wire pipelineMoveEv;
		
		AxisPipelineIntf #(.NumStages(NumStages))
		pipelineIntf
		(
		.aclk(aclk),
		.aresetn(aresetn),
		.i_tvalid(i_tvalid),
		.i_tready(i_tready),
		.o_tvalid(o_tvalid),
		.o_tready(o_tready),
		.pipelineMoveEv(pipelineMoveEv)
		);
		
		reg [DataWidth-1:0] data[NumStages-1:0];
		assign o_tdata = data[NumStages-1];
		
		integer i;
		always @(posedge aclk) begin
			if(aresetn) begin
				if(pipelineMoveEv) begin
					data[0] <= i_tdata;
					for(i = 1; i < NumStages; i = i + 1)
						data[i] <= data[i-1];
				end								
			end			
		end
		
	end
	else if(NumStages == 1) begin
		
		reg [DataWidth-1:0] o_tdata_reg;
		reg o_tvalid_reg;
		
		assign i_tready = ~o_tvalid | o_tready;		
		assign o_tvalid = o_tvalid_reg;
		assign o_tdata = o_tdata_reg;
		
		always @(posedge aclk) begin
			if(aresetn) begin
				if(i_tvalid & i_tready) begin
					o_tvalid_reg <= 1'b1;
					o_tdata_reg <= i_tdata;
				end
				else if(o_tvalid & o_tready)
					o_tvalid_reg <= 1'b0;
			end
			else
				o_tvalid_reg <= 1'b0;
		end
					
	end		
	else begin // NumStages == 0
		assign o_tvalid = i_tvalid;
		assign o_tdata = i_tdata;
		assign i_tready = o_tready;
	end
	
	endgenerate
	
endmodule
