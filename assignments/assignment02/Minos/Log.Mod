(* ported version of Minos to work with the ARM backend of the Fox Compiler Suite *)
MODULE Log;   (**  AUTHOR "fof"; PURPOSE "configurable output ";  **)

IMPORT SYSTEM, Kernel, Platform;
	(*** configurable output *)
	
	(**
		verbose: output for programmers
		normal: output understandable by a user
		error: error reports - assumed to be important 
	*)

CONST 
	quiet* = -2;  error* = -1;  normal* = 0;  verbose* = 1;  

	TAB = 9X;	(* ASCII number for tabulator *)

TYPE 
	strP* = PROCEDURE ( CONST str: ARRAY OF CHAR );  
	setP* = PROCEDURE ( s: SET );  
	intP* = PROCEDURE ( i: SIZE );  
	hexP* = PROCEDURE ( i: SIZE );  
	realP* = PROCEDURE ( real: FLOAT32 );  
	boolP* = PROCEDURE ( b: BOOLEAN );  
	trapModeP* = PROCEDURE ( b: BOOLEAN );  
	chP* = PROCEDURE ( c: CHAR );  
	lnP* = PROCEDURE;  
	clearP* = PROCEDURE;  
	flushP* = PROCEDURE;  
	bufferP* = PROCEDURE ( CONST buf: ARRAY OF CHAR (*SYSTEM.BYTE*);  offset, len: SIZE );  
	beepP* = PROCEDURE ( freq, duration: SIZE );  

VAR 
	gMode: INTEGER;  str: strP;  int: intP;  real: realP;  bool: boolP;  ln: lnP;  ch: chP;  
	flush: flushP;  hex: hexP;  set: setP;  buffer: bufferP;  clear: clearP;  beep: beepP;  
	trapMode: trapModeP;  
	
	(** output procedures, output only generated if mode <= current mode (gMode) *)
	PROCEDURE MStr*( mode: INTEGER;  CONST s: ARRAY OF CHAR );  
	BEGIN 
		IF gMode >= mode THEN str( s ) END;  
	END MStr;  

	PROCEDURE MInt*( mode: INTEGER;  i: SIZE );  
	BEGIN 
		IF gMode >= mode THEN int( i ) END;  
	END MInt;  

	PROCEDURE MHex*( mode: INTEGER;  i: SIZE );  
	BEGIN 
		IF gMode >= mode THEN hex( i ) END;  
	END MHex;  

	PROCEDURE MReal*( mode: INTEGER;  r: FLOAT32 );  
	BEGIN 
		IF gMode >= mode THEN real( r ) END;  
	END MReal;  

	PROCEDURE MBool*( mode: INTEGER;  b: BOOLEAN );  
	BEGIN 
		IF gMode >= mode THEN bool( b ) END;  
	END MBool;  

	PROCEDURE MCh*( mode: INTEGER;  c: CHAR );  
	BEGIN 
		IF gMode >= mode THEN ch( c ) END;  
	END MCh;  

	PROCEDURE MBuffer*( mode: INTEGER;  CONST buf: ARRAY OF CHAR (* SYSTEM.BYTE *);  
										 offset, len: SIZE );  
	BEGIN 
		IF gMode >= mode THEN buffer( buf, offset, len ) END;  
	END MBuffer;  

	PROCEDURE MLn*( mode: INTEGER );  
	BEGIN 
		IF gMode >= mode THEN ln;  END;  
	END MLn;  

	PROCEDURE MFlush*( mode: INTEGER );  
	BEGIN 
		IF gMode >= mode THEN flush END;  
	END MFlush;  

	PROCEDURE MClear*( mode: INTEGER );  
	BEGIN 
		IF gMode >= mode THEN clear END;  
	END MClear;  

	PROCEDURE MShowTD*( mode: INTEGER;  ptr: ADDRESS );  
	VAR size, i: SIZE;  
	BEGIN 
		IF gMode >= mode THEN 
			SYSTEM.GET( ptr - 4, ptr );  ptr := ptr MOD 1000000H + Platform.RAMCore;  
			str( "TD :" );  hex( ptr );  ln;  str( "TD Size: " );  SYSTEM.GET( ptr - 4, size );  
			int( size MOD 1000000H );  ln;  str( "RECORD Size: " );  SYSTEM.GET( ptr, size );  int( size );  
			ln;  i := 0;  
			WHILE i < 8 DO 
				ch( 09X );  ch( '[' );  SYSTEM.GET( ptr + 4 + i * 4, size );  int( i );  ch( ']' );  
				hex( size );  ln;  INC( i )
			END;  
			str( "Ptrs: " );  SYSTEM.GET( ptr + 36, size );  int( size );  ln;  
		END;  
	END MShowTD;  

	PROCEDURE MTime*( mode: INTEGER );  
	BEGIN 
		MInt( mode, Kernel.GetTime() );  
	END MTime;  

	PROCEDURE MBeep*( mode: INTEGER;  freq, duration: SIZE );  
	BEGIN 
		IF gMode >= mode THEN beep( freq, duration ) END;  
	END MBeep;  

	PROCEDURE MTab*( mode: INTEGER);  
	BEGIN 
		MCh(mode, TAB);
	END MTab;  

