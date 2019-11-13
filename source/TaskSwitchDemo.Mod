MODULE TaskSwitchDemo;

IMPORT SYSTEM,Out;

VAR 
	pstack, qstack: ARRAY 129 OF ADDRESS; 
	p,q,end: ADDRESS;

PROCEDURE P*;
VAR i: SIZE;
BEGIN
	FOR i := 1 TO 5 DO
		Out.String("P : i="); Out.Int(i); Out.Ln;
		SwitchTo(p,q);
	END;
	SwitchTo(p,end);
END P;

PROCEDURE Q*;
VAR i: SIZE;
BEGIN
	FOR i :=1 TO 5 DO
		Out.String("Q : i="); Out.Int(i); Out.Ln;
		SwitchTo(q,p);
	END;
	SwitchTo(q,end);
END Q;

PROCEDURE SwitchTo(VAR old: ADDRESS; new: ADDRESS);
BEGIN
	old := SYSTEM.GetFramePointer();
	SYSTEM.SetFramePointer(new);
END SwitchTo;

PROCEDURE Test*;

	PROCEDURE Setup(VAR newFP: ADDRESS; proc: PROCEDURE);
	BEGIN
		SYSTEM.PUT(newFP-SIZE OF ADDRESS, proc);
		SYSTEM.PUT(newFP-2 * SIZE OF ADDRESS, newFP); (* skip two arguments *)
		newFP := newFP- 2 * SIZE OF ADDRESS;
	END Setup;

BEGIN
	p := ADDRESS OF pstack[128];
	q := ADDRESS OF qstack[128];
	Setup(p,P);
	Setup(q,Q);
	SwitchTo(end,p);
END Test;

END TaskSwitchDemo.

System.Free TaskSwitchDemo ~ 
TaskSwitchDemo.Test ~ 
