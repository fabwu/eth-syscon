(* ported version of Minos to work with the ARM backend of the Fox Compiler Suite *)
MODULE Minos;  
(*---------------------------------------------------------*
*	Copyright (c) ETH Zurich. All Rights Reserved.
*
*	Minos
*---------------------------------------------------------*)

IMPORT SYSTEM, Kernel, Device,  Modules, Log, OFS, Strings, Platform, Tools, UartMin, Heaps;

CONST 
	
	(* Connection Constants *)
	MD* = 10X;  CP* = 11X;  MS* = 23X;  
	
	(* debug *)
	Nil = 0X;  BOol = 1X;  CHar = 2X;  INt = 3X;  REal = 4X;  PTr = 6X;  End = 0FFX;  VAr = 1X;  PAr = 2X;  REg = 8X;  
	REgparX = 9X;  PRoc = 10X;  

	SFtag = 0F5X;  
	
	(* form *)
	Undef = 0;  Bool = 1;  Char = 2;  Int = 3;  Real = 4;  Pointer = 5;  Rider = 6;  NilTyp = 7;  NoTyp = 8;  Proc = 10;  String = 11;  
	Array = 12;  Record = 13;  ImpTyp = 14;  OArray = 15;  
	
	(* class*)
	Var = 1;  Par = 2;  

	ParamLength = 32;	
	
TYPE 
	Task* = POINTER TO TaskDesc;  
	PeriodicTask* = POINTER TO PeriodicTaskDesc;  
	TaskCode = PROCEDURE ( me: Task );  
	
	(* A background task *)
	TaskDesc* = RECORD 
		proc: TaskCode;  						(* This procedure is executed in the task *)
		name: ARRAY 32 OF CHAR;		(* Name of this task *)
		next: Task;  								(* The next task in the list of tasks *)
		maxTime, meanTime, totalTime: SIZE			(* Max, mean and total time a task has needed to execute *)
	END;  
	
	(* A periodic task *)
	PeriodicTaskDesc* = RECORD (TaskDesc) 
		priority: SIZE;  				(* The priority determines the execution order *)
		interval: SIZE;				(* The task is executed every "interval" msecs *)	
	END;  

(*	Elem = RECORD 
		class, form, address: SIZE;  
		name: ARRAY 32 OF CHAR  
	END;  
*)

