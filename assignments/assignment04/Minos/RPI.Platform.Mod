MODULE Platform; (* platform specific runtime support -- partially taken from RPI.CPU.Mod by Florian Negele *)

IMPORT SYSTEM;

CONST
	KB*=1024;
	MB*=1024*KB;

	NUMCOMPORTS* 	= 1;
	HostLink* = "UART";  
	
	(* Timer, Timer rate, Scheduling *)
	TimerInterval* = 5000;
	TimerPeriod*= TimerInterval DIV 1000;
	HardwareClockrate*= 1000*1000;
	TimerRatePerSecond* 	= HardwareClockrate DIV TimerPeriod; 
	Tickrate* = HardwareClockrate;  
	
	(* Memory and Address Ranges *)
	MemorySize* = 964 * MB; 
	HeapBase*= 2*MB;
	HeapEnd* =  512*MB; 
	MemoryPageSize* 	= 1*MB; (* Size of one memory page*)
	RAMCore* 	= 108000H;  (* Location of OS image in RAM *)
	InitCodeSize = 13 * 4 ; (* 13 instructions *)
	ModRoot* = RAMCore + 4H + InitCodeSize; (* Depends on initializing code *);
	HighMemPage* = 0;	(* The physical base address of the page that is remapped for the high interrupt vectors *)
	
	MMUPhysicalTableBase* = HighMemPage + 0EC000H;  (* Physical Address!! size: 16 Kbyte, increasing *)
	MMULogicalTableBase* = 0FFF00000H + 0EC000H;  (* Logical address after initial mapping!! size: 16 Kbyte, increasing *)

	RAMLogicalLow* = 0H; 
	RAMLogicalHigh* = 768*MB;
	RAMPhysicalLow* 	= 0; 
	RAMPhysicalHigh* = 768*MB;

	(* Stack top addresss *)
	SVCSP* 		= 020000000H;  	(* Default stack initialisation for Supervisor mode *)
	FIQSP* 	= 0FFFE2000H;  (* Default stack initialisation for IRQ mode, decreasing *)
	IRQSP* 	= 0FFFE4000H;  (* Default stack initialisation for IRQ mode, decreasing *)
	ABORTSP* 	= 0FFFE8000H;  (* Default stack initialisation for Abort mode, decreasing *)
	UNDSP* 	= 0FFFEC000H;  (* Default stack initialisation for Undef. instr.  mode, decreasing *)

	(* File System *)
	OFSBlockSize* = 4096;  
	RAMDiskBase* 	= 20000000H;  
	RAMDiskSize* 	= 4096;   (* Size in disk blocks pf 4096 bytes = 16 Mbytes *)
	RAMDiskEnd* 	= RAMDiskBase + RAMDiskSize * OFSBlockSize;  

	(* IRQ range and numbers *)
	MaxNumIrq* = 96;  
	MaxValidIrq* = 95;  
	MinValidIrq* = 0;  
	UartInstallIrq* = 32 + 57; (* GPU interrupt -- use to install the interrupt *)
	UartEffectiveIrq*= 19 (* Corresponds with GPU interrupt 57 -- irq pending bit *);
	SystemTimerIRQ* = 33;
	
	(*------ CPSR ------*)
	(* Constants related to the Current Processor State Register (CPSR) *)
	(* ARM Processor Modes. Used to set the current processor mode in conjunction with SYSTEM.LDPSR  *)
	FIQMode* 		= 11H;   (* Fast Interrupt Mode *)
	IRQMode* 		= 12H;   (* Interrupt Mode *)
	SVCMode* 		= 13H;   (* SuperVisorMode *)
	UndefMode*	= 1BH;   (* Undefined instruction mode *)
	UserMode* 		= 10H;   (* User mode *)
	AbortMode* 	= 17H;   (* Abort mode *)
	(* Exceptions *)
	FIQDisabled* 	= 40H;   (* Fast interrupts disabled globally *)
	IRQDisabled* 	= 80H;   (* Interrupts disabled globally *)
	