(*** output procedures in normal mode, procedures with more than one argument add a line feed *)

	PROCEDURE S*( CONST s: ARRAY OF CHAR );  
	BEGIN 
		IF gMode >= normal THEN str( s );  END;  
	END S;  

	PROCEDURE Set*( s: SET );  
	BEGIN 
		IF gMode >= normal THEN set( s );  END;  
	END Set;  

	PROCEDURE SL*( CONST s: ARRAY OF CHAR );  
	BEGIN 
		IF gMode >= normal THEN str( s );  ln();  END;  
	END SL;  

	PROCEDURE IL*( i: SIZE );  
	BEGIN 
		IF gMode >= normal THEN int( i );  ln();  END;  
	END IL;  

	PROCEDURE RL*( r: FLOAT32 );  
	BEGIN 
		IF gMode >= normal THEN real( r );  ln();  END;  
	END RL;  

	PROCEDURE I*( i: SIZE );  
	BEGIN 
		IF gMode >= normal THEN int( i );  END;  
	END I;  

	PROCEDURE H*( i: SIZE );  
	BEGIN 
		IF gMode >= normal THEN hex( i );  END;  
	END H;  

	PROCEDURE R*( r: FLOAT32 );  
	BEGIN 
		IF gMode >= normal THEN real( r ) END;  
	END R;  

	PROCEDURE C*( c: CHAR );  
	BEGIN 
		IF gMode >= normal THEN ch( c ) END;  
	END C;  

	PROCEDURE B*( b: BOOLEAN );  
	BEGIN 
		IF gMode >= normal THEN bool( b ) END;  
	END B;  

	PROCEDURE L*( );  
	BEGIN 
		IF gMode >= normal THEN ln();  END;  
	END L;  

	PROCEDURE T*( );  
	BEGIN 
		C(TAB);
	END T;  

	PROCEDURE SS*( CONST s1, s2: ARRAY OF CHAR );  
	BEGIN 
		IF gMode >= normal THEN str( s1 );  ch( ':' );  str( s2 );  ln;  END;  
	END SS;  

	PROCEDURE SI*( CONST s: ARRAY OF CHAR;  i: SIZE );  
	BEGIN 
		IF gMode >= normal THEN 
			str( s );  ch( ':' );  
			IF i = MAX(SIZE) THEN str( "--" );  ELSE int( i );  END;  
			ln;  
		END;  
	END SI;  

	PROCEDURE SR*( CONST s: ARRAY OF CHAR;  r: FLOAT32 );  
	BEGIN 
		IF gMode >= normal THEN 
			str( s );  ch( ':' );  
			IF r = MAX(FLOAT32) THEN str( "--" ) ELSE real( r );  END;  
			ln;  
		END;  
	END SR;  

	PROCEDURE SC*( CONST s: ARRAY OF CHAR;  c: CHAR );  
	BEGIN 
		IF gMode >= normal THEN str( s );  ch( ':' );  ch( c );  ln;  END;  
	END SC;  

