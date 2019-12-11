MODULE SoundSampler;

IMPORT 
	Engines;

TYPE
	(* a component to receive data from i2s and stream data to uart *)
	Streamer= CELL: Engines.TRM {InstructionWidth=16,CodeMemorySize=512,DataMemorySize=256} (i2s: PORT IN; uartIn: PORT IN; uartOut: PORT OUT; led: PORT OUT);
	
		PROCEDURE OutHexDigits(number: UNSIGNED32);
		BEGIN
			IF number > 0xF THEN
				OutHexDigits(number DIV 0x10)
			END; 
			number := number MOD 0x10;
			IF number < 0xA THEN
				uartOut << ORD('0') + number;
			ELSE
				uartOut << ORD('A')-10 + number;
			END;			
		END OutHexDigits;		
	
		PROCEDURE OutHexNumber(number: SIGNED32);
		BEGIN
			IF number < 0 THEN 
				uartOut << ORD("-");
				number := -number;
			END;
			OutHexDigits(number);
			uartOut << 0DX;
			uartOut << 0AX;
		END OutHexNumber;
		
		PROCEDURE OutRawNumber(data: SIGNED32);
		BEGIN
				uartOut << data;
				uartOut << data DIV 100H;
				uartOut << data DIV 10000H;
				uartOut << data DIV 1000000H;
		END OutRawNumber;
		
	BEGIN
		VAR data, number,i: SIGNED32;
		LOOP
			led << 0; 
			REPEAT
				IF ~(number <<? uartIn) THEN 
					number := 0 
				END; 
			UNTIL number = 0x30; (* "0" start sending *)
			led << 1;

			i := 0;
			WHILE (i<8192) DO
				data << i2s;
				OutRawNumber(data);
				INC(i);
			END;
		END;
	END Streamer; 


	SerialConnection*=CELLNET (receiver: PORT OUT; sender: PORT IN)
	VAR
		tx : Engines.UartTx;
		rx: Engines.UartRx;
	BEGIN
		NEW( tx {ClkDivisorWidth=16, InitClkDivisor=434, CtsPortUnused=1});
		NEW( rx {ClkDivisorWidth=16, InitClkDivisor=434, RtsPortUnused=1});
		DELEGATE(receiver, rx.output);
		DELEGATE(sender, tx.input); 	
	END SerialConnection;

	(*
		Streamer
			<- rx
			<- I2S
			-> Gpo
			-> tx
	*)
	Network* = CELLNET
	BEGIN
		(* TODO: build a network connecting the streamer *)
	END Network; 
	
END SoundSampler.


