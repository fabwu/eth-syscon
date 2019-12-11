`timescale 1ns / 1ps // ETRM data memory 256x32  PDR 5.10.19
`default_nettype none

module DM #(parameter Inst=0, DAW=8, Size=256) (input wclk, rclk, wr, rd, input [DAW-1:0] wadr, radr, 
	input wire [31:0] wdata, output wire [31:0] rdata);

wire [31:0] rdat [0:DAW-8];
if (DAW > 8) begin
	wire [DAW-9:0] bradr, bwadr;
	reg [DAW-9:0] bradrr;
	assign bwadr = wadr[DAW-1:8];
	assign bradr = radr[DAW-1:8];
	assign rdata = rdat[bradrr];
end
else
begin
	wire bradr;
	wire bwadr;
	reg bradrr;
	assign bradr = 0;
	assign bwadr = 0;
	assign rdata = rdat[0];
end


always @ (posedge rclk) begin
	if (rd)	
		bradrr <= bradr;
end

genvar i;
generate for (i = 0; i < Size / 256; i = i + 1) begin
SB_RAM40_4K #(.READ_MODE(0), .WRITE_MODE(0),
  .INIT_0(256'hFEEDDA7A012300000000000000000000000000000000000000000000FFFFFFC0 + (Inst << 192) + (i << 128)),
  .INIT_1(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_2(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_3(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_4(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_5(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_6(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_7(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_8(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_9(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_A(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_B(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_C(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_D(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_E(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_F(256'h0000000000000000000000000000000000000000000000000000000000000000))
  bramL(.WCLK(wclk), .RCLK(rclk), .WE(wr & (bwadr == i)), .RE(rd),
    .WCLKE(1'b1), .RCLKE(1'b1), .MASK(16'b0),
    .WADDR({3'b0, wadr[7:0]}), .RADDR({3'b0, radr[7:0]}), .WDATA(wdata[15:0]), .RDATA(rdat[i][15:0]));

SB_RAM40_4K #(.READ_MODE(0), .WRITE_MODE(0),
  .INIT_0(256'hFEEDDA7A456700000000000000000000000000000000000000000000FFFFFFFF + (Inst << 192) + (i<<128)),
  .INIT_1(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_2(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_3(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_4(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_5(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_6(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_7(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_8(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_9(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_A(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_B(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_C(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_D(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_E(256'h0000000000000000000000000000000000000000000000000000000000000000),
  .INIT_F(256'h0000000000000000000000000000000000000000000000000000000000000000))
  bramH(.WCLK(wclk), .RCLK(rclk), .WE(wr & (bwadr == i)), .RE(rd),
    .WCLKE(1'b1), .RCLKE(1'b1), .MASK(16'b0),
    .WADDR({3'b0, wadr[7:0]}), .RADDR({3'b0, radr[7:0]}), .WDATA(wdata[31:16]), .RDATA(rdat[i][31:16]));
end endgenerate
endmodule 