MODULE Uart;   (* Interrupt driven UARTs driver for RPI *)

IMPORT Platform, SYSTEM, Kernel, Device, UartMin;

CONST 
	(* Size of UART buffer *)
	UARTBufLen* = 3000;

	UART0 = 0;  

	PNONE* = 0;  PODD* = 8;  PEVEN* = 24;  PFORCE1* = 40;  PFORCE0* = 56;  

TYPE 
	(* UART stuff *)
	UARTBuffer = ARRAY UARTBufLen OF SYSTEM.BYTE;  
	UartDesc* = RECORD (Device.DeviceDesc)
		id: SIZE;
		in, out, oin, oout: SIZE;   (* And and Out index in in (in, out) and outbuffer (oin, oout) *)
		open: BOOLEAN;   (* Is the uart already initialised and open? *)
		inbuffer, outbuffer: UARTBuffer   (* receive and sendbuffer *)
	END;  
	Uart* = POINTER TO UartDesc;  

VAR 
	uarts: ARRAY Platform.NUMCOMPORTS OF Uart;
	
	PROCEDURE Close( dev: Device.Device );  
	BEGIN 
		IF dev( Uart ).open = TRUE THEN 
			Platform.ClearBits(Platform.UART_CR, {Platform.UARTEN});
			Kernel.EnableIRQ( Platform.UartInstallIrq, FALSE );  
			dev( Uart ).open := FALSE;  
		END;  
	END Close;  

(* Bytes available for read *)
	PROCEDURE Available( dev: Device.Device ): SIZE;  
	BEGIN 
		RETURN (dev( Uart ).in - dev( Uart ).out) MOD UARTBufLen
	END Available;  

(* Get the number of bytes that are free in the send buffer *)
	PROCEDURE Free( dev: Device.Device ): SIZE;  
	VAR avail: SIZE;  
	BEGIN 
		avail := 0;  
		(* The last byte in the buffer cannot be used, as the oin and out pointer would point to the same location
		 which means that the buffer is empty *)
		avail :=  UARTBufLen - 1 - ((dev( Uart ).oin - dev( Uart ).oout) MOD UARTBufLen);  
		RETURN avail
	END Free;  

	PROCEDURE EnableTXInterrupt( dev: Uart;  enable: BOOLEAN );  
	BEGIN 
		IF enable THEN 
			Platform.SetBits(Platform.UART_IMSC, {Platform.TXIM});
		ELSE
			Platform.ClearBits(Platform.UART_IMSC, {Platform.TXIM}); 
		END;
	END EnableTXInterrupt;  
	
	PROCEDURE Write( dev: Device.Device;  CONST buf: ARRAY OF SYSTEM.BYTE;  
									 ofs: SIZE;  VAR len: SIZE );  
	VAR end, free: SIZE;  uart: Uart;  
	BEGIN 
		IF (len > 0) & (ofs >= 0) THEN 
			uart := dev( Uart );  free := Free( dev );  
			IF free < len THEN len := free;  END;  
			
			end := ofs + len;  
			WHILE ofs < end DO 
				uart.outbuffer[uart.oin] := buf[ofs];  
				uart.oin := (uart.oin + 1) MOD UARTBufLen;  
				INC( ofs );  
			END;  
			EnableTXInterrupt( uart, TRUE ); 
		ELSE len := 0;  
		END;  
	END Write;  

	PROCEDURE Read( dev: Device.Device;  VAR buf: ARRAY OF SYSTEM.BYTE;  
									 ofs: SIZE;  VAR len: SIZE );  
	VAR end, available: SIZE;  uart: Uart; 
	BEGIN 
		IF (len > 0) & (ofs >= 0) THEN 
			uart := dev( Uart );  available := Available( dev );  
			IF available < len THEN len := available;  END;  
			
			end := ofs + len;  
			WHILE ofs < end DO 
				buf[ofs] := uart.inbuffer[uart.out];  
				uart.out := (uart.out + 1) MOD UARTBufLen;  
				INC( ofs );  
			END;  
		ELSE 
			len := 0;
		END;
	END Read;  

	PROCEDURE Flush( dev: Device.Device );  
	BEGIN 
		REPEAT UNTIL Free( dev( Uart ) ) = UARTBufLen - 1;  (* writing  done *)
	END Flush;  

