MODULE SPI; (* Raspberry Pi 2 SPI Interface -- Polling *)

IMPORT Platform, Kernel, Log;

CONST
	(* CS register flags *)
	LEN_LONG=25;
	DAM_LEN = 24;
	CSPOL2 = 23;
	CSPOL1 = 22;
	CSPOL0 = 21;
	RXF = 20;
	RXR = 19;
	TXD = 18;
	RXD = 17;
	DONE = 16;
	SLEN = 13;
	REN = 12;
	ADCS = 11;
	INTR = 10;
	INTD = 9;
	DMAEN = 8;
	TA = 7;
	CSPOL = 6;
	CLEAR_RX = 4;
	CLEAR_TX = 5;
	CPOL = 3;
	CPHA = 2; 
	CS = 1;
	
	APBfrequency = 250000000;

	PROCEDURE SetGPIOs;
	BEGIN
		Platform.ClearAndSetBits(Platform.GPFSEL0, {21..29},{23,26,29}); (* alternate function 0 for GPIO pins 7, 8, 9 *)
		Platform.ClearAndSetBits(Platform.GPFSEL1, {0..5},{2,5}); (* alternate function 0 for GPIO pins 10 and 11 *)
	END SetGPIOs;
	
	(* simplified setup for MAX7219 *)
	PROCEDURE Init*;
	BEGIN
		Log.Int(Platform.ReadWord(Platform.SPI_CS));
		Platform.WriteWord(Platform.SPI_CLK, 1024);
		Platform.WriteBits(Platform.SPI_CS, {CLEAR_RX, CLEAR_TX}); (* select active low, polarity reset lo, phase 0 *)
	END Init;

	(* generic version 
	PROCEDURE Init*(frequency: INTEGER; selectActiveHigh, clkPolarityRestHigh, clkPhaseBeginning: BOOLEAN);
	VAR 
		divider: INTEGER;
		mask: SET;
	BEGIN
		(* Core clock = APB clock runs at 250 MHz = max fequency of SPI bus. Max SPI frequency 125 MHz *)
		IF frequency >= APBfrequency DIV 2 THEN divider := 2
		ELSIF frequency <= APBfrequency DIV 65536 THEN divider := 0
		ELSE divider := APBfrequency DIV frequency;
		END;
		Platform.WriteWord(Platform.SPI_CLK, divider );
		mask := {};
		IF selectActiveHigh THEN INCL(mask, CSPOL); INCL(mask, CSPOL0); END;
		IF clkPolarityRestHigh THEN INCL(mask, CPOL) END;
		IF clkPhaseBeginning THEN INCL(mask, CPHA) END;
		Platform.WriteBits(Platform.SPI_CS, mask);
		Platform.SetBits(Platform.SPI_CS, {CLEAR_RX, CLEAR_TX}); 
	END Init;
	*)
	
	
	PROCEDURE Write*(CONST a: ARRAY OF CHAR);
	VAR i: SIZE; junk: INTEGER;
	BEGIN
		Platform.SetBits(Platform.SPI_CS, {TA}); (* start transition: set select signal *)
		
		FOR i := 0 TO LEN(a)-1 DO
			REPEAT UNTIL TXD IN Platform.ReadBits(Platform.SPI_CS);
			Platform.WriteWord(Platform.SPI_FIFO, ORD(a[i]));
			junk := Platform.ReadWord(Platform.SPI_FIFO);
		END;
		
		REPEAT UNTIL DONE IN Platform.ReadBits(Platform.SPI_CS);
		Platform.ClearBits(Platform.SPI_CS, {TA}); (* transfer inactive, reset signal *)
	END Write;

BEGIN
	SetGPIOs;
END SPI.