(*** output procedures in error mode, procedures with more than one argument add a line feed *)
	PROCEDURE eS*( CONST s: ARRAY OF CHAR );  
	BEGIN 
		IF gMode >= error THEN str( s );  END;  
	END eS;  

	PROCEDURE eSet*( s: SET );  
	BEGIN 
		IF gMode >= error THEN set( s );  END;  
	END eSet;  

	PROCEDURE eSL*( CONST s: ARRAY OF CHAR );  
	BEGIN 
		IF gMode >= error THEN str( s );  ln();  END;  
	END eSL;  

	PROCEDURE eIL*( i: SIZE );  
	BEGIN 
		IF gMode >= error THEN int( i );  ln();  END;  
	END eIL;  

	PROCEDURE eRL*( r: FLOAT32 );  
	BEGIN 
		IF gMode >= error THEN real( r );  ln();  END;  
	END eRL;  

	PROCEDURE eI*( i: SIZE );  
	BEGIN 
		IF gMode >= error THEN int( i );  END;  
	END eI;  

	PROCEDURE eH*( i: SIZE );  
	BEGIN 
		IF gMode >= error THEN hex( i );  END;  
	END eH;  

	PROCEDURE eR*( r: FLOAT32 );  
	BEGIN 
		IF gMode >= error THEN real( r ) END;  
	END eR;  

	PROCEDURE eC*( c: CHAR );  
	BEGIN 
		IF gMode >= error THEN ch( c ) END;  
	END eC;  

	PROCEDURE eB*( b: BOOLEAN );  
	BEGIN 
		IF gMode >= error THEN bool( b ) END;  
	END eB;  

	PROCEDURE eL*( );  
	BEGIN 
		IF gMode >= error THEN ln();  END;  
	END eL;  

	PROCEDURE eT*( );  
	BEGIN 
		eC(TAB);
	END eT;  

	PROCEDURE eSS*( CONST s1, s2: ARRAY OF CHAR );  
	BEGIN 
		IF gMode >= error THEN str( s1 );  ch( ':' );  str( s2 );  ln;  END;  
	END eSS;  

	PROCEDURE eSI*( CONST s: ARRAY OF CHAR;  i: SIZE );  
	BEGIN 
		IF gMode >= error THEN 
			str( s );  ch( '=' );  
			IF i = MAX(SIZE) THEN str( "--" );  ELSE int( i );  END;  
			ln;  
		END;  
	END eSI;  

	PROCEDURE eSR*( CONST s: ARRAY OF CHAR;  r: FLOAT32 );  
	BEGIN 
		IF gMode >= error THEN 
			str( s );  ch( '=' );  
			IF r = MAX(FLOAT32) THEN str( "--" ) ELSE real( r );  END;  
			ln;  
		END;  
	END eSR;  

	PROCEDURE eSC*( CONST s: ARRAY OF CHAR;  c: CHAR );  
	BEGIN 
		IF gMode >= error THEN str( s );  ch( ':' );  ch( c );  ln;  END;  
	END eSC;  


