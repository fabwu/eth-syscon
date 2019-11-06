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

		PROCEDURE Push*(node: Node);
		END Push;

		PROCEDURE Pop*(): Node;
		END Pop;

	END BlockingStack; 
	
	LockfreeStack* = OBJECT(Stack)

		PROCEDURE Push*(new: Node);
		END Push;

		PROCEDURE Pop*(): Node;
		END Pop;

	END LockfreeStack; 
		
	PlaceholderStack* = OBJECT(Stack)

		PROCEDURE Push*(new: Node);
		END Push; 
		
		PROCEDURE Pop*(): Node;
		END Pop;

	END PlaceholderStack; 

END Stack.


