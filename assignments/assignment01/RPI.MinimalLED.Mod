MODULE MinimalLED;
(* task: let LED be lit on GPIO pin 21 *)

(* Import of Pseudomodule SYSTEM is required because
	we will do low-level operations here *)
IMPORT SYSTEM; 

(* PLAIN: Procedure without procedure activation frame *)
PROCEDURE {PLAIN} Code;
CODE
	(* Load address for function selection into r0 *)
	ldr r0, [FSEL21]
	(* Load constant 8 to r1 *)
	mov r1, #0x8
	(* Save 8 to function selection to set bit 3 to 1 *)
	str r1, [r0,#0]

	(* Load again the address of the output *)
	ldr r0, [GPSET0]
	(* Load number to set bit 21 *)
	mov r1, #0x200000
	(* Save the number *)
	str r1, [r0,#0]
	end: 
	b end
	(* FSEL21 Bit 5-3 001 *)
	FSEL21: d32 0x3F200008
	GPSET0: d32 0x3F20001C
END Code;

END MinimalLED.


(* compile the module *)
Compiler.Compile -p=RPI RPI.MinimalLED.Mos

(* link the kernel *)
Linker.Link -p=RPI MinimalLED ~

(* disassemble the kernel *)
FoxARMInstructionSet.Disassemble kernel.img  ~
