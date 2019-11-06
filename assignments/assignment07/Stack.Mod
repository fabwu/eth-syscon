MODULE Stack;

TYPE 
	Node* = OBJECT
	VAR
		value-: SIZE;
		next: Node;
		
		PROCEDURE & Init*(value: SIZE);
		BEGIN
			SELF.value := value;
		END Init;
	END Node; 
	
	Stack*= OBJECT {ABSTRACT}
		PROCEDURE {ABSTRACT} Push*(node: Node);
		END Push;
		
		PROCEDURE {ABSTRACT} Pop*(): Node;
		END Pop;
	END Stack; 
	
	UnprotectedStack* = OBJECT(Stack)
	VAR top: Node;

		PROCEDURE Push*(node: Node);
		BEGIN
			node.next := top;
			top := node;
		END Push;

		PROCEDURE Pop*(): Node;
		VAR head: Node;
		BEGIN
			head := top;
			IF head = NIL THEN 
				RETURN NIL
			ELSE top := head.next;
				RETURN head;
			END;
		END Pop;

	END UnprotectedStack; 
	
	BlockingStack* = OBJECT(Stack)
	VAR top: Node;

		PROCEDURE Push*(node: Node);
		BEGIN{EXCLUSIVE}
			node.next := top;
			top := node;
		END Push;

		PROCEDURE Pop*(): Node;
		VAR head: Node;
		BEGIN{EXCLUSIVE}
			head := top;
			IF head = NIL THEN 
				RETURN NIL
			ELSE top := head.next;
				RETURN head;
			END;
		END Pop;

	END BlockingStack; 
	
	LockfreeStack* = OBJECT(Stack)
	VAR top: Node;

		PROCEDURE Push*(new: Node);
		VAR head: Node;
		BEGIN
			LOOP
				head := CAS(top, NIL, NIL);
				new.next := head;
				IF CAS(top, head, new) = head THEN
					EXIT
				END;
			END;
		END Push;

		PROCEDURE Pop*(): Node;
		VAR head, next: Node;
		BEGIN
			LOOP
				head := CAS(top, NIL, NIL);
				IF head = NIL THEN
					RETURN NIL;
				END;
				next := head.next;
				IF CAS(top, head, next) = head THEN
					RETURN head;
				END;
			END;
		END Pop;

	END LockfreeStack; 
		
	PlaceholderStack* = OBJECT(Stack)
	TYPE 
		Placeholder = OBJECT
		VAR
			next: Placeholder;
			node: Node;
		END Placeholder;

	VAR top: Placeholder;

		PROCEDURE Push*(new: Node);
		VAR placeholder, head: Placeholder;
		BEGIN
			NEW(placeholder);
			placeholder.node := new;
			LOOP
				head := CAS(top, NIL, NIL);
				placeholder.next := head;
				IF CAS(top, head, placeholder) = head THEN
					EXIT
				END;
			END;
		END Push; 
		
		PROCEDURE Pop*(): Node;
		VAR head, next: Placeholder;
		BEGIN
			LOOP
				head := CAS(top, NIL, NIL);
				IF head = NIL THEN
					RETURN NIL;
				END;
				next := head.next;
				IF CAS(top, head, next) = head THEN
					RETURN head.node;
				END;
			END;
		END Pop;

	END PlaceholderStack; 

END Stack.


