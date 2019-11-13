MODULE TestMutexes;

IMPORT Activities, Mutexes, Trace, Timer;

CONST Iterations1 = 100;
CONST Iterations2 = 1000;
VAR 
	mutex: Mutexes.Mutex; 
	value: SIZE;
TYPE
	Activity = OBJECT
	VAR i: SIZE;
	BEGIN {ACTIVE}
		FOR i := 1 TO Iterations1 DO
			Work(Iterations2);
		END;
	END Activity;

	PROCEDURE Work(steps: SIZE);
	VAR i,t: SIZE;
	BEGIN
		Mutexes.Acquire(mutex);
		FOR i := 0 TO steps-1 DO
			t := value + 1;
			IF t MOD 100000 = 0 THEN Activities.Switch END;
			value := t;
		END;
		Mutexes.Release(mutex);
	END Work;
		
	PROCEDURE Test;
	CONST NumObjects = 8;
	VAR act: ARRAY NumObjects OF Activity; i: SIZE; 
		counter: SIGNED64;
	BEGIN
		value := 0;
		counter := Timer.GetCounter();
		FOR i := 0 TO NumObjects-1 DO
			NEW(act[i]);
		END;
		FOR i := 0 TO NumObjects-1 DO
			WAIT(act[i]);
		END;
		counter := Timer.GetCounter() - counter;
		counter := counter * 1000 DIV Timer.GetFrequency();
		Trace.String("Value should be ");  Trace.Int(NumObjects * Iterations1 * Iterations2,1); Trace.String(": "); Trace.Int(value,1); Trace.Ln;
		Trace.String("time (ms) = "); Trace.Int(counter,1); Trace.Ln;
		
	END Test;
	
BEGIN
	TRACE(Test);
	Test;
END TestMutexes.
