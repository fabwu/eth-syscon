MODULE Zeus; (** AUTHOR "fof"; PURPOSE ""; **)

IMPORT Streams, Kernel, SYSTEM, Commands (*, Texts, TextUtilities, *) , Files, Objects, (*Beep, *) Serials, V24; (* V24 imported for initialization of its body *)

CONST
	SFtag = -11;

	(* form values*)
		Bool = 2; Char = 3; Int = 4; Real = 5;
		Pointer = 7; Proc = 10;
		String = 11; Array = 12; Record = 13;

TYPE
	Elem = POINTER TO RECORD
		class, form: SIGNED16;
		address: SIGNED32;
		name: ARRAY 32 OF CHAR;
		next, dsc: Elem
	END;

VAR
	root: Elem;

	PROCEDURE MakeFileName( VAR s: ARRAY OF CHAR );
	VAR i: SIGNED16;
	BEGIN
		i := 0;
		WHILE s[i] # 0X DO INC( i ) END;
		s[i] := "."; s[i + 1] := "s"; s[i + 2] := "m"; s[i + 3] := "b"; s[i + 4] := 0X
	END MakeFileName;

	PROCEDURE NewElem( VAR e: Elem; class, form: SIGNED16; address: SIGNED32; name: ARRAY OF CHAR );
	BEGIN
		NEW( e ); e.class := class; e.form := form; e.address := address; COPY( name, e.name ); e.next := NIL; e.dsc := NIL;
	END NewElem;

