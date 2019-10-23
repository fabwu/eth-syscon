MODULE Kernel; (*The Kernel for Raspberry Pi. (c) Felix Friedrich 2015 *)

	IMPORT SYSTEM, Platform, UartMin;

	CONST
		kVersion* = "B007";

		(* constants for memory mapping *)
		Section = 2H; Domain0 = 0H; FullAccess = 0C00H; NormalWriteBackAllocate = 100CH; StronglyOrdered = 0H; Shareable = 10000H;
		NormalMemory = Section + Domain0 + FullAccess + NormalWriteBackAllocate + Shareable;
		StronglyOrderedMemory = Section + Domain0 + FullAccess + StronglyOrdered;
		MB = 1024 * 1024;
		
		Timer = Platform.STC1; (* can use timer STC1 or 3 *)
		TimerNr = 1; (* can use 1 or 3 on ARM, timer 0 and 2 are used for the GPU *)

	TYPE

		(* The prototype of an interrupt handler *)
		ExceptionHandler* = PROCEDURE {INTERRUPT} ( );

		(* The prototype of an interrupt handler *)
		Handler* = PROCEDURE();

		(* The prototype of a timer interrupt handler
			should be used to implement the scheduler *)
		TimerHandler* = PROCEDURE();

		(* The prototype of a trap handler
			As soon as the systen is up and running, a custom trap handler can be install *)
		TrapHandler* = PROCEDURE(type, adr, fp: ADDRESS; VAR resFP: ADDRESS);

		(* The prototype of a undefined instruction trap handler
			Can be used to decode custom instructions *)
		UDFHandler* = PROCEDURE(adr: ADDRESS);

	VAR
		(* the time, when the next timer interrupt shall occur *)
		nextTimerInterrupt: SIZE;

		(* main irq handlers *)
		irqHandlers: ARRAY Platform.MaxNumIrq OF Handler;

		(* The system time in milliseconds. Is updated by the primary timer interrupt
			handler *)
		timer: SIZE;

		(* User installable handlers for timer, traps and Udefinded instruction traps *)
		timerHandler: TimerHandler; trapHandler: TrapHandler;
		udfHandler: UDFHandler;

		(* Temporary variable that stores the lnk register. Must be a global variable to be
			accessible in all processor modes *)
		lnk: PROCEDURE;
		globalLR: ADDRESS;

	(*! STUDENT
		you may want to add global variables for the current state of stack / heap allocation 
	*)
	(* Address of the last valid stack / heap page*)
	lastValidStackPage, lastValidHeapPage: ADDRESS;


	(* Copy procedure like SYSTEM.MOVE. src and dst must be Aligned to 32 bit addresses *)
	PROCEDURE Move*(src, dst: ADDRESS; len: SIZE);
	VAR i, word: SIZE; chr: CHAR;
	BEGIN
		IF len > 0 THEN
			(* Copy Integerwise if possible *)
			IF (src MOD 4 # 0) OR (dst MOD 4 # 0) THEN
				WHILE len > 0 DO
					SYSTEM.GET(src, chr); SYSTEM.PUT(dst, chr);
					INC(src); INC(dst); DEC(len);
				END;
			ELSE
				i := len DIV 4;
				WHILE i > 0 DO
					SYSTEM.GET(src, word); SYSTEM.PUT(dst, word);
					INC(src, 4); INC(dst, 4); DEC(i);
				END;

				i := len MOD 4;
				WHILE i > 0 DO
					SYSTEM.GET(src, chr); SYSTEM.PUT(dst, chr);
					INC(src); INC(dst); DEC(i);
				END;
			END;
		END;
	END Move;

	(* switch off interrupts, if required, and flush and invalidate caches *)
	PROCEDURE CleanCache*();
	VAR irq: BOOLEAN; cpsr: SET32;
	BEGIN
		SYSTEM.STPSR(0, cpsr);
		irq := ~(7 IN cpsr); (* IRQs enabled *)
		IF irq THEN (* DisableIRQs *)
 			SYSTEM.LDPSR(0, cpsr + {7,8});
		END;
		Platform.FlushAndInvalidateDCache;
		Platform.InvalidateICache;
		IF irq THEN (* Enable IRQs *)
 			SYSTEM.LDPSR(0, cpsr);
		END;
	END CleanCache;
	
	(* Globally enable all interrupts *)
	PROCEDURE EnableIRQs*;
	VAR cpsr: SET32;
	BEGIN
		SYSTEM.STPSR(0, cpsr);
		cpsr :=cpsr - {7};
		SYSTEM.LDPSR(0, cpsr)
	END EnableIRQs;

	(* Globally disable all interrupts *)
	PROCEDURE DisableIRQs*;
	VAR cpsr: SET32;
	BEGIN
		SYSTEM.STPSR(0, cpsr);
		cpsr := cpsr + {7, 8};
		SYSTEM.LDPSR( 0, cpsr)
	END DisableIRQs;

	(* Enable the periodic system timer(currently 5 ms) *)
	PROCEDURE OSTimer*;
	BEGIN
		Platform.WriteBits (Platform.STCS, {TimerNr}); 
		nextTimerInterrupt := Platform.ReadWord(Platform.STCLO)+Platform.TimerInterval;
		Platform.WriteWord(Timer, nextTimerInterrupt);
		EnableIRQ(Platform.SystemTimerIRQ, TRUE);
	END OSTimer;

	(* Install an IRQ handler *)
	PROCEDURE InstallIrqHandler*(num: SIZE; handler: Handler);
	BEGIN
		DisableIRQs;
		IF(num >= Platform.MinValidIrq) &(num <= Platform.MaxValidIrq) THEN
			irqHandlers[num] := handler;
		END;
		EnableIRQs;
	END InstallIrqHandler;

	(* Remove an IRQ handler *)
	PROCEDURE RemoveIrqHandler*(num: SIZE);
	BEGIN
		DisableIRQs;
		IF(num >= Platform.MinValidIrq) &(num <= Platform.MaxValidIrq) THEN
			irqHandlers[num] := NIL;
		END;
		EnableIRQs;
	END RemoveIrqHandler;

	(* Enable or disable an interrupt *)
	PROCEDURE EnableIRQ*(num: SIZE; enable: BOOLEAN);
	BEGIN
		ASSERT(num >= 0); ASSERT(num < 96);
		IF enable THEN
			IF num < 32 THEN
				Platform.WriteBits(Platform.IRQEnableBasic, {num})
			ELSIF num < 64 THEN
				DEC(num, 32);
				Platform.WriteBits(Platform.IRQEnable1, {num})
			ELSE
				DEC(num, 64); 
				Platform.WriteBits(Platform.IRQEnable2, {num})
			END;
		ELSE
			IF num < 32 THEN
				Platform.WriteBits(Platform.IRQDisableBasic, {num})
			ELSIF num < 64 THEN
				Platform.WriteBits(Platform.IRQDisable1, {num-32})
			ELSE
				Platform.WriteBits(Platform.IRQDisable2, {num-64})
			END;
		END;
	END EnableIRQ;

	(* Register a second level timer handler, usually the Scheduler *)
	PROCEDURE RegisterTimerHandler*(newHandler: TimerHandler);
	BEGIN
		timerHandler := newHandler;
	END RegisterTimerHandler;

	(* Register a Trap handler *)
	PROCEDURE RegisterTrapHandler*(newHandler: TrapHandler);
	BEGIN
		trapHandler := newHandler;
	END RegisterTrapHandler;

	PROCEDURE Timer0IrqHandler( );
	VAR lr: ADDRESS;
	BEGIN
		IF TimerNr IN Platform.ReadBits(Platform.STCS) THEN
			EnableIRQ(Platform.SystemTimerIRQ, TRUE);
			REPEAT
				Platform.WriteBits (Platform.STCS, {TimerNr}); 
				INC(timer, Platform.TimerPeriod);
				INC(nextTimerInterrupt,Platform.TimerInterval);
				Platform.WriteWord(Timer, nextTimerInterrupt);
			UNTIL nextTimerInterrupt - Platform.ReadWord(Platform.STCLO) > 0;


			IF timerHandler # NIL THEN
				(* Context Switch to SVC mode, to save LR  *)
				SYSTEM.LDPSR( 0, Platform.SVCMode + Platform.IRQDisabled + Platform.FIQDisabled);
				globalLR := SYSTEM.LNK();
				SYSTEM.LDPSR( 0, Platform.IRQMode + Platform.IRQDisabled + Platform.FIQDisabled); 
				lr := globalLR;
				(* Enable Interrupts *)
				SYSTEM.LDPSR( 0, Platform.SVCMode );
				(* Execute timer handler (=Scheduler) *)
				timerHandler;
				(* Context Switch to IRQ mode*)
				SYSTEM.LDPSR( 0, Platform.IRQMode + Platform.IRQDisabled + Platform.FIQDisabled); 
				globalLR := lr;
				SYSTEM.LDPSR( 0, Platform.SVCMode + Platform.IRQDisabled + Platform.FIQDisabled);
				SYSTEM.SETLNK(globalLR);
				
				SYSTEM.LDPSR( 0, Platform.IRQMode + Platform.IRQDisabled + Platform.FIQDisabled);
			END;

		END
	END Timer0IrqHandler;
	
	PROCEDURE CallIrq(num: SIZE);
	VAR p: PROCEDURE;
	BEGIN
		p := irqHandlers[num];
		IF p # NIL THEN 
			p;
		ELSE
			UartMin.OpenComPort( 115200, UartMin.PNONE, 8, FALSE );
			UartMin.Str("Unhandled interrupt of "); UartMin.Hex(num); UartMin.StrLn("H"); 
		END;
	END CallIrq;

	(* Primary interrupt handler *)
	PROCEDURE {INTERRUPT, PCOFFSET=4} IRQTrap;
	VAR i, j: SIZE; spsr: SIZE;  basicPending, pending1, pending2: SET;
	BEGIN
		SYSTEM.STPSR( 1, spsr );   (* store SPSR *)
		basicPending := Platform.ReadBits(Platform.IRQBasicPending);
		pending1 := Platform.ReadBits (Platform.IRQPending1);
		pending2 := Platform.ReadBits (Platform.IRQPending2);
		Platform.WriteBits (Platform.IRQDisableBasic, basicPending); 
		Platform.WriteBits (Platform.IRQDisable1, pending1); 
		Platform.WriteBits (Platform.IRQDisable2, pending2);
		
		(* cf BCM2835 Manual, Section 7.5 *)
		FOR i := 0 TO 20 DO
			IF i IN basicPending THEN
				IF i = 8 THEN
					FOR j := 0 TO 31 DO
						IF j IN pending1 THEN 
							CallIrq(32+j);
						END;
					END
				ELSIF i = 9 THEN
					FOR j := 0 TO 31 DO
						IF j IN pending2 THEN
							CallIrq(64+j);
						END;
					END;
				ELSE
					CallIrq(i);
				END;
			END;
		END;
		
		SYSTEM.LDPSR( 1, spsr ); (* SPSR := old *)
	END IRQTrap;

	(* SWI trap handler *)
	PROCEDURE {INTERRUPT, PCOFFSET=0} SWITrap;
	VAR lnk, fp, resFP, number: ADDRESS;
	BEGIN
		(* We are in supervisor mode now *)
		(* Store exception location. The location that trapped was lnk - 4*)
		lnk := SYSTEM.LNK() - 4;
		fp := SYSTEM.FP();

		IF trapHandler # NIL THEN
			resFP := 0;
			trapHandler( Platform.SWI, lnk, fp, resFP );
		ELSE
			UartMin.OpenComPort( 115200, UartMin.PNONE, 8, FALSE );
			UartMin.Str("SWI ");
			SYSTEM.GET(lnk, number); number := number MOD 1000000H;
			UartMin.Hex(number);
			UartMin.StrLn(" at location:");
			UartMin.Hex( lnk );  UartMin.Str(", fp: "); UartMin.Hex(fp); UartMin.Ln;  
		END;
	END SWITrap;

		(* Undefined instruction trap *)
	PROCEDURE {INTERRUPT, PCOFFSET=0} UDF;
	VAR lnk, fp, resFP: ADDRESS;
	BEGIN
		(* Store exception location. The location that trapped was lnk - 4 *)
		lnk := SYSTEM.LNK() - 4;
		fp := SYSTEM.FP();
		IF trapHandler # NIL THEN
			resFP := 0;
			trapHandler( Platform.UndefInstr, lnk, fp, resFP );
		ELSE
			UartMin.OpenComPort( 115200, UartMin.PNONE, 8, FALSE );
			UartMin.Str("UDF trap at location: "); UartMin.Hex(lnk); UartMin.Ln;
		END;
	END UDF;

	(* Instruction Prefetch abort *)
	PROCEDURE {INTERRUPT, PCOFFSET=4} PrefetchAbort;
	VAR lnk, fp, resFP:ADDRESS;
	BEGIN
		(* Store exception location. The location that trapped was lnk - 4 *)
		lnk := SYSTEM.LNK() - 4;
		fp := SYSTEM.FP();

		IF trapHandler # NIL THEN
			resFP := 0;
			trapHandler( Platform.PrefAbort, lnk, fp, resFP );
		ELSE
			UartMin.OpenComPort( 115200, UartMin.PNONE, 8, FALSE );
			UartMin.Str("Prefetch abort at location: "); UartMin.Hex(lnk); UartMin.Ln;
		END;
	END PrefetchAbort;

	(* Map a memory page. Can only be used after initialisation *)
	PROCEDURE MapMemoryPage(logicalAdr, physAdr: ADDRESS);
	BEGIN
		DEC(physAdr, physAdr MOD MB);
		Platform.pageTable[logicalAdr DIV MB] := physAdr + NormalMemory;
		CleanCache();
	END MapMemoryPage;

	PROCEDURE ExtendStack;
	VAR
		physicalPage: ADDRESS;
	BEGIN
		lastValidStackPage := lastValidStackPage - Platform.MemoryPageSize;
		physicalPage := lastValidStackPage;
		MapMemoryPage(lastValidStackPage, physicalPage);
	END ExtendStack;

	PROCEDURE ExtendHeap;
	VAR
		physicalPage: ADDRESS;
	BEGIN
		lastValidHeapPage := lastValidHeapPage + Platform.MemoryPageSize;
		physicalPage := lastValidHeapPage;
		MapMemoryPage(lastValidHeapPage, physicalPage);
	END ExtendHeap;

	PROCEDURE DataAbortAdr(): ADDRESS;
	CODE
		MRC	P15, 0, R0, C6, C0, 0
	END DataAbortAdr;

	PROCEDURE {INTERRUPT, PCOFFSET=8} DataAbort;
	VAR lnk, fp, resFP, abortAdr: ADDRESS;
	BEGIN
		(* Store exception location. The location that trapped was lnk - 4 *)
		lnk := SYSTEM.LNK() - 8;
		fp := SYSTEM.FP();

		(* determine abort address via coprocessor instruction *)
		abortAdr := DataAbortAdr();

		(* Simple address validation *)
		IF (abortAdr >= Platform.RAMLogicalLow) & (abortAdr < Platform.RAMLogicalHigh) THEN
			(* Simple stack/heap distinction: We just use the closer address *)
			IF ABS(SIZE(lastValidStackPage - abortAdr)) < ABS(SIZE(lastValidHeapPage + Platform.MemoryPageSize - abortAdr )) THEN
				ExtendStack;
			ELSE
				ExtendHeap;
			END;

			(* Check for overflow *)
			IF (lastValidStackPage - lastValidHeapPage) <= Platform.MemoryPageSize THEN
				UartMin.Str("Stack / heap  collision! Rebooting the system.");  UartMin.Ln;
				Reset;
			END;
		ELSE
			IF trapHandler # NIL THEN
				resFP := 0;
				trapHandler( Platform.DataAbort, lnk, fp, resFP )
			ELSE
				UartMin.OpenComPort( 115200, UartMin.PNONE, 8, FALSE );
				UartMin.Str("Data abort at location: "); UartMin.Hex(lnk); UartMin.Ln;
			END;
		END;
		UartMin.MinosHostMode(FALSE);

	END DataAbort;

	(* Reset the watchdog. Do this periodically, otherwise the system will reboot *)
	PROCEDURE ResetWatchdog*;
	BEGIN
		StartWatchdog(LSH(1,16)); (* 1 second *)
	END ResetWatchdog;

	(* Enable the system Watchdog. Once enabled, the watchdog can only be disabled by rebooting the system *)
	PROCEDURE EnableWatchdog*;
	BEGIN
		StartWatchdog(LSH(1,16)); (* 1 second *)
	END EnableWatchdog;
	
	PROCEDURE StopWatchdog*;
	BEGIN
		Platform.WriteBits(Platform.RSTC, Platform.WDOGRESET);
	END StopWatchdog;

	PROCEDURE StartWatchdog*(time: SIZE);
	BEGIN
		Platform.WriteWord(Platform.WDOG, Platform.PASSWORD + time MOD 100000H); (* time: 2^16 ticks / second, max 16 seconds *)
		Platform.ClearAndSetBits(Platform.RSTC, Platform.SETM, Platform.FULLRESET);
	END StartWatchdog;
	
	PROCEDURE WatchdogTimeLeft*(): SIZE;
	BEGIN
		RETURN Platform.ReadWord(Platform.WDOG) MOD 100000H;
	END WatchdogTimeLeft;

	(* Get the internal hardware counter  *)
	PROCEDURE GetOSTimer*(): SIGNED32;
	BEGIN
		RETURN Platform.ReadWord(Platform.STCLO);
	END GetOSTimer;

	PROCEDURE MicroWait*(uSec: INTEGER);
	VAR target: SIGNED32;
	BEGIN
		target := Platform.ReadWord(Platform.STCLO) + uSec;
		REPEAT
		UNTIL  Platform.ReadWord(Platform.STCLO) - target >= 0
	END MicroWait;

	(* Wait mSec milliseconds *)
	PROCEDURE MilliWait*(mSec: INTEGER);
	BEGIN
		WHILE mSec > 0 DO MicroWait(1000); DEC(mSec); END;
	END MilliWait;

	(* Get the system time in milliseconds, driven by the timer interrupt, rel to system boot up *)
	PROCEDURE GetTime*(): INTEGER;
	BEGIN
		RETURN timer
	END GetTime;

	(* Get the date/time in Oberon time format (see Dates.Mos for details) *)
	(* Other implementation may use a RTC to get the current date. Currently, this is not possible... *)
	PROCEDURE GetCurrentDateTime*(VAR time, date: SIZE);
	VAR hour, min, sec, ms: SIZE;
	BEGIN
		time := GetTime(); ms := time MOD 1000; sec :=(time DIV 1000) MOD 60;
		min :=(time DIV(1000 * 60)) MOD 60;
		hour :=(time DIV(1000 * 60 * 60)) MOD 24;
		date :=(time DIV(1000 * 60 * 60 * 24));
		time := (((hour MOD 24) * 64 +(min MOD 60)) * 64 +(sec MOD 60)) * 1024 + (ms MOD 1000)
	END GetCurrentDateTime;

	(* Get the time in Oberon time format (see Dates.Mos for details) *)
	(* Other implementation may use a RTC to get the current date. Currently, this is not possible... *)
	PROCEDURE GetCurrentTime*(VAR time: SIZE);
	VAR date: SIZE;
	BEGIN
		GetCurrentDateTime(time, date);
	END GetCurrentTime;

	(* Install an exception handler. Use this with care!
		Locations are in PXA255.Platform.Mos, section "Exception vectors" *)
	PROCEDURE InstallHandler*(proc: ExceptionHandler; vector: ADDRESS);
	BEGIN
		SYSTEM.PUT32(vector, proc);
	END InstallHandler;

	(* Install all default interrupt and exception handlers *)
	PROCEDURE InitHandlers;
	VAR i: SIZE;
	BEGIN
		timerHandler:=NIL;

		FOR i := Platform.MinValidIrq TO Platform.MaxValidIrq DO
			irqHandlers[i] := NIL;
		END;

		(* IRQ/FIQ handlers *)
		InstallHandler(IRQTrap, Platform.IRQ);
		InstallHandler(IRQTrap, Platform.FIQ);

		(* Unknown *)
		InstallHandler(DataAbort, Platform.DataAbort);
		InstallHandler(PrefetchAbort, Platform.PrefAbort);

		(* Software interrupt *)
		InstallHandler(SWITrap, Platform.SWI);

		(* Undef *)
		InstallHandler(UDF, Platform.UndefInstr); (* dummy interrupt handler *)

		(* Register Timer handler *)
		InstallIrqHandler(Platform.SystemTimerIRQ, Timer0IrqHandler);

	END InitHandlers;

	(* Init the memory management unit *)
	PROCEDURE InitMMU;
	VAR i: SIZE;
	BEGIN
		Platform.DisableMemoryManagementUnit;
		Platform.pageTable[0] := 0; (* unmap page *)
		Platform.pageTable[4095] := 0*MB + StronglyOrderedMemory; (* use page 1 for irq vectors etc. *)
		(* unmap unused heap / stack pages *)
		FOR i := 2 TO 510 DO
			Platform.pageTable[i] := 0; (* unmapped *)
		END;
		lastValidHeapPage := 1*MB;
		lastValidStackPage := 511* MB;
		Platform.EnableMemoryManagementUnit;
	END InitMMU;

	(* Init the system *)
	PROCEDURE Init;
	BEGIN
		timer := 0;
		trapHandler := NIL;
		timerHandler := NIL;
		udfHandler := NIL;
	END Init;

	(* Setup the primary interrupt handler vectors. This must be done AFTER the MMU Setup, otherwise there's ROM mapped to
		memory location 0(Interrupt vectors)*)
	PROCEDURE SetupInterruptVectors;
		CONST Code = 0E59FF018H; (* Code that represents LDR pc, pc + 18 *)
		VAR i: SIZE;
	BEGIN
		FOR i := 0 TO 7 DO
			SYSTEM.PUT32(Platform.ExceptionVectorBase + 4*i, Code);
		END;
	END SetupInterruptVectors;

	(* Reboot the systen *)
	PROCEDURE Reset*; 
	BEGIN 
		StartWatchdog(1);
		WHILE TRUE DO END
	END Reset; 

BEGIN
	(* do not enter any call here --> link register consistency ! *)
	(* store LNK register in global variable, since stack is invalidated *)
	SYSTEM.PUT32(ADDRESSOF(lnk), SYSTEM.LNK());
	
	SYSTEM.LDPSR( 0, Platform.SVCMode + Platform.FIQDisabled + Platform.IRQDisabled );   (* Disable interrupts, init SP, FP *)
	SYSTEM.SETSP(Platform.SVCSP);   (* configure memory *)
	SYSTEM.SETFP(Platform.SVCSP);

	SYSTEM.LDPSR( 0, Platform.IRQMode + Platform.FIQDisabled + Platform.IRQDisabled );
	SYSTEM.SETSP(Platform.IRQSP);

	SYSTEM.LDPSR( 0, Platform.FIQMode + Platform.FIQDisabled + Platform.IRQDisabled );
	SYSTEM.SETSP(Platform.FIQSP);

	SYSTEM.LDPSR( 0, Platform.UndefMode + Platform.FIQDisabled + Platform.IRQDisabled );
	SYSTEM.SETSP(Platform.UNDSP);

	SYSTEM.LDPSR( 0, Platform.AbortMode + Platform.FIQDisabled + Platform.IRQDisabled );
	SYSTEM.SETSP(Platform.ABORTSP);

	SYSTEM.LDPSR( 0, Platform.SVCMode + Platform.FIQDisabled + Platform.IRQDisabled );   (* Disable interrupts, init SP, FP *)
	Init;
	InitMMU;	
	SetupInterruptVectors;
	InitHandlers;
	EnableIRQs;
	OSTimer;
	lnk
END Kernel.
