(* Runtime support for Mutexes *)

MODULE Mutexes;

IMPORT Activities, Queues;

(** Represents a synchronization object which acquires mutually exclusive access to shared resources. *)
TYPE 
	Mutex* = RECORD
		owner {UNTRACED} := NIL: Activities.Activity; (* stores the activity that has currently acquired the mutex, or NIL if it is not acquired *)
		q: Queues.Queue;
	END;	

(** Acquires mutual exclusive access to shared resources that are associated with a mutex. *)
(** If the mutex is currently acquired by some other activity, this procedure waits until it gets exclusive access to it. *)
PROCEDURE Acquire- (VAR mutex: Mutex);
VAR currentActivity {UNTRACED}, nextAct: Activities.Activity;
BEGIN
	currentActivity := Activities.GetCurrentActivity();
	WHILE CAS(mutex.owner, NIL, currentActivity) # NIL DO
		IF Activities.Select (nextAct, Activities.IdlePriority) THEN 
			Activities.SwitchTo (nextAct, Enqueue, ADDRESS OF mutex); 
			Activities.FinalizeSwitch; 
		END;
	END;

	(* Spin Lock *)
	(*  *)
	(* currentActivity := Activities.GetCurrentActivity (); *)
	(* LOOP *)
		(* IF CAS(mutex.owner, NIL, currentActivity) = NIL THEN EXIT END; *)
	(* END; *)
END Acquire;

PROCEDURE Enqueue(previous {UNTRACED}: Activities.Activity; m {UNTRACED}: POINTER {UNSAFE} TO Mutex);
VAR it: Queues.Item;
BEGIN
	Queues.Enqueue(previous, (m^).q);

	(* TODO: Check here if lock has been released and if so dequeue activity *)
END Enqueue;

(** Releases the mutual exclusive access to shared resources that are associated with a mutex. *)
(** This procedure must be called once after each corresponding call to the Mutexes.Acquire procedure. *)
(** A mutex may not be released if it was not acquired by the same activity beforehand. *)
PROCEDURE Release- (VAR mutex: Mutex);
VAR currentActivity {UNTRACED}: Activities.Activity; it: Queues.Item;
BEGIN
	currentActivity := Activities.GetCurrentActivity();
	ASSERT(CAS(mutex.owner, currentActivity, NIL) = currentActivity);

	IF Queues.Dequeue(it,mutex.q) THEN
		Activities.Resume((it (Activities.Activity)));
	END;

	(* Spin Lock *)
	(*  *)
	(* currentActivity := Activities.GetCurrentActivity (); *)
	(* reset the owner and check for consistency *)
	(* ASSERT(CAS(mutex.owner, currentActivity, NIL) = currentActivity); *)
END Release;

END Mutexes.
