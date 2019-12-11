MODULE PWMTest;

IMPORT 
	Engines;

TYPE 
	(* a component to test the three channel Pulse Width Modulator on an RGB LED *)
	PWMTester = CELL : Engines.TRM {InstructionWidth=16,CodeMemorySize=256,DataMemorySize=256}  (pwm: PORT OUT);
	VAR count: SIGNED32;
	CONST Red = 4; Green = 2; Blue = 1;
	
		PROCEDURE CountToColor(count: SIGNED32);
		VAR r,g,b: UNSIGNED32;
		BEGIN
			r := 0; g := 0; b := 0; 
			IF count <= 0 THEN 
				r := 255;
			ELSIF count < 256 THEN 
				r := 255 - count;
				g := count;
			ELSIF count < 512 THEN
				g := 255 - count MOD 256;
				b := count MOD 256;
			ELSE
				b := 255;
			END; 
			pwm << Red;
			pwm << r*100H;
			pwm << Green;
			pwm << g*100H;
			pwm << Blue;
			pwm << b*100H; 
		END CountToColor;
	BEGIN
		count := 0;
		LOOP
			count := count + 1;
			CountToColor(count DIV 1000H MOD 200H); 
		END;
	END PWMTester; 
	
	(*
		PWMTester-> Pwm
	*)
	Network* = CELLNET
	VAR
		pwmTester: PWMTester;
		pwm: Engines.Pwm;
	BEGIN
		NEW(pwmTester);
		NEW(pwm); 
		CONNECT(pwmTester.pwm,pwm.input); 
	END Network; 	

END PWMTest.
