MODULE MAX7219; (** MAX 7219 driver and test module *)

IMPORT Platform, Log, Kernel, SPI, Minos;

CONST
	NoOp = 0;
	Digits = 1;
	DecodeMode = 09H; NoDecode = 0; CodeB = 0FFH;
	Intensity = 0AH; 
	ScanLimit = 0BH;
	Shutdown = 0CH; NormalOperation = 1; ShutdownMode = 0;
	DisplayTest = 0FH; Test=1; NoTest=0;
	
	PROCEDURE Write2*(a1, a2: INTEGER);
	VAR arr: ARRAY 2 OF CHAR;
	BEGIN
		arr[0] := CHR(a1); 
		arr[1] := CHR(a2);
		SPI.Write(arr);
	END Write2;
	
	PROCEDURE HexDigit(at: INTEGER; n: SIZE);
	CONST digits = [0x7e, 0x30, 0x6d, 0x79, 0x33, 0x5b, 0x5f, 0x70, 0x7f, 0x7b, 0x77, 0x1f, 0x4e, 0x3d, 0x4f, 0x47]; 
	BEGIN
		Write2(Digits+at, digits[n]);
	END HexDigit;
	
	PROCEDURE HexDigits(n: SIZE);
	VAR j: INTEGER;
	BEGIN
		Write2(DecodeMode, NoDecode);
		FOR j := 0 TO 7 DO
			HexDigit(j, n MOD 10H);
			n := n DIV 10H;
		END;
	END HexDigits;
	
	PROCEDURE Loop*;
	VAR i,j: INTEGER;
	BEGIN
		SPI.Init;
		Write2(Shutdown, NormalOperation); (* normal operation *)
		Write2(DisplayTest, NoTest); (* no test mode *)
		Write2(DecodeMode, NoDecode); 
		Write2(ScanLimit, 7);
		FOR j := 0 TO 100000 DO
			HexDigits(j);
		END;
		Write2(Shutdown, ShutdownMode); (* shutdown *)
	END Loop;
	
	PROCEDURE TestMode*;
	BEGIN
		SPI.Init;
		Write2(DisplayTest,Test);
	END TestMode;

	PROCEDURE NormalMode*;
	BEGIN
		SPI.Init;
		Write2(DisplayTest,NoTest);
	END NormalMode;

	PROCEDURE Update(me: Minos.Task);
	BEGIN
			HexDigits(Kernel.GetOSTimer());
	END Update;
	
	PROCEDURE InstallTask*;
	VAR task: Minos.PeriodicTask;
	BEGIN
		SPI.Init;
		Write2(Shutdown, NormalOperation); (* normal operation *)
		Write2(DisplayTest, NoTest); (* no test mode *)
		Write2(DecodeMode, NoDecode); 
		Write2(ScanLimit, 7);
		NEW(task); 
		Minos.InstallPeriodicTask(task, Update, "Timer on Max", 20, 0);
	END InstallTask;
	
END MAX7219.


