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
	
	(* example of periodically scheduled tasks *)
	PROCEDURE InstallPeriodic*;
	VAR b:BlinkerTask; s: Minos.PeriodicTask;
	BEGIN
		NEW(b); 
		Minos.InstallPeriodicTask(b, Blinker, "Blinker", 5, 0); (* 5 ms *)
		NEW(s); 
		Minos.InstallPeriodicTask(s, Speaker, "Speaker", 5000, 0); (* 5 s *)
	END InstallPeriodic;
	
	(* watchdog task as background task *)
	PROCEDURE InstallWatchdog*;
	(*!STUDENT: start watchdog here *)
	BEGIN
	END InstallWatchdog;
	
	PROCEDURE Loop*;
	BEGIN
		LOOP END; (* loop forever and therefore block command scheduling *)
	END Loop;
	
END Tasks.