VAR 
	(* A list containing all background tasks, sorted by the priority (higher number = higher priority first) *) 
	backgroundTasks: Task; 
	(* A list containing all periodic threads, sorted by interval first and then by priority *)
	periodicTasks: PeriodicTask;
	(* The SyncTask that is currently running. Is set to NIL if a background task is running *)
	msg: ARRAY 5, 32 OF CHAR;
	mname, pname, param: ARRAY ParamLength OF CHAR;   (* array for call's parameters *)
	abortModeFP, supervisorModeFP: SIZE;		(* FramePointers per processor mode for recovery after trap *)
	dev: Device.Device;
	
	(*----------------- Scheduler ------------------------------ *)
	PROCEDURE Scheduler;
	VAR current: PeriodicTask;
		delta: SIZE;
		currentTime: SIZE;
	BEGIN
		currentTime := Kernel.GetTime();
		current := periodicTasks;
		WHILE current # NIL DO
			IF currentTime MOD current.interval = 0 THEN     
				delta := Kernel.GetOSTimer();  
				IF current.proc # NIL THEN
					current.proc( current );
				END;
				(* some book-keeping *)
				delta := Kernel.GetOSTimer() - delta;
				IF delta > current.maxTime THEN current.maxTime := delta END;   (* measure execution time *)
				current.meanTime := (current.meanTime*(Platform.TimerRatePerSecond - 1) + delta) DIV Platform.TimerRatePerSecond;
				current.totalTime := current.totalTime + delta;
			END;
			IF current.next # NIL THEN
				current := current.next(PeriodicTask);
			ELSE
				current := NIL
			END;
		END;
	END Scheduler;  

	PROCEDURE NullScheduler;
	BEGIN
	END NullScheduler;


(*----------------- System specific calls ------------------------------ *)

	PROCEDURE Time*( ): SIZE;  
	BEGIN 
		RETURN Kernel.GetTime()
	END Time;  

	PROCEDURE InstallTask*( t: Task;  proc: TaskCode; CONST name: ARRAY OF CHAR );  
	BEGIN
		IF (t # NIL) & (proc # NIL) THEN
			t.proc := proc;
			t.next := backgroundTasks;  backgroundTasks := t;  
			COPY(name, t.name); t.maxTime := 0; t.meanTime := 0; t.totalTime := 0;
		END;
	END InstallTask;  

	PROCEDURE RemoveTask*( t: Task );  
	VAR list: Task;
	BEGIN
		IF t # NIL THEN
			list := backgroundTasks;  
			IF list # NIL THEN  (* not empty *)
				IF list = t THEN backgroundTasks := list.next;	(* Remove first element *)
				ELSE
					WHILE (list.next # NIL) & (list.next # t) DO list := list.next END;  
					IF list.next = t THEN list.next := t.next END 
				END 
			END;
		END;
	END RemoveTask;

	PROCEDURE InstallPeriodicTask*( s: PeriodicTask; proc: TaskCode;  CONST name: ARRAY OF CHAR; interval: SIZE; priority: SIZE);
	VAR current: PeriodicTask;
	BEGIN
		IF (s # NIL) & (proc # NIL) THEN 
			(* align interval to unit *)
			IF (interval MOD Platform.TimerPeriod) # 0 THEN
				interval := interval - (interval MOD Platform.TimerPeriod);
			END;

			s.next := NIL;

			(* Install task *)
			Kernel.DisableIRQs;
			current := periodicTasks;
			IF current # NIL THEN  
				(* not empty *)
				(* Sort the thread first according to their deadline, then according to the priority. 
					Higher number means higher priority *)
				WHILE (current.next # NIL) & (current.interval < interval) DO current := current.next(PeriodicTask) END;  
				WHILE (current.next # NIL) & (current.interval = interval) & (current.priority >= priority) DO current := current.next(PeriodicTask) END;  

				IF current.next # NIL THEN 
					s.next := current.next; current.next := s;
				ELSE	(* last element *)
					current.next := s;
				END 
			ELSE (* first task *)
				periodicTasks := s; periodicTasks.next := NIL;
			END;  

			s.proc := proc;
			COPY(name, s.name);
			s.priority := priority;
			s.interval := interval;
			s.meanTime := 0;
			s.maxTime := 0;
			s.totalTime := 0;

			Kernel.EnableIRQs;
		END;
	END InstallPeriodicTask;  

	PROCEDURE RemovePeriodicTask*( s: PeriodicTask );  
	VAR slist: PeriodicTask;
	BEGIN 
		Kernel.DisableIRQs;  
		
		IF s # NIL THEN 
			slist := periodicTasks;  
			IF slist # NIL THEN  (* not empty *)
				IF slist = s THEN 
					(* Remove first element *)
					IF slist.next # NIL THEN
						periodicTasks := slist.next(PeriodicTask);	
					ELSE
						periodicTasks := NIL;
					END;
				ELSE
					WHILE (slist.next # NIL) & (slist.next # s) DO slist := slist.next(PeriodicTask) END;  
					IF slist.next = s THEN slist.next := s.next END 
				END 
			END;  
		END;
		Kernel.EnableIRQs;  
	END RemovePeriodicTask;  

	PROCEDURE StartSync*;  
	BEGIN 
		Kernel.RegisterTimerHandler(Scheduler);   (* interrupt handler *)
	END StartSync;  

	PROCEDURE StopSync*;  
	BEGIN 
		Kernel.RegisterTimerHandler(NullScheduler);   (* interrupt handler *)
	END StopSync;  

	(* Execute all background tasks one by one forever *)
	PROCEDURE ExecuteBGTasks;
	VAR actualTask: Task;   (* search a task to execute *)
		proc: TaskCode; delta: SIZE;  
	BEGIN
		actualTask := backgroundTasks;
		WHILE TRUE DO 
			IF (actualTask # NIL) THEN
				proc := actualTask.proc;
				delta := Kernel.GetOSTimer();
				proc( actualTask );
				delta := Kernel.GetOSTimer() - delta;

				actualTask.totalTime := actualTask.totalTime + delta;
				actualTask.meanTime := (actualTask.meanTime + delta) DIV 2;
				IF delta > actualTask.maxTime THEN actualTask.maxTime := delta; END;

				actualTask := actualTask.next;
			ELSE
				actualTask := backgroundTasks; 
			END;
		END;  
	END ExecuteBGTasks;  

	PROCEDURE GetParam*( VAR s: ARRAY OF CHAR );  
	VAR i: SIZE;  
	BEGIN 
		i := 0;  
		WHILE (param[i] # 0X) & (i < 32) DO s[i] := param[i];  INC( i ) END;  
		s[i] := 0X;  
	END GetParam;

	PROCEDURE Call*(CONST modname, pname: ARRAY OF CHAR): BOOLEAN;
	VAR
		ok: BOOLEAN;
		m: Modules.Module;
		i: SIZE;
	BEGIN
		ok := TRUE;
		Modules.ThisMod( modname, m );
		IF m = NIL THEN 
			ok := FALSE;
			i := Modules.GetRes( param );  Log.S( msg[i] );  
			IF i > Modules.OK THEN Log.Char(' ' );  Log.S( param ) END;  
			Log.L;  
		ELSE 
			 ok := Modules.CallP( m, pname ) ;
			 IF ~ok THEN Log.S( "command not found" );  Log.Ln() END;
		END;
		RETURN ok
	END Call;

	PROCEDURE HostCommand(task: Task);  
	VAR  m: Modules.Module; i, len: SIZE;  ch: CHAR;   ok: BOOLEAN;  
		
		PROCEDURE Split( VAR a, b: ARRAY OF CHAR );  
		VAR i, j: SIZE;  
		BEGIN 
			i := 0;  j := 0;  
			WHILE (a[i] # 0X) & (a[i] # '.') DO INC( i ) END;  
			IF a[i] = '.' THEN 
				a[i] := 0X;  INC( i );  
				WHILE a[i] # 0X DO b[j] := a[i];  INC( i );  INC( j ) END;  
			END;  
			b[j] := 0X;  
		END Split;  

	BEGIN 
		IF Device.Available( dev ) > 0 THEN 
			Device.Read( dev, ch );  
			IF (ch = MD) OR (ch = CP) THEN 
				Device.ReadStr( dev, mname );
				IF ch = CP THEN 
					Device.ReadInt( dev, len );  i := 0;  
					WHILE (i < len) & (i < (ParamLength  - 1)) DO Device.Read( dev, ch );  param[i] := ch;  INC( i ) END;  (** tt: safety check *)
					param[i] := 0X;  Log.S( "call " );  Log.S( mname );  Log.Char( ' ' );  Log.L;  
					
					Split( mname, pname );  
					ok := Call(mname, pname);
					Log.Char( '>' );  
				ELSE 
					Log.S( "load " );  Log.S( mname );  Log.Char( ' ' );  Log.L;  Modules.ThisMod( mname, m );  
					i := Modules.GetRes( param );  Log.S( msg[i] );  
					IF i > Modules.OK THEN Log.Char( ' ' );  Log.S( param );  Log.Ln() END;  
					Log.Char( '>' );  
				END;  
			END;  
		END;  
	END HostCommand;  

(*----------------- Trap Handler ------------------------------ *)

	PROCEDURE ReadString*(VAR R: OFS.Rider; VAR x: ARRAY OF CHAR);
		VAR i: SIZE; ch: CHAR;
	BEGIN i := 0;
		REPEAT
			OFS.Read(R, ch); x[i] := ch; INC(i);
		UNTIL ch = 0X
	END ReadString;

(*	PROCEDURE ReadElem( VAR r: OFS.Rider;  VAR elem: Elem ): BOOLEAN;  
	VAR ret: BOOLEAN;  ch: CHAR;  
	BEGIN 
		OFS.Read( r, ch );  ret := TRUE;  
		IF ~r.eof & (ch # 0X) THEN 
			elem.class := ORD( ch );  OFS.Read( r, ch );  elem.form := ORD( ch );  OFS.ReadBytes( r, elem.address, 4 );  
			ReadString( r, elem.name );
		ELSE ret := FALSE 
		END;  
		RETURN ret
	END ReadElem;  

	PROCEDURE NextProc( VAR r: OFS.Rider;  VAR proc: Elem ): BOOLEAN;  
	VAR ret: BOOLEAN;  ch: CHAR;  e: Elem;  
	BEGIN 
		OFS.Read( r, ch );  proc.class := 0;  
		IF ch = 0AX THEN 
			proc.class := ORD( ch );  OFS.Read( r, ch );  proc.form := ORD( ch );  OFS.ReadBytes( r, proc.address, 4 );  
			proc.address := proc.address * 4;  ReadString( r, proc.name );  
			WHILE ReadElem( r, e ) DO END;  
		END;  
		IF proc.class = 10 THEN ret := TRUE ELSE ret := FALSE END;  
		RETURN ret
	END NextProc;  

	PROCEDURE ReadProc( VAR r: OFS.Rider;  VAR e: Elem );  
	VAR ch: CHAR;  
	BEGIN 
		OFS.Read( r, ch );  
		IF ch = 0AX THEN 
			e.class := ORD( ch );  OFS.Read( r, ch );  e.form := ORD( ch );  OFS.ReadBytes( r, e.address, 4 );  e.address := e.address * 4;  
			ReadString( r, e.name )
		END;  
	END ReadProc;  

	PROCEDURE Write( VAR e: Elem;  val: SIZE );  
	VAR l: SIZE;  
	BEGIN 
		Log.Ch(logMode, 9X );  Log.Ch(logMode, 9X );  Log.S( e.name );  Log.S( " =  " );  
		IF e.form = Bool THEN 
			IF val = 0 THEN Log.S( "FALSE" ) ELSE Log.S( "TRUE" ) END 
		ELSIF e.form = Char THEN 
			IF (val > 20H) & (val < 80H) THEN Log.Ch(logMode, CHR( val ) ) ELSE Log.S( "CHR(" );  Log.I( val );  Log.Ch(logMode, ")" ) END 
		ELSIF e.form = Int THEN Log.I( val )
		ELSIF e.form = Real THEN Log.Hex(logMode, val )
		ELSIF e.form = Pointer THEN Log.Ch(logMode, "@" );  Log.Hex(logMode, val )
		ELSIF e.form = Rider THEN Log.S( "Rider" );  
		ELSIF e.form = Proc THEN Log.S( "Procedure" );  
		ELSIF e.form = String THEN Log.S( "String" );  
		ELSIF e.form = Array THEN Log.S( "Array" );  
		ELSIF e.form = Record THEN Log.S( "Record" );  
		ELSE Log.S( "not readable" )
		END;  
		Log.L;  
	END Write;  

	PROCEDURE GetVal( fp: SIZE;  VAR e: Elem;  VAR val: SIZE );  
	VAR adr: SIZE;  ch: CHAR;  
	BEGIN 
		IF e.class = Par THEN SYSTEM.GET( e.address + fp, adr ) ELSE adr := e.address + fp END;  
		IF e.form >= Int THEN SYSTEM.GET( adr, val ) ELSE SYSTEM.GET( adr, ch );  val := ORD( ch );  END 
	END GetVal;  
*)
	PROCEDURE ShowPostDebug( m: Modules.Module;  fp, reladr: SIZE );  
	(*
	VAR f: OFS.File;  r: OFS.Rider;  symfile: OFS.FileName;  tag: CHAR;  offset, key, pos, delta, val: SIZE;  elem: Elem;  
	BEGIN 
		Log.S( m.name );  Kernel.Copy( symfile, m.name );  Strings.Append( symfile, ".smb" );  f := OFS.Old( symfile );  
		IF f # NIL THEN 
			OFS.Set( r, f, 0 );  OFS.Read( r, tag );  OFS.ReadBytes( r, offset, 4 );  OFS.ReadBytes( r, key, 4 );  
			IF (tag = SFtag) & (m.key = key) THEN 
				OFS.Set( r, f, offset );  pos := offset;  delta := 0;  
				WHILE NextProc( r, elem ) & (elem.address < reladr) DO delta := OFS.Pos( r ) - pos;  pos := pos + delta END;  
				IF elem.class = 10 THEN 
					OFS.Set( r, f, pos - delta );  ReadProc( r, elem );  Log.Ch(logMode, "." );  Log.S( elem.name );  Log.Hex(logMode, elem.address );  
					Log.L;  
					WHILE ReadElem( r, elem ) DO GetVal( fp, elem, val );  Write( elem, val ) END 
				ELSE 
					Log.S( ".BODY" );  Log.L;  OFS.Set( r, f, pos );  ReadProc( r, elem );  
					WHILE ReadElem( r, elem ) DO GetVal( m.codeadr, elem, val );  Write( elem, val ) END 
				END 
			ELSE Log.S( "???" );  Log.Hex(logMode, m.codeadr );  Log.I( m.size );  Log.I( m.refcnt );  Log.L;  
			END;  
			OFS.Close( f )
		ELSE Log.Hex(logMode, m.codeadr );  Log.I( m.size );  Log.I( m.refcnt );  
		END;  
	*)
	END ShowPostDebug;  

	(* Dump the registers *)
	PROCEDURE DumpRegs(fp, pc: SIZE);
	CONST 
		FP = 12;
		SP = 13;
		LNK = 14;
		PC = 15;
	VAR
		i: SIZE;
		reg: SIZE;
	BEGIN
		FOR i := 0 TO 11 DO
			SYSTEM.GET(fp + 4*i, reg);
			Log.C('R'); Log.I(i); Log.S(" = "); Log.H(reg); Log.S(", ");
			
			IF (i+1 MOD 4) = 0 THEN Log.L; END;
		END;
		SYSTEM.GET(fp + 4*FP, reg); 
		Log.S("FP = "); Log.H(reg);

(*		SYSTEM.GET(fp + 4*(LNK-1), reg);	(* R13 is not on the stack *)
		Log.S(" LNK = "); Log.H(reg);
*)
		Log.S(" PC = "); Log.H(pc); 
		Log.L; 
	END DumpRegs;
	
	PROCEDURE TrapHandler( type, adr, fp: ADDRESS; VAR resFP: ADDRESS );  
	VAR op, nextFP, dataAdr: SIZE;  m, main: Modules.Module;
	BEGIN 
		Kernel.RegisterTimerHandler(NullScheduler);
		Kernel.EnableIRQs;
		Log.SetTrapMode(TRUE);
		
		(* Display type of the trap *)
		IF type = Platform.SWI THEN
			SYSTEM.GET( adr, op );  Log.S( "Trap no: " );  Log.Hex(op MOD 100H );  
			IF op MOD 100H = 1 THEN Log.S( " (index out of bounds)" );  
			ELSIF op MOD 100H = 2 THEN Log.S( " (type guard violation)" );  
			ELSIF op MOD 100H = 3 THEN Log.S( " (destination array shorter than source array)" );  
			ELSIF op MOD 100H = 4 THEN Log.S( " (invalid CASE index)" );  
			ELSIF op MOD 100H = 5 THEN Log.S( " (invalid array in NEW)" );  
			ELSIF op MOD 100H = 6 THEN Log.S( " (string too long or destination array too short)" );  
			ELSIF op MOD 100H = 7 THEN Log.S( " (integer division by zero or negative divisor or index out of bounds)" );  
			ELSE Log.S( " (Unknown error)" );  
			END;  
			Log.L;
		ELSIF type = Platform.UndefInstr THEN
			Log.S("Undefined instruction trap at location "); Log.H(adr); Log.L;
		ELSIF type = Platform.PrefAbort THEN
			Log.S("Prefetch Abort at PC adr ");  Log.H(adr); Log.L;
		ELSIF type = Platform.DataAbort THEN
			Log.S("Data Abort trap at PC adr ");  Log.H(adr); Log.L;
			SYSTEM.STCPR( 0F00H, 6H, dataAdr );	(* data access location that trapped *)
			Log.S("Tried to access adr ");  Log.H(dataAdr); Log.L;
		END;

		DumpRegs(fp, adr);

 		main := Modules.root;  m := main;  

 		WHILE (m # NIL ) & ((adr < m.pbase) OR (adr >= m.pbase + m.size)) DO m := m.next END;  

 		IF m # NIL THEN 
 			Log.S("Module: "); Log.S(m.name ); Log.S(", code base: "); Log.Hex(m.pbase );
 			Log.S(", code size: "); Log.I( m.size ); 
	 		Log.S(" PC = (abs: " ); Log.Hex(adr ); Log.S(") (rel: " );  Log.I(adr - m.pbase); Log.SL( ") " ); Log.Flush ();
 		ELSE
 			Log.S("Module: unknown"); Log.S(" PC = (abs: " ); Log.Hex(adr ); Log.SL( ") " ); Log.Flush ();
 		END;

		(* As all registers are saved while entering the trap, it is possible to get the original
			FP (reg12) from the local stack *)
		SYSTEM.GET(fp + 48, fp);
	 	(* traverse the stack *)
		SYSTEM.GET( fp, nextFP );

		WHILE (nextFP # abortModeFP) & (nextFP # abortModeFP) & (m # NIL) DO
			m := main;  SYSTEM.GET( fp + 4, adr );	(* the previous link register is stored in fp + 4 *)
			
			DEC(adr, 4);		(* We are not interested in the return address, but one before this *)
			
			WHILE (m # NIL ) & ((adr < m.pbase) OR (adr >= m.pbase + m.size)) DO  m := m.next  END;  

			IF m # NIL THEN
				Log.S("Module: "); Log.S(m.name ); Log.S(" PC = (abs: " );  Log.Hex(adr );  Log.S(") (rel: " );  Log.I( adr - m.pbase); Log.SL( ") " ); Log.Flush ();
				ShowPostDebug( m, nextFP, adr - m.pbase );  
				fp := nextFP;  SYSTEM.GET( fp, nextFP );  
			ELSE 
				Log.S("Unknown module, PC = (abs: " );  Log.Hex(adr );  Log.Char( ')' );  Log.L;
			END; 
		END;  
		Log.L;  
		Log.SetTrapMode(FALSE);

		Kernel.RegisterTimerHandler(Scheduler);
		SYSTEM.SETFP(fp);
	END TrapHandler;  
	(* SWI Mode *)
	
(* ------------------- Commands ----------------------- *)

	PROCEDURE SearchModule( pc: SIZE;  VAR m: Modules.Module );  
	BEGIN 
		m := Modules.root;
		WHILE (m # NIL ) & ((pc < m.pbase) OR (pc >= m.pbase + m.size)) DO m := m.next END;
	END SearchModule;  

	PROCEDURE Debug;  
	VAR class, form, byte: CHAR;  adr, int: SIZE;  
	BEGIN 
		Device.Read( dev, class );  
		WHILE class # End DO 
			Device.Read( dev, form );  Device.ReadInt( dev, adr );  
			IF class = VAr THEN 
				IF form >= INt THEN SYSTEM.GET( adr, int );  Device.WriteInt( dev, int );  
				ELSE SYSTEM.GET( adr, byte );  Device.WriteInt( dev, ORD( byte ) )
				END;  
			ELSIF class = PAr THEN 
				SYSTEM.GET( adr, adr );  
				IF form >= INt THEN SYSTEM.GET( adr, int );  Device.WriteInt( dev, int );  
				ELSE SYSTEM.GET( adr, byte );  Device.WriteInt( dev, ORD( byte ) )
				END;  
			ELSE 
				Device.WriteInt( dev, 0 ) (* Reg, RegI, and Proc cannot be debugged yet *)
			END;  
			Device.Read( dev, class )
		END 
	END Debug;  

	PROCEDURE ShowStatus*;
	VAR m, p: Modules.Module;  i, len: SIZE;  
	BEGIN 
		i := 0;  
		WHILE (param[i] # 0X) & (param[i] # 20X) & (param[i] # "~") & (i < 32) DO INC( i ) END;  
		param[i] := 0X;  m := Modules.root;  
		WHILE (m # NIL ) DO 
			IF m.name = param THEN p := m;  m := NIL ELSE m := m.next END 
		END;
		Log.SI(p.name, p.key);
	END ShowStatus;  

	PROCEDURE DumpModule*;  
	VAR m, p: Modules.Module;  x, i, j: SIZE;  
	BEGIN 
		i := 0;  
		WHILE (param[i] # 0X) & (param[i] # 20X) & (param[i] # "~") & (i < 32) DO INC( i ) END;  
		param[i] := 0X;  m := Modules.root;  p := NIL;  
		WHILE (m # NIL ) DO 
			IF m.name =  param THEN p := m;  m := NIL ELSE m := m.next END 
		END;
		Modules.PrintModuleInfo(p);
	END DumpModule;  

	PROCEDURE ShowModules*;  
	VAR m: Modules.Module;  
	BEGIN 
		m := Modules.root;  Log.S( "Loaded Modules : (name, size, refcnt)" );  Log.L;  
		WHILE m # NIL DO 
			Log.S( "     " );  Log.S( m.name );  Log.Char( ' ' );  Log.I( m.size );  
			Log.Char( ' ' );  Log.I( m.refcnt ); Log.L;  Log.Flush();
			m := m.next
		END 
	END ShowModules;  

	PROCEDURE ShowCommands*;  
	VAR m: Modules.Module;  i, j: SIZE;  
		name: ARRAY 32 OF CHAR;  
		ch: CHAR;  
		c: Modules.Command;
	BEGIN 
		i := 0;  
		WHILE (param[i] # 0X) & (param[i] # 20X) & (param[i] # "~") & (i < 32) DO INC( i ) END;  
		param[i] := 0X;  Log.S( "commands of " );  Log.S( param );  Log.L;  m := Modules.root;  
		WHILE m # NIL DO 
			IF m.name = param  THEN 
				c := m.command;  
				WHILE c # NIL DO
					Log.S(param); Log.S("."); Log.S(c.name); Log.L;
					c := c.next;
				END;
				m := NIL 
			ELSE m := m.next;
			END 
		END 
	END ShowCommands;  

	PROCEDURE ShowTasks*;  
	VAR list: Task;  slist: PeriodicTask;  d: REAL;  
		divisor: REAL;
	BEGIN 
		Log.S( "Sync Tasks: (name, interval, priority, max[us], mean[us], total[us])" );  Log.L;  
		
		divisor := (REAL(Platform.Tickrate) / 1000000.0);
		slist := periodicTasks;  
		WHILE slist # NIL DO 
			Log.Char( 9X );  Log.S( slist.name );  Log.Char( 9X ); Log.I(slist.interval); Log.Char( 9X ); Log.I( slist.priority );  Log.Char( 9X );  
			d := REAL( slist.maxTime ) / divisor; Log.I( ENTIER( d ) ); Log.Char( 9X );  d := REAL( slist.meanTime ) / divisor;  
			Log.I( ENTIER( d ) ); Log.Char( 9X ); d := REAL( slist.totalTime ) / divisor;  Log.I( ENTIER( d ) ); Log.L;  
			IF slist.next # NIL THEN slist := slist.next(PeriodicTask) ELSE slist := NIL; END;
		END;

		Log.S( "Background Tasks: (name, max[us], mean[us], total[us])" );  Log.L;  list := backgroundTasks;  
		WHILE list # NIL DO 
			Log.Char( 9X );  Log.S( list.name );  Log.Char( 9X ); d := REAL( list.maxTime ) /divisor; 
			Log.I( ENTIER( d ) ); Log.Char( 9X ); d := REAL( list.meanTime ) / divisor;  
			Log.I( ENTIER( d ) ); Log.Char( 9X ); d := REAL( list.totalTime ) / divisor;  
			Log.I( ENTIER( d ) ); Log.L;  list := list.next
		END;
	END ShowTasks;  

	PROCEDURE ShowMemory*;  
	VAR 
	fs: OFS.FileSystem;
		vol: OFS.Volume;
	BEGIN 
		Log.S( "Heap Size:" );  Log.I( Heaps.HeapSize() );  Log.S( " bytes" );  Log.L;  
		Log.S( "Free Memory:" );  Log.I( Heaps.Free() );  Log.S( " bytes" );  Log.L;  
		
		fs := OFS.First();
		REPEAT 
			vol := fs.vol;
			Log.S("Available bytes on disk "); Log.S(fs.prefix); Log.S(": "); Log.I(OFS.Available(fs.prefix)); Log.L;
			fs := OFS.Next(fs);
		UNTIL fs = NIL;
	END ShowMemory;  

	PROCEDURE ShowDir( CONST name: ARRAY OF CHAR; time, date, size: SIZE; VAR flags: SET);
	BEGIN
		Log.S(name); Log.S(", time: "); Log.I(time); Log.S(", size: "); Log.I(size); Log.L;
	END ShowDir;

	PROCEDURE Directory*;  
	VAR i: SIZE;  
		flags: SET;
	BEGIN 
		i := 0;  
		flags := {OFS.EnumSize, OFS.EnumTime};
		WHILE (param[i] > ' ') & (param[i] # '~') & (i < 32) DO INC( i ) END;  
		param[i] := 0X;  OFS.Enumerate( param, flags, ShowDir );
	END Directory;  

	PROCEDURE RemoteRead*;  
	VAR f: OFS.File;  name: OFS.FileName;
	BEGIN 
		f := Tools.RemoteReadFile( param );  
		IF f # NIL THEN 
			Log.S( "copied " );  OFS.GetName(f, name); Log.S(name);  Log.S( "   size: " );  Log.I( OFS.Length( f ) );  Log.L;  OFS.Register( f );
		ELSE Log.S( "not copied " );  
		END;  
	END RemoteRead;  

	PROCEDURE RemoteWrite*;  
	VAR f: OFS.File;  name: OFS.FileName;
	BEGIN 
		f := OFS.Old( param );  
		IF f # NIL THEN 
			Log.S( "writing " );  Tools.RemoteWriteFile( f ); OFS.GetName(f, name); Log.S( name );  Log.S( "   size: " );  Log.I( OFS.Length( f ) );  Log.L;  
			OFS.Close( f );
		END;  
	END RemoteWrite;  

	PROCEDURE Delete*;  
	VAR f: OFS.File;  
		res: INTEGER;
	BEGIN
		 f := OFS.Old( param );
		IF f # NIL THEN 
			Log.S( "deleting " );  OFS.Delete( param, res );  Log.S( param );  Log.L;  
			IF res # OFS.Ok THEN
				Log.S("Could not delete file");
			END;
		END;  
	END Delete;  

	PROCEDURE RESET*;  
	BEGIN 
		Log.S( "Reboot ..." );  Log.L; Log.Flush();
		Kernel.Reset;
	END RESET;  
	
	(*! STUDENT: this calls the modules unload functionality to be implemented by you. *)
	PROCEDURE Unload*;
	VAR name: OFS.FileName;
		i: SIZE;
	BEGIN
		i := 0;
		WHILE (param[i] > ' ') & (param[i] # '~') & (param[i] # ' ') &  (i < 32) DO INC( i ) END;
		param[i] := 0X;  Modules.Unload( param );
	END Unload;

	PROCEDURE FinishStartUp*;  
	VAR task: Task;
	BEGIN
		(* Install host command polling task *)
		NEW(task);
		InstallTask(task, HostCommand, "Host command");

		Log.Char('>' );  
		StartSync;
		ExecuteBGTasks;
	END FinishStartUp;  

	PROCEDURE InitMsg;  
	BEGIN 
		msg[Modules.OK] := "ok";  msg[Modules.NOTFOUND] := "no file found";  
		msg[Modules.NOTARM] := "incorrect object file" ;  msg[Modules.WRONGKEY] := "wrong key";  
		msg[Modules.NOMEMORY] := "non memory"
	END InitMsg;  
	
	PROCEDURE Init;
	BEGIN
		backgroundTasks := NIL; 
		periodicTasks := NIL;
	 	abortModeFP := 0;
	 	supervisorModeFP := 0;
		dev := Device.GetDevice(Platform.HostLink);
		IF dev = NIL THEN
			dev := Device.GetDevice("NULL");
		END;
		Device.Open(dev);
	END Init;

BEGIN
	Init;
	Log.SL("Minos started 2015/09/18 -- RPI (2) Version" );

	InitMsg;
	
	Kernel.RegisterTrapHandler(TrapHandler);   (* Trap handler *)
	
	supervisorModeFP := SYSTEM.FP();

	FinishStartUp;
END Minos.
