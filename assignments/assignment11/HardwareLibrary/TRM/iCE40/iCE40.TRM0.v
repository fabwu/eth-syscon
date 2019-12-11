`timescale 1ns / 1ps    // PDR 25.9.19 / 4.10.19
`default_nettype none   // based on TRM NW Aug 2010

module TRM0 #(parameter IAW = 8, // code memory address width - instructions
              parameter DAW = 8, // data memory address width - words
              parameter DW = 32, // data width
							parameter CodeMemorySize = 256,
							parameter DataMemorySize = 256,
              parameter Inst = 0)  // instance number
(input wire clk, rst, stall,irq0,irq1,
  input wire [DW-1:0] inbus, output wire iord, iowr,
  output wire [5:0] ioadr, output wire [DW-1:0] outbus);

localparam NOP = 16'b1110_1111_00000000; // never jump

reg N, Z, C, V, stall1;
reg [IAW-1:0] PCf, PC;
reg [15:0] IR;
reg [DW-1:0] R[7:0];
reg [DW-1:0] H;
reg [DW:0] adsbRes;

wire [15:0] IRf;  // register contained in Pmem
wire [3:0] op;
wire [2:0] dst, ird, irs;
wire [5:0] off;
wire [DW-1:0] src, Rd, regmux;
wire [DW-1:0] s1, s2, s3, /*divRes, remRes,*/ dmout;
wire [DW:0] aluRes;
wire [DW*2-1:0] mulRes;
wire [1:0] sc1, sc0;
wire [IAW-1:0] pcmux, nxpc, nxpcF;
wire [DAW:0] dadr;  // 1 extra bit to enable IO
wire MOV, NOT, ADD, SUB, MUL, DIV, AND, BIC, IOR, XOR, ROR;
wire BR, LD, ST, Bc, BL, ADSB;
wire S, cond, regwr, stall0, stallM, /*stallD,*/ ioenb;

Multiplier #(.DW(DW))
  mulUnit(.clk(clk), .mul(MUL), .A(Rd), .B(src),
    .stall(stallM), .mulRes(mulRes));
/*Divider #(.DW(DW))
  divUnit(.clk(clk), .div(DIV), .x(Rd), .y(src),
    .stall(stallD), .quot(divRes), .rem(remRes));*/

// IAW == 8
IM #(.Inst(Inst),.Size(CodeMemorySize),.IAW(IAW)) Pmem(.wclk(1'b0), .rclk(clk), .wr(1'b0), .rd(1'b1),
  .wadr(0), .radr(pcmux), .wdata(0), .rdata(IRf));
//if DW == 32
DM #(.Inst(Inst),.Size(DataMemorySize),.DAW(DAW)) Dmem(.wclk(clk), .rclk(clk), .wr(ST), .rd(1'b1),
  .wadr(dadr[DAW-1:0]), .radr(dadr[DAW-1:0]), .wdata(Rd), .rdata(dmout));

assign op = IR[15:12];
assign ird = IR[11:9];
assign irs = IR[2:0];
assign off = IR[8:3];

assign MOV = (op == 0);
assign NOT = (op == 1);
assign ADD = (op == 2);
assign SUB = (op == 3);
assign AND = (op == 4);
assign BIC = (op == 5);
assign IOR = (op == 6);
assign XOR = (op == 7);
assign MUL = (op == 8);
assign DIV = (op == 9);
assign ROR = (op == 10);
assign BR = (op == 11);
assign LD = (op == 12);
assign ST = (op == 13);
assign Bc = (op == 14);
assign BL = (op == 15);
assign ADSB = (IR[15:13] == 1); // ADD | SUB

