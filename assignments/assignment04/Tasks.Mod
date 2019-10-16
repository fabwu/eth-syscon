MODULE Tasks;

IMPORT Platform, Minos, Kernel, Log;

TYPE 

	(* example for a periodic task descriptor *)
	BlinkerTask = POINTER TO BlinkerTaskDesc;
	BlinkerTaskDesc = RECORD (Minos.PeriodicTaskDesc)
		num: INTEGER;
	END;

	(* example for the use of a periodic task descriptor *)
	PROCEDURE Blinker(me: Minos.Task);
	VAR num: INTEGER;
	BEGIN
		WITH me: BlinkerTask DO
			Platform.LED(ODD(me.num DIV 100) & ODD(me.num DIV 10));
			INC(me.num);
		END;
	END Blinker;
	
	(* example of a very simple task that does not require further data *)
	PROCEDURE Speaker(me: Minos.Task);
	BEGIN
		Log.SL("Hello");
	END Speaker;

	PROCEDURE Watchdog(me: Minos.Task);
	BEGIN
		Kernel.EnableWatchdog();
	END Watchdog;

	(* example of periodically scheduled tasks *)
	PROCEDURE InstallPeriodic*;
	VAR b:BlinkerTask; s: Minos.PeriodicTask;
	BEGIN
		NEW(b); 
		NEW(s); 
		b.num := 0;
		Minos.InstallPeriodicTask(b, Blinker, "Blinker", 5, 0); (* 5 ms *)
		Minos.InstallPeriodicTask(s, Speaker, "Speaker", 5000, 0); (* 5 s *)
	END InstallPeriodic;
	
	(* watchdog task as background task *)
	PROCEDURE InstallWatchdog*;
	VAR w: Minos.Task;
	(*!STUDENT: start watchdog here *)
	BEGIN
		NEW(w);
		Minos.InstallTask(w, Watchdog, "Watchdog")
	END InstallWatchdog;
	
	PROCEDURE Loop*;
	BEGIN
		LOOP END; (* loop forever and therefore block command scheduling *)
	END Loop;

BEGIN InstallWatchdog
	
END Tasks.