(*------ Exception vectors  ------*)
	(* Vectors are stored in RAM at execption vector address + 20H. The real vector hanlders are
	     installed by the bootloader *)
	ExceptionVectorBase* =  0FFFF0000H;			(* Use high vectors *)
	ExceptionBase 			= ExceptionVectorBase + 20H;			
	Reset* 							= ExceptionBase + 0H;  
	UndefInstr*		 		= ExceptionBase + 4H;
	SWI*					 			= ExceptionBase + 8H;  
	PrefAbort*			 		= ExceptionBase + 0CH;
	DataAbort*			 	= ExceptionBase + 10H;  
	IRQ*					 			= ExceptionBase + 18H;
	FIQ*					 			= ExceptionBase + 1CH;  


	(* hardware registers *)
	WDOG* = 03F100024H; 
	RSTC* = 03F10001CH; 
	PASSWORD* = 05A000000H; 
	PASSWORDM*= {30,28,27,25};
	SETM*={4,5};
	FULLRESET*={5}+PASSWORDM;
	WDOGRESET*={1,8}+PASSWORDM;


	GPFSEL0* = 03F200000H; FSEL0* = 0; FSEL1* = 3; FSEL2* = 6; FSEL3* = 9; FSEL4* = 12; FSEL5* = 15; FSEL6* = 18; FSEL7* = 21; FSEL8* = 24; FSEL9* = 27;
	GPFSEL1* = 03F200004H; FSEL10* = 0; FSEL11* = 3; FSEL12* = 6; FSEL13* = 9; FSEL14* = 12; FSEL15* = 15; FSEL16* = 18; FSEL17* = 21; FSEL18* = 24; FSEL19* = 27;
	GPFSEL2* = 03F200008H; 
	GPFSEL3* = 03F20000CH; 
	GPFSEL4* = 03F200010H; 
	GPFSEL5* = 03F200014H; 
	
	GPSET0* = 03F20001CH; GPSET1* = 03F200020H;
	GPCLR0* = 03F200028H; GPCLR1* = 03F20002CH;
	GPPUD* = 03F200094H; PUD* = 0;
	GPPUDCLK0* = 03F200098H; GPPUDCLK1* = 03F20009CH;

	IRQBasicPending* = 03F00B200H; IRQPending1* = 03F00B204H; IRQPending2* = 03F00B208H;
	IRQEnable1* = 03F00B210H; IRQEnable2* = 03F00B214H; IRQEnableBasic* = 03F00B218H;
	IRQDisable1* = 03F00B21CH; IRQDisable2* = 03F00B220H; IRQDisableBasic* = 03F00B224H;

	STCS* = 03F003000H; M0* = 0; M1* = 1; M2* = 2; M3* = 3;
	STCLO* = 03F003004H; STCHI* = 03F003008H;
	STC0* = 03F00300CH; STC1* = 03F003010H; STC2* = 03F003014H; STC3* = 03F003018H;

	(* uart controller 0 *)
	FUARTCLK* = 3000000;
	UART_DR* = 03F201000H;
	UART_FR* = 03F201018H; RXFE* = 4; TXFF* = 5; TXFE* = 7; BUSY*= 3;
	UART_IBRD* = 03F201024H;
	UART_FBRD* = 03F201028H;
	UART_LCRH* = 03F20102CH; FEN* = 4; WLEN8* = {5, 6};
	UART_CR* = 03F201030H; UARTEN* = 0; TXE* = 8; RXE* = 9; RTS*=11;
	UART_IFLS*= 03F201034H; 
	UART_IMSC* = 03F201038H; CTSMIM*=1; RXIM* = 4; TXIM*=5; RTIM*=6; FEIM*=7; PEIM*=8; BEIM*=9; OEIM*=10;
	UART_RIS* = 03F20103CH;  RXRIS*=4; TXRIS*=5;
	UART_MIS* = 03F201040H; RXMIS*=4; TXMIS*=5;
	UART_ICR* = 03F201044H; RXIC* = 4;

	(* spi controller 0 *)
	SPI_CS* = 	03F204000H;
	SPI_FIFO* = 	03F204004H;
	SPI_CLK* = 	03F204008H;
	SPI_DLEN* = 03F20400CH;
	SPI_LOTH* = 03F204010H;
	SPI_DC *= 	03F204014H; 
	
	TYPE
		SignedPointer=POINTER {UNSAFE,UNTRACED} TO RECORD value: SIGNED32 END;
		UnsignedPointer=POINTER {UNSAFE,UNTRACED} TO RECORD value: UNSIGNED32 END;
		SetPointer=POINTER {UNSAFE,UNTRACED} TO RECORD value: SET32 END;
		

	VAR 
		pageTable-: POINTER {UNSAFE,UNTRACED} TO ARRAY 4096 OF ADDRESS;

	(* write and read register values and bits *)
	
	PROCEDURE ReadWord- (register: SignedPointer):SIGNED32;
	BEGIN
		RETURN register.value;
	END ReadWord;

	PROCEDURE ReadBits- (register: SetPointer): SET32;
	BEGIN
		RETURN register.value;
	END ReadBits;

	PROCEDURE WriteWord- (register: UnsignedPointer; value: UNSIGNED32);
	BEGIN
		register.value := value;
	END WriteWord;

	PROCEDURE WriteBits- (register: SetPointer; value: SET);
	BEGIN
		register.value := value;
	END WriteBits;

	PROCEDURE SetBits- (register: SetPointer; value: SET);
	BEGIN
		register.value := register.value + value;
	END SetBits;

	PROCEDURE ClearBits- (register: SetPointer; value: SET);
	BEGIN
		register.value := register.value - value;
	END ClearBits;
	
	(* combined clear and set: clear mask and set bits on mask *)
	PROCEDURE ClearAndSetBits-(register: SetPointer; clear, set: SET);
	BEGIN
		register.value := register.value - clear + set;
	END ClearAndSetBits;

	(* cpu control *)
	PROCEDURE Delay- (cycles: SIZE);
	CODE
		LDR	R2, [FP, #cycles]
	delay:
		SUBS	R2, R2, #1
		BNE	delay
	END Delay;
	
	(* Page tables *)

	PROCEDURE IdentityMapMemory-;
	CONST 
		Section = 2H; Domain0 = 0H; FullAccess = 0C00H; NormalWriteBackAllocate = 100CH; StronglyOrdered = 0H; Shareable = 10000H;
		NormalMemory = Section + Domain0 + FullAccess + NormalWriteBackAllocate + Shareable;
		StronglyOrderedMemory = Section + Domain0 + FullAccess + StronglyOrdered;
	VAR index: SIZE;
	BEGIN
		pageTable := MMUPhysicalTableBase;
		FOR index := 0 TO MemorySize DIV MB - 1 DO pageTable[index] := index * MB +  NormalMemory  END;
		FOR index := MemorySize DIV MB TO LEN (pageTable) - 1 DO pageTable[index] := index * MB + StronglyOrderedMemory END;
	END IdentityMapMemory;

	PROCEDURE EnableMemoryManagementUnit-;
	BEGIN
		CODE
		load:
			LDR	R0, [PC, #page-$-8]
			LDR	R0, [R0, #0]
			MCR	P15, 0, R0, C2, C0, 0					; set page table base address
			B	grant
		page:
			d32 pageTable
		grant:
			MOV	R0, #0b11
			MCR	P15, 0, R0, C3, C0, 0					; enable full access to domain 0
		enable:
			MRC	P15, 0, R0, C1, C0, 0					; read old value
			ORR	R0, R0, #0b1							; memory protection
			ORR	R0, R0, #0b100						; data and unified cache
			ORR	R0, R0, #0b100000000000		; branch prediction
			ORR	R0, R0, #0b1000000000000	; instruction cache
			ORR	R0, R0, #0b10000000000000	; high vectors
			MCR	P15, 0, R0, C1, C0, 0
		END;
		pageTable := MMULogicalTableBase;
		FlushAndInvalidateDCache;
		InvalidateTLB;
		InvalidateICache;
	END EnableMemoryManagementUnit;

	(* caching *)

	PROCEDURE {PLAIN} FlushAndInvalidateDCache-;
	CODE
		invalidate_dcache:
			mrc	p15, 1, r0, c0, c0, 1		; read CLIDR
			ands	r3, r0, #7000000H
			mov	r3, r3, lsr #23			; cache level value (naturally aligned)
			beq	finished
			mov	r10, #0				; start with level 0
		loop1:
			add	r2, r10, r10, lsr #1		; work out 3xcachelevel
			mov	r1, r0, lsr r2			; bottom 3 bits are the Cache type for this level
			and	r1, r1, #7			; get those 3 bits alone
			cmp	r1, #2
			blt		skip				; no cache or only instruction cache at this level
			mcr	p15, 2, r10, c0, c0, 0		; write the Cache Size selection register
			d32	0F57FF060H 	; isb to sync the change to the CacheSizeID reg
			mrc	p15, 1, r1, c0, c0, 0		; reads current Cache Size ID register
			and	r2, r1, #7			; extract the line length field
			add	r2, r2, #4			; add 4 for the line length offset (log2 16 bytes)
			ldr	r4, [pc, #H0x3ff-$-8]
			ands	r4, r4, r1, lsr #3		; r4 is the max number on the way size (right aligned)
			clz	r5, r4				; r5 is the bit position of the way size increment
			ldr	r7, [pc, #H0x7fff-$-8]
			ands	r7, r7, r1, lsr #13		; r7 is the max number of the index size (right aligned)
		loop2:
			mov	r9, r4				; r9 working copy of the max way size (right aligned)
		loop3:
			orr	r11, r10, r9, lsl r5		; factor in the way number and cache number into r11
			orr	r11, r11, r7, lsl r2		; factor in the index number
			mcr	p15, 0, r11, c7, c14, 2		; clean & invalidate by set/way
			subs	r9, r9, #1			; decrement the way number
			bge		loop3
			subs	r7, r7, #1			; decrement the index
			bge		loop2
		skip:
			add	r10, r10, #2			; increment the cache number
			cmp	r3, r10
			bgt		loop1

		finished:
			mov	r10, #0				; swith back to cache level 0
			mcr	p15, 2, r10, c0, c0, 0		; select current cache level in cssr
			d32	0F57FF040H	; dsb
			d32	0F57FF060H	; isb

			bx	lr

			H0x3ff:		d32	03FFH
			H0x7fff:	d32	07FFFH
	END FlushAndInvalidateDCache;

	
	(* InvalidateICache - invalidates the ICache. Works only in a priviledged mode. *)
	PROCEDURE InvalidateICache-;
	CODE
		MCR p15, 0, R0, c7, c5, 0	; invalidate ICache & BTB
		DSB
		ISB
	END InvalidateICache;
	
	PROCEDURE DisableMemoryManagementUnit-;
	BEGIN
		CODE
			MRC	P15, 0, R0, C1, C0, 0
			BIC		R0, R0, #1
			MCR	P15, 0, R0, C1, C0, 0
		END;
		pageTable := MMUPhysicalTableBase;
		FlushAndInvalidateDCache;
		InvalidateTLB;
		InvalidateICache;
	END DisableMemoryManagementUnit;
	
	(* InvalidateTLB: data and instruction TLBs - Works only in a priviledged mode *)
	PROCEDURE InvalidateTLB;
	CODE
		MCR p15, 0, R0, c8, c7, 0	; invalidate I+D TLB
		DSB
		ISB
	END InvalidateTLB;

	(* minimalistic initial diagnostics *)		

	PROCEDURE LED- (status: BOOLEAN);
	BEGIN
		ClearAndSetBits(GPFSEL4, {21 .. 23}, {21});
		IF status THEN WriteBits (GPSET1, {15}) ELSE WriteBits (GPCLR1, {15}) END;
	END LED;

	PROCEDURE Blink-(n: INTEGER);
	BEGIN
		WHILE(n>0) DO
			DEC(n);
			LED(TRUE);
			Delay(32*1024*1024);
			LED(FALSE);
			Delay(32*1024*1024);
		END;
	END Blink;

BEGIN
	IdentityMapMemory; 
	EnableMemoryManagementUnit;
	Blink(3);
END Platform.
