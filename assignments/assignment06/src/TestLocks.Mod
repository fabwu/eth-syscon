MODULE TestLocks;

IMPORT
	Locks, KernelLog, Objects;

TYPE
	Logger*=OBJECT
	VAR 
		lock: Locks.RecursiveLock;
		
		PROCEDURE & Initialize(lock: Locks.RecursiveLock);
		BEGIN
			SELF.lock := lock
		END Initialize;	
		
		(* recursively output numbers from 0 to n *)
		PROCEDURE Log(n: INTEGER);
		VAR i: INTEGER;
		BEGIN
			lock.Acquire();

			Objects.Yield();(* to make scheduling even less deterministic *)
			
			IF n > 0 THEN 
				Log(n-1);
				KernelLog.String(","); 
			ELSE 
				KernelLog.Ln;
			END;
			KernelLog.Int(n,0);

			lock.Release();
		END Log;

	BEGIN{ACTIVE}
		Log(20);
	END Logger;

	PROCEDURE Test*;
	VAR logger: Logger; lock: Locks.RecursiveLock; VAR i: INTEGER;
	BEGIN
		NEW(lock); 
		FOR i := 0 TO 20 DO
			NEW(logger,lock)
		END;
	END Test;

END TestLocks.
