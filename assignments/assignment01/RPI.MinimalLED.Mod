MODULE MinimalLED;
(* task: let LED be lit on GPIO pin 21 *)

(* Import of Pseudomodule SYSTEM is required because
	we will do low-level operations here *)
IMPORT SYSTEM; 

(* PLAIN: Procedure without procedure activation frame *)
PROCEDURE {PLAIN} Code;
CODE
	ldr r0, [someNumber]
	mov r1, #0x30
	str r1, [r0,#0]
	end: 
	b end
	someNumber: d32 0x0000000
END Code;

END MinimalLED.


(* compile the module *)
Compiler.Compile -p=RPI RPI.MinimalLED.Mos

(* link the kernel *)
Linker.Link -p=RPI MinimalLED ~

(* disassemble the kernel *)
FoxARMInstructionSet.Disassemble kernel.img  ~
