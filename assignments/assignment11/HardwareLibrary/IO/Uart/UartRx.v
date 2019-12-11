/*
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: UART receiver component
*/

`timescale 1ns / 1ps

module UartRx
(
	aclk, // input clock
	aresetn, // active-low reset
		 
	rxd, // receiver input
	
	rts, // Request To Send (inform remote device about readiness to receive data; active-low)
		 
	out_tdata,
	out_tvalid, // active-high when data is available
	out_tready, // active-high when input on the other side is ready for new data	 
	
	// configuration input
	cfg_tdata,
	cfg_tvalid,
	cfg_tready
 );

parameter integer ClkDivisorWidth = 16; // bit width of the main clock divisor value used for baudrate generation
parameter integer InitClkDivisor = 868; // initial value of the main clock divisor used for baudrate generation
parameter integer RtsPortUnused = 1; // non-zero if RTS output is unused (unconnected)

input aclk; // input clock
input aresetn; // active-low reset

input rxd; // receiver input
	
output rts; // Request To Send (inform remote device about readiness to receive data; active-low)
		 
output reg [7:0] out_tdata;
output reg out_tvalid; // active-high when data is available
input out_tready; // active-high when input on the other side is ready for new data

// configuration input
input [ClkDivisorWidth-1:0] cfg_tdata;
input cfg_tvalid;
output cfg_tready;

// local states
localparam IDLE = 0;
localparam START = 1;
localparam DATA = 2;
localparam STOP = 3;

reg [ClkDivisorWidth-1:0] clk_div_1; // current value of clock divisor minus 1
reg [1:0] state;

reg [ClkDivisorWidth-1:0] counter;
reg [2:0] bit_counter;

reg rxd_reg;
wire rxdi;

/*generate
if(RtsPortUnused == 0)
begin*/
	assign rts = ~out_tready; // ready to receive data when the sink is ready
/*end
endgenerate*/

assign cfg_tready = (state == IDLE);
always @(posedge aclk) begin
	if(aresetn) begin
		if(cfg_tvalid & cfg_tready) begin
			clk_div_1 <= cfg_tdata[ClkDivisorWidth-1:0];
		end
	end
	else begin
		clk_div_1 <= InitClkDivisor-1;
	end
end

always @(posedge aclk)
begin
		
	if(aresetn)
	begin
	
		rxd_reg <= rxd; // register receiver input
		
		if(out_tvalid & out_tready) // go low next clock cycle after out_tready goes high
			out_tvalid <= 0;			
			
		if(state == IDLE)
		begin
			if(!rxd_reg) // possibly a start bit
			begin
				state <= START;
				counter <= {1'b0,clk_div_1[ClkDivisorWidth-1:1]}; // count half-bit interval to check that it's really a start bit and not a noisy spike
			end
		end
		else if(state == START)
		begin
			if(counter == 0) // reached the middle of expected start bit
			begin
				if(!rxd_reg) // start bit detection justified
				begin
					state <= DATA;
					bit_counter <= 0;
					counter <= clk_div_1; // count one-bit interval till the first data bit
				end	
				else // was a spike - not a start bit
					state <= IDLE;
			end
		end
		else if(state == DATA)
		begin
			if(counter == 0) // reached the middle of the next data bit
			begin
				out_tdata[bit_counter] <= rxd_reg;				
							
				if(bit_counter == 3'd7)					
					state <= STOP;					
				else					
					bit_counter <= bit_counter + 1'b1;				

				counter <= clk_div_1; // count one-bit interval till the next (data or stop) bit					
			end
		end
		else if((state == STOP) & (counter == 0))
		begin
			state <= IDLE; // go to IDLE in any case
			out_tvalid <= rxd_reg; // if not high -> frame error!			
		end
			
		if(counter) 
			counter <= counter - 1'b1;	
		
	end			
	else
	begin
		state <= IDLE;
		out_tdata <= 0;
		out_tvalid <= 0;		
		counter <= 0;
		bit_counter <= 0;
		rxd_reg <= 0;
	end
	
end

endmodule
