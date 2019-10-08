MODULE Blink; (** AUTHOR ""; PURPOSE ""; *)

IMPORT Minos, Platform, Strings; 

PROCEDURE Number(): INTEGER;
VAR str: ARRAY 32 OF CHAR; int: INTEGER; b: BOOLEAN;
BEGIN
	Minos.GetParam(str); 
	Strings.StrToInt(str, int, b);
	RETURN int;
END Number;


(* blink 5 times with the pulse duration (loop count) given by the number at the command line *)
(* numbers in the order of tens or hundreds of millions are reasonable *)
PROCEDURE Blink*;
VAR number: INTEGER; i: SIZE;
BEGIN
	number := Number();
	FOR i := 1 TO 5 DO
		Platform.LED(TRUE);
		Platform.Delay(number);
		Platform.LED(FALSE);
		Platform.Delay(number);
	END;
END Blink;

	

END Blink.
