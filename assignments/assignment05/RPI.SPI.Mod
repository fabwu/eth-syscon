MODULE SPI; (* Raspberry Pi 2 SPI Interface -- Polling *)

IMPORT Platform, Kernel;

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
	END SetGPIOs;
	
	PROCEDURE Init*;
	BEGIN
	END Init;
	
	PROCEDURE Write*(CONST a: ARRAY OF CHAR);
	VAR i,junk: INTEGER;
	BEGIN
	END Write;

BEGIN
	SetGPIOs;
END SPI.
