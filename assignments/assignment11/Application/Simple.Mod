MODULE Simple;

IMPORT 
	Engines;

TYPE
	(* a component to receive and send data from uart *)
	InOut= CELL: Engines.TRM {InstructionWidth=16,CodeMemorySize=512,DataMemorySize=256} 
		(uartIn: PORT IN; uartOut: PORT OUT; in: PORT IN; out: PORT OUT);
	
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
		
		PROCEDURE InHexNumber(): INTEGER;
		VAR value, digit: INTEGER;
		BEGIN
			value := 0; 
			LOOP
				digit << uartIn;
				uartOut << digit; (* echo *)
				IF (digit >= ORD('0')) & (digit <= ORD('9')) THEN
					DEC(digit, ORD('0'))
				ELSIF (digit >= ORD('a')) & (digit <= ORD('f')) THEN
					DEC(digit,ORD('a')-10)
				ELSE
					RETURN value
				END;
				value := value * 0x10 + digit;
			END;
		END InHexNumber;
		
	BEGIN
		VAR value: INTEGER;
		LOOP 
			out << InHexNumber();
			value << in;
			OutHexNumber(value); 
		END;
	END InOut; 

	Sum*= CELL : Engines.TRM {InstructionWidth=16,CodeMemorySize=256,DataMemorySize=256}  
			(in: PORT IN; out: PORT OUT);
	BEGIN
		VAR value,sum := 0: INTEGER;
		LOOP
			value << in;
			INC(sum, value);
			out << sum;
		END
	END Sum;

	SimpleNetwork* = CELLNET
	VAR 
		sum: Sum; inOut: InOut; 
		tx : Engines.UartTx;
		rx: Engines.UartRx;
	BEGIN
		NEW( tx {ClkDivisorWidth=16, InitClkDivisor=434, CtsPortUnused=1});
		NEW( rx {ClkDivisorWidth=16, InitClkDivisor=434, RtsPortUnused=1});
		NEW(sum); 
		NEW(inOut); 
		CONNECT(rx.output, inOut.uartIn,8); 
		CONNECT(inOut.uartOut, tx.input,8); 
		CONNECT(sum.out, inOut.in,8); 
		CONNECT(inOut.out, sum.in,8);
	END SimpleNetwork; 
	
END Simple.


