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
		Platform.ClearAndSetBits(Platform.GPFSEL0, 
			{Platform.FSEL7 .. Platform.FSEL7+2},
			{Platform.FSEL7 + 2}
		);
		Platform.ClearAndSetBits(Platform.GPFSEL0, 
			{Platform.FSEL8 .. Platform.FSEL8+2},
			{Platform.FSEL8 + 2}
		);
		Platform.ClearAndSetBits(Platform.GPFSEL0, 
			{Platform.FSEL9 .. Platform.FSEL9+2},
			{Platform.FSEL9 + 2}
		);
		Platform.ClearAndSetBits(Platform.GPFSEL1, 
			{Platform.FSEL10 .. Platform.FSEL10+2},
			{Platform.FSEL10 + 2}
		);		
		Platform.ClearAndSetBits(Platform.GPFSEL1, 
			{Platform.FSEL11 .. Platform.FSEL11+2},
			{Platform.FSEL11 + 2}
		);
	END SetGPIOs;
	
	PROCEDURE Init*;
	BEGIN
		(* Set clock speed *)
		Platform.WriteWord(Platform.SPI_CLK, 32);
		
		(* Clear buffers and set rest to zero *)
		Platform.WriteBits(Platform.SPI_CS, {CLEAR_RX,CLEAR_TX});


	END Init;
	
	PROCEDURE Write*(CONST a: ARRAY OF CHAR);
	VAR 
		i,junk: INTEGER;
	BEGIN
		(* Set TA bit *)
		Platform.SetBits(Platform.SPI_CS, {TA});

		WHILE ~(TXD IN Platform.ReadBits(Platform.SPI_CS)) DO
			Kernel.MilliWait(1);
		END;

		FOR i := 0 TO LEN(a) - 1 DO
			Platform.WriteWord(Platform.SPI_FIFO, ORD(a[i]));
			WHILE RXD IN Platform.ReadBits(Platform.SPI_CS) DO
			junk := Platform.ReadWord(Platform.SPI_FIFO);
			END;
		END;

		WHILE ~(DONE IN Platform.ReadBits(Platform.SPI_CS)) DO
			Kernel.MilliWait(1);
		END;
		
		Platform.ClearBits(Platform.SPI_CS, {TA});
	END Write;

BEGIN
	SetGPIOs;
END SPI.
