MODULE Heaps; (* originally called "MAU" *) (* Memory Allocation Unit; NW 15.12.2007*)
(* These procedures must remain in this order!*)

IMPORT SYSTEM, Platform;  

VAR 
	heapStart	: ADDRESS;	
	heap		: ADDRESS;   	(*origin of free space*)
	heapEnd	: ADDRESS;

	PROCEDURE New*( VAR p: ADDRESS;  T: ADDRESS);   (*1*)
	(*allocate record, add tag field of 1 word with offset -4*)
	VAR size: SIZE;  
	BEGIN 
		p := heap + 4;  
		SYSTEM.PUT( heap, T );   (*adr of type descriptor (tag) to tagfield of new record*)
		SYSTEM.GET( T, size );   (*obtain record size from type descriptor*)
		heap := p + size;
		ASSERT(heap < heapEnd);
	END New; 
	
	PROCEDURE AllocH*(VAR a: ADDRESS; len, elsize: SIZE);  (*2*)
		(*allocate open array on heap, prefix with size field of 1 word with offset -4*)
	VAR adr: ADDRESS; size: SIZE;
	BEGIN
		size := len * elsize + 4; adr := ADDRESSOF(a);
		SYSTEM.PUT(adr, heap - 12);   (*address of array into descriptor*)
		SYSTEM.PUT(adr-4, len);   (*length of array into descriptor*)
		SYSTEM.PUT(heap, size);   (*size of block into header*)
		heap := heap + size;

		ASSERT(heap < heapEnd);
	END AllocH;

	PROCEDURE AllocS*(VAR a: ADDRESS; len, elsize: SIZE);  (*3*)
		(*allocate open array on stack*)
	VAR adr: ADDRESS;
	BEGIN adr := ADDRESSOF(a); SYSTEM.SETSP(SYSTEM.SP() - len * elsize);
		SYSTEM.PUT(adr, SYSTEM.SP());   (*address of array into descriptor*)
		SYSTEM.PUT(adr-4, len)   (*length of array into descriptor*)
	END AllocS;
	
	PROCEDURE Alloc*( VAR adr: ADDRESS;  size: SIZE);
	(*allocate area from free space*)
	BEGIN 
		adr := heap;
		heap := heap + size;
		ASSERT(heap < heapEnd);
	END Alloc;  
	
	PROCEDURE HeapSize*(): SIZE;
	BEGIN
		RETURN heapEnd - heapStart
	END HeapSize;
	
	PROCEDURE Free*(): SIZE;
	BEGIN
		RETURN heapEnd - heap
	END Free;
	
	(* PROCEDURES THAT ARE USED BY THE FOX COMPILER *)
	
	(** NewSys - Implementation of SYSTEM.NEW. **)
	PROCEDURE NewSys*(VAR pointer: ANY; size: SIZE; isRealtime: BOOLEAN);
	VAR
		pointerAsInteger: ADDRESS;
	BEGIN	
		Alloc(pointerAsInteger, size);
		pointer := SYSTEM.VAL(ANY, pointerAsInteger)
	END NewSys;

	(** NewRec - Implementation of NEW with a record.
	- this is essentially a wrapper that calls New(...) **)
	PROCEDURE NewRec*(VAR pointer: ANY; typeTag: ADDRESS; isRealtime: BOOLEAN);
	VAR
		pointerAsInteger: ADDRESS;
	BEGIN
		New(pointerAsInteger, typeTag);
		pointer := SYSTEM.VAL(ANY, pointerAsInteger)
	END NewRec;

	(** NewArr - Implementation of NEW with an array containing pointers. *)
	PROCEDURE NewArr*(VAR p: ANY; elemTag: ADDRESS; numElems, numDims: SIZE; isRealtime: BOOLEAN);
	VAR
		openArray: ARRAY 2 OF ADDRESS;
	BEGIN
		AllocH(openArray[1], numElems * numDims, SYSTEM.GET32(elemTag));
		p := SYSTEM.VAL(ANY, openArray[1]);
	END NewArr;

	
	(* replacement for overcomplicated code emission -- at the cost of a slightly increased runtime cost *)
	PROCEDURE NewArray*(CONST a: ARRAY OF SIZE;  tag: ADDRESS; staticElements, elementSize: SIZE; VAR dest: ANY);
	TYPE
		UnsafeArray= POINTER {UNSAFE} TO UnsafeArrayDesc;
		UnsafeArrayDesc = RECORD
			header : ARRAY 3 OF ADDRESS; 
			len: ARRAY 8 OF SIZE;
		END;
	VAR p: ANY; dim: SIZE;
			
			PROCEDURE GetSize(): SIZE;
			VAR i: SIZE; size: SIZE;
			BEGIN
				size := 1;
				FOR i := 0 TO dim-1 DO
					size := size * a[i];
				END;
				RETURN size*staticElements;
			END GetSize;
			
			PROCEDURE SetSizes(dest: UnsafeArray);
			VAR i: SIZE;
			BEGIN
				FOR i := 0 TO dim-1 DO
					dest.len[i] := a[dim-1-i];
				END;
			END SetSizes;

		BEGIN
			(* static elements is requred for this case : POINTER TO ARRAY OF ARRAY X OF RecordWithPointer *)
			dim := LEN( a,0 );
			IF tag = NIL THEN
				NewSys(p, GetSize() * elementSize + dim * SIZEOF(ADDRESS) + 3 *SIZEOF(ADDRESS) + (dim DIV 2) * 2 * SIZEOF(ADDRESS), FALSE);
			ELSE
				NewArr(p, tag, GetSize(), dim, FALSE);
			END;
			SetSizes(p);
			dest := p;
	END NewArray;

BEGIN 
	 (* Init heap, currently done manually *)
	heapStart := Platform.HeapBase; heap := Platform.HeapBase;  heapEnd := Platform.HeapEnd;
END Heaps.

