MODULE Tuner;

IMPORT 
	Engines;

TYPE
	(* a cell to drive a pitch detection on a sampled bias corrected signal from i2s *)
	PitchDetector=CELL: Engines.TRM {InstructionWidth=16,CodeMemorySize=512,DataMemorySize=256} (i2s: PORT IN; uartOut: PORT OUT;uartIn: PORT IN; colorOut: PORT OUT);

		PROCEDURE DecimalDigits(number: UNSIGNED32);
		VAR next: UNSIGNED32; 
		BEGIN
			IF number > 9 THEN
				next := number DIV 10;
				DecimalDigits(next);
				number := number - next*10;
			END; 
			uartOut << ORD('0') + number;
		END DecimalDigits;		
	
		PROCEDURE DecimalNumber(number: SIGNED32);
		BEGIN
			IF number < 0 THEN 
				uartOut << ORD("-");
				number := -number;
			END;
			DecimalDigits(number);
			uartOut << 0DX;
			uartOut << 0AX;
		END DecimalNumber;
				
	BEGIN 
			VAR data, sum, count, prev: SIGNED32; 
			LOOP
			sum := 0; 
			prev := 0; 
			FOR count := 1 TO 2048 DO
				data << i2s;
				data := SHL(data,8); (* signed 32 bit number *)
				IF (prev > 0) # (data > 0) THEN
					INC(sum); 
				END; 
				prev := data;
			END; 
			sum := sum * 20000 DIV 2048 DIV 2;
			DecimalNumber(sum); 
			colorOut << (sum - 440) * 4;
			END; 
			
	END PitchDetector; 

	(* component to output a color ranging from red (input << 0) over green (input << 0x100) to red(input << 0x200) *)
	RainbowColor = CELL : Engines.TRM {InstructionWidth=16,CodeMemorySize=256,DataMemorySize=256}  (input: PORT IN; pwm: PORT OUT);
	CONST
		Blue = 1;
		Green = 2;
		Red = 4;
		
		PROCEDURE ToColor(value: SIGNED32);
		VAR r,g,b: UNSIGNED32;
		BEGIN
			r := 0; g := 0; b := 0; 
			IF value <= 0 THEN 
				r := 255;
			ELSIF value < 256 THEN 
				r := 255 - value;
				g := value;
			ELSIF value < 512 THEN
				g := 255 - value MOD 256;
				b := value MOD 256;
			ELSE
				b := 255;
			END; 
			pwm << Red;
			pwm << r*100H;
			pwm << Green; 
			pwm << g*100H;
			pwm << Blue;
			pwm << b*100H;
		END ToColor;
	BEGIN
		VAR value: SIGNED32;
		LOOP
			value << input;
			ToColor(value + 256);
		END; 			
	END RainbowColor; 
	
	(* input --> RainbowColor *)
	RGB = CELLNET (input: PORT IN)
	VAR pwm: Engines.Pwm;
	VAR colorOut: RainbowColor;
	BEGIN
		NEW(pwm); 
		NEW(colorOut);
		DELEGATE(input,colorOut.input);
		CONNECT(colorOut.pwm, pwm.input); 
	END RGB; 

	(* output <-- biasCorrector <-- sampler <-- i2s *)
	I2SSampler = CELLNET (output: PORT OUT);
	VAR 
		i2s: Engines.I2S;
		sampler: Engines.Sampler; 
	BEGIN
		NEW( i2s );
		NEW( sampler ); 
		CONNECT(i2s.output, sampler.input);
		DELEGATE(output, sampler.output); 
	END I2SSampler; 


	(* 
		PitchDetector 
			<- I2SSampler
			<- rx
			-> tx
			-> RGB
	*)
	Network* = CELLNET
	VAR
		detector: PitchDetector;
		tx : Engines.UartTx;
		rx: Engines.UartRx;
		sampler: I2SSampler; 
		rgb: RGB;
	BEGIN
		(*toplevel cellnet definition*)
		NEW( detector );
		NEW( tx {ClkDivisorWidth=16, InitClkDivisor=434, CtsPortUnused=1});
		NEW( rx {ClkDivisorWidth=16, InitClkDivisor=434, RtsPortUnused=1});
		NEW( rgb ); 
		NEW( sampler ); 
		CONNECT(detector.uartOut, tx.input);
		CONNECT(rx.output,detector.uartIn,8);
		CONNECT(sampler.output, detector.i2s); 
		CONNECT(detector.colorOut, rgb.input, 1); 
	END Network;

END Tuner.


