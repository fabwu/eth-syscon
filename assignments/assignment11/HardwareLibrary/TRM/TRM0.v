`timescale 1ns / 1ps  // TRM-3  NW 18.7.2010
module TRM0(
input clk, rst, stall,
input irq0, irq1,
input[31:0] inbus,
output [5:0] ioadr,
output iowr, iord,
output [31:0] outbus);

function [127:0] logFloor;
input [127:0] a;
reg [127:0] b;
    begin
    b = a; //copy the input
    if(b == 0) //ERROR: log(0) = -infinity
        logFloor = 0; //a better option: set a special error bit
    else //there is at least a bit in 1
        begin
        logFloor = 0;
        while(b != 1)
            begin
            b = b >> 1;
            logFloor = logFloor + 1;
            end
        end
    end
endfunction

parameter IMB = 2; //default BRAM numbers used for IM
parameter DMB = 2; //default BRAM numbers used for DM

localparam NOP = 18'b111011110000000000; //never jump

localparam LogIMBSize = logFloor(IMB);
localparam PAW = ((2 ** LogIMBSize) == IMB)? 11+LogIMBSize:
										12+LogIMBSize;
										
localparam BLS = (PAW <= 14)? PAW: 14;										

			
localparam PW = 18; //instruction width

localparam LogDMBSize = logFloor(DMB);
localparam DAW = ((2 ** LogDMBSize) == DMB)? 10 + LogDMBSize:
									11+LogDMBSize;
									


localparam DW = 32;

reg [PAW-1:0] PCf, PC;
wire [PAW-1:0] pcmux, nxpcF, nxpc;
wire [PW*2-1:0] pmout;
reg [PW-1:0] IR;
wire [PW-1:0] IRf;  //18-bit register IRf is contained in module pbram


//decoding signals
wire [3:0] op;
wire [DW-1:0] imm;
wire [2:0] ird, irs, dst;
wire [6:0] offset;
wire MOV, NOT, ADD, SUB, MUL, AND, BIC, OR, XOR, ROR;
wire LDR, ST, Bc, BLR, BL, BR, LDH;
wire vector;

//register file access signals
wire regwr;
wire [DW-1:0] AA, A, B, regmux;

//flag signals
reg Z, N, C, V;
wire S, cond;

//alu signals
wire [1:0] sc1, sc0;
wire [DW-1:0] s1, s2, s3;
wire [DW:0] minusA, aluRes;
wire [DW*2-1:0] mulRes;
reg [DW-1:0] H;  // product high

//data memory access signals
wire [DAW:0] dmadr;
wire dmwe;
wire [DW-1:0] dmin, dmout;
wire ioenb;
reg IoenbReg;
reg [DW-1:0] InbusReg;

//stall signals
reg stall1;
wire stall0, stallM;

//interrupt signals
reg intEnb0, intEnb1, intAck, intMd;
wire irq0e, irq1e;

// end declaration

//instruction memory	
IM imx(.clk(clk), .pmadr({{{33-PAW}{1'b0}},pcmux[PAW-1:1]}), .pmout(pmout));
						 
//data memory	
DM dmx(.clk(clk), 
   .wrDat(dmin),
	.wrAdr({{{31-DAW}{1'b0}},dmadr}),
	.rdAdr({{{31-DAW}{1'b0}},dmadr}),
	.wrEnb(dmwe),
	.rdDat(dmout)
	);	
	
assign S = N ^ V;
assign cond = IR[10] ^
  ((ird == 0) & Z | // EQ, NE
   (ird == 1) & C | // CS, CC
   (ird == 2) & N | // MI, PL
   (ird == 3) & V | // VS, VC
   (ird == 4) & ~(~C|Z) | // HI, LS
   (ird == 5) & ~S | // GE, LT
   (ird == 6) & ~(S|Z) |  // GT, LE
   (ird == 7));  // T, F
	
//pcmux
assign pcmux =
  (~rst) ? 0 :
  (stall0) ? PCf :
  (irq0e & intAck)? 2:
  (irq1e & intAck)? 3:
  (BL)? {{10{IR[BLS-1]}},IR[BLS-1: 0]}+ nxpc :
  (Bc & cond) ? {{{PAW-10}{IR[9]}}, IR[9:0]} + nxpc :
  (BLR | BR ) ? A[PAW-1:0] : nxpcF;

//stall  
assign stall0 = (LDR & ~stall1) | stallM | stall;
always @ (posedge clk) begin // stall generation
  if (~rst) stall1 <= 0;
  else stall1 <= (LDR & ~stall1);
end

//set interrupt signals
always @ (posedge clk) begin  // interrupt and mode handling
  if (~rst) begin intEnb0 <= 0; intEnb1 <= 0; intMd <= 0; intAck <= 0; end
  else if ((irq0e | irq1e) & ~intMd & ~stall0 & ~(IR == NOP)) begin 
    intAck <= 1; intMd <= 1; end
  else if (BR & IR[10] & IR[8]) intMd <= 0;  // return from interrupt
  else if (BR & ~IR[10]) begin // SetPSR
    intEnb0 <= IR[0]; intEnb1 <= IR[1]; intMd <= IR[2]; end
  if (intAck & ~stall0) intAck <= 0;
end 

assign irq0e = irq0 & intEnb0;
assign irq1e = irq1 & intEnb1;

assign IRf = (~rst)? NOP: (PCf[0]) ? pmout[35:18] : pmout[17:0];
assign nxpcF = PCf + 1;
assign nxpc = PC + 1;

//set pipeline registers
always @ (posedge clk) begin
  PCf <= pcmux;
  if (~rst) begin PC <= 0; IR <= NOP; end
  else if ((irq0e | irq1e) & intAck) begin PC <= PCf; IR <= NOP; end
  else if (stall0) 
    begin 
	   PC <= PC; IR <= IR; 
	 end
  else if ((Bc & cond) | BL | ((BLR | BR) & IR[10]))
    begin PC <= pcmux; IR <= NOP; end
  else 
    begin 
	   PC <= PCf; 
		IR <= IRf; 
	 end
end

//decoding
assign op = IR[17:14];
assign ird = IR[13:11];
assign irs = IR[2:0];
assign imm = {22'b0, IR[9:0]};
assign offset = IR[9:3];

assign vector = IR[10] & IR[9] & ~IR[8] & ~IR[7];

assign MOV = (op == 0);
assign NOT = (op == 1);
assign ADD = (op == 2);
assign SUB = (op == 3);
assign AND = (op == 4);
assign BIC = (op == 5);
assign OR  = (op == 6);
assign XOR = (op == 7);
assign MUL = (op == 8) & (~IR[10] | ~IR[9]);
assign ROR = (op == 10);
assign BR  = (op == 11) & IR[10] & ~IR[9];
assign LDR = (op == 12);
assign ST  = (op == 13);
assign Bc  = (op == 14);
assign BL  = (op == 15);
assign LDH = MOV & IR[10] & IR[3]; 
assign BLR = (op == 11) & IR[10] & IR[9];

assign dst = (BL | intAck) ? 7 : ird;

//register file
genvar i;
/*generate    //dual port register file
	for (i = 0; i < 32; i = i+1)
	begin: rf32
	RAM16X1D_1 # (.INIT(16'h0000))
	rfa(
	.DPO(AA[i]), // data out
	.SPO(B[i]),
	.A0(dst[0]),   // R/W address, controls D and SPO
	.A1(dst[1]),
	.A2(dst[2]),
	.A3(1'b0),
	.D(regmux[i]),  // data in
	.DPRA0(irs[0]), // read-only adr, controls DPO
	.DPRA1(irs[1]),
	.DPRA2(irs[2]),
	.DPRA3(1'b0),
	.WCLK(~clk),
	.WE(regwr));
	end
endgenerate*/

reg [31:0] regFile[0:15];

assign AA = regFile[{1'b0,irs[2:0]}];
assign B = regFile[{1'b0,dst[2:0]}];
// synchronous write to the destination register
always @(posedge clk)
begin
	if(regwr)
		regFile[{1'b0,dst[2:0]}] <= regmux;
end

assign A = (IR[10])? AA: {22'b0, imm};

//alu
/*Multiplier mulUnit(.CLK (clk),
	.RST (~MUL),
	.A ({{3{A[31]}}, A}),
	.B ({{3{B[31]}}, B}),
   .stall (stallM),
	.mulRes (mulRes));
*/
Multiplier mulUnit(.CLK(clk),
	.RST(~MUL),
	.A (A),
	.B (B),
   .stall(stallM),
	.mulRes (mulRes));
	
assign sc0 = A[1:0];
assign sc1 = A[3:2];
generate
  for (i = 0; i < 32; i = i+1)
  begin: rotblock
    assign s1[i] = (sc0 == 3) ? B[(i+3)%32] : (sc0 == 2) ? B[(i+2)%32] : (sc0 == 1) ? B[(i+1)%32] : B[i];
    assign s2[i] = (sc1 == 3) ? s1[(i+12)%32] : (sc1 == 2) ? s1[(i+8)%32] : (sc1 == 1) ? s1[(i+4)%32] : s1[i];
    assign s3[i] = A[4] ? s2[(i+16)%32] : s2[i];
  end
endgenerate

assign minusA = {1'b0, ~A} + 33'd1;

assign aluRes =
    (MOV) ? A :
    (ADD) ? {1'b0, B} + {1'b0, A} :
    (SUB) ? {1'b0, B} + minusA :
    (AND) ? B & A :
    (BIC) ? B & ~A :
    (OR)  ? B | A :
    (XOR) ? B ^ A :
    ~A;
	 
//set flag registers
always @ (posedge clk) begin  // flags handling
  if (~rst) begin N <= 0; Z <= 0; C <= 0; V <= 0; end
  else if (BR & IR[10] & IR[8]) begin //return from interrupt
    N <= A[31]; Z <= A[30]; C <= A[29]; V <= A[28]; end
  else if (regwr) begin
    N <= aluRes[31];
    Z <= (aluRes[31:0] == 0);
    C <= (ROR & s3[0]) | (~ROR & aluRes[32]);
    V <= ADD & ((~A[31] & ~B[31] & aluRes[31]) | (A[31] & B[31] & ~aluRes[31]))
             | SUB & ((~B[31] & A[31] & aluRes[31]) | (B[31] & ~A[31] & ~aluRes[31])); // why aluRes[32 ^ aluRes[31]?
  end  
  if (MUL) H <= mulRes[63:32];
end

//write back
assign regwr = ((intAck) | BL | BLR | LDR & ~IR[10] | ( ~(IR[17] & IR[16]) & ~BR & ~vector)) & ~stall0;
assign regmux = 
  (intAck) ? {N, Z, C, V, 16'b0, PC}:
  (BL | BLR) ? {{{32-PAW}{1'b0}}, nxpc} :
  (LDR & ~IoenbReg) ? dmout :
  (LDR & IoenbReg)? InbusReg: //from IO
  (MUL) ? mulRes[31:0] :
  (ROR) ? s3 :
  (LDH) ? H :
  aluRes;

//signals for accessing data memory
assign dmadr = (irs == 7) ? {{{DAW-6}{1'b0}}, offset} : (AA[DAW:0] + {{{DAW-6}{1'b0}}, offset});
assign dmwe = ST & ~IR[10] & ~ioenb;
assign dmin = B;

assign ioenb = &(dmadr[DAW:6]);
assign ioadr = dmadr[5:0];
assign iord = LDR & ~IR[10] & ioenb;
assign iowr = ST & ~IR[10] & ioenb;
assign outbus = B;

always @(posedge clk)
  begin
    IoenbReg <= ioenb;
    InbusReg <= inbus;
  end
 
endmodule 
