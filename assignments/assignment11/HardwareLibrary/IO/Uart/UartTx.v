/*
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: UART transmitter component
*/

`timescale 1ns / 1ps

module UartTx
(
	aclk, // system clock
	aresetn, // active-low reset
	 
	txd, // transmitter output
	
	// RTS/CTS flow control
	cts, // Clear To Send (remote device is ready to receive data; active-low)
	
	inp_tdata,
	inp_tvalid, // active-high when data is available
	inp_tready, // active-high when is ready to get new data
	
	// configuration input
	cfg_tdata, // ls bit determines EnableRtsCts setting, upper ClkDivisorWidth determine the value of clock divisor used for baudrate generation
	cfg_tvalid,
	cfg_tready
);

parameter integer ClkDivisorWidth = 16; // bit width of the main clock divisor value used for baudrate generation
parameter integer InitClkDivisor = 868; // initial value of the main clock divisor used for baudrate generation
parameter integer InitEnableRtsCts = 0; // enable/disable RTS/CTS flow control setting at the reset time
parameter integer CtsPortUnused = 1; // non-zero if CTS output is unused (unconnected)

input aclk; // system clock
input aresetn; // active-low reset
	 
output txd; // transmitter output
	
// RTS/CTS flow control
input cts; // Clear To Send (remote device is ready to receive data; active-low)
	
input [7:0] inp_tdata;
input inp_tvalid; // active-high when data is available
output inp_tready; // active-high when is ready to get new data

// configuration input
input [ClkDivisorWidth:0] cfg_tdata; // ls bit determines EnableRtsCts setting, upper ClkDivisorWidth determine the value of clock divisor used for baudrate generation
input cfg_tvalid;
output cfg_tready;
	
// local states
localparam IDLE = 0;
localparam START = 1;
localparam DATA = 2;
localparam STOP = 3;

reg enableRtsCts;
reg [ClkDivisorWidth-1:0] clk_div_1; // current value of clock divisor minus 1
reg [1:0] state;

reg [ClkDivisorWidth-1:0] counter;
reg [2:0] bit_counter;

reg [7:0] data; // internal storage for data to send

reg txd_reg;
reg inp_tready_reg;

generate
if(CtsPortUnused == 0)
	assign inp_tready = inp_tready_reg & (~cts | ~enableRtsCts);
else
	assign inp_tready = inp_tready_reg;
endgenerate

assign cfg_tready = (state == IDLE);
always @(posedge aclk) begin
	if(aresetn) begin
		if(cfg_tvalid & cfg_tready) begin
			enableRtsCts <= cfg_tdata[0];
			clk_div_1 <= cfg_tdata[ClkDivisorWidth:1];
		end
	end
	else begin
		enableRtsCts <= InitEnableRtsCts;
		clk_div_1 <= InitClkDivisor-1;
	end
end

assign txd = txd_reg;

always @(posedge aclk)
begin
	
	if(aresetn)
	begin
			
		if(state == IDLE)
		begin			
			if(inp_tvalid) // latch the data and start to send start bit
			begin
				state <= START;
				txd_reg <= 1'b0;				
				data <= inp_tdata;
				inp_tready_reg <= 1'b0;
				counter <= clk_div_1;	
			end
		end
		else if(state == START)
		begin
			if(counter == 0) // start bit is sent
			begin
				state <= DATA;
				txd_reg <= data[0]; // send first data bit					
				bit_counter <= 1;
				counter <= clk_div_1;			
			end				
		end
		else if(state == DATA)
		begin
			if(counter == 0) // sent a data bit
			begin					
				if(bit_counter)
				begin
					txd_reg <= data[bit_counter];
					bit_counter <= bit_counter + 1'b1;
				end
				else // overflow means finished sending of last bit
				begin
					state <= STOP;
					txd_reg <= 1'b1;
				end

				counter <= clk_div_1; // count one-bit interval till the next (data or stop) bit					
			end					
		end
		else if((state == STOP) & (counter == 0))
		begin
			state <= IDLE;
			inp_tready_reg <= 1'b1;
		end
			
		if(counter)
			counter <= counter - 1'b1;
		
	end
	else
	begin
		state <= IDLE;
		txd_reg <= 1'b1;
		inp_tready_reg <= 1'b1;
		counter <= 0;
		bit_counter <= 0;	
	end
end

endmodule