(* Copy the data from the UART into the OS buffer *)
	PROCEDURE EmptyFIFO( dev: Uart );  
	VAR used: SIZE;  character: CHAR;  
	BEGIN 
		used := (dev.in - dev.out) MOD UARTBufLen;  
		WHILE ~(Platform.RXFE IN Platform.ReadBits (Platform.UART_FR)) DO 
			character := CHR (Platform.ReadWord (Platform.UART_DR));
			IF used < UARTBufLen - 1 THEN (* drop data when buffer is full *)
				dev.inbuffer[dev.in] := character;
				dev.in := (dev.in + 1) MOD UARTBufLen;
				INC( used );  
			END;  
		END;
	END EmptyFIFO;  

	(* Fill UART FIFO *)
	PROCEDURE FillFIFO( dev: Uart );  
	VAR i: SIZE;  break: BOOLEAN;  
	BEGIN 
		i := 0;  break := FALSE;  
		WHILE ~(Platform.TXFF IN Platform.ReadBits (Platform.UART_FR)) & (dev.oin # dev.oout) DO
			Platform.WriteWord (Platform.UART_DR, ORD (dev.outbuffer[dev.oout]));
			dev.oout := (dev.oout + 1) MOD UARTBufLen;  
		END;
	END FillFIFO;  

	PROCEDURE Command( dev: Device.Device;  cmd, param: INTEGER;  VAR res: INTEGER );  
	VAR uart: Uart;  
	BEGIN 
		uart := dev( Uart );  res := 0;  
	END Command;  

	PROCEDURE OpenComPort*( uart:Uart; baudrate, parity, databits (* fof *) : INTEGER;  
													   flowControl: BOOLEAN );  
	BEGIN 
		IF (uart # NIL ) & (~uart.open) THEN 
			Platform.WriteBits(Platform.UART_CR, {}); (* enable uart *)
			Platform.WriteWord (Platform.UART_IBRD, Platform.FUARTCLK DIV (16 * baudrate));
			Platform.WriteWord (Platform.UART_FBRD, (Platform.FUARTCLK MOD (16 * baudrate)) * 64 DIV (16 * baudrate));
			Platform.WriteBits (Platform.UART_LCRH, Platform.WLEN8+{Platform.FEN});
			Platform.WriteBits (Platform.UART_IMSC, {Platform.RXIM, Platform.RTIM});
			Platform.WriteBits (Platform.UART_CR, {Platform.UARTEN, Platform.TXE, Platform.RXE});
			Kernel.EnableIRQ( Platform.UartInstallIrq , TRUE );
		END 
	END OpenComPort;  

	PROCEDURE Open( dev: Device.Device );  
	BEGIN 
		OpenComPort( dev(Uart), 115200, PNONE, 8, FALSE );  
	END Open;  

	PROCEDURE UARTHandler( uart: Uart );  
	VAR pending: SET;
	BEGIN 
		pending := Platform.ReadBits(Platform.UART_MIS);
		IF (Platform.RXMIS IN pending) OR (Platform.RTIM IN pending) THEN
			EmptyFIFO( uart );  
		END;
		IF Platform.TXMIS IN pending THEN
			FillFIFO( uart );  
			IF uart.oin = uart.oout THEN  (* no more data -> disable Tx interrupts *)
				EnableTXInterrupt( uart, FALSE );  
			END;
		END;
		Kernel.EnableIRQ( Platform.UartInstallIrq , TRUE );   (* was switched off by IRQ Handler *)
	END UARTHandler;  
	
	PROCEDURE UartHandler0;  
	BEGIN 
		UARTHandler( uarts[UART0] );  
	END UartHandler0;  
		
	PROCEDURE InitUART( );  
	VAR i: SIZE;  uart: Uart;  
	BEGIN 
		FOR i := 0 TO Platform.NUMCOMPORTS - 1 DO
			NEW( uarts[i] );
		END;  
		
		FOR i := 0 TO Platform.NUMCOMPORTS - 1 DO 
			uart := uarts[i];  
			uart.in := 0;  uart.out := 0;  uart.oin := 0;  uart.oout := 0;  
			uart.open := FALSE;  			
		END;  
	END InitUART;  

	PROCEDURE SetTrapMode*(enable: BOOLEAN);
	BEGIN
		
	END SetTrapMode;
	
	PROCEDURE Install*;  
	VAR i: SIZE;  
	BEGIN 
		FOR i := 0 TO Platform.NUMCOMPORTS - 1 DO 
			Device.InitDevice( uarts[i] );  
			uarts[i].Close := Close;  uarts[i].Write := Write;  uarts[i].Read := Read;  
			uarts[i].Available := Available;  uarts[i].Free := Free;  
			uarts[i].Command := Command;  uarts[i].Flush := Flush;  
			uarts[i].Open := Open;  
			uarts[i].id := i;  
		END;  
		
		Kernel.InstallIrqHandler(Platform.UartEffectiveIrq , UartHandler0);
		Device.Install( uarts[UART0], "UART" );  
	END Install;  

BEGIN
	InitUART;  
	Install;  
END Uart.