(* -------------------------------------------------------------------------------------- *)

	PROCEDURE LoadInfo( VAR w: Streams.Writer; s: ARRAY OF CHAR; implkey: SIGNED32 );
	VAR tag: SIGNED8; offset, key: SIGNED32;
		name: ARRAY 32 OF CHAR;
		F: Files.File; R: Files.Reader;
		(*S: Texts.Scanner;*)
		elem: Elem;

		PROCEDURE ReadScope( VAR proc: Elem );
		VAR class, form: SIGNED8; adr: SIGNED32;
			name: ARRAY 32 OF CHAR;
			e, prev: Elem;
		BEGIN
			R.RawSInt( class ); prev := NIL; proc := NIL;
			WHILE (R.Available() > 0) & (class # 0) DO
				R.RawSInt( form ); R.RawLInt( adr ); R.RawString( name ); NewElem( e, class, form, adr, name );
				IF prev = NIL THEN
					ASSERT ( class = Proc, 120 );
					proc := e
				ELSIF prev = proc THEN proc.dsc := e
				ELSE prev.next := e
				END;
				prev := e; R.RawSInt( class )
			END
		END ReadScope;

	BEGIN
		MakeFileName( s ); root := NIL; F := Files.Old( s );
		IF F # NIL THEN
			Files.OpenReader( R, F, 0 ); R.RawSInt( tag ); R.RawLInt( offset ); R.RawLInt( key );
			IF (tag = SFtag) & (key = implkey) THEN
				R.RawString( name ); Files.OpenReader( R, F, offset ); NewElem( root, -1, 0, 0, name ); ReadScope( elem );
				WHILE elem # NIL DO elem.next := root; root := elem; ReadScope( elem ) END
			ELSE w.String( s ); w.String( " not a valid smb or wrong key" ); w.Ln()
			END
		ELSE w.String( s ); w.String( " not found" ); w.Ln()
		END;
		(* RETURN (F # NIL) & (tag = SFtag) & (key = implkey) & (root # NIL) *)
	END LoadInfo;

	PROCEDURE ThisScope( VAR name: ARRAY OF CHAR ): Elem;
	VAR e: Elem;
	BEGIN
		e := root;
		WHILE (e # NIL ) & (e.name # name) DO e := e.next END;
		RETURN e
	END ThisScope;

	PROCEDURE ThisAdrScope( adr: SIGNED32 ): Elem;
	VAR e: Elem;
	BEGIN
		e := root;
		WHILE (e # NIL ) & (e.address > adr DIV 4) DO e := e.next END;
		RETURN e
	END ThisAdrScope;

	PROCEDURE Write( VAR w: Streams.Writer; e: Elem; val: SIGNED32 );
	BEGIN
		w.Char( 9X );
		CASE e.class OF
		2:w.String( "VAR " )
		| 8: w.String( "REG " )
		| 9: w.String( "REGI " )
		ELSE w.String( "" )
		END;
		w.String( e.name ); w.String( " = " );
		CASE e.form OF
		Bool:
				IF val = 0 THEN w.String( "FALSE" ) ELSE w.String( "TRUE" ) END
		| Char:
				IF (val > 20H) & (val < 80H) THEN w.Char( CHR( val ) ) ELSE w.String( "CHR(" ); w.Int( val, 0 ); w.Char( ")" ) END
		| Int:
				w.Int( val, 0 )
		| Real:
				w.FloatFix( SYSTEM.VAL( FLOAT32, val ), 5, 5, 0 )
		| Pointer:
				w.Char( "@" ); w.Hex( val, 0 )
		| Proc:
				w.String( "Procedure" );
		| String:
				w.String( "String" );
		| Array:
				w.String( "Array" );
		| Record:
				w.String( "Record" );
		ELSE w.String( "not disponible" );
		END;
		w.Ln();
	END Write;


CONST
	UpdateInterval = 50;
	CommandBase = 4D5B9878H;
	MD = 10X; CP = 11X; (* PC commands *)
	LOG = 20H; FR = 21H; MS = 23H; FD = 24H; FS = 25H; BEEP = 26H; CMD = 27H; (* ARM commands *)
	LN = 21X; STR = 22X; CH = 23X; INT = 24X; HEX = 25X; FLOAT = 26X;
	SETS = 27X;
	TIME = 28X; CLEAR = 29X; BUF = 30X; (* LogTypes *) (*tt*)

	PacketSize = 8; ACK = 0FH; NACK = 00H; MAXRETR = 20;
	OK = 0; (* V24.Ok, UDP.done *)
	TIMEOUT = -1;

	RcvBufLen = 1460; SndBufLen = 1460; TAB = 09X;

TYPE

	Connection* = OBJECT
	VAR w: Streams.Writer;
		out: Streams.Writer;
		timer: Kernel.Timer;
		c: Serials.Port;
		active, finished, break: BOOLEAN;
		sndBuf: ARRAY SndBufLen OF CHAR;
		rcvBuf: ARRAY RcvBufLen OF CHAR;
		sndBufPos, rcvBufPos, rcvBufN: SIZE;

		cmd: SIGNED32;
		newLine: BOOLEAN;

		PROCEDURE & Init( w: Streams.Writer; c: Serials.Port; out: Streams.Writer );
		BEGIN
			SELF.w := w; NEW( timer ); SELF.c := c; SELF.out := out; active := TRUE; finished := FALSE;
			newLine := TRUE; w.Update(); sndBufPos := 0; rcvBufPos := 0; rcvBufN := 0;
			break := FALSE; cmd := 0;
		END Init;

		PROCEDURE Timeout;
		BEGIN {EXCLUSIVE}
			finished := TRUE;
			IF c # NIL THEN
				c.Close(); out.String( "Closed port (after time out, brute force) " ); out.String( c.name ); out.Ln;
				c := NIL;
			END;
		END Timeout;

		PROCEDURE Close*;
		VAR timeout: Objects.Timer;
		BEGIN {EXCLUSIVE}
			active := FALSE; out.String( "Closing port " );
			out.String( c.name ); out.Ln; NEW( timeout );
			Objects.SetTimeout( timeout, SELF.Timeout, 2000 ); AWAIT( finished );
			Objects.CancelTimeout( timeout );
		END Close;

		PROCEDURE SendBytes( VAR x: ARRAY OF CHAR; n: SIZE; VAR res: SIGNED32 ); (* from Aos.V24.Mod *)
		BEGIN
			IF break THEN HALT( 111 ) END;
			c.Send( x, 0, n, TRUE , res );
		END SendBytes;

		PROCEDURE ReceiveBytes( VAR x: ARRAY OF CHAR; n: SIGNED32; VAR res: SIGNED32 ); (* from Aos.V24.Mod *)
		VAR i: SIGNED32;
		BEGIN
			IF break THEN HALT( 112 ) END;
			(* we do have an own buffer here, so cannot use c.Receive rightaway *)

			i := 0; res := Serials.Ok;
			WHILE (i # n) & (res = Serials.Ok) DO ReceiveChar( x[i], res ); INC( i ) END (*@007 tt,fof: to be optimized some time *)
		END ReceiveBytes;

		PROCEDURE Available( ): SIZE;
		VAR n: SIZE; res: SIGNED32;
		BEGIN
			IF break THEN HALT( 113 ) END;
			IF sndBufPos > 0 THEN SendBytes( sndBuf, sndBufPos, res ); sndBufPos := 0 END;
			n := rcvBufN - rcvBufPos;
			IF n = 0 THEN n := c.Available() END;
			RETURN n
		END Available;

		PROCEDURE Command*;
		END Command;

		PROCEDURE SendChar( ch: CHAR; VAR res: SIGNED32 );
		BEGIN
			IF break THEN HALT( 114 ) END;
			sndBuf[sndBufPos] := ch; INC( sndBufPos );
			IF sndBufPos >= SndBufLen THEN
			SendBytes( sndBuf, sndBufPos, res ); sndBufPos := 0
			ELSE res := OK
			END
		END SendChar;

		PROCEDURE ReceiveChar( VAR ch: CHAR; VAR res: SIGNED32 );
		VAR n, len: SIZE;
		BEGIN
			IF break THEN HALT( 115 ) END;
			IF sndBufPos > 0 THEN SendBytes( sndBuf, sndBufPos, res ); sndBufPos := 0 END;
			IF rcvBufPos >= rcvBufN THEN
			n := c.Available();
			IF n > LEN( rcvBuf ) THEN n := LEN( rcvBuf ) END;
			IF n > 0 THEN
			c.Receive( rcvBuf, 0, n, n, len, res ); rcvBufPos := 0; rcvBufN := n;
			ASSERT ( n = len ); (*@007 tt,fof *)
			ELSE rcvBufPos := 0; rcvBufN := 0; c.ReceiveChar( ch, res ); RETURN
			END
			END;
			ch := rcvBuf[rcvBufPos]; INC( rcvBufPos ); res := OK
		END ReceiveChar;

		PROCEDURE SendLong( x: SIGNED32 );
		VAR i, res: SIGNED32;
		BEGIN
			FOR i := 0 TO 3 DO SendChar( CHR( x MOD 100H ), res ); x := x DIV 100H END
		END SendLong;

		PROCEDURE ReceiveLong( VAR x, res: SIGNED32 );
		VAR ch: CHAR; i: SIGNED32;
		BEGIN
			x := 0; i := 0; res := OK;
			WHILE (res >= OK) & (i < 4) DO
			ReceiveChar( ch, res ); x := ROT( x, -8 ) + ORD( ch ); INC( i )
			END;
			x := ROT( x, -8 )
		END ReceiveLong;

		PROCEDURE SendStr( s: ARRAY OF CHAR );
		VAR i, res: SIGNED32; ch: CHAR;
		BEGIN
			i := 0;
			REPEAT ch := s[i]; SendChar( ch, res ); INC( i ) UNTIL ch = 0X
		END SendStr;

		PROCEDURE PrintBuf( VAR buf: ARRAY OF CHAR; len: SIGNED32 );
		VAR i, j: SIGNED32; ch: CHAR;
		BEGIN
			FOR i := 0 TO len - 1 BY 16 DO
			w.Hex( i, 9 );
			FOR j := i TO i + 15 DO
			IF j < len THEN w.Hex( ORD( buf[j] ), -3 ) ELSE w.String( " " ) END
			END;
			w.String( " " );
			FOR j := i TO i + 15 DO
			IF j < len THEN
				ch := buf[j];
				IF (ch < " ") OR (ch >= CHR( 127 )) THEN ch := "." END;
				w.Char( ch )
			END
			END;
			w.Ln
			END;
		END PrintBuf;

		PROCEDURE Receive( VAR ch: CHAR; VAR res: SIGNED32 );
		VAR timeout: SIGNED64;
		BEGIN
			timeout := Kernel.GetTicks() + 5000; (* 5 sec*)
			WHILE (Available() <= 0) & (timeout > Kernel.GetTicks()) DO END;
			IF Available() > 0 THEN ReceiveChar( ch, res ); res := OK
			ELSE ch := 0X; out.String( "Timeout on receive" ); out.Ln; res := TIMEOUT
			END
		END Receive;

		PROCEDURE ReceiveStr( VAR s: ARRAY OF CHAR; VAR res: SIGNED32 );
		VAR i: SIGNED32; ch: CHAR;
		BEGIN
			i := 0;
			REPEAT Receive( ch, res ); s[i] := ch; INC( i )
			UNTIL (ch = 0X) OR (res < OK) OR (i = LEN( s ));
		END ReceiveStr;

		PROCEDURE call( name: ARRAY OF CHAR; len: SIGNED32; par: ARRAY OF CHAR; VAR res: SIGNED32);
		VAR i: SIGNED32;
		BEGIN
			newLine := TRUE; (* force new line for responding log *)
			SendChar( CP, res ); SendStr( name ); SendLong( len ); i := 0;
			WHILE i < len DO SendChar( par[i], res ); INC( i ) END;
		END call;

		PROCEDURE loadModule( name: ARRAY OF CHAR );
		VAR res: SIGNED32;
		BEGIN
			SendChar( MD, res ); SendStr( name )
		END loadModule;

		PROCEDURE Receiver;
		VAR ch: CHAR;
			s: ARRAY 512 OF CHAR;
			f: Files.File; r: Files.Reader; W: Files.Writer;
			size: SIGNED64; 
			i, j, x, adr, key, step, checksum, res, len, n, retr: SIGNED32;
			proc:Elem; first: BOOLEAN;
			buf: ARRAY PacketSize + 1 OF CHAR;
			trapped: BOOLEAN; time, hz, ms: SIGNED32; update: BOOLEAN;
			dynBuf: POINTER TO ARRAY OF CHAR;
		BEGIN
			trapped := TRUE; break := FALSE; time := 0; update := FALSE;
			WHILE (Available() > 0) & active DO
				ReceiveChar( ch, res ); cmd := ROT (cmd DIV 100H * 100H + ORD( ch ), -8);
				CASE cmd - CommandBase OF
					LOG:
						ReceiveChar( ch, res );
						IF newLine THEN w.Ln; w.String("---M-->"); newLine := FALSE; END;
						CASE ch OF
							LN: (*w.Ln();*) newLine := TRUE;
							| STR:
								ReceiveStr( s, res ); s[LEN( s ) - 1] := 0X; (* fof: guard *)
								w.String( s ); w.Update();
							| CH:
								ReceiveChar( ch, res ); w.Char( ch );
							| INT:
								ReceiveLong( x, res ); w.Int( x, 0 )
							| HEX:
								ReceiveLong( x, res ); w.Hex( x, -8 )
							| SETS:
								ReceiveLong( x, res ); first := TRUE; w.Char( "{" );
								FOR i := 0 TO 31 DO
								IF i IN SYSTEM.VAL( SET32, x ) THEN
								IF ~first THEN w.Char( "," ) END;
								first := FALSE; w.Int( i, 0 )
								END
								END;
								w.Char( "}" )
							| FLOAT:
								ReceiveLong( x, res ); w.Float( SYSTEM.VAL( FLOAT32, x ), 16 )
							| TIME:
								w.Int( Kernel.GetTicks(), 0 )
							| CLEAR: (*Texts.Delete(log, 0, log.len)*)
							| BUF:
								ReceiveLong( x, res ); (* tt *)
								IF x > 1000 THEN (* fof: extremely improbable that this was really a command, we better assume it to be random coincidence *)
									HALT( 100 ); (* restart *)
								END;
								IF x > 0 THEN
									NEW( dynBuf, x ); ReceiveBytes( dynBuf^, x, res );
									PrintBuf( dynBuf^, x ); dynBuf := NIL;
								END;
						ELSE w.Char( "?" )
						END;
						IF Kernel.GetTicks() > time THEN
							w.Update(); time := Kernel.GetTicks() + 200;
						ELSE update := TRUE;
						END;
					| FR:
						ReceiveStr( s, res ); w.String( "sending file " ); w.String( s ); w.Char( " " );
						w.Update(); f := Files.Old( s );
						IF f = NIL THEN SendLong( -1 ); w.String( "not found." )
						ELSE
							size := f.Length(); len := SIGNED32(size); SendLong( len ); w.Update();
							Files.OpenReader( r, f, 0 ); i := 0; checksum := 0;
							WHILE i < len DO
								IF r.Pos() MOD (len DIV 10) = 0 THEN w.Char( "." ); w.Update(); END;
								r.Char( ch ); SendChar( ch, res );
								checksum := checksum + ORD( ch ); INC( i );
								IF i MOD 200 = 0 THEN (* Primitive flow control *)	(*@ 008 *)
									ReceiveChar(ch, res);
								END;
							END;
							SendLong( checksum ); w.String( " done." ); w.Char( "(" );
							w.Int( checksum, 0 ); w.Char( ")" )
						END;
						w.Ln(); w.Update();
					| FS: (* file receive in packets *)
						ReceiveStr( s, res ); w.String( "receiving file " ); w.String( s ); w.Char( " " );
						f := Files.New( s ); Files.OpenWriter( W, f, 0 );
						ReceiveLong( len, res ); w.Int( len, 0 ); w.Char( " " ); w.Update();
						j := 0; checksum := 0; step := len DIV 10; key := step; retr := 0;
						w.Char( "(" );
						WHILE (res >= OK) & (len > 0) & (retr < MAXRETR) DO
							n := SHORT( len DIV PacketSize ) MOD 2; ReceiveChar( ch, res );
							buf[j] := ch; INC( j ); checksum := checksum + ORD( ch );
							IF (res >= OK) & ((j = PacketSize + 1) OR (j = len + 1)) THEN
								ReceiveChar( ch, res );
								IF (res >= OK) & (ch = CHR( checksum )) & (n = ORD( buf[0] )) THEN
									FOR i := 1 TO j - 1 DO W.Char( buf[i] ) END;
									len := len - (j - 1); (* write buf without n *)
									SendChar( CHR( ACK + n * 16 ), res ); retr := 0;
									IF (W.Pos() >= key) THEN
										w.Int( (W.Pos() DIV step - 1), 1 ); key := key + step;
										w.Update();
									ELSIF (key = 0) THEN
										w.Int( (W.Pos() DIV PacketSize), 1 ); w.Update();
									END
								ELSIF (res >= OK) & (n = ORD( buf[0] )) & (ch # CHR( checksum )) THEN (* error on right packet *)
									SendChar( CHR( NACK + n * 16 ), res ); INC( retr ); w.Char( "+" );
									w.Update();
								ELSIF (res >= OK) & (n # ORD( buf[0] )) THEN (* already got acknowledge but do not store *)
									SendChar( CHR( ACK + ORD( buf[0] ) * 16 ), res ); w.Char( "-" );
									w.Update();
								END;
								j := 0; checksum := 0
							ELSIF res < OK THEN (* discard the packet *)
								j := 0; checksum := 0; INC( retr )
							END
						END;
						w.Char( ")" ); w.Update();
						IF len = 0 THEN W.Update(); Files.Register( f ); w.String( " done." )
						ELSE w.String( " failed." )
						END;
						w.Ln(); w.Update();
					| FD: (* receive Frame *)
						ReceiveStr( s, res ); ReceiveLong( key, res );
						ReceiveLong( adr, res ); LoadInfo( w, s, key );
						proc := ThisAdrScope( adr );
						ReceiveLong( adr, res );
						IF proc # NIL THEN
							w.String( s ); w.Char( "." ); w.String( proc.name ); w.Ln();
							proc := proc.dsc;
							WHILE proc # NIL DO
								SendChar( CHR( proc.class ), res ); SendChar( CHR( proc.form ), res );
								SendLong( proc.address + adr ); ReceiveLong( x, res );
								Write( w, proc, x ); proc := proc.next
							END
						END;
						SendChar( 0FFX, res ); w.Update();
					| MS: (* display module status *)
						ReceiveStr( s, res ); ReceiveLong( key, res );
						ReceiveLong( adr, res ); LoadInfo( w, s, key );
						proc := ThisScope( s );
						IF proc # NIL THEN
							w.String( s ); w.Ln(); proc := proc.dsc;
							WHILE proc # NIL DO
								SendChar( CHR( proc.class ), res ); SendChar( CHR( proc.form ), res );
								SendLong( proc.address + adr ); ReceiveLong( x, res );
								Write( w, proc, x ); proc := proc.next
							END;
						END;
						SendChar( 0FFX, res ); w.Update();
					| BEEP: (* beep signal with given frequency (in hz) and duration (in ms) *)
						ReceiveLong( hz, res ); ReceiveLong( ms, res );
						(* beeper.DoBeep( hz, ms );*)
					| CMD: (* this is a special command *)
						Command
				ELSE (* ignore *)
				END
			END;
			trapped := FALSE;
			IF update THEN w.Update END;
			FINALLY; (* ";" for the formatter *)
				IF trapped THEN
				break := FALSE; w.Update; w.Ln; w.String( "! Receiver trapped !" ); w.Ln; w.Update;
				END;
		END Receiver;

	BEGIN {ACTIVE}
		finished := FALSE;
		WHILE (active) DO Receiver(); timer.Sleep( UpdateInterval ); END;
		BEGIN {EXCLUSIVE}
			IF c # NIL THEN
				c.Close(); out.String( "Closed port " ); out.String( c.name ); out.Ln;
				c := NIL;
			END;
			finished := TRUE
		END;
	END Connection;

	VAR c: Connection;

	PROCEDURE Connect*( context: Commands.Context );
	VAR (* s: Texts.Scanner; D: Documents.Document; *) C: Serials.Port;
		port, res: SIGNED32;
		R: Streams.Reader;
	BEGIN
		IF c # NIL THEN c.Close(); c := NIL END;
		R := context.arg;
		port := 0; R.Int( port, FALSE );
		context.out.String( "Opening V24 connection on port COM" ); context.out.Int( port, 0 ); context.out.Ln;
		C:= Serials.GetPort( port );
		IF C # NIL THEN
			C.Open( 115200, 8, Serials.ParNo, Serials.Stop1, res );
			IF res = Serials.Ok THEN
			NEW(c, context.out, C, context.out);
			ELSE
				context.error.String("connection could not be established"); context.error.Ln;
			END;
		ELSE
			context.error.String("no such port"); context.error.Ln;
		END;
	END Connect;

	PROCEDURE Disconnect*( context: Commands.Context);
	BEGIN
		IF c # NIL THEN
			c.Close();
			c := NIL;
		END;
	END Disconnect;

	PROCEDURE Cmd*(context: Commands.Context);
	VAR pos, len, res: SIGNED32;
		name, par, s: ARRAY 256 OF CHAR;
	BEGIN
		context.arg.LnEOT(s);
		IF c # NIL THEN
			pos := 0; 
			WHILE (s[pos] = " ") OR (s[pos] = TAB) DO INC( pos ) END;
			len := 0; 
			WHILE (s[pos] # 0X) & (s[pos] # " ") & (s[pos] # TAB) DO
				name[len] := s[pos]; INC( pos ); INC( len );
			END;
			name[len] := 0X;
			WHILE (s[pos] = " ") OR (s[pos] = TAB) DO INC( pos ) END;
			len := 0;
			WHILE (s[pos] # 0X) OR (s[pos] = TAB) DO
				par[len] := s[pos]; INC( pos ); INC( len );
			END;
			par[len] := 0X;
			c.call( name, len, par, res);
		END;
	END Cmd;


(*BEGIN
	Modules.InstallTermHandler( Cleanup )
	*)
END Zeus.

System.Free Zeus ~


Zeus.Connect 5
Zeus.Cmd Minos.ShowModules 

Zeus.Disconnect


Compiler.Compile -p=Win32G
	Serials.Mod
	Win32.V24.Mod
	Zeus.Mod
	~

Compiler.Compile -p=Linux32G 
	Serials.Mod
	Unix.V24.Mod
	Zeus.Mod
	~