MODULE TestAllocation;
IMPORT Minos, Strings, Log;

CONST MB = 100000H; 

(* parse a number from the arguments of a command *)
PROCEDURE Number(): INTEGER;
VAR str: ARRAY 32 OF CHAR; int: INTEGER; b: BOOLEAN;
BEGIN
	Minos.GetParam(str); 
	Strings.StrToInt(str, int, b);
	RETURN int;
END Number;

(* allocate given number of 1MB blocks pages *)
PROCEDURE Heap*;
VAR a: POINTER TO ARRAY OF CHAR; i, number: INTEGER;
BEGIN
	number := Number();
	Log.SI("Allocating 1MB heap blocks: ",  number);
	FOR i := 1 TO number DO
		NEW(a, MB);
	END;
END Heap;

PROCEDURE Recursive(max: INTEGER);
VAR someSpace: ARRAY 1024*1024 OF CHAR; (* 1MB stack frame *)
BEGIN
	IF max > 0 THEN
		Recursive(max-1);
	END;
END Recursive;

(* Recurse the stack using a number of 1MB stack frames  *)
PROCEDURE Stack*;
VAR number: INTEGER;
BEGIN
	number := Number();
	Log.SI("Recursion with 1MB stack frames: ",  number);
	Recursive(Number());
END Stack;

END TestAllocation.

Test your implementation, for example with calls to
TestAllocation.Heap 400
TestAllocation.Stack 113

