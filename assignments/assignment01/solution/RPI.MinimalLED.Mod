MODULE MinimalLED;
(* task: let LED be lit on GPIO pin 21 *)
IMPORT SYSTEM; 

PROCEDURE {PLAIN} Code;
CODE
	ldr r0, [gpio]			; load base address of gpio
	mov r1, #8					; write 3rd bit ... 
	str r1, [r0,#8] 		; ... to register at 3f200000 + 8 
	mov r1, #0x200000		; write 21st bit ...
	str r1, [r0, #0x1c]	; ... to register at 3f200000 + 0x1c
	b end								; ... branch to end
	; data section
	gpio: d32 0x3f200000	; data
	end:				
	b end
END Code;

(*
	some students try to write to an address directly by writing something like 
		str r1, [gpio] 
	However, this is writing to the address of the variable gpio, and not to the address denoted by the value stored by variable gpio
*)

END MinimalLED.


(* compile the module *)
Compiler.Compile -p=RPI RPI.MinimalLED.Mos

(* link the kernel *)
Linker.Link -p=RPI MinimalLED ~

(* disassemble the kernel *)
FoxARMInstructionSet.Disassemble kernel.img  ~