assign src = IR[8] ? R[irs] : {{DW-8{1'b0}}, IR[7:0]};
assign dst = BL ? 7 : ird;
assign Rd = R[dst];
assign regwr = (~LD | stall1) & ~ST & ~Bc & ~BR;
assign outbus = Rd;
assign dadr = ((irs == 7) ? {DAW+1{1'b0}} : R[irs][DAW:0]) + {{DAW-5{1'b0}}, off};
//(irs == 7) ? {{{DAW-6}{1'b0}}, offset} : (AA[DAW:0] + {{{DAW-6}{1'b0}}, offset});

assign aluRes =
  MOV ? src :
  NOT ? ~src :
  ADSB ? adsbRes :
  AND ? Rd & src :
  BIC ? Rd & ~src :
  IOR ? Rd | src :
  MUL ? mulRes[DW-1:0] :
  /*DIV ? divRes :*/
  Rd ^ src; //XOR

//if DW == 32
assign sc0 = src[1:0];
assign sc1 = src[3:2];
genvar i;
generate
  for (i = 0; i < 32; i = i+1) begin: rotblock
    assign s1[i] = (sc0 == 3) ? Rd[(i+3)%32]
      : (sc0 == 2) ? Rd[(i+2)%32] : (sc0 == 1) ? Rd[(i+1)%32] : Rd[i];
    assign s2[i] = (sc1 == 3) ? s1[(i+12)%32]
      : (sc1 == 2) ? s1[(i+8)%32] : (sc1 == 1) ? s1[(i+4)%32] : s1[i];
    assign s3[i] = src[4] ? s2[(i+16)%32] : s2[i];
  end
endgenerate

assign S = N ^ V;
assign cond = IR[8] ^ ( // xor
    (ird == 0) & Z  // EQ, NE
  | (ird == 1) & C  // CS, CC
  | (ird == 2) & N  // MI, PL
  | (ird == 3) & V  // VS, VC
  | (ird == 4) & ~(~C|Z)  // HI, LS
  | (ird == 5) & ~S  // GE, LT
  | (ird == 6) & ~(S|Z)  // GT, LE
  | (ird == 7) );  // T, F

assign stall0 = ((ADSB | LD) & ~stall1) | stallM | /*stallD |*/ stall;
assign nxpc = PC + 1;
assign nxpcF = PCf + 1;
assign pcmux = (~rst) ? 0 : stall0 ? PCf
  : BL ? IR[IAW-1:0] + nxpc
  : (Bc & cond) ? {{IAW-8{IR[7]}}, IR[7:0]} + nxpc
  : (BR & IR[8]) ? R[irs][IAW-1:0] : nxpcF;

assign ioenb = dadr[DAW];
assign iord = LD & stall1 & ioenb;  //or ~stall1
assign iowr = ST & ioenb;
assign ioadr = dadr[5:0];
assign outbus = Rd;

assign regmux = LD ? ioenb ? inbus : dmout
  : ROR ? s3 : (BL | BR) ? {{DW-IAW{1'b0}}, nxpc} : aluRes;

always @ (posedge clk) begin
  PCf <= pcmux;
  if (~rst) begin PC <= 0; IR <= NOP; stall1 <= 0; end
  else begin
    if (stall0) begin PC <= PC; IR <= IR;
    end else if ((Bc & cond) | BL | BR & IR[8]) begin
      PC <= pcmux; IR <= NOP;
    end else begin PC <= PCf; IR <= IRf;
    end
    stall1 <= (ADSB | LD) & ~stall1;
    adsbRes <= ADD ? {Rd[DW-1], Rd} + {src[DW-1], src} : {Rd[DW-1], Rd} - {src[DW-1], src};
    if (regwr) begin
      R[dst] <= regmux;
      N <= aluRes[DW-1];
      Z <= (aluRes == 0);
      C <= ADSB ? aluRes[DW] : ROR ? s3[0] : C;
      V <= ADSB ? (aluRes[DW] ^ aluRes[DW-1]) : V;
      H <= MUL ? mulRes[DW*2-1:DW] : /*DIV ? remRes :*/ H;
    end
  end
end

endmodule

//               1111 11
//               5432 109 876543 210
// Register ops |-op-|-d-|0 --imm---
//              |-op-|-d-|1xxxxx|-s-
// Ld & ST      |-op-|-d-|-off--|-s-
// Branches     |-14-|cond| --off---
//              |-15-|  -----off----


