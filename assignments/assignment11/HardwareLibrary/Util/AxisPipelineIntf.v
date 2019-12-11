`timescale 1ns / 1ps
module AxisPipelineIntf
	#(
		parameter integer NumStages = 2 // number of pipeline stages
	)
	(
		input aclk,
		input aresetn, // active low reset
		
		// input stream flow control signals
		input i_tvalid,
		output i_tready,
		
		// output stream flow control
		output o_tvalid,			// HIGH when the pipeline produced a valid result
		input o_tready,
				
		output pipelineMoveEv	// pipeline movement event, HIGH when data in the pipeline is to be moved to the next stage
	);		

	generate
	
	if(NumStages >= 1) begin
				
		reg [NumStages-1:0] tvalid;
		
		wire outConsumedBySink = ~o_tvalid | o_tready; // pipeline output data has been or is being consumed by the sink
		assign o_tvalid = tvalid[NumStages-1];
		assign i_tready = outConsumedBySink;
		assign pipelineMoveEv = outConsumedBySink; // move the pipeline only if its output data has been or is being consumed by the sink
		
		integer i;
		
		always @(posedge aclk) begin
			
			if(aresetn) begin
								
				if(pipelineMoveEv) begin // propagate the pipeline
				
					for(i = 1; i < NumStages; i = i + 1)
						tvalid[i] <= tvalid[i-1];
						
				end
				
				if(i_tvalid & i_tready)
					tvalid[0] <= 1'b1;
				else if(i_tready)
					tvalid[0] <= 1'b0;
				
			end
			else begin
			
				for(i = 0; i < NumStages; i = i + 1)
					tvalid[i] <= 1'b0;
				
			end
		end
		
	end
	else if(NumStages == 0) begin // no pipeline
		
		assign o_tvalid = i_tvalid;
		assign i_tready = o_tready;
		assign pipelineMoveEv = 1'b0;
		
	end
	
	endgenerate

endmodule
