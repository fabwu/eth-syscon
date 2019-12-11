MODULE Candle;

IMPORT 
	Engines;

TYPE 

	(* a toy component that switches off an LED (the "candle") when microphone reports sound with high amplitude (e.g. when blowing on the microphone)
			"candle" slowly lights up again after some time period.
	*)
	CandleCell= CELL: Engines.TRM {InstructionWidth=16,CodeMemorySize=256,DataMemorySize=256} (i2s: PORT IN; pwm: PORT OUT);
	VAR data,brightness,count: SIGNED32; 
	CONST Blue = 1; Green = 2; Red = 4;
	BEGIN
		LOOP
			data << i2s; (* receive 24 bit (signed) data *)
			data := SHR(SHL(data,8),14); (* extend to 32 bit, then strip to 18 bit precision *)
			IF data > 256 THEN
				(* TODO: switch off LEDs, reset counter *)
			END; 
			(* TODO: if counter reaches certain value, switch on LED *)
			(* OPTIONAL: ramp up LED brightness slowly *)
			INC(count); 
		END;
	END CandleCell; 
	
	(*
		CandleCell
			<- I2S
			-> pwm
	*)
	Network*= CELLNET;
	VAR i2s: Engines.I2S;
			 pwm: Engines.Pwm;
			 candle: CandleCell;
	BEGIN
		NEW(i2s);
		NEW(pwm); 
		NEW(candle);
		CONNECT(i2s.output, candle.i2s); 
		CONNECT(candle.pwm, pwm.input);
	END Network;

END Candle.

