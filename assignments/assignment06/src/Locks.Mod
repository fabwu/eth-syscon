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

		(** initializer, will be called when object is instantiated *)
		PROCEDURE &New*;
		BEGIN
		END New;

		(** acquire a lock on the object *)
		PROCEDURE Acquire*;
		VAR me : ANY;
		BEGIN {EXCLUSIVE}
		END Acquire;

		(** release the read/write lock on the object *)
		PROCEDURE Release*;
		BEGIN {EXCLUSIVE}
		END Release;

	END RecursiveLock;

END Locks.