(*** output procedures in verbose mode, procedures with more than one argument add a line feed*)
	PROCEDURE vS*( CONST s: ARRAY OF CHAR );  
	BEGIN 
		IF gMode >= verbose THEN str( s );  END;  
	END vS;  

	PROCEDURE vSet*( s: SET );  
	BEGIN 
		IF gMode >= verbose THEN set( s );  END;  
	END vSet;  

	PROCEDURE vSL*( CONST s: ARRAY OF CHAR );  
	BEGIN 
		IF gMode >= verbose THEN str( s );  ln();  END;  
	END vSL;  

	PROCEDURE vI*( i: SIZE );  
	BEGIN 
		IF gMode >= verbose THEN int( i );  END;  
	END vI;  

	PROCEDURE vIL*( i: SIZE );  
	BEGIN 
		IF gMode >= verbose THEN int( i );  ln();  END;  
	END vIL;  

	PROCEDURE vRL*( r: FLOAT32 );  
	BEGIN 
		IF gMode >= verbose THEN real( r );  ln();  END;  
	END vRL;  

	PROCEDURE vH*( i: SIZE );  
	BEGIN 
		IF gMode >= verbose THEN hex( i );  END;  
	END vH;  

	PROCEDURE vR*( r: FLOAT32 );  
	BEGIN 
		IF gMode >= verbose THEN real( r ) END;  
	END vR;  

	PROCEDURE vC*( c: CHAR );  
	BEGIN 
		IF gMode >= verbose THEN ch( c ) END;  
	END vC;  

	PROCEDURE vB*( b: BOOLEAN );  
	BEGIN 
		IF gMode >= verbose THEN bool( b ) END;  
	END vB;  

	PROCEDURE vL*( );  
	BEGIN 
		IF gMode >= verbose THEN ln();  END;  
	END vL; 

	PROCEDURE vT*( );  
	BEGIN 
		vC(TAB);
	END vT;  

	PROCEDURE vSS*( CONST s1, s2: ARRAY OF CHAR );  
	BEGIN 
		IF gMode >= verbose THEN str( s1 );  ch( ':' );  str( s2 );  ln;  END;  
	END vSS;  

	PROCEDURE vSI*( CONST s: ARRAY OF CHAR;  i: SIZE );  
	BEGIN 
		IF gMode >= verbose THEN 
			str( s );  ch( '=' );  
			IF i = MAX(SIZE) THEN str( "--" );  ELSE int( i );  END;  
			ln;  
		END;  
	END vSI;  

	PROCEDURE vSR*( CONST s: ARRAY OF CHAR;  r: FLOAT32 );  
	BEGIN 
		IF gMode >= verbose THEN 
			str( s );  ch( '=' );  
			IF r = MAX(FLOAT32) THEN str( "--" ) ELSE real( r );  END;  
			ln;  
		END;  
	END vSR;  

	PROCEDURE vSC*( CONST s: ARRAY OF CHAR;  c: CHAR );  
	BEGIN 
		IF gMode >= verbose THEN str( s );  ch( ':' );  ch( c );  ln;  END;  
	END vSC;  

(** set output procedures *)
	PROCEDURE Redirect1*( s: strP;  i: intP;  h: hexP;  ss: setP;  r: realP;  b: boolP );  
	BEGIN 
		str := s;  int := i;  hex := h;  set := ss;  real := r;  bool := b;  
	END Redirect1;  

	PROCEDURE Redirect2*( c: chP;  l: lnP;  buf: bufferP;  cl: clearP;  fl: flushP;  
											   be: beepP;  trap: trapModeP );  
	BEGIN 
		ch := c;  ln := l;  buffer := buf;  clear := cl;  flush := fl;  beep := be;  
		trapMode := trap;  
	END Redirect2;  

(** set output mode *)
	PROCEDURE SetMode*( mode: INTEGER );  
	BEGIN 
		gMode := mode;  
	END SetMode;  

(** get output mode *)
	PROCEDURE GetMode*( ): INTEGER;  
	BEGIN 
		RETURN gMode
	END GetMode;  

