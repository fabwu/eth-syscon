MODULE Heaps; (* fof, dynamic allocation runtime for TRM / Active Cells *)

IMPORT SYSTEM, TRMRuntime;

CONST AddressSize=1;
		ArrayAlignment = 8;
VAR adr-: INTEGER;

PROCEDURE NewSys*(VAR p: ANY; size: SIZE; isRealtime: BOOLEAN);
BEGIN
	p := SYSTEM.VAL(ANY, adr);
	INC(adr, size);
END NewSys;

PROCEDURE NewRec*(VAR p: ANY; tag: ADDRESS; isRealtime: BOOLEAN);
VAR size: INTEGER;
BEGIN
	SYSTEM.PUT(adr,tag);
	INC(adr);
	p := SYSTEM.VAL(ANY, adr);
	SYSTEM.GET(tag,size);
	INC(adr, size);
END NewRec;

(** NewArr - Implementation of NEW with an array containing pointers. *)
PROCEDURE NewArr*(VAR p: ANY; elemTag: ADDRESS; numElems, numDims: SIZE; isRealtime: BOOLEAN);
VAR elemSize, arrSize, size,arrayDataOffset: SIZE;
BEGIN
	SYSTEM.GET(elemTag, elemSize);
	arrSize := numElems * elemSize;
	arrayDataOffset := numDims * AddressSize + 3 * AddressSize;
	(* presumably not necessary
	INC(arrayDataOffset, (-arrayDataOffset) MOD ArrayAlignment);  (* round up to multiple of ArrayAlignment to ensure that first array element is aligned at 0 MOD ArrayAlignment *)
	*)
	size := arrayDataOffset + arrSize;
	NewSys(p, size, isRealtime);
END NewArr;

BEGIN
	adr := TRMRuntime.lastDataAddress;
END Heaps.

