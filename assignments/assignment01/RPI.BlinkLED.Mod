MODULE BlinkLED; 
(* task: let LED blink on GPIO pin 21, use high level functions 
	rewrite waiting with assembler and measure execution speed. What are your conjectures?
	(low speed, much lower than expected at 700 MHz. In the order of MHz.
	--> instruction cache! --> next week
*)

IMPORT SYSTEM;

CONST
	GPIO = 03F200000H;

VAR
	gpio EXTERN GPIO: RECORD (* pinned to GPIO address *)
		GPFSEL: ARRAY 6 OF SET32;
		res0: SET32;
		GPFSET: ARRAY 2 OF SET32;
		res1: SET32;
		GPFCLR: ARRAY 2 OF SET32;
	END;

	(* the stack pointer has to be set up before any procedure call happens *)
	PROCEDURE {OPENING} Entry;
	CODE
	END Entry;

	PROCEDURE {CLOSING} Exit;
	BEGIN
		LOOP END;
	END Exit;

	(* simple loop to wait for some cycles *)
	PROCEDURE Wait(n: INTEGER);
	VAR i: INTEGER;
	BEGIN
		FOR i := 1 TO n DO END;
	END Wait;

	(* currently nothing blinks -- only the LED should light up 
		but it does not work. Change this and implement blinking afterwards.
	*)
	PROCEDURE Blink;
	VAR wait: INTEGER; 
	BEGIN
		gpio.GPFSEL[2] := {3};
		gpio.GPFSET[0] := {21};
		LOOP END;
	END Blink;

BEGIN
	Blink;
END BlinkLED.

(* compile the module *)
Compiler.Compile -p=ARM RPI.BlinkLED.Mos

(* link the kernel *)
Linker.Link -p=RPI BlinkLED ~

(* disassemble the kernel *)
FoxARMInstructionSet.Disassemble kernel.img  ~
