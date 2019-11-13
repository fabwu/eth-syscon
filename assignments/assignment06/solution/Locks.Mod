MODULE Locks;

(*
Recursive locks.  The critical regions protected by these locks may
be re-entered by the process holding them.

Usage:

VAR lock: RecursiveLock;

	NEW(lock);
	...
	lock.Acquire();
	... (* critical section (without AWAIT) *)
	lock.Release()

*)

(* Hint: Get the currently active object by using this call: Objects.ActiveObject();
	A variable that can point to any type of object is declared with type ANY.
	Example: object: ANY; *)

IMPORT
	Objects;

TYPE

	(** Implements a recursive lock *)
	RecursiveLock* = OBJECT
	VAR
		lockLevel : INTEGER;
		lockedBy : ANY;

		PROCEDURE &New*;
		BEGIN
			lockLevel := 0; lockedBy := NIL
		END New;

		(** acquire a lock on the object *)
		PROCEDURE Acquire*;
		VAR me : ANY;
		BEGIN {EXCLUSIVE}
			me := Objects.ActiveObject();
			IF lockedBy = me THEN
				INC(lockLevel);
			ELSE
				AWAIT(lockedBy = NIL);
				lockedBy := me; lockLevel := 1
			END;
		END Acquire;

		(** release the read/write lock on the object *)
		(** MUST hold lock *)
		PROCEDURE Release*;
		BEGIN {EXCLUSIVE}
			ASSERT(HasLock(), 3010);
			DEC(lockLevel);
			IF lockLevel = 0 THEN lockedBy := NIL END
		END Release;

		PROCEDURE HasLock*() : BOOLEAN;
		BEGIN
			RETURN lockedBy = Objects.ActiveObject();
		END HasLock;

	END RecursiveLock;

END Locks.
