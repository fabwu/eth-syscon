MODULE Out; (** AUTHOR "FOF"; PURPOSE "Simple console output with a common  A2/Minos Interface"; *)

IMPORT Log;

PROCEDURE String*(CONST s: ARRAY OF CHAR);
BEGIN
	Log.String(s);	
END String;

PROCEDURE Char*(c: CHAR);
BEGIN
	Log.Char(c);
END Char;

PROCEDURE Ln*();
BEGIN
	Log.Ln();
END Ln;

PROCEDURE Set*(s: SET);
VAR i: INTEGER; first: BOOLEAN;
BEGIN
	Char("{");
	first := TRUE;
	FOR i := 0 TO MAX(SET) DO
		IF i IN s THEN 
			IF ~first THEN Char(",") END;
			Int(i); first := FALSE;
		END;
	END;
	Char("}");
END Set;

PROCEDURE Int*(i: SIZE);
BEGIN
	Log.Int(i);
END Int;

PROCEDURE Hex*(i: SIZE);
BEGIN
	Log.Hex(i);
END Hex;

PROCEDURE Address*(a: ADDRESS);
BEGIN
	Hex(a);
END Address;

PROCEDURE Float*(x: FLOAT32);
BEGIN
	Log.Real(x);
END Float;

PROCEDURE Update*;
BEGIN
	Log.Flush();
END Update;

END Out.
