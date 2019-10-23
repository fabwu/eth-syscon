MODULE UartMin;   (* Author: tt, Purpose: Minimal Log over UART without interrrupts *)

(*@
 DO NOT use DIV, MOD or Real in this module as the floting point emulation might not yet be installed!!!
*)

(* Offsets :
	Serial 1 = Full Function UART: 100000H
	Serial 2 = Bluetooth UART: 200000H
	Serial 3 = Standard UART: 700000H
*)

IMPORT SYSTEM, Platform;  

CONST
	PNONE* = 0;  PODD* = 8;  PEVEN* = 24;  PFORCE1* = 40;  PFORCE0* = 56;  

	(* MinosHost Commands *)
	CommandBase = 4D5B9878H;
	LOG* = CommandBase + 20H;  

	(*LogTypes*)
	LN* = 21X;  STR* = 22X;  CH* = 23X;  INT* = 24X;  HEX* = 25X;  FLOAT* = 26X;  
	SETS* = 27X;  TIME* = 28X;  CLEAR* = 29X;  BUF* = 30X;

TYPE
	FlushProc = PROCEDURE();

VAR 
	(* MinosHost mode or plain text mode *)
	minosHostMode: BOOLEAN;
	flush: FlushProc;

	PROCEDURE RegisterFlushProcedure*( f : FlushProc );  
	BEGIN 
		flush := f;
	END RegisterFlushProcedure;

	PROCEDURE WriteChar- (character: CHAR);
	BEGIN 
		WHILE Platform.TXFF IN Platform.ReadBits (Platform.UART_FR) DO END;
		Platform.WriteWord (Platform.UART_DR, ORD (character));
	END WriteChar;

	PROCEDURE ReadChar- (VAR character: CHAR): BOOLEAN;
	BEGIN
		WHILE Platform.RXFE IN Platform.ReadBits (Platform.UART_FR) DO END;
		character := CHR (Platform.ReadWord (Platform.UART_DR));
		RETURN TRUE;
	END ReadChar;

	PROCEDURE Flush-;
	BEGIN
		REPEAT UNTIL Platform.TXFE IN Platform.ReadBits (Platform.UART_FR);
	END Flush
	
	PROCEDURE WriteInt(i: INTEGER);
	BEGIN
		WriteChar(CHR(i));
		WriteChar(CHR(i DIV 100H));
		WriteChar(CHR(i DIV 10000H));
		WriteChar(CHR(i DIV 1000000H));
 		 Flush;
	END WriteInt;
	
	PROCEDURE Cmd(cmd: CHAR);
	BEGIN
		IF minosHostMode THEN
			WriteInt(LOG);
			WriteChar(cmd);
		END;
	END Cmd;

	PROCEDURE OpenComPort*( baudrate, parity, databits (* fof *) : INTEGER; flowControl: BOOLEAN );  
	BEGIN 
		Platform.WriteBits (Platform.UART_CR, {}); 
		Platform.ClearBits (Platform.GPPUD, {Platform.PUD}); Platform.Delay (150);
		Platform.SetBits (Platform.GPPUDCLK0, {14, 15}); Platform.Delay (150);
		Platform.WriteBits (Platform.GPPUDCLK0, {});
		Platform.WriteBits (Platform.UART_ICR, {1, 4..10});
		Platform.WriteWord (Platform.UART_IBRD, Platform.FUARTCLK DIV (16 * baudrate));
		Platform.WriteWord (Platform.UART_FBRD, (Platform.FUARTCLK MOD (16 * baudrate)) * 64 DIV (16 * baudrate));
		Platform.WriteBits (Platform.UART_LCRH, Platform.WLEN8);
		Platform.WriteBits (Platform.UART_IMSC, {Platform.RXIM});
		Platform.WriteBits (Platform.UART_CR, {Platform.UARTEN, Platform.TXE, Platform.RXE});
	END OpenComPort;

	PROCEDURE Init*;  
	BEGIN 
		minosHostMode := FALSE;
		flush := NIL;
	END Init;    
	
	PROCEDURE Ln*;
	BEGIN 
		IF minosHostMode THEN
			Cmd(LN);
		ELSE
			WriteChar (0DX); WriteChar (0AX)
		END;
		Flush;
	END Ln;
	
	PROCEDURE Ch* (c: CHAR);
	BEGIN 
		Cmd(CH);
		WriteChar (c); 
	END Ch;
	
	PROCEDURE Str* (CONST text: ARRAY OF CHAR);
	VAR i: SIZE;
	BEGIN
		Cmd(STR);
		i := 0; WHILE (i # LEN (text)) & (text[i] # 0X) DO WriteChar (text[i]); INC (i) END;
		IF minosHostMode THEN WriteChar (0X); END;
	END Str;
	
	PROCEDURE StrLn* (CONST text: ARRAY OF CHAR);
	BEGIN Str (text); Ln;
	END StrLn;
	
	PROCEDURE Hex*( val: INTEGER);  
	VAR 
		i, j: INTEGER;
		digits: ARRAY 36 OF INTEGER;
		str: ARRAY 36 OF CHAR;
	BEGIN
		i := 0; j := 0;
		REPEAT 
(*			digits[i] := val MOD 10H;  INC( i );  val := val DIV 10H; UNTIL val = 0;   *)
			digits[i] := val MOD 10H;  INC( i );  val := LSH(val, -4); UNTIL val = 0;
		DEC( i );
		WHILE i >= 0 DO
			IF digits[i] > 9 THEN 
				str[j] := CHR( digits[i] - 10 + ORD( 'A' ) );  
			ELSE
				str[j] := CHR( digits[i] + ORD( '0' ) );  
			END;
			INC( j );  DEC( i ) 
		END;
		str[j] := 0X;  

		Str(str);
	END Hex;

(*	PROCEDURE Int* (val: LONGINT);
	BEGIN Value (val, 10)
	END Int;

	PROCEDURE Bits* (val: SET);
	BEGIN HexValue (SYSTEM.VAL (LONGINT, val), 2);
	END Bits;
*)
	PROCEDURE Bool* (bol: BOOLEAN);
	BEGIN IF bol THEN Str ("TRUE") ELSE Str ("FALSE") END
	END Bool;
	
	PROCEDURE Mem* (adr: ADDRESS; size: SIZE);
	VAR b: CHAR; i: SIZE;
	BEGIN
		WHILE size # 0 DO
			Hex (adr); Ch (20X);
			IF size > 8 THEN i := 8 ELSE i := size END;
			REPEAT
				SYSTEM.GET (adr, b);
				Hex(ORD(b) DIV 10H);
				Hex (ORD (b) MOD 10H);
				Ch (20X); INC (adr); DEC (i); DEC (size);
			UNTIL i = 0;
			Ln;
		END;
	END Mem;

	PROCEDURE Set* (val: SET);
	VAR i: INTEGER; comma: BOOLEAN;
	BEGIN
		Ch ('{'); i := 0; comma := FALSE;
		WHILE i # 32 DO
			IF i IN val THEN
				IF comma THEN Str (", ") ELSE comma := TRUE END;
				IF i >= 10H THEN Hex(i DIV 10H) END; 
				Hex (i MOD 10H);
			END; 
			INC (i)
		END;
		Ch ('}');
	END Set;

	PROCEDURE MinosHostMode*(minosMode: BOOLEAN);
	BEGIN
		Ln;
		IF minosMode & (flush # NIL) THEN flush(); END;
		Flush();
		minosHostMode := minosMode;
	END MinosHostMode;
	

BEGIN
	Init;
	OpenComPort( 115200, PNONE, 8, FALSE );
	StrLn("UartMin.");
END UartMin.