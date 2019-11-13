MODULE SPI; (* Raspberry Pi 2 SPI Interface -- Polling *)
(* SPI interface 0 version *)

IMPORT Platform, Kernel;

CONST
	SELECT = {8};
	Select1 = {7};
	MISO = {9};
	MOSI = {10};
	CLOCK = {11};
	HalfClock = 20; (* microseconds -- very conservative*)
VAR
	
	PROCEDURE SetGPIOs;
	BEGIN
		(* pin 7 : spi select 1 *)
		(* pin 8 : spi select 0 *)
		(* pin 9 : spi MISO *)
		(* pin 10 : spi MOSI *)
		(* pin 11 : spi clock *)
		Platform.ClearAndSetBits(Platform.GPFSEL0, {21..29},{21,24}); (* direct write control for GPIO pins 7, 8, no control MISO *)
		Platform.ClearAndSetBits(Platform.GPFSEL1, {0..5},{0,3}); (* direct write control for GPIO pins 10 and 11 *)
	END SetGPIOs;

	PROCEDURE Init*;
	BEGIN
		Platform.WriteBits(Platform.GPCLR0, CLOCK); (* clock down *)
		Platform.WriteBits(Platform.GPCLR0, SELECT); (* one empty frame *)
		Kernel.MicroWait(HalfClock);
		Platform.WriteBits(Platform.GPSET0, SELECT); (* active low -> set bit when idle *)
	END Init;
	
	PROCEDURE WriteByte(ch:CHAR);
	VAR i, n, s: INTEGER;
	BEGIN
		FOR i := 7 TO 0 BY -1 DO
			(* set bit *) 
			n := ORD(ch);
			s := -i;
			IF ASH(n,s) MOD 2 = 1 THEN
				Platform.WriteBits(Platform.GPSET0, MOSI);
			ELSE
				Platform.WriteBits(Platform.GPCLR0, MOSI);
			END;
			Kernel.MicroWait(HalfClock);
			Platform.WriteBits(Platform.GPSET0, CLOCK); (* clock up *)
			Kernel.MicroWait(HalfClock);
			Platform.WriteBits(Platform.GPCLR0, CLOCK); (* clock down *)
		END;
		
	END WriteByte;
	
	PROCEDURE Write*(CONST a: ARRAY OF CHAR);
	VAR i: SIZE;
	BEGIN
		Kernel.MicroWait(HalfClock);
		Platform.WriteBits(Platform.GPCLR0, SELECT); (* signal select *)
		
		Kernel.MicroWait(HalfClock);

		FOR i := 0 TO LEN(a)-1 DO
			WriteByte(a[i]);
		END;
		
		Kernel.MicroWait(HalfClock);

		Platform.WriteBits(Platform.GPSET0, SELECT); (* signal deselect *)
	END Write;

BEGIN
	SetGPIOs;
END SPI.