(*** commands to set output modes *)
	PROCEDURE Verbose*;  
	BEGIN 
		SetMode( verbose );  
	END Verbose;  

	PROCEDURE Normal*;  
	BEGIN 
		SetMode( normal );  
	END Normal;  

	PROCEDURE Error*;  
	BEGIN 
		SetMode( error );  
	END Error;  

	PROCEDURE Quiet*;  
	BEGIN 
		SetMode( quiet );  
	END Quiet;  

	PROCEDURE SetTrapMode*( enable: BOOLEAN );  
	BEGIN 
		trapMode( enable );  
	END SetTrapMode;  

	PROCEDURE Null*;  
	BEGIN 
	END Null;  

	PROCEDURE NullStr*( CONST str: ARRAY OF CHAR );  
	BEGIN 
	END NullStr;  

	PROCEDURE NullSet*( s: SET );  
	BEGIN 
	END NullSet;  

	PROCEDURE NullInt*( i: SIZE );  
	BEGIN 
	END NullInt;  

	PROCEDURE NullHex*( i: SIZE );  
	BEGIN 
	END NullHex;  

	PROCEDURE NullReal*( real: FLOAT32 );  
	BEGIN 
	END NullReal;  

	PROCEDURE NullBool*( b: BOOLEAN );  
	BEGIN 
	END NullBool;  

	PROCEDURE NullChar*( c: CHAR );  
	BEGIN 
	END NullChar;  

	PROCEDURE NullBuffer*( CONST buf: ARRAY OF CHAR (* SYSTEM.BYTE *);  offset, len: SIZE );  
	BEGIN 
	END NullBuffer;  

	PROCEDURE NullBeep*( freq, duration: SIZE );  
	BEGIN 
	END NullBeep;  

	PROCEDURE NullTrapMode*( trap: BOOLEAN );  
	BEGIN 
	END NullTrapMode;  

(** reset output mode  and redirect output to Log  *)
	PROCEDURE Reset*;  
	BEGIN 
		Redirect1( NullStr, NullInt, NullHex, NullSet, NullReal, NullBool );  
		Redirect2( NullChar, Null, NullBuffer, Null, Null, NullBeep, NullTrapMode );  
		SetMode( normal );  
	END Reset;
	
(* Customary interface *)

	(** output procedures, output only generated if mode <= current mode (gMode) *)
	PROCEDURE String*(CONST s: ARRAY OF CHAR );  
	BEGIN 
		MStr(normal, s);
	END String;  

	PROCEDURE Int*(i: SIZE );  
	BEGIN 
		MInt(normal, i);
	END Int;  

	PROCEDURE Hex*(i: SIZE );  
	BEGIN 
		MHex(normal, i);
	END Hex;  

	PROCEDURE Real*( r: FLOAT32 );  
	BEGIN 
		MReal(normal, r);
	END Real;  

	PROCEDURE Bool*( b: BOOLEAN );  
	BEGIN 
		MBool(normal, b);
	END Bool;  

	PROCEDURE Char*( c: CHAR );  
	BEGIN 
		MCh(normal, c);
	END Char;  

	PROCEDURE Buffer*( CONST buf: ARRAY OF CHAR (* SYSTEM.BYTE *);  
										 offset, len: SIZE );  
	BEGIN 
		MBuffer(normal, buf, offset, len);
	END Buffer;  

	PROCEDURE Ln*();  
	BEGIN 
		MLn(normal);
	END Ln;  

	PROCEDURE Flush*();  
	BEGIN 
		MFlush(normal);
	END Flush;  

	PROCEDURE Clear*();  
	BEGIN 
		MClear(normal);
	END Clear;  

	PROCEDURE ShowTD*(ptr: ADDRESS );  
	BEGIN 
		MShowTD(normal, ptr);
	END ShowTD;  

	PROCEDURE Time*();  
	BEGIN 
		MTime(normal);
	END Time;  

	PROCEDURE Beep*( mode: INTEGER;  freq, duration: SIZE );  
	BEGIN 
		MBeep(normal, freq, duration);
	END Beep;  

	PROCEDURE Tab*();  
	BEGIN 
		MCh(normal, TAB);
	END Tab;  

BEGIN 
	Reset;  
END Log.
