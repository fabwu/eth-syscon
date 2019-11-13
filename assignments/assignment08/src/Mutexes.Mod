(* Runtime support for Mutexes *)

MODULE Mutexes;

IMPORT Activities;

(** Represents a synchronization object which acquires mutually exclusive access to shared resources. *)
TYPE 
	Mutex* = RECORD
		owner {UNTRACED} := NIL: Activities.Activity; (* stores the activity that has currently acquired the mutex, or NIL if it is not acquired *)
	END;

(** Acquires mutual exclusive access to shared resources that are associated with a mutex. *)
(** If the mutex is currently acquired by some other activity, this procedure waits until it gets exclusive access to it. *)
PROCEDURE Acquire- (VAR mutex: Mutex);
VAR currentActivity {UNTRACED}: Activities.Activity;
BEGIN
	currentActivity := Activities.GetCurrentActivity ();
END Acquire;

(** Releases the mutual exclusive access to shared resources that are associated with a mutex. *)
(** This procedure must be called once after each corresponding call to the Mutexes.Acquire procedure. *)
(** A mutex may not be released if it was not acquired by the same activity beforehand. *)
PROCEDURE Release- (VAR mutex: Mutex);
VAR currentActivity {UNTRACED}: Activities.Activity; 
BEGIN
	currentActivity := Activities.GetCurrentActivity ();	
	(* reset the owner and check for consistency *)
END Release;

END Mutexes.
