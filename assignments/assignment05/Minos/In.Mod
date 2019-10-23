MODULE In; (** AUTHOR "FOF"; PURPOSE "Simple argument parser; common interface A2/Minos"; *)

IMPORT Minos, Strings;


PROCEDURE String*(VAR s: ARRAY OF CHAR): BOOLEAN;
BEGIN
	Minos.GetParam(s); 
	RETURN s # "";
END String;

PROCEDURE Int*(VAR i: INTEGER): BOOLEAN;
VAR s: ARRAY 32 OF CHAR; res: BOOLEAN;
BEGIN
	res := FALSE;
	IF String(s) THEN
		Strings.StrToInt(s,i,res)
	END;
	RETURN res;
END Int;

END In.


