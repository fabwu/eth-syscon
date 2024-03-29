MODULE MinimalInit; (** AUTHOR ""; PURPOSE ""; *)

IMPORT SYSTEM;

PROCEDURE {OPENING} Entry;
CODE
	LDR	FP, [pc, #InitialFP-$-8]				; set stack pointer
	LDR	SP, [pc, #InitialFP-$-8]				; set frame pointer
	MOV R0, #0
	MOV R1, #0x100000
	MOV R2, #0x100000
	loop:
	LDR R3, [R0,#0]
	STR R3, [R1,#0]
	ADD R0,R0,#4
	ADD R1,R1,#4
	CMP R0,R2
	bne loop
	b 	#0x100000 - 0x4 ; jump 1 MB + 1 instruction ahead
	InitialFP: d32 0x108000 ; 1 MB + 0x8000
	end:
END Entry;

END MinimalInit.
