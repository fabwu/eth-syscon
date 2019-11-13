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
	
	Stack*= OBJECT{ABSTRACT}
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
		VAR head: Node; ignore: ADDRESS;
		BEGIN
			LOOP
				head := CAS(top, NIL, NIL);
				IGNORE CAS(new.next, new.next, head);
				IF CAS(top, head, new) = head THEN
					RETURN;
				END;
			END;
		END Push;

		PROCEDURE Pop*(): Node;
		VAR head, next: Node;
		BEGIN
			LOOP
				head := CAS(top, NIL, NIL);
				IF head = NIL THEN 
					RETURN NIL
				END;
				next := CAS(head.next, NIL, NIL);
				IF CAS(top, head, next) = head THEN
					RETURN head;
				END;
			END;
		END Pop;

	END LockfreeStack; 
	
	ItemNode* = OBJECT
	VAR
		item: Node;
		next: ItemNode;
		
		PROCEDURE & Init*(value: Node);
		BEGIN
			SELF.item := value;
		END Init;
		
	END ItemNode; 
	
	PlaceholderStack* = OBJECT(Stack)
	VAR top: ItemNode;

		PROCEDURE Push*(new: Node);
		VAR newI, head: ItemNode; ignore: ADDRESS;
		BEGIN
			NEW(newI, new);
			LOOP
				head := CAS(top, NIL, NIL);
				IGNORE CAS(newI.next, newI.next, head);
				IF CAS(top, head, newI) = head THEN
					RETURN;
				END;
			END;
		END Push;

		PROCEDURE Pop*(): Node;
		VAR head, next: ItemNode;
		BEGIN
			LOOP
				head := CAS(top, NIL, NIL);
				IF head = NIL THEN 
					RETURN NIL
				END;
				next := CAS(head.next, NIL, NIL);
				IF CAS(top, head, next) = head THEN
					RETURN head.item;
				END;
			END;
		END Pop;

	END PlaceholderStack; 

END Stack.


