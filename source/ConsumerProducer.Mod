MODULE ConsumerProducer; (** AUTHOR ""; PURPOSE ""; *)

IMPORT
	Out, Streams; 

CONST N = 16; 

TYPE 

Ring = OBJECT
VAR 
	head, tail, available, free: SIZE;
	buf: ARRAY N OF SIZE;
	
	PROCEDURE & Init;
	BEGIN
		available := 0; free := N; head := 0; tail := 0;
	END Init;
	
	PROCEDURE Produce(x: SIZE);
	BEGIN{EXCLUSIVE}
		AWAIT(free # 0);
		DEC(free); buf[tail] := x;
		INC(tail); tail := tail MOD N;
		INC(available);
	END Produce;
	
	PROCEDURE Consume(): SIZE;
	VAR x: SIZE;
	BEGIN{EXCLUSIVE}
		AWAIT(available # 0);
		DEC(available); x := buf[head];
		INC(head); head := head MOD N;
		INC (free);
		RETURN x;
	END Consume;
END Ring; 

Consumer = OBJECT
VAR r: Ring; sum,i: SIZE; done: BOOLEAN;

	PROCEDURE & Init(r: Ring);
	BEGIN
		SELF.r := r; done := FALSE;
	END Init;
	
	PROCEDURE AwaitDone;
	BEGIN{EXCLUSIVE}
		AWAIT(done); 
	END AwaitDone;
	
	
BEGIN{ACTIVE,EXCLUSIVE}
	sum := 0; 
	FOR i := 0 TO 256 DO
		INC(sum, r.Consume());
	END; 
	Report(sum);
	done := TRUE; 
END Consumer;

Producer = OBJECT
VAR r: Ring; i: SIZE; done: BOOLEAN; 

	PROCEDURE & Init(r: Ring);
	BEGIN
		SELF.r := r; done := FALSE;
	END Init;
	
BEGIN{ACTIVE}
	FOR i := 0 TO 256 DO
		r.Produce(i);
	END; 
END Producer;

VAR log: Streams.Writer;
VAR s := 0 : SIZE; 

PROCEDURE Report(sum: SIZE);
BEGIN{EXCLUSIVE}
	log.String("consumed items with sum = "); 
	log.Int(sum,1); 
	log.Ln; 
END Report;


PROCEDURE Test*;
VAR p: ARRAY 4 OF Producer;
VAR c: ARRAY 4 OF Consumer; 
VAR r: Ring; 
	i: SIZE
BEGIN
	s := 0; log := Out.GetWriter(); 
	NEW(r); 
	FOR i := 0 TO LEN(p)-1 DO
		NEW(p[i],r); 
	END; 
	FOR i := 0 TO LEN(c)-1 DO
		NEW(c[i],r); 
	END; 
	FOR i := 0 TO LEN(c)-1 DO
		c[i].AwaitDone();
	END; 
	Out.String("overal sum = "); Out.Int(s); Out.Ln; 
	
END Test;


	

END ConsumerProducer.

SystemTools.Free ConsumerProducer ~
ConsumerProducer.Test 
