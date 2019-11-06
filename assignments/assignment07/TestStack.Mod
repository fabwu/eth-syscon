MODULE TestStack;

IMPORT Commands, Stack;
		
TYPE 
	StackType = Stack.Stack;

State = ENUM Idle, Running, Stopped END;

TYPE 
	Runner = OBJECT
	VAR 
		stack: StackType;
		state: State;
		operations: SIZE;
		
		PROCEDURE &Init(s: StackType; ops: SIZE);
		BEGIN
			stack := s;
			state := State.Idle;
			operations := ops;
		END Init;
		
		PROCEDURE Await(code: State);
		BEGIN{EXCLUSIVE}
			AWAIT(state = code);
		END Await;

		PROCEDURE Set(code: State);
		BEGIN{EXCLUSIVE}
			state := code;
		END Set;
		
		PROCEDURE Action();
		VAR i: SIZE; node: Stack.Node;
		BEGIN
			FOR i := 1 TO operations DO
				node := stack.Pop();
				IF node # NIL THEN stack.Push(node) END;
			END; 
		END Action;
		
	BEGIN{ACTIVE}
		Await(State.Running);
		Action();
		Set(State.Stopped);
	END Runner;

	PROCEDURE Assert(cond: BOOLEAN; CONST msg: ARRAY OF CHAR);
	BEGIN
		ASSERT(cond);
	END Assert;
		
	PROCEDURE Check(s: StackType; nodes: SIZE);
	VAR n: Stack.Node; sum,count: SIZE; 
	BEGIN
		sum := 0; 
		count := 0; 
		n := s.Pop();
		WHILE n # NIL DO
			INC(sum, n.value);
			INC(count); 
			Assert(count<=nodes,"too many nodes?"); 
			n := s.Pop(); 
		END; 
		Assert(count =nodes,"lost nodes?"); 
		Assert(sum = nodes * (nodes -1) DIV 2,"the sum of node values does not match");
	END Check; 


	(* #threads  #operations #nodes *)
	PROCEDURE Test*(context: Commands.Context);
	VAR s: StackType; 
		i: SIZE; 
		runners: POINTER TO ARRAY OF Runner;
		node: Stack.Node;
		threads, operations, nodes: INTEGER;
		kind: ARRAY 32 OF CHAR;
	BEGIN
		IF context.arg.GetString(kind) & context.arg.GetInteger(threads,FALSE) & context.arg.GetInteger(operations,FALSE) & context.arg.GetInteger(nodes,FALSE) THEN
			NEW(runners, threads); 
			IF kind = "unprotected" THEN s := NEW Stack.UnprotectedStack();
			ELSIF kind = "blocking" THEN s := NEW Stack.BlockingStack();
			ELSIF kind = "lockfree" THEN s := NEW Stack.LockfreeStack();
			ELSIF kind = "placeholder" THEN s := NEW Stack.PlaceholderStack();
			END; 
			FOR i := 0 TO nodes-1 DO
				NEW(node,i); 
				s.Push(node);
			END;
			FOR i := 0 TO LEN(runners)-1 DO 
				NEW(runners[i], s, operations); 
			END;
			FOR i := 0 TO LEN(runners)-1 DO 
				runners[i].Set(State.Running);
			END;
			FOR i := 0 TO LEN(runners)-1 DO 
				runners[i].Await(State.Stopped); 
			END;
			Check(s,nodes);
			context.out.String("done."); context.out.Ln;
		ELSE
			context.error.String("Please provide ('unprotected'|'blocking'|'lockfree'|'placeholder') #threads #operations/stack #nodes"); context.error.Ln; 
		END;	
	END Test;

END TestStack.

System.Free TestStack Stack ~ 
TestStack.Test unprotected 10 100 10 ~ 
TestStack.Test blocking 10 100 10 ~ 
TestStack.Test lockfree 10 100 10 ~ 
TestStack.Test placeholder 10 100 10 ~ 


