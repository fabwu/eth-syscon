(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: ActiveCells Hardware Description Language (HDL) generation backend
*)
module AcHdlBackend;

import
	system, Strings, FoxBasic, Diagnostics, Streams, BitSets, Commands, Files,
	Modules, Locks, FSTools, PathTools, Options,
	KernelLog, Debugging, FoxBackend, FoxIntermediateLinker, FoxFormats, SyntaxTree := FoxSyntaxTree, ActiveCellsRuntime,
	CryptoHashes, CryptoUtils, HostOsApps, Pipes;

const
	ErrNotInitialized* = 1; (** lack of proper initialization *)
	ErrInvalidName* = 2; (** object has an invalid name *)
	ErrInvalidType* = 3; (** object has invalid type *)
	ErrInvalidValue* = 4; (** invalid/unsupported value *)
	ErrAlreadyExists* = 5; (** item already exists *)
	ErrNotDefined* = 6; (** an object is not defined *)
	ErrNotFound* = 7; (** object was not found *)
	ErrTypeMismatch* = 8; (** object type mismatch *)
	ErrTimeoutExpired* = 9; (** timeout has expired while execution an operation *)
	ErrExternal* = 10; (** error reported by an external tool *)
	ErrNotImplemented* = 256; (** not yet implemented functionality *)

	ErrUnexpected* = -1; (** an unexpected error *)

	(** port directions *)
	Out* = 0;
	In* = 1;
	Inout* = 2;

	(** Pull types *)
	PullNone* = 0;
	PullUp* = 1;
	PullDown* = 2;

	(** Signal polarity types *)
	UndefinedPolarity* = 0;
	ActiveHigh* = 1;
	ActiveLow* = -1;

	Master* = true;
	Slave* = false;

	SystemClockName* = "SystemClock"; (** name of the system clock *)
	SystemResetName* = "SystemReset"; (** name of the system reset *)

	ExternalClockName* = "ExternalClock"; (** name of the external clock *)
	ClockGenName* = "ClockGen"; (** clock generator name *)

	MainClockInputName* = "clock"; (* name of the main clock input port of a cell *)
	MainResetInputName* = "reset"; (* name of the main reset input port a cell *)

	DefaultProcessorType* = "TRM"; (** default processor type *)

	DefaultChanDepth* = 0; (** default channel depth in number of elements *)

	PropGroupId* = "GroupId";
	PropSourceClock* = "Source";
	PropFrequency* = "Frequency";
	PropPeriod* = "Period";
	PropDutyCycle* = "DutyCycle";
	PropJitter* = "Jitter";
	PropMulFactor* = "MulFactor";
	PropDivFactor* = "DivFactor";
	PropPhase* = "Phase";

	FlagCommPort* = 0; (** flag for distinguishing pear-to-pear communication ports from other IO ports *)
	FlagSkipImplementation* = 1; (** flag for skipping HDL code generation (e.g. for a processor) *)
	FlagSoftwarePort* = 2; (** flag for distinguishig from a software and hardware-based communication port *)

	ObjFileExtension* = "GofW";

	TraceBackOnError* = false; (** produce a trace back output when an error occurres *)

	FingerprintAlgo = "CryptoMD5";
	FingerprintSize = 16;
	MaxFingerprintSize = 256;

	EngineCountLimit = -1; (*! limit for the number of engines in an ActiveCells project *)
	ProcessorCountLimit = -1; (*! limit for the number of processors in an ActiveCells project *)

	EnableTrace = false;

type
	IntegerType* = signed64;
	RealType* = float64;
	StringType* = array of char;
	SetType* = set;

	LongString* = array 2048 of char;
	
	LengthType = signed32;
	WidthType = signed32;
	DepthType = signed32;

const
	MinInteger* = min(IntegerType);
	MaxInteger* = max(IntegerType);

	(** machine precision for RealType *)
	Eps = 2.22D-16;

	Tab = 9X;

type

	(**
		ActiveCells design context
	*)
	Context* = object
	var
		res-: integer; (** error code for last error, 0 if no error occured *)
		diag-: Diagnostics.Diagnostics;

		lock: Locks.Lock;

		cellCounter: size;
		portCounter: size;

		procedure &InitContext*(diagnostics: Diagnostics.Diagnostics);
		var
			sdiag: Diagnostics.StreamDiagnostics;
			w: Streams.Writer;
		begin
			res := 0;
			if diagnostics = nil then
				new(w,KernelLog.Send,4096);
				new(sdiag,w); diag := sdiag;
			else
				diag := diagnostics;
			end;
		end InitContext;

		(**
			Lock the context for exclusive access
		*)
		procedure Lock*();
		begin
			lock.Acquire;
		end Lock;

		(**
			Unlock the context
		*)
		procedure Unlock*();
		begin
			lock.Release;
		end Unlock;

		(**
			Returns TRUE if the context is being locked by the current process
		*)
		procedure HasLock*(): boolean;
		begin
			return lock.HasLock();
		end HasLock;

		(**
			Process an error
		*)
		procedure Error*(const source: array of char; position, errorCode: integer; const message: array of char);
		begin
			if res # ErrUnexpected then (* do not produce the unexpected error message multiple times *)
				assert(errorCode # 0);
				res := errorCode; (*! remember the last error code *)
				diag.Error(source,position,message);
			end;
		end Error;

		(**
			Produce a warning
		*)
		procedure Warning*(const source: array of char; position, warningCode : integer; const message: array of char);
		begin
			diag.Warning(source,position,message);
		end Warning;

		(**
			Produce an info message
		*)
		procedure Information*(const source: array of char; position, infoCode: integer; const message: array of char);
		begin
			diag.Information(source,position,message);
		end Information;

		(**
			A message to show when a feature is not yet implemented
		*)
		procedure ErrorNotImplemented*(const message: array of char);
		begin
			Error("",Streams.Invalid,ErrNotImplemented,message);
		end ErrorNotImplemented;

		(**
			An unexpected error (e.g. a trap-caused error) message
		*)
		procedure ErrorUnexpected*();
		begin
			if res # ErrUnexpected then (* do not produce the error message multiple times *)
				res := ErrUnexpected;
				Error("",Streams.Invalid,res,"Unexpected error");
			end;
		end ErrorUnexpected;

		procedure ClearError*();
		begin
			res := 0;
		end ClearError;

	end Context;

	(**
		Object base type
	*)
	Object* = object
	var
		ctx-: Context; (** ActiveCells design context *)
		parent-: Object; (** reference to the parent object *)

		flags-: set; (** object specific flags *)

		procedure &InitObject*();
		begin
			ctx := globalContext;
		end InitObject;

		(** Get type name of the object *)
		procedure GetTypeName*(var typeName: array of char);
		var desc: Modules.TypeDesc;
		begin
			desc := Modules.TypeOf(self);
			copy(desc.name,typeName);
		end GetTypeName;

		(** Returns TRUE if the object has same type as a given object instance *)
		procedure HasSameTypeAs*(obj: Object): boolean;
		var desc1, desc2: Modules.TypeDesc;
		begin
			if obj # nil then
				desc1 := Modules.TypeOf(self);
				desc2 := Modules.TypeOf(obj);
				return desc1.name = desc2.name;
			else return false;
			end;
		end HasSameTypeAs;

		(**
			Setup the context of the HDL object
		*)
		procedure SetContext*(context: Context);
		begin
			ctx := context;
		end SetContext;

		(*
			Create a new instance of the object type
		*)
		procedure New(): Object;
		var
			typeDesc: Modules.TypeDesc;
		begin
			typeDesc := Modules.TypeOf(self);
			return Modules.NewObj(typeDesc,false)(Object);
		end New;

		(**
			Copy the object
		*)
		procedure Copy*(): Object;
		var cpy: Object;
		begin
			cpy := New();
			CopyContent(cpy);
			return cpy;
		end Copy;

		(*
			Copy object content
		*)
		procedure CopyContent*(cpy: Object);
		begin
			cpy.ctx := ctx;
		end CopyContent;

		(*
			A helper procedure for simple generation of object-specific error messages
		*)
		procedure Error*(errorCode: integer; const message: array of char);
		begin
			ctx.Error("",Streams.Invalid,errorCode,message);
		end Error;

		(*
			A helper procedure for simple warning handling
		*)
		procedure Warning*(const message: array of char);
		begin
			ctx.Warning("",Streams.Invalid,Streams.Invalid,message);
		end Warning;

		(*
			A helper procedure for simple information message handling
		*)
		procedure Information*(const message: array of char);
		begin
			ctx.Information("",Streams.Invalid,Streams.Invalid,message);
		end Information;

		(**
			A message to show when a feature is not yet implemented
		*)
		procedure ErrorNotImplemented*(const message: array of char);
		begin
			ctx.ErrorNotImplemented(message);
		end ErrorNotImplemented;

		(**
			An unexpected error (e.g. a trap-caused error) message
		*)
		procedure ErrorUnexpected*();
		begin
			ctx.ErrorUnexpected;
		end ErrorUnexpected;

	end Object;

	(**
		Object list
	*)
	ObjectList* = object(Object)
	var
		list: FoxBasic.List;

		procedure &InitObjectList*(initSize: size);
		begin
			InitObject;
			new(list,initSize);
			list.multipleAllowed := false;
			list.nilAllowed := false;
		end InitObjectList;

		procedure SetContext(context: Context);
		var i, n: size;
		begin
			SetContext^(context);
			n := Length();
			for i := 0 to n-1 do
				list.Get(i)(Object).SetContext(context);
			end;
		end SetContext;

		(**
			Returns the length of the list
		*)
		procedure Length*(): size;
		begin
			return list.Length();
		end Length;

		(**
			Add an object to the list without overwriting the parent property of the object
		*)
		procedure Add0*(obj: Object);
		begin
			list.Add(obj);
		end Add0;

		(**
			Add an object to the list
		*)
		procedure Add*(obj: Object);
		begin
			obj.parent := self;
			list.Add(obj);
		end Add;

		(**
			Add entries from a list without overwriting the parent property of the objects
		*)
		procedure AddList0*(objList: ObjectList);
		var k: size;
		begin
			for k := 0 to objList.list.count-1 do Add0(objList.Get(k)); end;
		end AddList0;

		(**
			Add entries from a list
		*)
		procedure AddList*(objList: ObjectList);
		var k: size;
		begin
			for k := 0 to objList.list.count-1 do Add(objList.Get(k)); end;
		end AddList;

		(**
			Get an object from the list by its index
		*)
		procedure Get*(i: size): Object;
		var obj: any; n: size;
		begin
			n := list.Length();
			if (i >= 0) & (i < n) then
				obj := list.Get(i);
				if obj # nil then return obj(Object); else return nil; end;
			else return nil; end;
		end Get;

		(**
			Returns index of the specified object
		*)
		procedure IndexOf*(obj: Object): size;
		begin
			return list.IndexOf(obj);
		end IndexOf;

		(**
			Returns TRUE if the object is contained in the list
		*)
		procedure Contains*(obj: Object): boolean;
		begin
			return list.IndexOf(obj) >= 0;
		end Contains;

		(**
			Put object in the list at a location specified by index
		*)
		procedure Set*(i: size; obj: Object);
		begin
			list.Set(i,obj);
		end Set;

		(** Remove an object from the list *)
		procedure Remove*(obj: Object);
		begin
			list.Remove(obj);
		end Remove;

		(** Remove first entry in the list *)
		procedure RemoveFirst*();
		begin
			list.RemoveByIndex(0);
		end RemoveFirst;

		(** Remove last entry in the list *)
		procedure RemoveLast*();
		begin
			list.RemoveByIndex(list.Length()-1);
		end RemoveLast;

		(**
			Clear the list
		*)
		procedure Clear*();
		begin
			list.Clear;
		end Clear;

		procedure CopyContent(cpy: Object);
		var k: size;
		begin
			CopyContent^(cpy);
			with cpy : ObjectList do
				new(cpy.list,list.count);
				cpy.list.multipleAllowed := list.multipleAllowed;
				cpy.list.nilAllowed := list.nilAllowed;
				for k := 0 to list.count-1 do
					cpy.Add(Get(k).Copy());
				end;
			end;
		end CopyContent;

		(**
			Traverse all object in the list given a traversal function
		*)
		procedure Traverse*(func: procedure{DELEGATE}(obj: Object; param: any): boolean; param: any);
		var i, n: size;
		begin
			n := Length();
			while (i < n) & func(Get(i),param) do inc(i); end;
		end Traverse;

	end ObjectList;

	(** Procedure used for handling an object *)
	ObjectHandlerProc* = procedure{DELEGATE}(obj: Object; param: any): boolean;

	(*
		List of object handler procedures
	*)
	ObjectHandlerProcList = object(Object)
	var
		list: pointer to array of ObjectHandlerProc;
		count: size;

		procedure &InitObjectHandlerProcList(initialSize: size);
		begin
			new(list,initialSize); count := 0;
		end InitObjectHandlerProcList;

		procedure Length(): size;
		begin return count;
		end Length;

		procedure Add(proc: ObjectHandlerProc);
		begin
			if count = len(list) then Grow; end;
			list[count] := proc;
			inc(count);
		end Add;

		procedure Get(i: size): ObjectHandlerProc;
		begin
			if (i >= 0) & (i < count) then return list[i];
			else return nil;
			end;
		end Get;

		procedure IndexOf(proc: ObjectHandlerProc): size;
		var k: size;
		begin
			k := 0;
			while (k < count) & (proc # list[k]) do inc(k); end;

			if k < count then return k;
			else return -1;
			end;
		end IndexOf;

		procedure Grow();
		var
			k: size;
			old: pointer to array of ObjectHandlerProc;
		begin
			old := list;
			new(list,(len(list) * 3+1) div 2) ;
			for k := 0 to count - 1 do list[k] := old[k]; end;
		end Grow;

		procedure Clear();
		var k: size;
		begin
			for k := 0 to count-1 do list[k] := nil; end;
			count := 0;
		end Clear;

		procedure CopyContent(cpy: Object);
		var k: size;
		begin
			CopyContent^(cpy);
			with cpy : ObjectHandlerProcList do
				new(cpy.list,count);
				for k := 0 to count-1 do cpy.Add(Get(k)); end;
			end;
		end CopyContent;

	end ObjectHandlerProcList;

	(**
		Generic value type
	*)
	Value* = object(Object)

		procedure &InitValue();
		begin
			InitObject;
		end InitValue;

		(**
			Convert the value to a type specified by a prototype instance

			Returns NIL in case if the conversion is not possible
		*)
		procedure To*(proto: Value): Value;
		begin
			if proto is BinaryValue then return ToBinaryValue();
			elsif proto is Boolean then return ToBoolean();
			elsif proto is Integer then return ToInteger();
			elsif proto is Real then return ToReal();
			elsif proto is String then return ToString();
			elsif proto is Set then return ToSet();
			end;
			return nil;
		end To;

		(**
			Get binary representation of the value

			Returns NIL in case if the conversion is not possible
		*)
		procedure ToBinaryValue*(): BinaryValue;
		begin
			return nil;
		end ToBinaryValue;

		(**
			Get boolean representation of the value

			Returns NIL in case if the conversion is not possible
		*)
		procedure ToBoolean*(): Boolean;
		begin
			return nil;
		end ToBoolean;

		(**
			Get integer representation of the value

			Returns NIL in case if the conversion is not possible
		*)
		procedure ToInteger*(): Integer;
		begin
			return nil;
		end ToInteger;

		procedure ToSet*(): Set;
		begin
			return nil;
		end ToSet;

		(**
			Get float32 representation of the value

			Returns NIL in case if the conversion is not possible
		*)
		procedure ToReal*(): Real;
		begin
			return nil;
		end ToReal;

		(**
			Get string representation of the value

			Returns NIL in case if the conversion is not possible
		*)
		procedure ToString*(): String;
		begin
			return nil;
		end ToString;

		(** Returns TRUE if the value is same as the specified value *)
		procedure SameAs*(v: Value): boolean;
		begin
			halt(100);
		end SameAs;

		(** print value in HDL code *)
		procedure HdlPrint*(w: Streams.Writer);
		begin
			halt(100);
		end HdlPrint;

		(**
			Returns a copy of the value
		*)
		procedure CopyValue*(): Value;
		begin
			return Copy()(Value);
		end CopyValue;

	end Value;

	BinaryValue* = object(Value)
	var
		val-: Strings.String; (** binary value in HEX format *)

		procedure &InitBinaryValue(const value: array of char);
		var n: size;
		begin
			InitValue;
			if CheckBinaryValueFormat(value) then
				val := NormalizeValue(value);
				n := Strings.Length(val^);
			else
				val := nil;
			end;
		end InitBinaryValue;

		procedure NormalizeValue(const value: array of char): Strings.String;
		var n: size;
		begin
			n := Strings.Length(value);
			if cap(value[n-1]) = 'H' then
				new(result,n);
				Strings.Copy(value,0,n-1,result^);
			elsif (value[0] = '0') & (cap(value[1]) = 'X') then
				new(result,n-1);
				Strings.Copy(value,2,n-2,result^);
			else
				result := nil;
			end;
			return result;
		end NormalizeValue;

		(**
			Get the number of bits used to represent the current binary value
		*)
		procedure GetNumBits*(): size;
		begin
			if val # nil then
				return Strings.Length(val^)*4;
			else
				return 0;
			end;
		end GetNumBits;

		procedure ToBinaryValue*(): BinaryValue;
		begin
			return self;
		end ToBinaryValue;

		procedure ToInteger(): Integer;
		var
			x: IntegerType;
			k, n: size;
			ch: char;
		begin
			n := GetNumBits();
			if n <= sizeof(IntegerType)*8 then
				x := 0;
				for k := 0 to n-1 do
					ch := val[k];
					if (ch >= "0") & (ch <= "9") then x := 16 * x + ord(ch) - ord("0");
					elsif (cap(ch) >= "A") & (cap(ch) <= "F") then x := 16 * x + ord(cap(ch)) - ord("A") + 10;
					else halt(100);
					end;
				end;
				new(result,x);
			else
				result := nil;
			end;

			return result;
		end ToInteger;

		procedure SameAs(v: Value): boolean;
		begin
			return (v # nil) & (v is BinaryValue) & (v(BinaryValue).val^ = val^);
		end SameAs;

		procedure HdlPrint(w: Streams.Writer);
		begin
			assert(val # nil);
			w.Int(GetNumBits(),0); w.String("'h"); w.String(val^);
		end HdlPrint;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			cpy(BinaryValue).val := Strings.NewString(val^);
		end CopyContent;

	end BinaryValue;

	(**
		Boolean value
	*)
	Boolean* = object(Value)
	var
		val-: boolean;

		procedure &InitBoolean*(value: boolean);
		begin
			InitValue;
			val := value;
		end InitBoolean;

		procedure ToBinaryValue(): BinaryValue;
		begin
			if val then
				new(result,"1H");
			else
				new(result,"0H");
			end;
			return result;
		end ToBinaryValue;

		procedure ToBoolean(): Boolean;
		begin
			return self;
		end ToBoolean;

		procedure ToInteger(): Integer;
		begin
			if val then new(result,1);
			else new(result,0); end;
			return result;
		end ToInteger;

		procedure ToReal(): Real;
		begin
			if val then new(result,1);
			else new(result,0); end;
			return result;
		end ToReal;

		procedure ToString(): String;
		var str: array 64 of char;
		begin
			if val then str := "TRUE"; else str := "FALSE"; end;
			new(result,str);
			return result;
		end ToString;

		procedure SameAs(v: Value): boolean;
		begin
			return (v # nil) & (v is Boolean) & (v(Boolean).val = val);
		end SameAs;

		procedure HdlPrint(w: Streams.Writer);
		begin
			if val then w.Char("1"); else w.Char("0"); end;
		end HdlPrint;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			cpy(Boolean).val := val;
		end CopyContent;

	end Boolean;

	(**
		Integer value
	*)
	Integer* = object(Value)
	var
		val-: IntegerType;

		procedure &InitInteger*(value: IntegerType);
		begin
			InitValue;
			val := value;
		end InitInteger;

		procedure ToBinaryValue(): BinaryValue;
		var str: LongString;
		begin
			IntToHexStr(val,-1,str);
			new(result,str);
			return result;
		end ToBinaryValue;

		procedure ToInteger(): Integer;
		begin
			return self;
		end ToInteger;

		procedure ToReal(): Real;
		begin
			new(result,val);
			return result;
		end ToReal;

		procedure ToString(): String;
		var str: array 64 of char;
		begin
			IntegerToStr(val,str); new(result,str);
			return result;
		end ToString;

		procedure SameAs(v: Value): boolean;
		begin
			return (v # nil) & (v is Integer) & (v(Integer).val = val);
		end SameAs;

		procedure HdlPrint(w: Streams.Writer);
		begin
			w.Int(val,0);
		end HdlPrint;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			cpy(Integer).val := val;
		end CopyContent;

	end Integer;

	(**
		Set value
	*)
	Set* = object(Value)
	var
		val-: SetType;

		procedure &InitSet*(value: SetType);
		begin
			InitValue;
			val := value;
		end InitSet;

		procedure ToSet(): Set;
		begin
			return self;
		end ToSet;

		procedure ToInteger(): Integer;
		var
			i: size;
			x: IntegerType;
		begin
			x := 0;
			for i := 0 to sizeof(SetType)*8-1 do
				if i in val then inc(x,lsh(IntegerType(1),i)); end;
			end;
			new(result,x);
			return result;
		end ToInteger;

		procedure ToBinaryValue(): BinaryValue;
		var
			str: LongString;
			i: size;
			x: IntegerType;
		begin
			x := 0;
			for i := 0 to sizeof(SetType)*8-1 do
				if i in val then inc(x,lsh(IntegerType(1),i)); end;
			end;
			IntToHexStr(x,-1,str);
			Strings.Append(str,"H");
			new(result,str);
			return result;
		end ToBinaryValue;

		procedure SameAs(v: Value): boolean;
		begin
			return (v # nil) & (v is Set) & (v(Set).val = val);
		end SameAs;

		procedure HdlPrint(w: Streams.Writer);
		begin
			ToBinaryValue().HdlPrint(w);
		end HdlPrint;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			cpy(Set).val := val;
		end CopyContent;

	end Set;

	(**
		Real value
	*)
	Real* = object(Value)
	var
		val-: RealType;

		procedure &InitReal*(value: RealType);
		begin
			InitValue;
			val := value;
		end InitReal;

		procedure ToBinaryValue(): BinaryValue;
		var str: LongString;
		begin
			assert(sizeof(IntegerType) = sizeof(RealType));
			IntToHexStr(system.val(IntegerType,val),-1,str);
			new(result,str);
			return result;
		end ToBinaryValue;

		procedure ToInteger(): Integer;
		var v: IntegerType;
		begin
			v := Round(val);
			if abs(val-v) < Eps then
				new(result,v);
			else
				result := nil;
			end;
			return result;
		end ToInteger;

		procedure ToReal(): Real;
		begin
			return self;
		end ToReal;

		procedure ToString(): String;
		var str: array 64 of char;
		begin
			RealToStr(val,str); new(result,str);
			return result;
		end ToString;

		procedure SameAs(v: Value): boolean;
		begin
			return (v # nil) & (v is Real) & (v(Real).val = val);
		end SameAs;

		procedure HdlPrint(w: Streams.Writer);
		begin
			w.Float(val,27);
		end HdlPrint;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			cpy(Real).val := val;
		end CopyContent;

	end Real;

	(**
		String value
	*)
	String* = object(Value);
	var
		val-: Strings.String;

		procedure &InitString*(const value: array of char);
		begin
			InitValue;
			val := Strings.NewString(value);
		end InitString;

		procedure ToString*(): String;
		begin
			return self;
		end ToString;

		procedure SameAs(v: Value): boolean;
		begin
			return (v # nil) & (v is String) & (v(String).val^ = val^);
		end SameAs;

		procedure HdlPrint(w: Streams.Writer);
		begin
			w.Char('"'); w.String(val^); w.Char('"');
		end HdlPrint;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			cpy(String).val := Strings.NewString(val^);
		end CopyContent;

	end String;

	(**
		String list
	*)
	StringList* = object(ObjectList)

		(** Get string vaue by its index *)
		procedure GetString*(i: size): String;
		var obj: Object;
		begin
			obj := Get(i);
			if obj # nil then return obj(String);
			else return nil;
			end;
		end GetString;

		procedure IndexOf1*(const str: array of char): size;
		var k: size;
		begin
			k := 0;
			while (k < list.count) & (GetString(k).val^ # str) do inc(k); end;

			if k < list.count then return k;
			else return -1;
			end;
		end IndexOf1;

	end StringList;

	(**
		HDL object
	*)
	HdlObject* = object(Object)
	var
		acName-: Strings.String; (** name in ActiveCells *)
		hdlName-: Strings.String; (** name in HDL *)
		description-: Strings.String; (** description text, if available *)

		procedure &InitHdlObject*(const nameInAc, nameInHdl: array of char);
		begin
			InitObject;
			if nameInAc # "" then acName := Strings.NewString(nameInAc); else acName := nil; end;
			if nameInHdl # "" then hdlName := Strings.NewString(nameInHdl); else hdlName := nil; end;
		end InitHdlObject;

		(**
			Set object name in ActiveCells
		*)
		procedure SetAcName*(const nameInAc: array of char);
		begin
			if nameInAc # "" then acName := Strings.NewString(nameInAc); else acName := nil; end;
		end SetAcName;

		(**
			Set object name in HDL
		*)
		procedure SetHdlName*(const nameInHdl: array of char);
		begin
			if nameInHdl # "" then hdlName := Strings.NewString(nameInHdl); else hdlName := nil; end;
		end SetHdlName;

		(**
			Get the reference to the parent HDL project
		*)
		procedure GetProject*(): HdlProject;
		begin
			if ctx is HdlProject then return ctx(HdlProject); else return nil; end;
		end GetProject;

		(**
			Get the reference to the target specification object
		*)
		procedure GetTarget*(): TargetDevice;
		begin
			if ctx is HdlProject then return ctx(HdlProject).target; else return nil; end;
		end GetTarget;

		(**
			Set object description
		*)
		procedure SetDescription*(const descr: array of char);
		begin
			description := Strings.NewString(descr);
		end SetDescription;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : HdlObject do
				(*! copy strings by reference since no runtime modifications are envisioned *)
				cpy.acName := acName;
				cpy.hdlName := hdlName;
				cpy.description := description;
			end;
		end CopyContent;

	end HdlObject;

	(**
		HDL object list
	*)
	HdlObjectList* = object(ObjectList)

		(** Get object by its index *)
		procedure GetObj*(i: size): HdlObject;
		var obj: Object;
		begin
			obj := Get(i);
			if obj # nil then return obj(HdlObject);
			else return nil;
			end;
		end GetObj;

		(** Get object by its ActiveCells name *)
		procedure GetObjByAcName*(const name: array of char): HdlObject;
		var
			i, n: size;
			obj: HdlObject;
		begin
			i := 0; n := list.Length();
			while i < n do
				obj := GetObj(i);
				if (obj.acName # nil) & (obj.acName^ = name) then return obj; end;
				inc(i);
			end;
			return nil;
		end GetObjByAcName;

		(** Get object by its HDL name *)
		procedure GetObjByHdlName*(const name: array of char): HdlObject;
		var
			i, n: size;
			obj: HdlObject;
		begin
			i := 0; n := list.Length();
			while i < n do
				obj := GetObj(i);
				if (obj.hdlName # nil) & (obj.hdlName^ = name) then return obj; end;
				inc(i);
			end;
			return nil;
		end GetObjByHdlName;

	end HdlObjectList;

	(**
		Procedure type for checking the value of a cell property
	*)
	CheckPropertyValueProc* = procedure{DELEGATE}(prop: Property; val: Value): boolean;

	(**
		Cell property
	*)
	Property* = object(HdlObject)
	var
		value-: Value; (** property value *)
		checkValue-: CheckPropertyValueProc; (* pointer to the procedure that checks the value of the property to be set for correctness *)

		(**
			Create a property

			nameInAc: name of the property in ActiveCells code
			nameInHdl: name of the property in HDL code (HDL parameter name)
			initValue: initial value of the property (serves as a prototype)
			checkValueProc: pointer to the procedure that checks the value of the property to be set for correctness
		*)
		procedure &InitProperty*(
								const nameInAc, nameInHdl: array of char;
								initValue: Value;
								checkValueProc: procedure{DELEGATE}(prop: Property; val: Value): boolean
								);
		begin
			InitHdlObject(nameInAc,nameInHdl);
			assert(initValue # nil);
			value := initValue;
			value.parent := self;
			checkValue := checkValueProc;
		end InitProperty;

		(**
			Set value of the property

			val: value to set
		*)
		procedure SetValue*(val: Value): boolean;
		var old: Value;
		begin
			if val = nil then
				Error(ErrInvalidValue,"specified value is NIL");
				return false;
			end;

			old := val;

			(* check for possiblity to convert "val" to the type of "value" *)
			val := val.To(value);
			if val = nil then
				Error(ErrInvalidType,"conversion to the property value type is not possible");
				return false;
			end;

			if (checkValue = nil) or checkValue(self,val) then
				if old # val then value := val; else value := val.CopyValue(); end;
				value.parent := self;
				return true;
			elsif ctx.res = 0 then
				Error(ErrUnexpected,"the value of the property did not pass the check");
			end;
			return false;
		end SetValue;

		(**
			Get parent cell
		*)
		procedure GetCell*(): Cell;
		begin
			return parent(PropertyList).parent(Cell);
		end GetCell;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : Property do
				cpy.value := value.CopyValue(); cpy.value.parent := cpy;
				cpy.checkValue := checkValue;
			end;
		end CopyContent;

		procedure Error(errorCode: integer; const message: array of char);
		var
			str: LongString;
			c: Cell;
		begin
			c := parent(PropertyList).parent(Cell);
			str := "cell ";
			if c.acInstName # nil then
				Strings.Concat(str,'instance "',str);
				Strings.Concat(str,c.acInstName^,str);
				Strings.Concat(str,'" ',str);
			end;
			Strings.Concat(str,'of type "',str);
			Strings.Concat(str,c.acName^,str);
			Strings.Concat(str,'", property "',str);
			Strings.Concat(str,self(Property).acName^,str);
			Strings.Concat(str,' of type "',str);
			
			if value is BinaryValue then str := str & 'BinaryValue"';
			elsif value is Boolean then str := str & 'Boolean"';
			elsif value is Integer then str := str & 'Integer"';
			elsif value is Set then str := str & 'Set"';
			elsif value is Real then str := str & 'Real"';
			elsif value is String then str := str & 'String"';
			else
				halt(100);
			end;
			ctx.Error(str,Streams.Invalid,errorCode,message);
		end Error;

		procedure Warning(const message: array of char);
		var
			str: LongString;
			c: Cell;
		begin
			c := parent(PropertyList).parent(Cell);
			str := "cell";
			if c.acInstName # nil then
				Strings.Concat(str,' instance "',str);
				Strings.Concat(str,c.acInstName^,str);
				Strings.Concat(str,'", ',str);
			end;
			Strings.Concat(str,'of type "',str);
			Strings.Concat(str,c.acName^,str);
			Strings.Concat(str,'", property "',str);
			Strings.Concat(str,self(Property).acName^,str);
			Strings.Concat(str,'"',str);
			ctx.Warning(str,Streams.Invalid,Streams.Invalid,message);
		end Warning;

	end Property;

	(**
		Cell property list
	*)
	PropertyList* = object(HdlObjectList)

		(** Get property by its index *)
		procedure GetProperty*(i: size): Property;
		var obj: HdlObject;
		begin
			obj := GetObj(i);
			if obj # nil then return obj(Property);
			else return nil;
			end;
		end GetProperty;

		(** Get property by its ActiveCells name *)
		procedure GetPropertyByAcName*(const name: array of char): Property;
		var obj: HdlObject;
		begin
			obj := GetObjByAcName(name);
			if obj # nil then return obj(Property);
			else return nil;
			end;
		end GetPropertyByAcName;

		(** Get property by its HDL name *)
		procedure GetPropertyByHdlName*(const name: array of char): Property;
		var obj: HdlObject;
		begin
			obj := GetObjByHdlName(name);
			if obj # nil then return obj(Property);
			else return nil;
			end;
		end GetPropertyByHdlName;

	end PropertyList;

	(*
		A helper object used for checking the value of an integer property based on a specified range of property values
	*)
	IntegerPropertyRangeChecker = object(Object)
	var
		minVal: IntegerType; (* minimal permitted value *)
		maxVal: IntegerType; (* maximal permitted value *)

		procedure &InitConstraint(minValue, maxValue: IntegerType);
		begin
			InitObject;
			minVal := minValue;
			maxVal := maxValue;
		end InitConstraint;

		(*
			Returns TRUE if the given property value satisfies the range constraint
		*)
		procedure CheckValue(prop: Property; value: Value): boolean;
		var
			i: Integer;
			str: LongString;
			strNum: array 64 of char;
		begin
			i := value.ToInteger();
			if i = nil then
				prop.Error(ErrInvalidValue,"failed to convert the property value to Integer");
				return false;
			end;

			if (i.val >= minVal) & (i.val <= maxVal) then
				return true;
			else
				str := "property value ";
				IntegerToStr(i.val,strNum);
				Strings.Concat(str,strNum,str);
				Strings.Concat(str," is outside of the permitted range ",str);
				IntegerToStr(minVal,strNum);
				Strings.Concat(str,"[",str);
				Strings.Concat(str,strNum,str);
				if maxVal # MaxInteger then IntegerToStr(maxVal,strNum);
				else strNum := "inf";
				end;
				Strings.Concat(str,", ",str);
				Strings.Concat(str,strNum,str);
				Strings.Concat(str,"]",str);

				prop.Error(ErrInvalidValue,str);
				return false;
			end;
		end CheckValue;

	end IntegerPropertyRangeChecker;


	PortArray* = object(HdlObject)
	var
		length: size;
		lenArray: pointer to array of size;

		procedure &InitPortArray*
								(
									const nameInAc: array of char;
									aLen: size;
									aLenA: pointer to array of size
								);
		begin
			InitHdlObject(nameInAc,"");
			length := aLen;
			lenArray := aLenA;
		end InitPortArray;

	end PortArray;


	(**
		Port object
	*)
	Port* = object(HdlObject)
	var
		direction-: integer; (** port data direction: In, Out, Inout *)
		width-: size; (** port data width in number of bits, -1 if the width is specified by "widthProp" *)
		optional-: boolean; (** TRUE if the port is optional and can be unused *)
		unused-: boolean; (** TRUE if the port is unused; set by the runtime *)
		littleEndian-: boolean; (** TRUE for little endian; default is TRUE *)

		props-: PropertyList; (** list of port's properties *)

		channel-: Channel; (* reference to the channel*)
		channels-: ChannelList; (* list of channels in case if a single output port is connected to multiple input ports *)

		delegateOf-: CellnetPort;
		inArray: PortArray;

		procedure &InitPort*
								(
									const nameInAc, nameInHdl: array of char;
									portDirection: integer; portWidth: size
								);
		begin
			InitHdlObject(nameInAc,nameInHdl);
			direction := portDirection;
			width := portWidth;
			inArray := nil;
		end InitPort;

		procedure InArray(inA: PortArray);
		begin
			inArray := inA
		end InArray;

		(**
			Get parent cell object
		*)
		procedure GetCell*(): Cell;
		begin
			if parent is Port then
				return parent(Port).GetCell();
			else
				assert(parent is PortList);
				return parent(PortList).parent(Cell);
			end;
		end GetCell;

		(** Set/Clear port unused flag *)
		procedure SetUnused*(portIsUnused: boolean);
		begin
			unused := portIsUnused;
		end SetUnused;

		(**
			Setup port width
		*)
		procedure SetWidth*(w: size);
		begin
			assert(w >= 0);
			width := w;
		end SetWidth;

		(**
			Set endianness of the port data

			littleEndian: TRUE for little-endian, FALSE for big-endian
		*)
		procedure SetEndianness*(littleEndian: boolean);
		begin
			self.littleEndian := littleEndian;
		end SetEndianness;

		(**
			Set the port as optional
		*)
		procedure SetOptional*(optional: boolean);
		begin
			self.optional := optional;
		end SetOptional;

		(** Get a property by its ActiveCells name *)
		procedure GetPropertyByAcName*(const name: array of char): Property;
		begin
			if props # nil then
				return props.GetPropertyByAcName(name);
			else return nil;
			end;
		end GetPropertyByAcName;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : Port do
				cpy.direction := direction;
				cpy.width := width;
				cpy.optional := optional;
				cpy.unused := unused;
				cpy.littleEndian := littleEndian;
				cpy.flags := flags;
			end;
		end CopyContent;

	end Port;

	(**
		Port list
	*)
	PortList* = object(HdlObjectList)

		(** Get port by its index *)
		procedure GetPort*(i: size): Port;
		var obj: HdlObject;
		begin
			obj := GetObj(i);
			if obj # nil then return obj(Port);
			else return nil;
			end;
		end GetPort;

		(** Get port by its ActiveCells name *)
		procedure GetPortByAcName*(const name: array of char): Port;
		var obj: HdlObject;
		begin
			obj := GetObjByAcName(name);
			if obj # nil then return obj(Port);
			else return nil;
			end;
		end GetPortByAcName;

		(** Get port by its HDL name *)
		procedure GetPortByHdlName*(const name: array of char): Port;
		var obj: HdlObject;
		begin
			obj := GetObjByHdlName(name);
			if obj # nil then return obj(Port);
			else return nil;
			end;
		end GetPortByHdlName;

	end PortList;

	(*
		A helper object used for setting a port based on the value of a given property
	*)
	PortFromPropertySetter = object(Object)
	var
		portHdlName: Strings.String;
		propHdlName: Strings.String;

		procedure &Init(const portNameInHdl, propNameInHdl: array of char);
		begin
			InitObject;
			portHdlName := Strings.NewString(portNameInHdl);
			propHdlName := Strings.NewString(propNameInHdl);
		end Init;

		procedure SetPortWidth(obj: Object; par: any): boolean;
		var
			c: Cell;
			p: Port;
			prop: Property;
			v: Integer;
			str: LongString;
		begin
			c := obj(Cell);

			p := c.GetPortByHdlName(portHdlName^);
			if p = nil then
				Strings.Concat('could not find port with HDL name "',portHdlName^,str);
				Strings.Concat(str,'"',str);
				c.Error(ErrInvalidValue,str);
				return false;
			end;

			prop := c.GetPropertyByHdlName(propHdlName^);
			if prop = nil then
				Strings.Concat('could not find property with HDL name "',propHdlName^,str);
				Strings.Concat(str,'"',str);
				c.Error(ErrInvalidValue,str);
				return false;
			end;
			v := prop.value.ToInteger();
			if v = nil then
				Strings.Concat('could not convert the value of property "',propHdlName^,str);
				Strings.Concat(str,'" to integer',str);
				c.Error(ErrInvalidValue,str);
				return false;
			end;
			p.SetWidth(short(v.val));
			return true;
		end SetPortWidth;

	end PortFromPropertySetter;

	(**
		HDL port
	*)
	HdlPort* = object(Port)
	var
		isExternal-: boolean; (** TRUE if the port is external *)
		isDifferential-: boolean; (** TRUE if each port bit corresponds to a differential signal *)
		signalPolarity-: integer; (** polarity for all port signals: ActiveHigh, ActiveLow, UndefinedPolarity (default) *)

		(**
			Create an HDL port

			nameInAc: name of the port in ActiveCells code
			nameInHdl: name of the port in HDL code
			portDirection: direction of the port (In, Out or Inout)
			portWidth: width of the port in number of bits
		*)
		procedure &InitHdlPort*
									(
									const nameInAc, nameInHdl: array of char;
									portDirection: integer; portWidth: size
									);
		begin
			InitPort(nameInAc,nameInHdl,portDirection,portWidth);
			isExternal := false;
			isDifferential := false;
			signalPolarity := UndefinedPolarity;
		end InitHdlPort;

		(** Make the port external *)
		procedure MakeExternal*(yes: boolean);
		begin
			isExternal := yes;
		end MakeExternal;

		(** Make the port differential *)
		procedure MakeDifferential*(yes: boolean);
		begin
			isDifferential := yes;
		end MakeDifferential;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : HdlPort do
				cpy.isExternal := isExternal;
				cpy.isDifferential := isDifferential;
				cpy.signalPolarity := signalPolarity;
			end;
		end CopyContent;

	end HdlPort;

	(**
		Clock signal abstraction
	*)
	Clock* = object(Object)
	var
		name-: Strings.String; (** signal name *)
		frequency-: float64; (** frequency of the clock in Hz *)
		dutyCycle-: float64; (** duty cycle in % *)
		jitter-: float64; (** clock jitter in % of unit interval *)

		source-: Object; (** clock source: a ClockOutputPort in case of an internal clock or a PldIo in case of an external clock *)

		procedure &InitClock(const clockName: array of char);
		begin
			InitObject;
			name := Strings.NewString(clockName);
			(* setup invalid value of clock parameters - that means the clock is not yet initialized *)
			frequency := -1; (* not defined *)
			dutyCycle := 50; (* 50% duty cycle by default *)
			jitter := -1; (* not defined *)
		end InitClock;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : Clock do
				cpy.name := name; (*! copy by reference *)
				cpy.frequency := frequency;
				cpy.dutyCycle := dutyCycle;
				cpy.jitter := jitter;
				cpy.source := source; (*! copy by reference *)
			end;
		end CopyContent;

	end Clock;

	(**
		Clock list
	*)
	ClockList* = object(ObjectList)

		(** Get clock by its index *)
		procedure GetClock*(i: size): Clock;
		var obj: Object;
		begin
			obj := Get(i);
			if obj # nil then return obj(Clock);
			else return nil;
			end;
		end GetClock;

		(** Get clock by its name *)
		procedure GetClockByName*(const name: array of char): Clock;
		var
			i, n: size;
			clock: Clock;
		begin
			i := 0; n := list.Length();
			while i < n do
				clock := GetClock(i);
				if (clock.name # nil) & (clock.name^ = name) then return clock; end;
				inc(i);
			end;
			return nil;
		end GetClockByName;

	end ClockList;

	(**
		Derived clock signal description
	*)
	DerivedClock* = object(Clock)
	var
		refClock-: Clock; (** reference clock *)
		mulFactor-, divFactor-: float64; (** multiplication and division factors; the frequency is defined by (mulFactor*refClock.frequency)/divFactor *)
		phase-: float64; (** output phase relative to the reference clock, in degrees (0 to 360) *)

		procedure &InitDerivedClock(
											const clockName: array of char;
											reference: Clock;
											multiplicationFactor, divisionFactor: float64
											);
		begin
			assert(~(reference is DerivedClock));
			assert(multiplicationFactor > 0);
			assert(divisionFactor > 0);
			InitClock(clockName);
			refClock := reference;
			mulFactor := multiplicationFactor;
			divFactor := divisionFactor;
			dutyCycle := 1/2;
			phase := 0;
			frequency := refClock.frequency*mulFactor/divFactor;
		end InitDerivedClock;

		(**
			Setup the duty cycle for the derived clock output, in %
		*)
		procedure SetDutyCycle*(dutyCycleValue: float64);
		begin
			assert((dutyCycleValue > 0) & (dutyCycleValue < 100));
			dutyCycle := dutyCycleValue;
		end SetDutyCycle;

		(**
			Setup the phase shift of the derived clock output relative to the reference clock, in degrees (0 to 360)
		*)
		procedure SetPhaseShift*(phaseShift: float64);
		begin
			assert((phaseShift >= 0) & (phaseShift <= 360));
			phase := phaseShift;
		end SetPhaseShift;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : DerivedClock do
				cpy.refClock := refClock; (*! copy by reference *)
				cpy.mulFactor := mulFactor;
				cpy.divFactor := divFactor;
				cpy.phase := phase;
			end;
		end CopyContent;

	end DerivedClock;

	(**
		HDL clock input port
	*)
	ClockInputPort* = object(HdlPort)
	var
		clock-: Clock; (** clock signal assigned to the port (set by the runtime) *)

		procedure &InitClockInputPort*(const nameInAc, nameInHdl: array of char);
		begin
			InitHdlPort(nameInAc,nameInHdl,In,1);
		end InitClockInputPort;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : ClockInputPort do
				cpy.clock := clock; (*! copy by reference *)
			end;
		end CopyContent;

	end ClockInputPort;

	(**
		HDL clock output port
	*)
	ClockOutputPort* = object(HdlPort)
	var
		clock-: Clock; (** output clock signal description *)

		procedure &InitClockOutputPort*(const nameInAc, nameInHdl: array of char);
		begin
			InitHdlPort(nameInAc,nameInHdl,Out,1);
		end InitClockOutputPort;

		(** Setup clock signal *)
		procedure SetClock*(clockSignal: Clock);
		begin
			clock := clockSignal;
		end SetClock;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : ClockOutputPort do
				cpy.clock := clock; (*! copy by reference *)
			end;
		end CopyContent;

	end ClockOutputPort;

	(**
		ARM AMBA AXI4 Stream port
	*)
	AxisPort* = object(Port)
	var
		tvalid-: HdlPort; (** TVALID (required) *)
		tready-: HdlPort; (** TREADY (optional) *)
		tdata-: HdlPort; (** TDATA (optional) *)
		tstrb-: HdlPort; (** TSTRB (optional) *)
		tkeep-: HdlPort; (** TKEEP (optional) *)
		tlast-: HdlPort; (** TLAST (optional) *)
		tid-: HdlPort; (** TID (optional) *)
		tdest-: HdlPort; (** TDEST (optional) *)
		tuser-: HdlPort; (** TUSER (optional) *)

		aclk-: ClockInputPort; (** reference to the clock port *)
		aresetn-: HdlPort; (** reference to the reset port *)

		(**
			Create an AXI4-Stream port

			nameInAc: name of the port in ActiveCells code
			nameInHdl: name of the port in HDL code
			portDirection: direction of the port (In, Out or Inout)
			portWidth: width of the port in number of bits
		*)
		procedure &InitAxisPort*
										(
										const nameInAc, nameInHdl: array of char;
										portDirection: integer; portWidth: size
										);
		var
			str: LongString;
		begin
			InitPort(nameInAc,nameInHdl,portDirection,portWidth);
			if portDirection = Inout then
				Error(ErrInvalidValue,'AXI4-Stream port cannot have "Inout" direction'); return;
			end;
			if portWidth < 0 then
				Error(ErrInvalidValue,'AXI4-Stream port data width cannot be negative'); return;
			end;

			(* TVALID *)
			Strings.Concat(nameInHdl,"_tvalid",str);
			if portDirection = Out then new(tvalid,"",str,Out,1);
			else new(tvalid,"",str,In,1);
			end;
			tvalid.parent := self;

			(* TREADY *)
			Strings.Concat(nameInHdl,"_tready",str);
			if portDirection = Out then new(tready,"",str,In,1);
			else new(tready,"",str,Out,1);
			end;
			tready.parent := self;

			(* TDATA *)
			if portWidth > 0 then
				Strings.Concat(nameInHdl,"_tdata",str);
				new(tdata,"",str,portDirection,portWidth);
				tdata.parent := self;
			end;
		end InitAxisPort;

		procedure SetWidth(w: size);
		var str: LongString;
		begin
			SetWidth^(w);
			if w > 0 then
				if tdata = nil then
					Strings.Concat(hdlName^,"_tdata",str);
					if direction = Out then new(tdata,"",str,Out,w);
					else new(tdata,"",str,In,w);
					end;
				end;
				tdata.parent := self;
				tdata.SetWidth(w);
			else
				tdata := nil;
			end;
		end SetWidth;

		(**
			Setup user data carried together with the port data

			userDataWidth: width of the user data
		*)
		procedure SetUserData*(userDataWidth: size);
		var str: LongString;
		begin
			if userDataWidth > 0 then
				str := hdlName^ & "_tuser";
				new(tuser,"",str,direction,userDataWidth);
				tuser.parent := self;
			end;
		end SetUserData;

		(**
			Set reference to the clock port
		*)
		procedure SetClock*(clockInp: ClockInputPort);
		begin
			assert(clockInp # nil);
			aclk := clockInp;
		end SetClock;

		(**
			Set reference to reset port
		*)
		procedure SetReset*(resetInp: HdlPort);
		begin
			assert(resetInp # nil);
			aresetn := resetInp;
		end SetReset;

		(** Set/Clear port unused flag *)
		procedure SetUnused*(portIsUnused: boolean);
		begin
			if tvalid # nil then tvalid.SetUnused(portIsUnused); end;
			if tready # nil then tready.SetUnused(portIsUnused); end;
			if tdata # nil then tdata.SetUnused(portIsUnused); end;
			if tstrb # nil then tstrb.SetUnused(portIsUnused); end;
			if tkeep # nil then tkeep.SetUnused(portIsUnused); end;
			if tlast # nil then tlast.SetUnused(portIsUnused); end;
			if tid # nil then tid.SetUnused(portIsUnused); end;
			if tdest # nil then tdest.SetUnused(portIsUnused); end;
			if tuser # nil then tuser.SetUnused(portIsUnused); end;
			unused := portIsUnused;
		end SetUnused;


		(**
			Setup port routing (multiplexing/demultiplexing) with a specified number of channels (TDEST signal);
			master is TRUE if the port belongs to a master component, such as processor (TDEST has output direction)
		*)
		procedure SetRouting*(numChannels: size; master: boolean);
		var str: LongString;
		begin
			assert(numChannels >= 0);
			Strings.Concat(hdlName^,"_tdest",str);
			if master then
				new(tdest,"",str,Out,NumBits(numChannels));
			else
				new(tdest,"",str,In,NumBits(numChannels));
			end;
			tdest.parent := self;
		end SetRouting;

		procedure CopyContent(cpy: Object);
		var
			c: Cell;
			p: Port;
		begin
			CopyContent^(cpy);
			with cpy : AxisPort do
				cpy.tvalid := tvalid.Copy()(HdlPort);
				cpy.tvalid.parent := cpy;
				if tready # nil then
					cpy.tready := tready.Copy()(HdlPort);
					cpy.tready.parent := cpy;
				end;
				if tdata # nil then
					cpy.tdata := tdata.Copy()(HdlPort);
					cpy.tdata.parent := cpy;
				end;
				if tstrb # nil then
					cpy.tstrb := tstrb.Copy()(HdlPort);
					cpy.tstrb.parent := cpy;
				end;
				if tkeep # nil then
					cpy.tkeep := tkeep.Copy()(HdlPort);
					cpy.tkeep.parent := cpy;
				end;
				if tlast # nil then
					cpy.tlast := tlast.Copy()(HdlPort);
					cpy.tlast.parent := cpy;
				end;
				if tid # nil then
					cpy.tid := tid.Copy()(HdlPort);
					cpy.tid.parent := cpy;
				end;
				if tdest # nil then
					cpy.tdest := tdest.Copy()(HdlPort);
					cpy.tdest.parent := cpy;
				end;
				if tuser # nil then
					cpy.tuser := tuser.Copy()(HdlPort);
					cpy.tuser.parent := cpy;
				end;
				c := GetCell();
				if aclk # nil then
					p := c.GetPortByHdlName(aclk.hdlName^);
					cpy.aclk := p(ClockInputPort);
				end;
				if aresetn # nil then
					p := c.GetPortByHdlName(aresetn.hdlName^);
					cpy.aresetn := p(HdlPort);
				end;
			end;
		end CopyContent;

	end AxisPort;

	AxiWritePort* = object(Port)
	var
		(*
			Write address channel
		*)
		awid-: HdlPort;
		awaddr-: HdlPort;
		awlen-: HdlPort;
		awsize-: HdlPort;
		awburst-: HdlPort;
		awlock-: HdlPort;
		awcache-: HdlPort;
		awprot-: HdlPort;
		awqos-: HdlPort;
		awregion-: HdlPort;
		awuser-: HdlPort;
		awvalid-: HdlPort;
		awready-: HdlPort;

		(*
			Write data channel
		*)
		wid-: HdlPort;
		wdata-: HdlPort;
		wstrb-: HdlPort;
		wlast-: HdlPort;
		wuser-: HdlPort;
		wvalid-: HdlPort;
		wready-: HdlPort;

		(*
			Write response channel
		*)
		bid-: HdlPort;
		bresp-: HdlPort;
		buser-: HdlPort;
		bvalid-: HdlPort;
		bready-: HdlPort;

		aclk-: ClockInputPort; (** reference to the clock port *)
		aresetn-: HdlPort; (** reference to the reset port *)

		procedure &InitAxiWritePort*(const nameInAc, nameInHdl: array of char;
												const version: array of char;
												master: boolean;
												addrWidth, dataWidth, idWidth, maxBurstLen: size);
		var
			dir, dirInv: integer;
			axi3, axi4: boolean;
		begin
			assert((version = "AXI3") or (version = "AXI4") or (version = "AXI4-Lite"));
			assert(dataWidth mod 8 =0);
			assert(addrWidth mod 8 = 0);

			if master then dir := Out; dirInv := In; else dir := In; dirInv := Out; end;
			InitPort(nameInAc,nameInHdl,dir,dataWidth);

			axi3 := version = "AXI3";
			axi4 := version = "AXI4";

			(*
				Write address channel
			*)
			if axi3 or axi4 then
				new(awid,"",nameInHdl & "_awid",dir,idWidth);
			end;
			new(awaddr,"",nameInHdl & "_awaddr",dir,addrWidth);
			if axi3 or axi4 then
				new(awlen,"",nameInHdl & "_awlen",dir,NumBits(maxBurstLen));
				new(awsize,"",nameInHdl & "_awsize",dir,3);
				new(awburst,"",nameInHdl & "_awburst",dir,2);
				new(awlock,"",nameInHdl & "_awlock",dir,2); (*! AXI4 actually requires only one bit *)
				new(awcache,"",nameInHdl & "_awcache",dir,4);
			end;
			new(awprot,"",nameInHdl & "_awprot",dir,3); (* also supported in AXI4-Lite *)
			if axi4 then
				new(awqos,"",nameInHdl & "_awqos",dir,4);
				(*new(awregion,"",nameInHdl & "_awregion",dir,4);*)(*! optional *)
				(*new(awuser,"",nameInHdl & "_awuser",dir,addrWidth);*)(*! optional *)
			end;
			new(awvalid,"",nameInHdl & "_awvalid",dir,1);
			new(awready,"",nameInHdl & "_awready",dirInv,1);

			(*
				Write data channel
			*)
			if axi3 then
				new(wid,"",nameInHdl & "_wid",dir,idWidth); (*! for unknown reason Xilinx uses WID in AXI4!!! *)
			end;
			new(wdata,"",nameInHdl & "_wdata",dir,dataWidth);
			new(wstrb,"",nameInHdl & "_wstrb",dir,dataWidth div 8);
			if axi3 or axi4 then
				new(wlast,"",nameInHdl & "_wlast",dir,1);
				(*new(wuser,"",nameInHdl & "_wuser",dir,dataWidth);*) (*! optional *)
			end;
			new(wvalid,"",nameInHdl & "_wvalid",dir,1);
			new(wready,"",nameInHdl & "_wready",dirInv,1);

			(*
				Write response channel
			*)
			if axi3 or axi4 then
				new(bid,"",nameInHdl & "_bid",dirInv,idWidth);
			end;
			new(bresp,"",nameInHdl & "_bresp",dirInv,2);
			if axi4 then
				(*new(buser,"",nameInHdl & "_buser",dir,dataWidth);*) (*! optional *)
			end;
			new(bvalid,"",nameInHdl & "_bvalid",dirInv,1);
			new(bready,"",nameInHdl & "_bready",dir,1);

		end InitAxiWritePort;

		(**
			Set reference to the clock port
		*)
		procedure SetClock*(clockInp: ClockInputPort);
		begin
			assert(clockInp # nil);
			aclk := clockInp;
		end SetClock;

		(**
			Set reference to reset port
		*)
		procedure SetReset*(resetInp: HdlPort);
		begin
			assert(resetInp # nil);
			aresetn := resetInp;
		end SetReset;

		(** Set/Clear port unused flag *)
		procedure SetUnused*(portIsUnused: boolean);
		begin
			if awid # nil then awid.SetUnused(portIsUnused); end;
			if awaddr # nil then awaddr.SetUnused(portIsUnused); end;
			if awlen # nil then awlen.SetUnused(portIsUnused); end;
			if awsize # nil then awsize.SetUnused(portIsUnused); end;
			if awburst # nil then awburst.SetUnused(portIsUnused); end;
			if awlock # nil then awlock.SetUnused(portIsUnused); end;
			if awcache # nil then awcache.SetUnused(portIsUnused); end;
			if awprot # nil then awprot.SetUnused(portIsUnused); end;
			if awqos # nil then awqos.SetUnused(portIsUnused); end;
			if awregion # nil then awregion.SetUnused(portIsUnused); end;
			if awuser # nil then awuser.SetUnused(portIsUnused); end;
			if awvalid # nil then awvalid.SetUnused(portIsUnused); end;
			if awready # nil then awready.SetUnused(portIsUnused); end;

			if wid # nil then wid.SetUnused(portIsUnused); end;
			if wdata # nil then wdata.SetUnused(portIsUnused); end;
			if wstrb # nil then wstrb.SetUnused(portIsUnused); end;
			if wlast # nil then wlast.SetUnused(portIsUnused); end;
			if wuser # nil then wuser.SetUnused(portIsUnused); end;
			if wvalid # nil then wvalid.SetUnused(portIsUnused); end;
			if wready # nil then wready.SetUnused(portIsUnused); end;

			if bid # nil then bid.SetUnused(portIsUnused); end;
			if bresp # nil then bresp.SetUnused(portIsUnused); end;
			if buser # nil then buser.SetUnused(portIsUnused); end;
			if bvalid # nil then bvalid.SetUnused(portIsUnused); end;
			if bready # nil then bready.SetUnused(portIsUnused); end;
			unused := portIsUnused;
		end SetUnused;

		procedure CopyContent(cpy: Object);
		var
			c: Cell;
			p: Port;
		begin
			CopyContent^(cpy);
			with cpy : AxiWritePort do
				if awid # nil then
					cpy.awid := awid.Copy()(HdlPort);
					cpy.awid.parent := cpy;
				end;
				if awaddr # nil then
					cpy.awaddr := awaddr.Copy()(HdlPort);
					cpy.awaddr.parent := cpy;
				end;
				if awlen # nil then
					cpy.awlen := awlen.Copy()(HdlPort);
					cpy.awlen.parent := cpy;
				end;
				if awsize # nil then
					cpy.awsize := awsize.Copy()(HdlPort);
					cpy.awsize.parent := cpy;
				end;
				if awburst # nil then
					cpy.awburst := awburst.Copy()(HdlPort);
					cpy.awburst.parent := cpy;
				end;
				if awlock # nil then
					cpy.awlock := awlock.Copy()(HdlPort);
					cpy.awlock.parent := cpy;
				end;
				if awcache # nil then
					cpy.awcache := awcache.Copy()(HdlPort);
					cpy.awcache.parent := cpy;
				end;
				if awprot # nil then
					cpy.awprot := awprot.Copy()(HdlPort);
					cpy.awprot.parent := cpy;
				end;
				if awqos # nil then
					cpy.awqos := awqos.Copy()(HdlPort);
					cpy.awqos.parent := cpy;
				end;
				if awregion # nil then
					cpy.awregion := awregion.Copy()(HdlPort);
					cpy.awregion.parent := cpy;
				end;
				if awuser # nil then
					cpy.awuser := awuser.Copy()(HdlPort);
					cpy.awuser.parent := cpy;
				end;
				if awvalid # nil then
					cpy.awvalid := awvalid.Copy()(HdlPort);
					cpy.awvalid.parent := cpy;
				end;
				if awready # nil then
					cpy.awready := awready.Copy()(HdlPort);
					cpy.awready.parent := cpy;
				end;

				if wid # nil then
					cpy.wid := wid.Copy()(HdlPort);
					cpy.wid.parent := cpy;
				end;
				if wdata # nil then
					cpy.wdata := wdata.Copy()(HdlPort);
					cpy.wdata.parent := cpy;
				end;
				if wstrb # nil then
					cpy.wstrb := wstrb.Copy()(HdlPort);
					cpy.wstrb.parent := cpy;
				end;
				if wlast # nil then
					cpy.wlast := wlast.Copy()(HdlPort);
					cpy.wlast.parent := cpy;
				end;
				if wuser # nil then
					cpy.wuser := wuser.Copy()(HdlPort);
					cpy.wuser.parent := cpy;
				end;
				if wvalid # nil then
					cpy.wvalid := wvalid.Copy()(HdlPort);
					cpy.wvalid.parent := cpy;
				end;
				if wready # nil then
					cpy.wready := wready.Copy()(HdlPort);
					cpy.wready.parent := cpy;
				end;

				if bid # nil then
					cpy.bid := bid.Copy()(HdlPort);
					cpy.bid.parent := cpy;
				end;
				if bresp # nil then
					cpy.bresp := bresp.Copy()(HdlPort);
					cpy.bresp.parent := cpy;
				end;
				if buser # nil then
					cpy.buser := buser.Copy()(HdlPort);
					cpy.buser.parent := cpy;
				end;
				if bvalid # nil then
					cpy.bvalid := bvalid.Copy()(HdlPort);
					cpy.bvalid.parent := cpy;
				end;
				if bready # nil then
					cpy.bready := bready.Copy()(HdlPort);
					cpy.bready.parent := cpy;
				end;

				c := GetCell();
				if aclk # nil then
					p := c.GetPortByHdlName(aclk.hdlName^);
					cpy.aclk := p(ClockInputPort);
				end;
				if aresetn # nil then
					p := c.GetPortByHdlName(aresetn.hdlName^);
					cpy.aresetn := p(HdlPort);
				end;
			end;
		end CopyContent;

	end AxiWritePort;

	AxiReadPort* = object(Port)
	var
		(*
			Read address channel
		*)
		arid-: HdlPort;
		araddr-: HdlPort;
		arlen-: HdlPort;
		arsize-: HdlPort;
		arburst-: HdlPort;
		arlock-: HdlPort;
		arcache-: HdlPort;
		arprot-: HdlPort;
		arqos-: HdlPort;
		arregion-: HdlPort;
		aruser-: HdlPort;
		arvalid-: HdlPort;
		arready-: HdlPort;

		(*
			Read data channel
		*)
		rid-: HdlPort;
		rdata-: HdlPort;
		rresp-: HdlPort;
		rlast-: HdlPort;
		ruser-: HdlPort;
		rvalid-: HdlPort;
		rready-: HdlPort;

		aclk-: ClockInputPort; (** reference to the clock port *)
		aresetn-: HdlPort; (** reference to the reset port *)

		procedure &InitAxiReadPort*(const nameInAc, nameInHdl: array of char;
												const version: array of char;
												master: boolean;
												addrWidth, dataWidth, idWidth, maxBurstLen: size);
		var
			dir, dirInv: integer;
			axi3, axi4: boolean;
		begin
			assert((version = "AXI3") or (version = "AXI4") or (version = "AXI4-Lite"));
			assert(dataWidth mod 8 =0);
			assert(addrWidth mod 8 = 0);

			if master then dir := Out; dirInv := In; else dir := In; dirInv := Out; end;
			InitPort(nameInAc,nameInHdl,dir,dataWidth);

			axi3 := version = "AXI3";
			axi4 := version = "AXI4";

			(*
				Read address channel
			*)
			if axi3 or axi4 then
				new(arid,"",nameInHdl & "_arid",dir,idWidth);
			end;
			new(araddr,"",nameInHdl & "_araddr",dir,addrWidth);
			if axi3 or axi4 then
				new(arlen,"",nameInHdl & "_arlen",dir,NumBits(maxBurstLen));
				new(arsize,"",nameInHdl & "_arsize",dir,3);
				new(arburst,"",nameInHdl & "_arburst",dir,2);
				new(arlock,"",nameInHdl & "_arlock",dir,2); (*! AXI4 actually requires only one bit *)
				new(arcache,"",nameInHdl & "_arcache",dir,4);
			end;
			new(arprot,"",nameInHdl & "_arprot",dir,3); (* also supported in AXI4-Lite *)
			if axi4 then
				new(arqos,"",nameInHdl & "_arqos",dir,4);
				(*new(arregion,"",nameInHdl & "_arregion",dir,4);*)(*! optional *)
				(*new(aruser,"",nameInHdl & "_aruser",dir,dataWidth);*)(*! optional *)
			end;
			new(arvalid,"",nameInHdl & "_arvalid",dir,1);
			new(arready,"",nameInHdl & "_arready",dirInv,1);

			(*
				Read data channel
			*)
			if axi3 or axi4 then
				new(rid,"",nameInHdl & "_rid",dirInv,idWidth);
			end;
			new(rdata,"",nameInHdl & "_rdata",dirInv,dataWidth);
			new(rresp,"",nameInHdl & "_rresp",dirInv,2);
			if axi3 or axi4 then
				new(rlast,"",nameInHdl & "_rlast",dirInv,1);
				(*new(ruser,"",nameInHdl & "_ruser",dirInv,dataWidth);*)(*! optional *)
			end;
			new(rvalid,"",nameInHdl & "_rvalid",dirInv,1);
			new(rready,"",nameInHdl & "_rready",dir,1);

		end InitAxiReadPort;

		(**
			Set reference to the clock port
		*)
		procedure SetClock*(clockInp: ClockInputPort);
		begin
			assert(clockInp # nil);
			aclk := clockInp;
		end SetClock;

		(**
			Set reference to reset port
		*)
		procedure SetReset*(resetInp: HdlPort);
		begin
			assert(resetInp # nil);
			aresetn := resetInp;
		end SetReset;

		(** Set/Clear port unused flag *)
		procedure SetUnused*(portIsUnused: boolean);
		begin
			if arid # nil then arid.SetUnused(portIsUnused); end;
			if araddr # nil then araddr.SetUnused(portIsUnused); end;
			if arlen # nil then arlen.SetUnused(portIsUnused); end;
			if arsize # nil then arsize.SetUnused(portIsUnused); end;
			if arburst # nil then arburst.SetUnused(portIsUnused); end;
			if arlock # nil then arlock.SetUnused(portIsUnused); end;
			if arcache # nil then arcache.SetUnused(portIsUnused); end;
			if arprot # nil then arprot.SetUnused(portIsUnused); end;
			if arqos # nil then arqos.SetUnused(portIsUnused); end;
			if arregion # nil then arregion.SetUnused(portIsUnused); end;
			if aruser # nil then aruser.SetUnused(portIsUnused); end;
			if arvalid # nil then arvalid.SetUnused(portIsUnused); end;
			if arready # nil then arready.SetUnused(portIsUnused); end;

			if rid # nil then rid.SetUnused(portIsUnused); end;
			if rdata # nil then rdata.SetUnused(portIsUnused); end;
			if rresp # nil then rresp.SetUnused(portIsUnused); end;
			if rlast # nil then rlast.SetUnused(portIsUnused); end;
			if ruser # nil then ruser.SetUnused(portIsUnused); end;
			if rvalid # nil then rvalid.SetUnused(portIsUnused); end;
			if rready # nil then rready.SetUnused(portIsUnused); end;
			unused := portIsUnused;
		end SetUnused;

		procedure CopyContent(cpy: Object);
		var
			c: Cell;
			p: Port;
		begin
			CopyContent^(cpy);
			with cpy : AxiReadPort do
				if arid # nil then
					cpy.arid := arid.Copy()(HdlPort);
					cpy.arid.parent := cpy;
				end;
				if araddr # nil then
					cpy.araddr := araddr.Copy()(HdlPort);
					cpy.araddr.parent := cpy;
				end;
				if arlen # nil then
					cpy.arlen := arlen.Copy()(HdlPort);
					cpy.arlen.parent := cpy;
				end;
				if arsize # nil then
					cpy.arsize := arsize.Copy()(HdlPort);
					cpy.arsize.parent := cpy;
				end;
				if arburst # nil then
					cpy.arburst := arburst.Copy()(HdlPort);
					cpy.arburst.parent := cpy;
				end;
				if arlock # nil then
					cpy.arlock := arlock.Copy()(HdlPort);
					cpy.arlock.parent := cpy;
				end;
				if arcache # nil then
					cpy.arcache := arcache.Copy()(HdlPort);
					cpy.arcache.parent := cpy;
				end;
				if arprot # nil then
					cpy.arprot := arprot.Copy()(HdlPort);
					cpy.arprot.parent := cpy;
				end;
				if arqos # nil then
					cpy.arqos := arqos.Copy()(HdlPort);
					cpy.arqos.parent := cpy;
				end;
				if arregion # nil then
					cpy.arregion := arregion.Copy()(HdlPort);
					cpy.arregion.parent := cpy;
				end;
				if aruser # nil then
					cpy.aruser := aruser.Copy()(HdlPort);
					cpy.aruser.parent := cpy;
				end;
				if arvalid # nil then
					cpy.arvalid := arvalid.Copy()(HdlPort);
					cpy.arvalid.parent := cpy;
				end;
				if arready # nil then
					cpy.arready := arready.Copy()(HdlPort);
					cpy.arready.parent := cpy;
				end;

				if rid # nil then
					cpy.rid := rid.Copy()(HdlPort);
					cpy.rid.parent := cpy;
				end;
				if rdata # nil then
					cpy.rdata := rdata.Copy()(HdlPort);
					cpy.rdata.parent := cpy;
				end;
				if rresp # nil then
					cpy.rresp := rresp.Copy()(HdlPort);
					cpy.rresp.parent := cpy;
				end;
				if rlast # nil then
					cpy.rlast := rlast.Copy()(HdlPort);
					cpy.rlast.parent := cpy;
				end;
				if ruser # nil then
					cpy.ruser := ruser.Copy()(HdlPort);
					cpy.ruser.parent := cpy;
				end;
				if rvalid # nil then
					cpy.rvalid := rvalid.Copy()(HdlPort);
					cpy.rvalid.parent := cpy;
				end;
				if rready # nil then
					cpy.rready := rready.Copy()(HdlPort);
					cpy.rready.parent := cpy;
				end;

				c := GetCell();
				if aclk # nil then
					p := c.GetPortByHdlName(aclk.hdlName^);
					cpy.aclk := p(ClockInputPort);
				end;
				if aresetn # nil then
					p := c.GetPortByHdlName(aresetn.hdlName^);
					cpy.aresetn := p(HdlPort);
				end;
			end;
		end CopyContent;

	end AxiReadPort;

	(**
		A cellnet port
	*)
	CellnetPort* = object(Port)
	var
		protoPort-: Port; (** prototype port used for HDL code generation (derived based on the delegated ports) *)
		delegatedTo-: PortList; (** a list of ports defining the delegation of the current port ; set by the runtime *)

		ios-: PldIoList; (** list of IO's corresponding to each signal of the port (setup by the runtime and available only for the top level cellnet) *)

		(*
			Construct a cellnet port given a name in ActiveCells code
		*)
		procedure &InitCellnetPort(const name: array of char; portDirection: integer; portWidth: size);
		var normalizedName: LongString;
		begin
			InitPort(name,"",portDirection,portWidth);
			GetHdlNormalizedName(acName^,normalizedName);
			if acName^ = normalizedName then
				hdlName := acName;
			else
				hdlName := Strings.NewString(normalizedName);
			end;
		end InitCellnetPort;

		procedure SetupProtoPort(p: Port): boolean;
		var
			hdlPort: HdlPort;
			clockInputPort: ClockInputPort;
			clockOutputPort: ClockOutputPort;
			axisPort: AxisPort;
			logicalPort: LogicalPort;
			str: LongString;
		begin
			(*if protoPort # nil then
				assert(width = p.width);
				return true;
			end;*)

			protoPort := p; (*! it seems there is no need to createa a separate port instance *)
(*
			if p is ClockInputPort then
				str := ""; (*Strings.Concat(GetCell().acName^,"_",str);*)
				Strings.Concat(str,acName^,str);
				GetHdlNormalizedName(str,str);
				new(clockInputPort,acName^,str);
				protoPort := clockInputPort;
			elsif p is ClockOutputPort then
				str := ""; (*Strings.Concat(GetCell().acName^,"_",str);*)
				Strings.Concat(str,acName^,str);
				GetHdlNormalizedName(str,str);
				new(clockOutputPort,acName^,str);
				protoPort := clockOutputPort;
			elsif p is AxisPort then
				str := ""; (*Strings.Concat(GetCell().acName^,"_",str);*)
				Strings.Concat(str,acName^,str);
				GetHdlNormalizedName(str,str);
				new(axisPort,acName^,str,p.direction,p.width);
				with p : AxisPort do
					assert(((axisPort.tvalid # nil) & (axisPort.tvalid # nil)) or ((axisPort.tvalid = nil) & (axisPort.tvalid = nil)));
					assert(((axisPort.tready # nil) & (axisPort.tready # nil)) or ((axisPort.tready = nil) & (axisPort.tready = nil)));
					assert(((axisPort.tdata # nil) & (axisPort.tdata # nil)) or ((axisPort.tdata = nil) & (axisPort.tdata = nil)));
					assert(((axisPort.tstrb # nil) & (axisPort.tstrb # nil)) or ((axisPort.tstrb = nil) & (axisPort.tstrb = nil)));
					assert(((axisPort.tkeep # nil) & (axisPort.tkeep # nil)) or ((axisPort.tkeep = nil) & (axisPort.tkeep = nil)));
					assert(((axisPort.tlast # nil) & (axisPort.tlast # nil)) or ((axisPort.tlast = nil) & (axisPort.tlast = nil)));
					assert(((axisPort.tid # nil) & (axisPort.tid # nil)) or ((axisPort.tid = nil) & (axisPort.tid = nil)));
					assert(((axisPort.tdest # nil) & (axisPort.tdest # nil)) or ((axisPort.tdest = nil) & (axisPort.tdest = nil)));
					assert(((axisPort.tuser # nil) & (axisPort.tuser # nil)) or ((axisPort.tuser = nil) & (axisPort.tuser = nil)));
				end;
				protoPort := axisPort;
			elsif p is CellnetPort then
				assert(p(CellnetPort).protoPort # nil);
				if ~SetupProtoPort(p(CellnetPort).protoPort) then return false; end;
			else
				if p is HdlPort then
					str := ""; (*Strings.Concat(GetCell().acName^,"_",str);*)
					Strings.Concat(str,acName^,str);
					GetHdlNormalizedName(str,str);
					new(hdlPort,"",str,p.direction,p.width);
					protoPort := hdlPort;
				else
					assert(p is LogicalPort);
					trace(acName^,p.GetCell().acName^,p.acName^,p.direction,p.width);
					str := ""; (*Strings.Concat(GetCell().acName^,"_",str);*)
					Strings.Concat(str,acName^,str);
					GetHdlNormalizedName(str,str);
					new(logicalPort,"",str,p.direction,p.width);
					protoPort := logicalPort;
				end;
			end;

			protoPort.parent := self;
*)
			width := protoPort.width;

			return true;
		finally
			return false;
		end SetupProtoPort;

		(*
			Delegate the port to another port;
			multiple delegations of the same port is allowed only in the case when the current port has input direction
		*)
		procedure DelegateTo(p: Port): boolean;
		var
			str, str1: LongString;
			pp, pp1: Port;
		begin
			assert(direction = p.direction);
			if (direction = Out) & (delegatedTo # nil) then
				Error(ErrInvalidValue,'forbidden multiple delegation of output port "' & acName^ & '; attempt to delegate to port "' & p.acName^);
				return false;
			end;

			if p is CellnetPort then pp := p(CellnetPort).protoPort; else pp := p; end;
			assert(pp # nil);
			assert(~(pp is CellnetPort));

			if (protoPort # nil) & ~protoPort.HasSameTypeAs(pp)   then
				GetTypeName(str1);
				str := 'forbidden delegation of port "' & acName^ & '" of type "' & str1 & '" to port "' & p.acName^;
				p.GetTypeName(str1);
				Error(ErrTypeMismatch,str & '" of type "' & str1 & '"');
				return false;
			end;

			if ~SetupProtoPort(pp) then return false; end;

			if delegatedTo = nil then new(delegatedTo,3); delegatedTo.parent := self; end;
			delegatedTo.list.Add(p); (*! do not change the parent of the port object *)
			assert(p.delegateOf = nil);
			p.delegateOf := self;
			return true;
		finally
			return false;
		end DelegateTo;

		(* Recursively check optionality of a cellnet port *)
		procedure IsOptional(): boolean;
		var
			i, n: size;
			p: Port;
		begin
			if optional then return true; end;

			if delegatedTo # nil then
				n := delegatedTo.Length();
				i := 0;
				while (i < n) & ~optional do
					p := delegatedTo.GetPort(i);
					if p is CellnetPort then
						optional := p(CellnetPort).IsOptional();
					else
						optional := p.optional;
					end;
					inc(i);
				end;
				return optional;
			else
				return false;
			end;
		end IsOptional;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : CellnetPort do
				if delegatedTo # nil then cpy.delegatedTo := delegatedTo; end; (*! copy by reference *)
			end;
		end CopyContent;

	end CellnetPort;

	(**
		PLD IO object description
	*)
	PldIo* = object(Object)
	var
		name-: Strings.String; (** IO name *)
		direction-: integer; (** IO direction: In, Out, Inout *)
		ioStandard-: Strings.String; (** IO standard; default "" *)
		signalPolarity-: integer; (** polarity for all port signals: ActiveHigh, ActiveLow, UndefinedPolarity (default) *)

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : PldIo do
				if name # nil then cpy.name := Strings.NewString(name^); end;
				cpy.direction := direction;
				cpy.ioStandard := Strings.NewString(ioStandard^);
				cpy.signalPolarity := signalPolarity;
			end;
		end CopyContent;

	end PldIo;

	(**
		PLD IO list
	*)
	PldIoList* = object(ObjectList)
	var
		name-: Strings.String; (** list name *)

		procedure &InitPldIoList(const listName: array of char; initSize: size);
		begin
			InitObjectList(initSize);
			name := Strings.NewString(listName);
		end InitPldIoList;

		(** Get port by its index *)
		procedure GetIo*(i: size): PldIo;
		var obj: Object;
		begin
			obj := Get(i);
			if obj # nil then return obj(PldIo);
			else return nil;
			end;
		end GetIo;

		procedure GetIoByLocation*(const location: array of char): PldIo;
		var
			i, n: size;
			io: PldIo;
		begin
			n := Length();
			i := 0;
			for i := 0 to n-1 do
				io := GetIo(i);
				if io is IoPin then
					if io(IoPin).location^ = location then return io; end;
				else
					if io(IoDiffPair).pinP.location^ = location then
						return io(IoDiffPair).pinP;
					elsif io(IoDiffPair).pinN.location^ = location then
						return io(IoDiffPair).pinN;
					end;
				end;
			end;

			return nil;
		end GetIoByLocation;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : PldIoList do
				cpy.name := Strings.NewString(name^);
			end;
		end CopyContent;

	end PldIoList;

	(**
		Single ended PLD IO description
	*)
	IoPin* = object(PldIo)
	var
		location-: Strings.String; (** pin location in the PLD *)
		pullType-: integer; (** pull type: PullNone, PullUp, PullDown; default is PullNone *)

		procedure &InitPin*(
									pinDirection: integer;
									const pinLocation: array of char;
									const pinIoStandard: array of char
									);
		begin
			InitObject;
			direction := pinDirection;
			location := Strings.NewString(pinLocation);
			ioStandard := Strings.NewString(pinIoStandard);
		end InitPin;

		(**
			Setup pull type: PullNone, PullUp, PullDown
		*)
		procedure SetPullType*(pull: integer);
		begin
			assert((pull = PullNone) or (pull = PullUp) or (pull = PullDown));
			pullType := pull;
		end SetPullType;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : IoPin do
				cpy.location := Strings.NewString(location^);
				cpy.pullType := pullType;
			end;
		end CopyContent;

	end IoPin;

	(**
		differential IO pin pair
	*)
	IoDiffPair* = object(PldIo)
	var
		pinP-: IoPin; (** positive IO pin *)
		pinN-: IoPin; (** negative IO pin *)

		procedure &InitIoDiffPair*
										(
										pairDirection: integer;
										const pinLocationP, pinLocationN: array of char;
										const pairIoStandard: array of char
										);
		begin
			new(pinP,pairDirection,pinLocationP,pairIoStandard);
			new(pinN,pairDirection,pinLocationN,pairIoStandard);
		end InitIoDiffPair;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : IoDiffPair do
				cpy.pinP := pinP.Copy()(IoPin); cpy.pinP.parent := cpy;
				cpy.pinN := pinN.Copy()(IoPin); cpy.pinN.parent := cpy;
			end;
		end CopyContent;

	end IoDiffPair;

	(** Connection channel description *)
	Channel* = object(Object)
	var
		outPort-, inPort-: Port; (** output and input port of the channel *)
		depth-: size; (** depth of the channel; 0 in case of a signal channel (wire) *)

		procedure &InitChannel*(outChanPort, inChanPort: Port; chanDepth: size);
		begin
			outPort := outChanPort;
			inPort := inChanPort;
			depth := chanDepth;
			inPort.channel := self;
			(* handle cases of multiple output port connections *)
			if (outPort.channel = nil) & (outPort.channels = nil) then
				outPort.channel := self;
			else
				if outPort.channels = nil then new(outPort.channels,8); end;
				if outPort.channel # nil then
					outPort.channels.Add(outPort.channel);
					outPort.channel := nil;
				end;
				outPort.channels.Add(self);
			end;
		end InitChannel;

	end Channel;

	(**
		Channel list
	*)
	ChannelList* = object(ObjectList)

		(** Get port by its index *)
		procedure GetChannel*(i: size): Channel;
		var obj: Object;
		begin
			obj := Get(i);
			if obj # nil then return obj(Channel);
			else return nil;
			end;
		end GetChannel;

	end ChannelList;

	(**
		Dependency object
	*)
	Dependency* = object(Object)
	var
		name-: Strings.String; (** dependency name *)
		included-: boolean; (** TRUE in case if the dependency is included; by default equal to TRUE; set by the runtime, not by the user *)
		makeLocalCopy-: boolean; (** TRUE in case if the dependency is to be copied to the current project directory *)
		topLevel-: boolean; 

		pathName-: Strings.String; (** full pathname; set by the runtime *)

		resource: ResourceItem;

		procedure &InitDependency*(const name: array of char; included, makeLocalCopy: boolean);
		begin
			InitObject;
			self.makeLocalCopy := makeLocalCopy;
			self.included := included;
			self.name := Strings.NewString(name);
			self.topLevel := false;
		end InitDependency;
		
		procedure SetTop*();
		begin
			topLevel := true;
		end SetTop;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : Dependency do
				cpy.name := name; (*! copy by reference *)
				cpy.resource := resource;
				cpy.pathName := pathName; (*! copy by reference *)
				cpy.included := included;
				cpy.makeLocalCopy := makeLocalCopy;
				cpy.topLevel := topLevel;
			end;
		end CopyContent;

	end Dependency;

	DependencyList* = object(ObjectList)

		(** Get dependency by its index *)
		procedure GetDependency*(i: size): Dependency;
		var obj: Object;
		begin
			obj := Get(i);
			if obj # nil then return obj(Dependency);
			else return nil;
			end;
		end GetDependency;

		(**
			Find a dependency by its name
		*)
		procedure GetDependencyByName*(const name: array of char): Dependency;
		var i, n: size;
		begin
			i := 0; n := Length();
			while (i < n) & (GetDependency(i).name^ # name) do inc(i); end;
			if i < n then return GetDependency(i); else return nil; end;
		end GetDependencyByName;

	end DependencyList;

	(**
		Cell object
	*)
	Cell* = object(HdlObject)
	var
		props-: PropertyList; (** list of cell's properties *)

		ports-: PortList; (** list of all cell ports *)

		(*
			cell ports sorted by function
		*)
		mainClockInput-: Port; (** main clock input port *)
		mainResetInput-: Port; (** main reset input port *)
		clockInputs-: PortList; (** clock input ports *)
		clockOutputs-: PortList; (** clock output ports *)
		inputs-: PortList; (** other input ports *)
		outputs-: PortList; (** other output ports *)
		inoutputs-: PortList; (** other inout ports *)

		dependencies-: DependencyList; (** list of all dependency files *)

		postParamSetters-: ObjectHandlerProcList; (** list of cell's post parameterization setters *)
		postAssemblySetters-: ObjectHandlerProcList; (** list of cell's setters to be called just after assembly of the whole ActiveCells architecture *)

		acInstType-: Strings.String; (** ActiveCells cell instance type name; extracted from the ActiveCells code *)
		acInstName-: Strings.String; (** ActiveCells cell instance name; extracted from the ActiveCells code *)
		hdlInstName-: Strings.String; (** HDL cell instance name; set by the runtime *)

		maxNumInstances- := -1: size; (** maximal number of instances on the current target (< 0 for unlimited number) *)

		instId-: signed32; (** instance ID (set up by the runtime) *)

		acCellInd: size; (* cell index in the ActiveCells code (for internal use only) *)
		acPortCounter: size; (* ActiveCells port counter (for internal use only) *)

		(**
			Create a cell with a given name in ActiveCells and in HDL code
		*)
		procedure &InitCell*(const nameInAc, nameInHdl: array of char);
		begin
			InitHdlObject(nameInAc,nameInHdl);
		end InitCell;

		procedure SetContext(context: Context);
		begin
			SetContext^(context);
			if props # nil then props.SetContext(context); end;

			if ports # nil then ports.SetContext(context); end;

			if dependencies # nil then dependencies.SetContext(context); end;
			if postParamSetters # nil then postParamSetters.SetContext(context); end;
			if postAssemblySetters # nil then postAssemblySetters.SetContext(context); end;
		end SetContext;

		(**
			Returns parent cellnet
		*)
		procedure GetCellnet*(): Cellnet;
		begin
			if parent # nil then
				return parent(CellList).parent(Cellnet);
			else
				return nil;
			end;
		end GetCellnet;

		(**
			Returns TRUE if the cell implementation is supported on the given target
		*)
		procedure SupportedOnTarget*(target: TargetDevice): boolean;
		begin
			return true;
		end SupportedOnTarget;

		(**
			Add a property to the list of properties supported by the cell
		*)
		procedure AddProperty*(property: Property);
		var str: LongString;
		begin

			if (property.hdlName # nil) & (props # nil) & (props.GetPropertyByHdlName(property.hdlName^) # nil) then
				Strings.Concat('property with HDL name "',property.hdlName^,str);
				Strings.Concat(str,'" already exists',str);
				Error(ErrInvalidValue,str);
				return;
			end;

			if (property.acName # nil) & (props # nil) & (props.GetPropertyByAcName(property.acName^) # nil) then
				Strings.Concat('property with ActiveCells name "',property.acName^,str);
				Strings.Concat(str,'" already exists',str);
				Error(ErrInvalidValue,str);
				return;
			end;

			if props = nil then
				new(props,3);
				props.parent := self;
			end;

			if EnableTrace then
				if (property.acName # nil) then trace(property.acName^, props.Length()); end;
			end;

			props.Add(property);
		end AddProperty;

		(** Get a property by its index *)
		procedure GetProperty*(i: size): Property;
		begin
			if props # nil then
				return props.GetProperty(i);
			else return nil;
			end;
		end GetProperty;

		(** Get a property by its ActiveCells name *)
		procedure GetPropertyByAcName*(const name: array of char): Property;
		begin
			if props # nil then
				return props.GetPropertyByAcName(name);
			else return nil;
			end;
		end GetPropertyByAcName;

		(** Get a property by its HDL name *)
		procedure GetPropertyByHdlName*(const name: array of char): Property;
		begin
			if props # nil then
				return props.GetPropertyByHdlName(name);
			else return nil;
			end;
		end GetPropertyByHdlName;

		(** Get a port by its ActiveCells name *)
		procedure GetPortByAcName*(const name: array of char): Port;
		var p: Port;
		begin
			if ports # nil then p := ports.GetPortByAcName(name); end;
			return p;
		end GetPortByAcName;

		(** Get an port by its HDL name *)
		procedure GetPortByHdlName*(const name: array of char): Port;
		var p: Port;
		begin
			if ports # nil then p := ports.GetPortByHdlName(name); end;
			return p;
		end GetPortByHdlName;

		(**
			Add a port to the cell's port list
		*)
		procedure AddPort*(p: Port);
		var str: LongString;
		begin

			if (p.hdlName # nil) & (GetPortByHdlName(p.hdlName^) # nil) then
				Strings.Concat('port with HDL name "',p.hdlName^,str);
				Strings.Concat(str,'" already exists',str);
				Error(ErrInvalidValue,str);
				return;
			end;

			if (p.acName # nil) & (GetPortByAcName(p.acName^) # nil) then
				Strings.Concat('port with ActiveCells name "',p.acName^,str);
				Strings.Concat(str,'" already exists',str);
				Error(ErrInvalidValue,str);
				return;
			end;

			if ports = nil then
				new(ports,3);
				ports.parent := self;
			end;
			ports.Add(p);

			if p.direction = Out then
				if p is ClockOutputPort then
					if clockOutputs = nil then
						new(clockOutputs,3);
						clockOutputs.parent := self;
					end;
					clockOutputs.Add0(p);
				else
					if outputs = nil then
						new(outputs,3);
						outputs.parent := self;
					end;
					outputs.Add0(p);
				end;
			elsif p.direction = In then
				if p is ClockInputPort then
					if clockInputs = nil then
						new(clockInputs,3);
						clockInputs.parent := self;
					end;
					clockInputs.Add0(p);
				else
					if inputs = nil then
						new(inputs,3);
						inputs.parent := self;
					end;
					inputs.Add0(p);
				end;
			else
				assert(p.direction = Inout);
				if inoutputs = nil then
					new(inoutputs,3);
					inoutputs.parent := self;
				end;
				inoutputs.Add0(p);
			end;

		end AddPort;

		procedure RemovePort*(p: Port);
		begin
			if p.acName^ = MainClockInputName then
				mainClockInput := nil;
			elsif p.acName^ = MainResetInputName then
				mainResetInput := nil;
			end;

			if p is ClockInputPort then
				clockInputs.Remove(p);
			elsif p is ClockOutputPort then
				clockOutputs.Remove(p);
			elsif p.direction = In then
				inputs.Remove(p);
			elsif p.direction = Out then
				outputs.Remove(p);
			else
				assert(p.direction = Inout);
				inoutputs.Remove(p);
			end;

			ports.Remove(p);
		end RemovePort;

		(**
			Add a dependency
		*)
		procedure AddDependency*(dependency: Dependency);
		begin
			if dependencies = nil then
				new(dependencies,3);
				dependencies.parent := self;
			end;
			dependencies.Add(dependency);
		end AddDependency;

		procedure GetDependency*(i: size): Dependency;
		begin
			if dependencies # nil then
				return dependencies.GetDependency(i);
			else
				return nil;
			end;
		end GetDependency;

		(** Remove all component dependencies *)
		procedure RemoveDependencies*();
		begin
			if dependencies = nil then return; end;
			dependencies.Clear;
		end RemoveDependencies;

		(**
			Add a post-parameterization cell setup procedure
		*)
		procedure AddPostParamSetter*(setter: ObjectHandlerProc);
		begin
			if postParamSetters = nil then
				new(postParamSetters,3);
				postParamSetters.parent := self;
			end;
			postParamSetters.Add(setter);
		end AddPostParamSetter;

		(**
			Add a post-assembly cell setup procedure
		*)
		procedure AddPostAssemblySetter*(setter: ObjectHandlerProc);
		begin
			if postAssemblySetters = nil then
				new(postAssemblySetters,3);
				postAssemblySetters.parent := self;
			end;
			postAssemblySetters.Add(setter);
		end AddPostAssemblySetter;

		(**
			Set limit for the number of instances of the component on the current target

			limit: instance count limit; <= 0 in case if there is no limit
		*)
		procedure SetInstanceCountLimit*(limit: size);
		begin
			maxNumInstances := limit;
		end SetInstanceCountLimit;

		(**
			A helper procedure for creating and automatically adding a property

			nameInAc: name of the property in ActiveCells code
			nameInHdl: name of the property (parameter) in HDL code
			initValue: initial value of the property (serves as a prototype)
			checkValueProc: pointer to the procedure that checks the value of the property for correctness
		*)
		procedure NewProperty*(
										const nameInAc, nameInHdl: array of char;
										initValue: Value;
										checkValueProc: procedure{DELEGATE}(prop: Property; val: Value): boolean
										);
		var prop: Property;
		begin
			new(prop,nameInAc,nameInHdl,initValue,checkValueProc);
			AddProperty(prop);
		end NewProperty;

		(**
			Create a new HDL port

			nameInAc: name of the port in ActiveCells code
			nameInHdl: name of the port in HDL code
			portDirection: direction of the port (In, Out or Inout)
			portWidth: width of the port in number of bits
		*)
		procedure NewHdlPort*(
										const nameInAc, nameInHdl: array of char;
										portDirection: integer; portWidth: size
										);
		var
			p: HdlPort;
		begin
			new(p,nameInAc,nameInHdl,portDirection,portWidth);
			AddPort(p);
		end NewHdlPort;

		(**
			Create a new external (e.g. coming directly from/to physical pins) HDL port

			nameInAc: name of the port in ActiveCells code
			nameInHdl: name of the port in HDL code
			portDirection: direction of the port (In, Out or Inout)
			portWidth: width of the port in number of bits
		*)
		procedure NewExternalHdlPort*(
										const nameInAc, nameInHdl: array of char;
										portDirection: integer; portWidth: size
										);
		var
			p: HdlPort;
		begin
			new(p,nameInAc,nameInHdl,portDirection,portWidth);
			p.isExternal := true;
			AddPort(p);
		end NewExternalHdlPort;

		(**
			Create a new AXI4-Stream port

			nameInAc: name of the port in ActiveCells code
			nameInHdl: name of the port in HDL code
			portDirection: direction of the port (In, Out or Inout)
			portWidth: width of the port in number of bits
		*)
		procedure NewAxisPort*(
										const nameInAc, nameInHdl: array of char;
										portDirection: integer; portWidth: size
										);
		var
			p: AxisPort;
		begin
			new(p,nameInAc,nameInHdl,portDirection,portWidth);
			if mainClockInput # nil then
				p.SetClock(mainClockInput(ClockInputPort));
			end;
			if mainResetInput # nil  then
				p.SetReset(mainResetInput(HdlPort));
			end;
			AddPort(p);
		end NewAxisPort;

		procedure NewAxiWritePort*(
												const nameInAc, nameInHdl: array of char;
												const version: array of char;
												master: boolean;
												addrWidth, dataWidth, idWidth, maxBurstLen: size
											);
		var
			p: AxiWritePort;
		begin
			new(p,nameInAc,nameInHdl,version,master,addrWidth,dataWidth,idWidth,maxBurstLen);
			if mainClockInput # nil then
				p.SetClock(mainClockInput(ClockInputPort));
			end;
			if mainResetInput # nil  then
				p.SetReset(mainResetInput(HdlPort));
			end;
			AddPort(p);
		end NewAxiWritePort;

		procedure NewAxiReadPort*(
												const nameInAc, nameInHdl: array of char;
												const version: array of char;
												master: boolean;
												addrWidth, dataWidth, idWidth, maxBurstLen: size
											);
		var
			p: AxiReadPort;
		begin
			new(p,nameInAc,nameInHdl,version,master,addrWidth,dataWidth,idWidth,maxBurstLen);
			if mainClockInput # nil then
				p.SetClock(mainClockInput(ClockInputPort));
			end;
			if mainResetInput # nil  then
				p.SetReset(mainResetInput(HdlPort));
			end;
			AddPort(p);
		end NewAxiReadPort;

		(**
			Create a new clock input port

			nameInAc: name of the port in ActiveCells code
			nameInHdl: name of the port in HDL code
		*)
		procedure NewClockInput*(const nameInAc, nameInHdl: array of char);
		var clockInp: ClockInputPort;
		begin
			new(clockInp,nameInAc,nameInHdl);
			AddPort(clockInp);
		end NewClockInput;

		(**
			Describe main clock input port

			nameInHdl: name of the port in HDL code
			checkAssignedClock: procedure to check the clock to be assigned to the port
		*)
		procedure SetMainClockInput*(const nameInHdl: array of char);
		var p: ClockInputPort;
		begin
			assert(~(self is Cellnet));
			new(p,MainClockInputName,nameInHdl);
			p.SetContext(ctx);
			mainClockInput := p;
			AddPort(p);
		end SetMainClockInput;

		(**
			Setup main reset input

			nameInHdl: name of the port in HDL code
			activeHigh: TRUE for active-high reset signal polarity
		*)
		procedure SetMainResetInput*(const nameInHdl: array of char; polarity: integer);
		var p: HdlPort;
		begin
			assert(~(self is Cellnet));
			assert((polarity = ActiveHigh) or (polarity = ActiveLow));
			new(p,MainResetInputName,nameInHdl,In,1);
			p.signalPolarity := polarity;

			p.SetContext(ctx);
			mainResetInput := p;
			AddPort(p);
		end SetMainResetInput;

		(**
			Create a new clock output port
		*)
		procedure NewClockOutput*(const nameInAc, nameInHdl: array of char);
		var clockOut: ClockOutputPort;
		begin
			new(clockOut,nameInAc,nameInHdl);
			AddPort(clockOut);
		end NewClockOutput;

		(**
			Create a new dependency
		*)
		procedure NewDependency*(const name: array of char; included, makeLocalCopy: boolean);
		var dependency: Dependency;
		begin
			new(dependency,name,included,makeLocalCopy);
			AddDependency(dependency);
		end NewDependency;

		

		(**
			Returns TRUE if the cell implementation is supported on a given PLD
		*)
		procedure SupportedOnPld*(pld: PldPart): boolean;
		begin
			halt(100);
		end SupportedOnPld;

		procedure PostParamSetup*(): boolean;
		var
			k, n: size;
			setter: ObjectHandlerProc;
		begin
			if postParamSetters = nil then return true; end;
			n := postParamSetters.Length();
			for k := 0 to n-1 do
				setter := postParamSetters.Get(k);
				if ~setter(self,nil) then return false; end;
			end;
			return true;
		finally
			return false;
		end PostParamSetup;

		procedure PostAssemblySetup(): boolean;
		var
			k, n: size;
			setter: ObjectHandlerProc;
		begin
			if postAssemblySetters = nil then return true; end;
			n := postAssemblySetters.Length();
			for k := 0 to n-1 do
				setter := postAssemblySetters.Get(k);
				if ~setter(self,nil) then return false; end;
			end;
			return true;
		finally
			return false;
		end PostAssemblySetup;

		procedure CopyContent(cpy: Object);
		var
			k: size;
			p: Port;
		begin
			CopyContent^(cpy);
			with cpy : Cell do
				if props # nil then
					assert(cpy.props = nil);
					cpy.props := props.Copy()(PropertyList);
					cpy.props.parent := cpy;
				end;
				if ports # nil then
					cpy.ports := ports.Copy()(PortList);
					cpy.ports.parent := cpy;
				end;
				if clockInputs # nil then
					new(cpy.clockInputs,clockInputs.Length());
					cpy.clockInputs.parent := cpy;
				end;
				if clockOutputs # nil then
					new(cpy.clockOutputs,clockOutputs.Length());
					cpy.clockOutputs.parent := cpy;
				end;
				if inputs # nil then
					new(cpy.inputs,inputs.Length());
					cpy.inputs.parent := cpy;
				end;
				if outputs # nil then
					new(cpy.outputs,outputs.Length());
					cpy.outputs.parent := cpy;
				end;
				if inoutputs # nil then
					new(cpy.inoutputs,inoutputs.Length());
					cpy.inoutputs.parent := cpy;
				end;

				for k := 0 to cpy.ports.Length()-1 do
					p := cpy.ports.GetPort(k);
					if p is ClockInputPort then
						cpy.clockInputs.Add0(p);
					elsif p is ClockOutputPort then
						cpy.clockOutputs.Add0(p);
					elsif p.direction = In then
						cpy.inputs.Add0(p);
					elsif p.direction = Out then
						cpy.outputs.Add0(p);
					else
						assert(p.direction = Inout);
						cpy.inoutputs.Add0(p);
					end;
				end;

				if mainClockInput # nil then
					cpy.mainClockInput := cpy.clockInputs.GetPortByAcName(MainClockInputName);
				end;
				if mainResetInput # nil then
					cpy.mainResetInput := cpy.inputs.GetPortByAcName(MainResetInputName);
				end;

				if ports # nil then
					assert(cpy.ports.Length() = ports.Length());
					assert((mainClockInput # nil) = (cpy.mainClockInput # nil));
					assert((mainResetInput # nil) = (cpy.mainResetInput # nil));
				end;

				if dependencies # nil then
					cpy.dependencies := dependencies.Copy()(DependencyList);
					cpy.dependencies.parent := cpy;
				end;
				if postParamSetters # nil then
					cpy.postParamSetters := postParamSetters.Copy()(ObjectHandlerProcList);
					cpy.postParamSetters.parent := cpy;
				end;
				if postAssemblySetters # nil then
					cpy.postAssemblySetters := postAssemblySetters.Copy()(ObjectHandlerProcList);
					cpy.postAssemblySetters.parent := cpy;
				end;

				cpy.maxNumInstances := maxNumInstances;

				(*! do not copy things set by the runtime *)
				(*
				cpy.acInstType := acInstType; (*! copy by reference *)
				cpy.acInstName := acInstName; (*! copy by reference *)
				cpy.hdlInstName := hdlInstName; (*! copy by reference *)
				*)
			end;
		end CopyContent;

		(**
			Create a copy of the cell instance
		*)
		procedure CopyCell*(): Cell;
		var obj: Object;
		begin
			result := nil;
			obj := Copy();
			if obj # nil then result := obj(Cell); end;
		finally
			return result;
		end CopyCell;

		procedure CheckForUnconnectedPorts(): boolean;
		begin
			return true;
		end CheckForUnconnectedPorts;

		procedure PatchOutputPortConnections(p: Port): boolean;
		var
			repeater: Cell;
			net: Cellnet;
			str, str1: LongString;
			depth: size; k, n: size;
			pp: Port;
		begin
			if p.channels = nil then return true; end;

			if p is HdlPort then return true; end;

			assert((p is AxisPort) or ((p is CellnetPort) & (p(CellnetPort).protoPort is AxisPort)));

			repeater := hwLibrary.NewCellByAcNameAndTarget("StreamRepeater",ctx(HdlProject).target);
			if repeater = nil then
				Error(ErrNotFound,'could not find HDL component with name "StreamRepeater"');
				return false;
			end;
			repeater.SetContext(ctx);

			(* compose the name of repeater instance *)
			GetHdlNormalizedName(hdlInstName^,str);
			Strings.Concat("repeater_",str,str);
			Strings.Concat(str,"_",str);
			GetHdlNormalizedName(p.acName^,str1);
			Strings.Concat(str,str1,str);
			repeater.hdlInstName := Strings.NewString(str);
			repeater.acInstName := repeater.hdlInstName;

			assert(repeater.GetPropertyByAcName("DataWidth").SetValue(NewInteger(p.width)));
			assert(repeater.GetPropertyByAcName("NumOutputs").SetValue(NewInteger(p.channels.Length())));
			assert(repeater.PostParamSetup());

			net := GetCellnet();
			net.AddChild(repeater);

			assert(p.channel = nil);
			n := p.channels.Length();
			for k := 0 to n-1 do
				pp := p.channels.GetChannel(k).inPort;
				assert(pp.channel # nil);
				assert(pp.channels = nil);

				(*
					replace the old channel by a new one
				*)
				(* remove the old channel *)
				net.channels.Remove(pp.channel);
				depth := pp.channel.depth;
				pp.channel := nil;
				(* add a new channel *)
				DoConnect(repeater.outputs.GetPort(k),pp,depth);
			end;

			p.channels := nil;
			DoConnect(p,repeater.inputs.GetPortByAcName("input"),0);

			return true;
		finally
			return false;
		end PatchOutputPortConnections;

		procedure PatchMultipleOutputConnections(): boolean;
		var
			k, n: size;
			p: Port;
		begin
			if clockOutputs # nil then
				n := clockOutputs.Length();
				for k := 0 to n-1 do
					p := clockOutputs.GetPort(k);
					if ~PatchOutputPortConnections(p) then return false; end;
				end;
			end;

			if outputs # nil then
				n := outputs.Length();
				for k := 0 to n-1 do
					p := outputs.GetPort(k);
					if ~PatchOutputPortConnections(p) then return false; end;
				end;
			end;
			return true;
		finally
			return false;
		end PatchMultipleOutputConnections;

		procedure IdentifyUnusedPorts(): boolean;
		var
			i, j, n: size;
			p, pp: Port;
			unused, optional: boolean;
			ioSetup: IoSetup;
			ioPort: PldIoList;
		begin
			if clockInputs # nil then
				n := clockInputs.Length();
				for i := 0 to n-1 do
					p := clockInputs.GetPort(i);
					assert(p.channels = nil);
					unused := p.unused;
					if ~unused then
						unused := ~((p is HdlPort) & p(HdlPort).isExternal) & (p.channel = nil) & (p.delegateOf = nil);
					end;
					if unused & ~p.optional then Error(ErrNotDefined,'port "' & p.acName^ & '" cannot be left unconnected!'); return false; end;
					p.SetUnused(unused);
				end;
			end;

			if clockOutputs # nil then
				n := clockOutputs.Length();
				for i := 0 to n-1 do
					p := clockOutputs.GetPort(i);
					unused := p.unused;
					if ~unused then
						unused := ~((p is HdlPort) & p(HdlPort).isExternal) & (p.channel = nil) & (p.channels = nil) & (p.delegateOf = nil);
					end;
					if unused & ~p.optional then Error(ErrNotDefined,'port "' & p.acName^ & '" cannot be left unconnected!'); return false; end;
					p.SetUnused(unused);
				end;
			end;

			if inputs # nil then
				n := inputs.Length();
				for i := 0 to n-1 do
					p := inputs.GetPort(i);

					assert(p.channels = nil);
					unused := p.unused;
					optional := p.optional;
					if ~unused then
						if optional & (p is HdlPort) & p(HdlPort).isExternal then
							ioSetup := ctx(HdlProject).target.GetIoSetupByName(acName^ & "_" & instId);
							if ioSetup = nil then
								Error(ErrNotDefined,'IO setup with name "' & acName^ & "_" & instId & '" is not defined');
								return false;
							end;
							ioPort := ioSetup.GetIoPortByName(p.acName^);
							if ioPort = nil then
								unused := true;
							else
								unused := false;
							end;
						elsif p is CellnetPort then
							unused := p(CellnetPort).delegatedTo.GetPort(0).unused;
						elsif ((p is HdlPort) & p(HdlPort).isExternal) or (* an external HDL port *)
							(p.channel # nil) or (* port is connected to another port *)
							((p.delegateOf # nil) & ~p.delegateOf.unused) then (* port is delegated to an unused cellnet port *)
							unused := false;
						else
							unused := true;
						end;
					end;
					if unused & (p is CellnetPort) & ~optional then
						optional := p(CellnetPort).IsOptional();
					end;
					if unused & ~optional then
						Error(ErrNotDefined,'port "' & p.acName^ & '" cannot be left unconnected!'); return false;
					end;
					p.SetUnused(unused);

					if EnableTrace & unused & (p.acName # nil) then
						trace(acName^,p.acName^);
					end;
				end;
			end;

			if outputs # nil then
				n := outputs.Length();
				for i := 0 to n-1 do
					p := outputs.GetPort(i);

					unused := p.unused;
					optional := p.optional;
					if ~unused then
						if optional & (p is HdlPort) & p(HdlPort).isExternal then
							ioSetup := ctx(HdlProject).target.GetIoSetupByName(acName^ & "_" & instId);
							if ioSetup = nil then
								Error(ErrNotDefined,'IO setup with name "' & acName^ & "_" & instId & '" is not defined');
								return false;
							end;
							ioPort := ioSetup.GetIoPortByName(p.acName^);
							if ioPort = nil then
								unused := true;
							else
								unused := false;
							end;
						elsif p is CellnetPort then
							j := 0;
							while (j < p(CellnetPort).delegatedTo.Length()) & ~unused do
								unused := p(CellnetPort).delegatedTo.GetPort(j).unused;
								pp := p(CellnetPort).delegatedTo.GetPort(j);
								inc(j);
							end;
						elsif ((p is HdlPort) & p(HdlPort).isExternal) or (* an external HDL port *)
							((p.channel # nil) or (p.channels # nil)) or (* port is connected to another port *)
							((p.delegateOf # nil) & ~p.delegateOf.unused) then (* port is delegated to an unused cellnet port *)
							unused := false;
						else
							unused := true;
						end;
					end;
					if unused & (p is CellnetPort) & ~optional then
						optional := p(CellnetPort).IsOptional();
					end;
					if unused & ~optional then Error(ErrNotDefined,'port "' & p.acName^ & '" cannot be left unconnected!'); return false; end;
					p.SetUnused(unused);

					if EnableTrace & unused & (p.acName # nil) then
						trace(acName^,p.acName^);
					end;

				end;
			end;

			return true;

		finally
			return false;
		end IdentifyUnusedPorts;

		procedure Error(errorCode: integer; const message: array of char);
		var str: LongString;
		begin
			str := "cell ";
			if acInstName # nil then
				Strings.Concat(str,'instance "',str);
				Strings.Concat(str,acInstName^,str);
				Strings.Concat(str,'", ',str);
			end;
			Strings.Concat(str,'of type "',str);
			Strings.Concat(str,acName^,str);
			Strings.Concat(str,'"',str);
			ctx.Error(str,Streams.Invalid,errorCode,message);
		end Error;

		procedure Warning(const message: array of char);
		var str: LongString;
		begin
			str := "cell ";
			if acInstName # nil then
				Strings.Concat(str,'instance "',str);
				Strings.Concat(str,acInstName^,str);
				Strings.Concat(str,'", ',str);
			end;
			Strings.Concat(str,'of type "',str);
			Strings.Concat(str,acName^,str);
			Strings.Concat(str,'"',str);
			ctx.Warning(str,Streams.Invalid,Streams.Invalid,message);
		end Warning;

	end Cell;

	(**
		Cell list
	*)
	CellList* = object(HdlObjectList)

		(** Get cell by its index *)
		procedure GetCell*(i: size): Cell;
		var obj: HdlObject;
		begin
			obj := GetObj(i);
			if obj # nil then return obj(Cell);
			else return nil;
			end;
		end GetCell;

		(** Get cell by its ActiveCells name *)
		procedure GetCellByAcName*(const name: array of char): Cell;
		var obj: HdlObject;
		begin
			obj := GetObjByAcName(name);
			if obj # nil then return obj(Cell);
			else return nil;
			end;
		end GetCellByAcName;

		(** Get cell by its ActiveCells instance name *)
		procedure GetCellByAcInstName*(const name: array of char): Cell;
		var
			i, n: size;
			c: Cell;
		begin
			i := 0; n := Length();
			while i < n do
				c := GetCell(i);
				if (c.acInstName # nil) & (c.acInstName^ = name) then return c; end;
				inc(i);
			end;
			return nil;
		end GetCellByAcInstName;

		(** Get cell by its HDL name *)
		procedure GetCellByHdlName*(const name: array of char): Cell;
		var obj: HdlObject;
		begin
			obj := GetObjByHdlName(name);
			if obj # nil then return obj(Cell);
			else return nil;
			end;
		end GetCellByHdlName;

	end CellList;

	(**
		An engine
	*)
	Engine* = object(Cell)

		procedure &InitEngine*(const nameInAc, nameInHdl: array of char);
		begin
			InitCell(nameInAc,nameInHdl);
		end InitEngine;

	end Engine;

	(** Processor logical port *)
	LogicalPort* = object(Port)
	var
		acPortInd-: size; (** corresponding port index in the ActiveCells code (in the order of runtime code execution) *)
		commPortInd-: size; (** corresponding index in the physical communication port list (either Processor.commInputs or Processor.commOutputs depending on the port direction) *)
		muxPortInd-: size; (** corresponding multiplexed/demultiplexed port index *)
	end LogicalPort;

	(**
		A soft processor core
	*)
	Processor* = object(Cell)
	var
		isa-: Strings.String; (** instruction set architecture (determines compiler backend) *)

		commInputs-: PortList; (** list of physical input ports used for communication *)
		commOutputs-: PortList; (** list of physical outpus ports used for communication *)

		BasePortAddress-: unsigned64; (** Address of IO space for this processor*)
		logicalPorts-: PortList; (** list of logical ports mapped to communication input ports (these ports are not in the "ports" list) *)
		logicalInputs-: PortList; (** list of logical input ports *)
		logicalOutputs-: PortList; (** list of logical output ports *)

		procedure &InitProcessor*(const nameInAc, nameInHdl, instructionSet: array of char);
		begin
			InitCell(nameInAc,nameInHdl);
			BasePortAddress:=unsigned64(0xFFFFFFC0); (*default, matches TRM*)
			if instructionSet # "" then isa := Strings.NewString(instructionSet); end;
		end InitProcessor;

		procedure SetContext(context: Context);
		begin
			SetContext^(context);
			if logicalInputs # nil then logicalInputs.SetContext(context); end;
			if logicalOutputs # nil then logicalOutputs.SetContext(context); end;
		end SetContext;

		(**
			set the base port address which the software running on this processor uses to access communication channels.
			This is used in the generateCode routine to patch the port addresses
		*)
		procedure SetBasePortAddress*(newBasePort: unsigned64);
		begin
			trace(newBasePort);
			BasePortAddress:=newBasePort;
		end SetBasePortAddress;

		(**
			Create a new AXI4-Stream port used for peer-to-peer communication

			nameInHdl: name of the port in HDL code
			portDirection: direction of the port (In, Out or Inout)
			portWidth: width of the port in number of bits
		*)
		procedure NewCommAxisPort*(
												const nameInHdl: array of char;
												portDirection: integer; portWidth: size
												);
		var p: Port;
		begin
			NewAxisPort("",nameInHdl,portDirection,portWidth);
			p := GetPortByHdlName(nameInHdl);
			incl(p.flags,FlagCommPort);
			if portDirection = In then
				if commInputs = nil then new(commInputs,3); commInputs.parent := self; end;
				commInputs.Add0(p);
			else
				if commOutputs = nil then new(commOutputs,3); commOutputs.parent := self; end;
				commOutputs.Add0(p);
			end;
		end NewCommAxisPort;

		procedure AddLogicalPort(p: LogicalPort);
		begin
			if logicalPorts = nil then
				new(logicalPorts,3);
				logicalPorts.parent := self;
			end;
			logicalPorts.Add(p);
			if p.direction = Out then
				if logicalOutputs = nil then
					new(logicalOutputs,3);
					logicalOutputs.parent := self;
				end;
				logicalOutputs.Add0(p);
			else
				if logicalInputs = nil then
					new(logicalInputs,3);
					logicalInputs.parent := self;
				end;
				logicalInputs.Add0(p);
			end;
		end AddLogicalPort;

		procedure RemoveLogicalPort(p: LogicalPort);
		begin
			assert(logicalPorts.Contains(p));
			logicalPorts.Remove(p);
			if p.direction = Out then
				assert(logicalOutputs.Contains(p));
				logicalOutputs.Remove(p);
			else
				assert(logicalInputs.Contains(p));
				logicalInputs.Remove(p);
			end;
		end RemoveLogicalPort;

		procedure GetPortGroupId(p: Port; var id: IntegerType): boolean;
		var
			prop: Property;
			value: Integer;
		begin
			prop := p.GetPropertyByAcName(PropGroupId);
			if prop # nil then
				value := prop.value.ToInteger();
				if value # nil then id := value.val; return true;
				else return false; end;
			else id := 0; return true;
			end;
		end GetPortGroupId;

		(* multiplex a physical input among multiple logical ports *)
		procedure MultiplexInput(input: AxisPort; logInputs: PortList): boolean;
		var
			i, k, n: size;
			net: Cellnet;
			mux: Cell;
			str, str1: LongString;
			chan: Channel;
			p, pp: Port;
		begin
			if logInputs # nil then
				if logInputs.Length() > 1 then
					mux := hwLibrary.NewCellByAcNameAndTarget("StreamPortMux",ctx(HdlProject).target);
					if mux = nil then
						Error(ErrNotFound,'could not find HDL component with name "StreamPortMux"');
						return false;
					end;
					mux.SetContext(ctx);

					(* compose the name of StreamPortMux instance *)
					GetHdlNormalizedName(hdlInstName^,str);
					Strings.Concat("mux_",str,str);
					Strings.Concat(str,"_",str);
					GetHdlNormalizedName(input.hdlName^,str1);
					Strings.Concat(str,str1,str);
					mux.hdlInstName := Strings.NewString(str);

					assert(mux.GetPropertyByAcName("NumInputs").SetValue(NewInteger(logInputs.Length())));
					assert(mux.GetPropertyByAcName("DataWidth").SetValue(NewInteger(input.width)));
					assert(mux.PostParamSetup());
					net := GetCellnet();
					net.AddChild(mux);

					(* patch channels with logical inputs *)
					n := logInputs.Length();
					for i := 0 to n-1 do
						p := logInputs.GetPort(i);
						assert(~(FlagSoftwarePort in p.flags));

						p(LogicalPort).muxPortInd := i;
						chan := p.channel;
						if chan # nil then
							chan.inPort := mux.inputs.GetPort(i);
							chan.inPort.channel := chan;
						else
							assert(p.channels = nil);
							assert(p.delegateOf # nil);
							k := p.delegateOf(CellnetPort).delegatedTo.IndexOf(p); assert(k >= 0);
							pp := mux.inputs.GetPort(i);
							p.delegateOf(CellnetPort).delegatedTo.Set(k,pp);
							assert(p.delegateOf(CellnetPort).delegatedTo.Length()=1); (*! todo: implement check for compatibility of multiple ports *)
							assert(p.delegateOf(CellnetPort).protoPort is LogicalPort);
							assert(p.delegateOf(CellnetPort).SetupProtoPort(pp));
							pp.delegateOf := p.delegateOf;
						end;
					end;
					DoConnect(mux.outputs.GetPort(0),input,0);
				else (* single logical input port - no need to multiplex *)
					p := logInputs.GetPort(0);
					if p.channel # nil then
						chan := p.channel;
						chan.inPort := input;
						input.channel := chan;
					else
						assert(p.channels = nil);
						assert(p.delegateOf # nil);
						k := p.delegateOf(CellnetPort).delegatedTo.IndexOf(p); assert(k >= 0);
						p.delegateOf(CellnetPort).delegatedTo.Set(k,input);
						assert(p.delegateOf(CellnetPort).delegatedTo.Length()=1); (*! todo: implement check for compatibility of multiple ports *)
						assert(p.delegateOf(CellnetPort).protoPort is LogicalPort);
						assert(p.delegateOf(CellnetPort).SetupProtoPort(input));
						input.delegateOf := p.delegateOf;
					end;
				end;
			end;
			return true;
		end MultiplexInput;

		(* demultiplex a physical output to multiple logical ports *)
		procedure DemultiplexOutput(output: AxisPort; logOutputs: PortList): boolean;
		var
			i, j, n: size;
			net: Cellnet;
			demux: Cell;
			p, pp, pDemux: Port;
			str, str1: LongString;
			chan: Channel;
		begin
			if (logOutputs # nil) then
				if (logOutputs.Length() > 1) then
					demux := hwLibrary.NewCellByAcNameAndTarget("StreamPortDemux",ctx(HdlProject).target);
					if demux = nil then
						Error(ErrNotFound,'could not find HDL component with name "StreamPortDemux"');
						return false;
					end;
					demux.SetContext(ctx);

					(* compose the name of StreamPortDemux instance *)
					GetHdlNormalizedName(hdlInstName^,str);
					Strings.Concat("demux_",str,str);
					Strings.Concat(str,"_",str);
					GetHdlNormalizedName(output.hdlName^,str1);
					Strings.Concat(str,str1,str);
					demux.hdlInstName := Strings.NewString(str);

					assert(demux.GetPropertyByAcName("NumOutputs").SetValue(NewInteger(logOutputs.Length())));
					assert(demux.GetPropertyByAcName("DataWidth").SetValue(NewInteger(output.width)));
					assert(demux.PostParamSetup());
					net := GetCellnet();
					net.AddChild(demux);

					(* patch channels with logical outputs *)
					n := logOutputs.Length();
					for i := 0 to n-1 do
						p := logOutputs.GetPort(i);
						assert(~(FlagSoftwarePort in p.flags));
						p(LogicalPort).muxPortInd := i;
						if p.channels # nil then (* this logical output is connected to multiple inputs *)
							pDemux := demux.outputs.GetPort(i);
							for j := 0 to p.channels.Length()-1 do
								chan := p.channels.GetChannel(j);
								chan.outPort := pDemux;
							end;
							pDemux.channels := p.channels;
						elsif p.channel # nil then
							chan := p.channel;
							chan.outPort := demux.outputs.GetPort(i);
							chan.outPort.channel := chan;
						else
							assert(p.delegateOf # nil);
							assert(p.delegateOf(CellnetPort).delegatedTo.Length()=1);
							pp := demux.outputs.GetPort(i);
							p.delegateOf(CellnetPort).delegatedTo.Set(0,pp);
							assert(p.delegateOf(CellnetPort).SetupProtoPort(pp));
							pp.delegateOf := p.delegateOf;
						end;
					end;
					DoConnect(output,demux.inputs.GetPort(0),0);
				else (* single logical output port - no need to demultiplex *)

					p := logOutputs.GetPort(0);

					if p.channels # nil then (* this logical output is connected to multiple inputs *)
						for i := 0 to p.channels.Length()-1 do
							chan := p.channels.GetChannel(i);
							chan.outPort := output;
						end;
						output.channels := p.channels;
					elsif p.channel # nil then
						chan := p.channel;
						chan.outPort := output;
						output.channel := chan;
					else
						assert(p.delegateOf # nil);
						assert(p.delegateOf(CellnetPort).delegatedTo.Length()=1);
						p.delegateOf(CellnetPort).delegatedTo.Set(0,output);
						assert(p.delegateOf(CellnetPort).SetupProtoPort(output));
						output.delegateOf := p.delegateOf;
					end;
				end;
			end;
			return true;
		end DemultiplexOutput;

		(* patch logical ports by using port multiplexers *)
		procedure PatchLogicalPorts(): boolean;
		var
			i, j, n: size;
			p: Port;
			id: IntegerType;
			logInputs, logOutputs: pointer to array of PortList;
		begin

			trace(FlagSkipImplementation in self.flags);

			assert(logicalPorts # nil);

			assert(commInputs # nil);
			assert(commOutputs # nil);

			(*!TODO: account for logical ports with channel having FlagSoftwareChannel flag *)

			if logicalInputs # nil then
				n := logicalInputs.Length();
				for i := 0 to n-1 do
					p := logicalInputs.GetPort(i);
					if ~(FlagSoftwarePort in p.flags) then
						if (p.channel = nil) & (p.delegateOf = nil) then (*! do not allow unconnected processor ports *)
							Error(ErrNotDefined,'processor input port "' & p.acName^ & '" is left unconnected');
							return false;
						end;
						if GetPortGroupId(p,id) then
							if (id < 0) or (id >= commInputs.Length()) then
								Error(ErrNotDefined,'processor input port "' & p.acName^ & '" has invalid value of "' & PropGroupId & '" property');
								return false;
							end;
						else
							Error(ErrNotDefined,'processor input port "' & p.acName^ & '" has invalid specification of "' & PropGroupId & '" property');
							return false;
						end;
					end;
				end;
			end;

			if logicalOutputs # nil then
				n := logicalOutputs.Length();
				for i := 0 to n-1 do
					p := logicalOutputs.GetPort(i);
					if ~(FlagSoftwarePort in p.flags) then
						if (p.channel = nil) & (p.channels = nil) & (p.delegateOf = nil) then (*! do not allow unconnected processor ports *)
							Error(ErrNotDefined,'processor output port "' & p.acName^ & '" is left unconnected');
							return false;
						end;
						if GetPortGroupId(p,id) then
							if (id < 0) or (id >= commOutputs.Length()) then
								Error(ErrNotDefined,'processor output port "' & p.acName^ & '" has invalid value of "' & PropGroupId & '" property');
								return false;
							end;
						else
							Error(ErrNotDefined,'processor output port "' & p.acName^ & '" has invalid specification of "' & PropGroupId & '" property');
							return false;
						end;
					end;
				end;
			end;

			if logicalInputs # nil then
				assert(logicalInputs.Length() > 0);
				new(logInputs,commInputs.Length());
				(*
					sort logical ports by the assigned physical port
				*)
				n := logicalInputs.Length();
				for i := 0 to n-1 do
					p := logicalInputs.GetPort(i);
					if ~(FlagSoftwarePort in p.flags) then
						assert(GetPortGroupId(p,id));
						if logInputs[id] = nil then new(logInputs[id],4); end;
						p(LogicalPort).commPortInd := size(id);
						logInputs[id].Add0(p);
					end;
				end;
				(*
					multiplex each used physical port
				*)
				for i := 0 to len(logInputs,0)-1 do
					if logInputs[i] # nil then
						if ~MultiplexInput(commInputs.GetPort(i)(AxisPort),logInputs[i]) then return false; end;
					end;
				end;
			end;

			if logicalOutputs # nil then
				assert(logicalOutputs.Length() > 0);
				new(logOutputs,commOutputs.Length());
				(*
					sort logical ports by the assigned physical port
				*)
				n := logicalOutputs.Length();
				for i := 0 to n-1 do
					p := logicalOutputs.GetPort(i);
					if ~(FlagSoftwarePort in p.flags) then
						assert(GetPortGroupId(p,id));
						p(LogicalPort).commPortInd := size(id);
						if logOutputs[id] = nil then new(logOutputs[id],4); end;
						logOutputs[id].Add0(p);
					end;
				end;
				(*
					demultiplex each used physical port
				*)
				for i := 0 to len(logOutputs,0)-1 do
					if logOutputs[i] # nil then
						if ~DemultiplexOutput(commOutputs.GetPort(i)(AxisPort),logOutputs[i]) then return false; end;
					end;
				end;
			end;

			return true;
		finally
			return false;
		end PatchLogicalPorts;

		procedure CopyContent(cpy: Object);
		var
			i: size;
			p: Port;
		begin
			CopyContent^(cpy);
			with cpy :  Processor do
				cpy.isa := isa; (*! copy by reference *)
				if commInputs # nil then
					new(cpy.commInputs,commInputs.Length());
					for i := 0 to cpy.inputs.Length()-1 do
						p := cpy.inputs.GetPort(i);
						if FlagCommPort in p.flags then cpy.commInputs.Add0(p); end;
					end;
				end;
				if commOutputs # nil then
					new(cpy.commOutputs,commOutputs.Length());
					for i := 0 to cpy.outputs.Length()-1 do
						p := cpy.outputs.GetPort(i);
						if FlagCommPort in p.flags then cpy.commOutputs.Add0(p); end;
					end;
				end;
				assert(logicalPorts = nil);
				assert(logicalInputs = nil);
				assert(logicalOutputs = nil);
				(*if logicalInputs # nil then
					cpy.logicalInputs := logicalInputs.Copy()(PortList);
					cpy.logicalInputs.parent := cpy;
				end;
				if logicalOutputs # nil then
					cpy.logicalOutputs := logicalOutputs.Copy()(PortList);
					cpy.logicalOutputs.parent := cpy;
				end;*)
				cpy.BasePortAddress:=BasePortAddress;
			end;
		end CopyContent;

	end Processor;

	Cellnet* = object(Cell)
	var
		level-: size; (** hierarchical level (>=0); 0 is for the top-level cellnet (the architecture) *)

		children-: CellList; (** contains all children in case if this is a cellnet, otherwise is NIL *)
		channels-: ChannelList; (** list of all channels used for connecting cells within the cellnet *)

		clockSynthesizer-: Cell; (* synthesizer of architecture clocks *)

		procedure &InitCellNet(const name: array of char);
		begin
			InitCell(name,"");

			new(children,3);
			children.parent := self;

			new(channels,3);
			channels.parent := self;
		end InitCellNet;

		procedure AddChild(c: Cell);
		begin
			children.Add(c);
		end AddChild;

		procedure HasChild*(c: Cell): boolean;
		begin
			return children.IndexOf(c) >= 0;
		end HasChild;

		procedure FindChildByAcInstName*(const name: array of char; recursive: boolean): Cell;
		var
			i, n: size;
			c: Cell;
		begin
			c := children.GetCellByAcInstName(name);
			if c # nil then return c; end;
			if recursive then
				i := 0; n := children.Length();
				for i := 0 to n-1 do
					c := children.GetCell(i);
					if c is Cellnet then
						c := c(Cellnet).FindChildByAcInstName(name,true);
						if c # nil then return c; end;
					end
				end;
			end;
			return nil;
		end FindChildByAcInstName;

		procedure ReplaceChild*(cOld: Cell; cNew: Cell);
		var i: size;
		begin
			i := children.IndexOf(cOld);
			assert(i >= 0);
			children.Set(i,cNew);
			cNew.parent := children;
		end ReplaceChild;

		procedure CheckForUnconnectedPorts(): boolean;
		var
			i, n: size;
			p: Port;
		begin
			if ports # nil then
				n := ports.Length();
				for i := 0 to n-1 do
					p := ports.GetPort(i);
					with p : CellnetPort do
						if p.delegatedTo = nil then
							assert(p.protoPort = nil);
							Error(ErrNotDefined,'cellnet port ' & p.acName^ & " is left undelegated");
							return false;
						end;
					end;
				end;
			end;

			n := children.Length();
			for i := 0 to n-1 do
				if ~children.GetCell(i).CheckForUnconnectedPorts() then return false; end;
			end;

			return true;
		end CheckForUnconnectedPorts;

		procedure PatchMultipleOutputConnections(): boolean;
		var
			k, n: size;
			c: Cell;
		begin

			assert((mainClockInput = nil) or (mainClockInput.channel = nil));
			assert((mainResetInput = nil) or (mainResetInput.channel = nil));
			assert(clockInputs = nil);

			if ~PatchMultipleOutputConnections^() then
				return false;
			end;

			n := children.Length();
			for k := 0 to n-1 do
				c := children.GetCell(k);
				if ~c.PatchMultipleOutputConnections() then return false; end;
			end;
			return true;
		finally
			return false;
		end PatchMultipleOutputConnections;

		procedure CollectLimitedInstanceProcessors(c: Cell; param: any): boolean;
		begin
			with c : Processor do
				if c.maxNumInstances > 0 then
					param(CellList).Add0(c);
				end;
			else
			end;
			return true;
		end CollectLimitedInstanceProcessors;

		(* Hierarchical delegation of a port to a cellnet of lower level *)
		procedure HierarchicalDelegate(p: Port; destNet: Cellnet): CellnetPort;
		var
			level: size;
			pnet: CellnetPort;
		begin
			level := p.GetCell().GetCellnet().level;
			assert(level > destNet.level);
			new(pnet,p.GetCell().hdlInstName^ & "_" & p.acName^,p.direction,p.width);
			p.GetCell().GetCellnet().AddPort(pnet);
			DoDelegate(pnet,p);
			if level-1 > destNet.level then
				return HierarchicalDelegate(pnet,destNet);
			else
				return pnet;
			end;
		end HierarchicalDelegate;

		(* Complete removal of a connection *)
		procedure RemoveConnection(channel: Channel);
		var
			net: Cellnet;
			po, pi: Port;
		begin
			pi := channel.inPort; assert(pi.channel = channel);
			po := channel.outPort;
			channel.parent(ChannelList).Remove(channel);
			if po.channel # nil then
				assert(po.channels = nil);
				po.channel := nil;
			else
				assert(po.channels # nil);
				assert(po.channels.Contains(channel));
				po.channels.Remove(channel);
			end;
			pi.channel := nil;
			channel.outPort := nil; channel.inPort := nil;
		end RemoveConnection;

		(* Get the terminal of a cellnet port: traverses through all delegations until reaches a channel connection or the predefined level *)
		procedure GetCellnetPortTerminal(pnet: CellnetPort; upToLevel: size; var connectedDelegates: PortList): CellnetPort;
		var pnet1: CellnetPort;
		begin
			upToLevel := max(0,upToLevel);
			while (pnet.GetCell()(Cellnet).level > upToLevel) & (pnet.delegateOf # nil) do
				if pnet.direction = Out then
					if (pnet.channel # nil) or (pnet.channels # nil) then connectedDelegates.Add0(pnet); end;
				else
					assert(pnet.direction = In);
				end;
				pnet1 := pnet;
				pnet := pnet.delegateOf;
				assert(pnet1.GetCell().ports.Contains(pnet1));
			end;
			return pnet;
		end GetCellnetPortTerminal;

		(* Removal of a delegate up to a given level (excluding this level) *)
		procedure RemoveDelegation(p: Port; upToLevel: size);
		var pnet, pnet1: CellnetPort;
		begin
			assert(p.delegateOf # nil);
			upToLevel := max(0,upToLevel);
			pnet := p.delegateOf;
			while (pnet.delegatedTo.Length() = 0) & (pnet.GetCell()(Cellnet).level > upToLevel) & (pnet.delegateOf # nil) do
				pnet1 := pnet;
				pnet := pnet.delegateOf;
				pnet.delegatedTo.Remove(pnet1);
				assert(pnet1.GetCell().ports.Contains(pnet1));
				pnet1.GetCell().RemovePort(pnet1);
			end;
		end RemoveDelegation;

		(* patch processors with limited number of instances  *)
		procedure PatchProcessors(): boolean;
		var
			processors, procs: CellList;
			proc0, proc1: Processor;
			pl: LogicalPort;
			pnet: CellnetPort;
			connPorts: PortList;
			p: Port;
			i: size; depth: size;
		begin

			(* collect all processors in the architecture which have a limited number of instances on the given target *)
			new(processors,8);
			if ~TraverseCells(CollectLimitedInstanceProcessors,true,processors) then
				return false;
			end;

			new(procs,8);
			new(connPorts,4);

			while processors.Length() > 0 do

				(* find a group of processors of the same type *)
				proc0 := processors.GetCell(0)(Processor);
				processors.Remove(proc0);
				procs.Clear;
				for i := 0 to processors.Length()-1 do
					proc1 := processors.GetCell(i)(Processor);
					if proc1.acName^ = proc0.acName^ then procs.Add0(proc1); end;
				end;
				for i := 0 to procs.Length()-1 do processors.Remove(procs.Get(i)); end;

				if procs.Length()+1 > proc0.maxNumInstances then

					(*!TODO: check whether the processor's runtime supports active objects *)
					(*!TODO: check whether the processor has AXIS ports for implementing the logical ports *)

					if proc0.maxNumInstances > 1 then
						ErrorNotImplemented("patching of processors with maxNumInstances > 1 is not yet implemented!");
						return false;
					end;

					for i := 0 to procs.Length()-1 do

						proc1 := procs.GetCell(i)(Processor);

						assert(proc1.logicalPorts # nil);
						while proc1.logicalPorts.Length() # 0 do
							pl := proc1.logicalPorts.GetPort(0)(LogicalPort);
							(* move the port to proc0 *)
							proc1.RemoveLogicalPort(pl); proc0.AddLogicalPort(pl);
							if pl.direction = In then (* input port *)

								if pl.delegateOf = nil then (* direct connection *)
									assert(pl.channel # nil);
									p := pl.channel.outPort;
									if p.GetCell().acName^ # proc0.acName^ then (* port is not connected to a processor of the same type - hardware-based port *)
										if p.GetCell().GetCellnet() # proc0.GetCellnet() then (* port p is at a different level than proc0 *)
											depth := pl.channel.depth;
											RemoveConnection(pl.channel); assert(pl.channel = nil);
											pnet := HierarchicalDelegate(p,proc0.GetCellnet());
											DoConnect(pnet,pl,depth);
										end;
									else (* software-based port *)
										RemoveConnection(pl.channel); assert(pl.channel = nil);
										incl(p.flags,FlagSoftwarePort);
										incl(pl.flags,FlagSoftwarePort);
										if p.GetCell() # proc0 then (* move the connected logical port to proc0 *)
											p.GetCell()(Processor).RemoveLogicalPort(p(LogicalPort)); proc0.AddLogicalPort(p(LogicalPort));
										end;
									end;
								else (* logical input port is delegated *)
									assert(pl.channels = nil);
									pnet := GetCellnetPortTerminal(pl.delegateOf,proc0.GetCellnet().level-1,connPorts);
									assert(pnet.direction = In);
									if pnet.delegateOf = nil then (* port connected directly to a component *)
										assert(pnet.channel # nil);
										p := pnet.channel.outPort;
										if p.GetCell().acName^ # proc0.acName^ then (* hardware-based port *)
											RemoveDelegation(pl,proc0.GetCellnet().level-1);
											(* remove port channel from the current level *)
											depth := pnet.channel.depth;
											RemoveConnection(pnet.channel);
											pnet.GetCell().RemovePort(pnet);
											if p.GetCell().GetCellnet() # proc0.GetCellnet() then (* port p is at a different level than proc0 *)
												pnet := HierarchicalDelegate(p,proc0.GetCellnet());
												DoConnect(pnet,pl,depth);
											else (* proc1 is at the same level as proc0 *)
												DoConnect(p,pl,depth);
											end;
										else (* software-based port: port is connected to a processor of the same type as proc0 *)
											RemoveDelegation(pl,proc0.GetCellnet().level-1);
											RemoveConnection(pnet.channel); assert(pnet.channel = nil);
											pnet.GetCell().RemovePort(pnet);
											incl(p.flags,FlagSoftwarePort);
											incl(pl.flags,FlagSoftwarePort);
											if p.GetCell() # proc0 then (* move the connected logical port to proc0 *)
												p.GetCell()(Processor).RemoveLogicalPort(p(LogicalPort)); proc0.AddLogicalPort(p(LogicalPort));
											end;
										end;
									else
										assert(pnet.GetCell() = proc0.GetCellnet());
										RemoveDelegation(pl.delegateOf,proc0.GetCellnet().level-1);
										DoDelegate(pnet,pl);
									end;
								end;

							else (* output port *)

								assert(pl.direction = Out);
								if pl.channel # nil then
									p := pl.channel.inPort;
									if p.GetCell().acName^ # proc0.acName^ then (* port is not connected to a processor of the same type - hardware-based port *)
										if p.GetCell().GetCellnet() # proc0.GetCellnet() then (* port p is at a different level than proc0 *)
											depth := pl.channel.depth;
											(* remove port channel from the current level *)
											RemoveConnection(pl.channel);
											pnet := HierarchicalDelegate(p,proc0.GetCellnet());
											DoConnect(pl,pnet,depth);
										end;
									else (* software-based port *)
										RemoveConnection(pl.channel); assert(pl.channel = nil);
										incl(p.flags,FlagSoftwarePort);
										incl(pl.flags,FlagSoftwarePort);
										if p.GetCell() # proc0 then (* move the connected logical port to proc0 *)
											p.GetCell()(Processor).RemoveLogicalPort(p(LogicalPort)); proc0.AddLogicalPort(p(LogicalPort));
										end;
									end;
								elsif pl.channels # nil then
									halt(100);
								end;
								if pl.delegateOf # nil then
									connPorts.Clear;
									pnet := GetCellnetPortTerminal(pl.delegateOf,proc0.GetCellnet().level-1,connPorts);
									assert(pnet.direction = Out);
									if pnet.channel # nil  then

										p := pnet.channel.inPort;
										if p.GetCell().acName^ # proc0.acName^ then (* hardware-based port *)
											RemoveDelegation(pl,proc0.GetCellnet().level-1);
											(* remove port channel from the current level *)
											depth := pnet.channel.depth;
											RemoveConnection(pnet.channel);
											pnet.GetCell().RemovePort(pnet);
											if p.GetCell().GetCellnet() # proc0.GetCellnet() then (* port p is at a different level than proc0 *)
												pnet := HierarchicalDelegate(p,proc0.GetCellnet());
												DoConnect(pl,pnet,depth);
											else (* proc1 is at the same level as proc0 *)
												DoConnect(pl,p,depth);
											end;
										else (* software-based port: port is connected to a processor of the same type as proc0 *)
											RemoveDelegation(pl,proc0.GetCellnet().level-1);
											RemoveConnection(pnet.channel); assert(pnet.channel = nil);
											pnet.GetCell().RemovePort(pnet);
											incl(p.flags,FlagSoftwarePort);
											incl(pl.flags,FlagSoftwarePort);
											if p.GetCell() # proc0 then (* move the connected logical port to proc0 *)
												p.GetCell()(Processor).RemoveLogicalPort(p(LogicalPort)); proc0.AddLogicalPort(p(LogicalPort));
											end;
										end;

									elsif pnet.channels # nil then
										halt(100);
									end;
									if pnet.delegateOf # nil then
										halt(100);
									end;
									if connPorts.Length() > 0 then
										halt(100);
									end;
								end;
							end;
						end;
						proc1.logicalPorts := nil;
						proc1.logicalInputs := nil;
						proc1.logicalOutputs := nil;

						(* skip HDL code emission for the given processor instance *)
						incl(proc1.flags,FlagSkipImplementation);
					end;

					procs.Clear;
				end;
			end;

			return true;
		finally
			return false;
		end PatchProcessors;

		(* patch logical ports by using port multiplexers *)
		procedure PatchProcessorLogicalPorts(): boolean;
		var
			k, n: size;
			c: Cell;
		begin
			n := children.Length();
			for k := 0 to n-1 do
				c := children.GetCell(k);
				if c is Cellnet then
					if ~c(Cellnet).PatchProcessorLogicalPorts() then return false; end;
				elsif (c is Processor) & ~(FlagSkipImplementation in c.flags) & ~c(Processor).PatchLogicalPorts() then return false; end;
			end;
			return true;
		finally
			return false;
		end PatchProcessorLogicalPorts;

		procedure PatchChannel(chan: Channel; var chanIndex: size): boolean;
		var
			fifo: Cell;
			p: Port;
			outCell: Cell;
			str: LongString;
			chan1: Channel;
			outPort, inPort: Port;
		begin
			if chan.depth = 0 then return true; end;

			outCell := chan.outPort.GetCell();

			outPort := chan.outPort;
			if outPort is CellnetPort then outPort := outPort(CellnetPort).protoPort; end;

			inPort := chan.inPort;
			if inPort is CellnetPort then inPort := inPort(CellnetPort).protoPort; end;

			if (outPort is AxisPort) & (inPort is AxisPort) then

				fifo := hwLibrary.NewCellByAcNameAndTarget("Fifo",ctx(HdlProject).target);
				if fifo = nil then
					Error(ErrNotFound,'could not find HDL component with name "Fifo"');
					return false;
				end;
				fifo.SetContext(outCell.ctx);

				(* compose the name of FIFO instance *)
				Strings.IntToStr(chanIndex,str);
				Strings.Concat("fifo",str,str);
				fifo.hdlInstName := Strings.NewString(str);

				assert(fifo.GetPropertyByAcName("DataWidth").SetValue(NewInteger(outPort.width)));
				assert(fifo.GetPropertyByAcName("Length").SetValue(NewInteger(chan.depth)));
				assert(fifo.PostParamSetup());
				outCell.GetCellnet().AddChild(fifo);

				p := fifo.GetPortByAcName("output"); assert(p # nil);
				new(chan1,p,chan.inPort,0);
				outCell.GetCellnet().channels.Add(chan1);

				p := fifo.GetPortByAcName("input"); assert(p # nil);
				chan.inPort := p;
				p.channel := chan;
				chan.depth := 0;

				inc(chanIndex);

				return true;
			else
				halt(111);
				return false;
			end;

		finally
			return false;
		end PatchChannel;

		(* patch port channel connections using FIFOs *)
		procedure PatchChannels(): boolean;
		var
			i, n: size;
			c: Cell;
			chanIndex: size;
		begin
			n := channels.Length();
			i := 0; chanIndex := 0;
			while (i < n) & PatchChannel(channels.GetChannel(i),chanIndex) do inc(i); end;
			if i < n then return false; end;

			n := children.Length();
			for i := 0 to n-1 do
				c := children.GetCell(i);
				if (c is Cellnet) & ~c(Cellnet).PatchChannels() then return false; end;
			end;

			return true;

		finally
			return false;
		end PatchChannels;

		procedure PatchInputPortDelegations(p: CellnetPort): boolean;
		var
			repeater: Cell;
			str: LongString;
			k, n: size;
		begin
			if (p.delegatedTo = nil) or (p.delegatedTo.Length() = 1) or (p.protoPort is HdlPort) then return true; end;

			assert(p.protoPort is AxisPort);

			repeater := hwLibrary.NewCellByAcNameAndTarget("StreamRepeater",ctx(HdlProject).target);
			if repeater = nil then
				Error(ErrNotFound,'could not find HDL component with name "StreamRepeater"');
				return false;
			end;
			repeater.SetContext(ctx);

			(* compose the name of repeater instance *)
			GetHdlNormalizedName(p.acName^,str);
			Strings.Concat("repeater_",str,str);
			repeater.hdlInstName := Strings.NewString(str);
			repeater.acInstName := repeater.hdlInstName;

			assert(repeater.GetPropertyByAcName("DataWidth").SetValue(NewInteger(p.width)));
			assert(repeater.GetPropertyByAcName("NumOutputs").SetValue(NewInteger(p.delegatedTo.Length())));
			assert(repeater.PostParamSetup());
			AddChild(repeater);

			n := p.delegatedTo.Length();
			for k := 0 to n-1 do
				DoConnect(repeater.outputs.GetPort(k),p.delegatedTo.GetPort(k),0);
			end;

			p.delegatedTo.Clear;
			DoDelegate(p,repeater.inputs.GetPort(0));

			return true;
		finally
			return false;
		end PatchInputPortDelegations;

		(*
			Patch multiple input port delegations by inserting stream repeaters
		*)
		procedure PatchMultipleInputDelegations(): boolean;
		var
			k, n: size;
			c: Cell;
			p: Port;
		begin

			assert((mainClockInput = nil) or (mainClockInput.channel = nil));
			assert((mainResetInput = nil) or (mainResetInput.channel = nil));
			assert(clockInputs = nil);

			if inputs # nil then
				n := inputs.Length();
				for k := 0 to n-1 do
					p := inputs.GetPort(k);
					if p is CellnetPort then
						if ~PatchInputPortDelegations(p(CellnetPort)) then return false; end;
					end;
				end;
			end;

			n := children.Length();
			for k := 0 to n-1 do
				c := children.GetCell(k);
				if (c is Cellnet) & ~c(Cellnet).PatchMultipleInputDelegations() then return false; end;
			end;
			return true;
		finally
			return false;
		end PatchMultipleInputDelegations;

		procedure PatchMainClockInputPorts(): boolean;
		var
			i, n: size;
			c: Cell;
			str: LongString;
			pnet: CellnetPort;
			delegated: boolean;
		begin
			(* first patch all children cellnets *)
			n := children.Length();
			for i := 0 to n-1 do
				c := children.GetCell(i);
				if c is Cellnet then
					if ~c(Cellnet).PatchMainClockInputPorts() then
						return false;
					end;
				end;
			end;

			(* now patch locally *)
			i := 0;
			while (i < n) & ((children.GetCell(i).mainClockInput = nil) or (children.GetCell(i).mainClockInput.channel = nil)) do inc(i); end;
			assert(i = n);

			if mainClockInput = nil then
				new(pnet,MainClockInputName,In,1);
				pnet.SetContext(ctx);
				mainClockInput := pnet;
				AddPort(pnet);
			end;

			delegated := false;
			for i := 0 to n-1 do
				c := children.GetCell(i);
				if c.mainClockInput # nil then
					c.mainClockInput.GetTypeName(str);
					assert(c.mainClockInput.channel = nil);
					if ~mainClockInput(CellnetPort).DelegateTo(c.mainClockInput) then return false; end;
					delegated := true;
				end;
			end;

			if ~delegated then
				RemovePort(pnet);
			end;

			return true;

		finally
			return false;
		end PatchMainClockInputPorts;

		procedure PatchMainResetInputPorts(): boolean;
		var
			i, n: size;
			c: Cell;
			str: LongString;
			pnet: CellnetPort;
			delegated: boolean;
		begin
			(* first patch all children cellnets *)
			n := children.Length();
			for i := 0 to n-1 do
				c := children.GetCell(i);
				if c is Cellnet then
					if ~c(Cellnet).PatchMainResetInputPorts() then
						return false;
					end;
				end;
			end;

			(* now patch locally *)
			i := 0;
			while (i < n) & ((children.GetCell(i).mainResetInput = nil) or (children.GetCell(i).mainResetInput.channel = nil)) do inc(i); end;
			assert(i = n);

			(*if GetCellnet() # nil then (* create mainResetInput port if it is not a top level cellnet *)*)
			if mainResetInput = nil then
				new(pnet,MainResetInputName,In,1);
				pnet.SetContext(ctx);
				mainResetInput := pnet;
				AddPort(pnet);
			end;
			(*end;*)

			delegated := false;
			for i := 0 to n-1 do
				c := children.GetCell(i);
				if c.mainResetInput # nil then
					c.mainResetInput.GetTypeName(str);
					if ~mainResetInput(CellnetPort).DelegateTo(c.mainResetInput) then return false; end;
					delegated := true;
				end;
			end;

			if ~delegated then
				RemovePort(pnet);
			end;

			return true;

		finally
			return false;
		end PatchMainResetInputPorts;

		(* Process external ports, which come directly from/to FPGA pins *)
		procedure PatchExternalPorts(): boolean;
		var
			i, j, m, n: size;
			c: Cell;
			p, pp: Port;
			pnet: CellnetPort;
		begin
			(* first patch all children cellnets *)
			n := children.Length();
			for i := 0 to n-1 do

				c := children.GetCell(i);
				if (c is Cellnet) & ~(FlagSkipImplementation in c.flags) then
					if ~c(Cellnet).PatchExternalPorts() then
						return false;
					end;
				end;

				if ~(FlagSkipImplementation in c.flags) & (c.ports # nil) then
					m := c.ports.Length();
					for j := 0 to m-1 do
						p := c.ports.GetPort(j);
						if p is CellnetPort then
							pp := p(CellnetPort).protoPort;
							assert(pp # nil);
						else pp := p;
						end;
						assert(~(pp is CellnetPort));
						if (pp is HdlPort) & (pp(HdlPort).isExternal) then
							new(pnet,acName^ & pp.GetCell().hdlInstName^ & "_" & p.hdlName^,p.direction,p.width);
							if ~pnet.DelegateTo(p) then return false; end;
							AddPort(pnet);
						end;
						(*
						if p is CellnetPort then pp := p(CellnetPort).protoPort; else pp := p; end;
						assert(~(pp is CellnetPort));
						if pp = nil then
							Error(ErrNotDefined,'cellnet port "' & p.acName^ & '" is left floating');
							return false;
						end;
						if ~pp.unused & (pp is HdlPort) & pp(HdlPort).isExternal then
							new(pnet,pp.GetCell().hdlInstName^ & "_" & pp.hdlName^,pp.direction,pp.width);
							assert(pnet.SetupProtoPort(pp));
							assert(pnet.DelegateTo(p));
							AddPort(pnet);
						end;
						*)
					end;
				end;

			end;

			return true;

		finally
			return false;
		end PatchExternalPorts;

		(*
			identify all clocks in the architecture

			clocks: list with all distinct clocks used in the architecture
			allMainClockInpsAreConnected: TRUE if main clock inputs of all components are connected to a clock output
		*)
		procedure IdentifyClocks(
										var clocks: ClockList;
										var allMainClockInpsAreConnected: boolean
										): boolean;
		var
			i, j, k, n: size;
			c: Cell;
			clockOutput: ClockOutputPort;
			p_SourceClock, p_MulFactor, p_DivFactor, p_Phase, p_DutyCycle: Property;
			clockInput: ClockInputPort;
			clock: Clock;
			derivedClock: DerivedClock;
			str: Strings.String;
			p: Port;
		begin
			n := children.Length();
			for i := 0 to n-1 do

				c := children.GetCell(i);

				if ~(c is Cellnet) then

					if c.acName^ = SystemClockName then (* SystemClock component *)

						if clocks.GetClockByName(SystemClockName) # nil then
							Error(ErrAlreadyExists,"SystemClock is defined multiple times");
							return false;
						end;

						p_MulFactor := c.GetPropertyByAcName(PropMulFactor);
						p_DivFactor := c.GetPropertyByAcName(PropDivFactor);
						p_DutyCycle := c.GetPropertyByAcName(PropDutyCycle);
						p_Phase := c.GetPropertyByAcName(PropPhase);

						clockInput := c.clockInputs.Get(0)(ClockInputPort);
						if clockInput.channel # nil then (* SystemClock.input is connected to a clock output port *)
							p := clockInput.channel.outPort;
							if p is CellnetPort then
								while p is CellnetPort do
									p := p(CellnetPort).delegatedTo.GetPort(0);
								end;
							end;
							clock := p(ClockOutputPort).clock;
							if clock is DerivedClock then
								ErrorNotImplemented(""); return false;
							end;
						else (*! SystemClock.input is unconnected, look for the presence of system clock in the target specification *)
							clock := GetProject().target.systemClock;
							if clock = nil then
								Error(ErrNotDefined,"SystemClock source signal is not defined");
								return false;
							end;
							clock := clock(DerivedClock).refClock;
						end;

						new(derivedClock,SystemClockName,clock,p_MulFactor.value.ToReal().val,p_DivFactor.value.ToReal().val);
						derivedClock.SetDutyCycle(p_DutyCycle.value.ToReal().val);
						derivedClock.SetPhaseShift(p_Phase.value.ToReal().val);
						clockOutput := c.clockOutputs.Get(0)(ClockOutputPort);
						clockOutput.clock := derivedClock;
						derivedClock.source := clockOutput;
						clocks.Add(derivedClock);

					elsif c.acName^ = ExternalClockName then (* an external clock *)

						p_SourceClock := c.GetPropertyByAcName(PropSourceClock);

						str := p_SourceClock.value.ToString().val;
						clock := GetTarget().clocks.GetClockByName(str^);

						if clock = nil then
							Error(ErrNotDefined,"external clock " & str^ & " is not defined in the target specification");
							return false;
						end;

						clockOutput := c.clockOutputs.Get(0)(ClockOutputPort);
						if (clockOutput.channel # nil) or (clockOutput.channels # nil) then

							p_MulFactor := c.GetPropertyByAcName(PropMulFactor);
							p_DivFactor := c.GetPropertyByAcName(PropDivFactor);
							p_DutyCycle := c.GetPropertyByAcName(PropDutyCycle);
							p_Phase := c.GetPropertyByAcName(PropPhase);

							new(derivedClock,c.hdlInstName^,clock,p_MulFactor.value.ToReal().val,p_DivFactor.value.ToReal().val);
							derivedClock.SetDutyCycle(p_DutyCycle.value.ToReal().val);
							derivedClock.SetPhaseShift(p_Phase.value.ToReal().val);
							clockOutput.clock := derivedClock;
							derivedClock.source := clockOutput;
							clocks.Add(derivedClock);

						end;

					elsif c.acName^ = ClockGenName then (* a clock generator *)

						clockOutput := c.clockOutputs.Get(0)(ClockOutputPort);
						if (clockOutput.channel # nil) or (clockOutput.channels # nil) then

							p_MulFactor := c.GetPropertyByAcName(PropMulFactor);
							p_DivFactor := c.GetPropertyByAcName(PropDivFactor);
							p_DutyCycle := c.GetPropertyByAcName(PropDutyCycle);
							p_Phase := c.GetPropertyByAcName(PropPhase);

							clockInput := c.clockInputs.Get(0)(ClockInputPort);
							if clockInput.channel # nil then (* SystemClock.input is connected to a clock output port *)
								clock := clockInput.channel.outPort(ClockOutputPort).clock;
								if clock is DerivedClock then
									ErrorNotImplemented(""); return false;
								end;
							else (*! ClockGen.input is unconnected *)
								Error(ErrNotDefined,ClockGenName & " source signal is not defined");
								return false;
							end;

							new(derivedClock,c.hdlInstName^,clock,p_MulFactor.value.ToReal().val,p_DivFactor.value.ToReal().val);
							derivedClock.SetDutyCycle(p_DutyCycle.value.ToReal().val);
							derivedClock.SetPhaseShift(p_Phase.value.ToReal().val);
							clockOutput.clock := derivedClock;
							derivedClock.source := clockOutput;
							clocks.Add(derivedClock);
						end;

					else (* other cases when an internal clock output port is directly connected to a clock input of a component *)

						if c.clockOutputs # nil then

							for j := 0 to c.clockOutputs.Length()-1 do

								clockOutput := c.clockOutputs.GetPort(j)(ClockOutputPort);

								if (clockOutput.channel # nil) or (clockOutput.channels # nil) then

									if (clockOutput.clock = nil) or (clockOutput.clock.frequency <= 0) then (*! clock is not defined *)
										Error(ErrNotDefined,"frequency of the clock signal provided by the port " & clockOutput.acName^ & " is not defined");
										return false;
									end;

									if clockOutput.channel # nil then (* the clock output is connected to a single input *)
										assert(clockOutput.channels = nil);
										assert(clockOutput.clock.source = clockOutput); (* an internal clock *)
										assert(~(clockOutput.clock is DerivedClock));

										str := clockOutput.channel.inPort.GetCell().acName;
										if (str^ # SystemClockName) & (str^ # ExternalClockName) & (str^ # ClockGenName) then
											assert(clocks.IndexOf(clockOutput.clock) = -1);
											clocks.Add(clockOutput.clock);
										end;
									else (* the clock output is connected to multiple inputs *)
										k := 0; n := clockOutput.channels.Length();
										repeat
											str := clockOutput.channels.GetChannel(k).inPort.GetCell().acName;
											inc(k);
										until (k = n) or ~((str^ = SystemClockName) or (str^ = ExternalClockName) or (str^ = ClockGenName));
										if k < n then (* there is a connection to a non-dedicated component *)
											assert(clocks.IndexOf(clockOutput.clock) = -1);
											clocks.Add(clockOutput.clock);
										end;
									end;

								end;
							end;
						end;

						if (c.mainClockInput # nil) & (c.mainClockInput.channel = nil) then
							allMainClockInpsAreConnected := false;
						end;

					end;
				else
					if ~c(Cellnet).IdentifyClocks(clocks,allMainClockInpsAreConnected) then return false; end;
				end;
			end;

			return true;
		end IdentifyClocks;

		procedure PatchClocks(): boolean;
		var
			i, j: size;
			clock, inpClock, outClock: Clock;
			inpClockInd: size;
			clocks: ClockList;
			inputClocks, outputClocks: ClockList;
			p, pp: Port;
			chan: Channel;
			chans: ChannelList;
			clockComp: Cell;
			allMainClockInpsAreConnected: boolean;
			derivedClock: DerivedClock;
		begin
			(*
				first identify all clock signals
			*)
			new(clocks,8);
			allMainClockInpsAreConnected := true;
			if ~IdentifyClocks(clocks,allMainClockInpsAreConnected) then return false; end;

			if (clocks.Length() = 0) & (mainClockInput = nil) then
				return true;
			end;

			if (clocks.GetClockByName(SystemClockName) = nil) & (GetTarget().systemClock # nil) then
				clocks.Add(GetTarget().systemClock);
			elsif (clocks.Length() = 0) & ~allMainClockInpsAreConnected then
				Error(ErrNotDefined,"no system clock is defined and one of the component's main clock input is left unconnected");
				return false;
			end;

			new(inputClocks,clocks.Length());
			new(outputClocks,clocks.Length());

			for i := 0 to clocks.Length()-1 do
				clock := clocks.Get(i)(Clock);
				if clock is DerivedClock then (* derived clock *)
					assert(clock(DerivedClock).refClock.source # nil);
					if clock(DerivedClock).refClock is DerivedClock then
						ErrorNotImplemented("deriving from a derived clock not yet implemented");
						return false;
					end;
					if inputClocks.GetClockByName(clock(DerivedClock).refClock.name^) = nil then
						inputClocks.Add(clock(DerivedClock).refClock);
					end;
					outputClocks.Add(clock);
				else (* internal clock *)
					assert(clock.source is ClockOutputPort);
					if inputClocks.GetClockByName(clock.name^) = nil then
						inputClocks.Add(clock);
					end;
					new(derivedClock,"",clock,1,1);
					outputClocks.Add(derivedClock);
				end;
			end;

			(*
				Generate all clocks
			*)
			if ~CreateClockSynthesizer(inputClocks,outputClocks,false,clockSynthesizer) then
				return false;
			end;

			children.Add(clockSynthesizer);

			(*
				Replace virtual clock generation components by connecting all clock
				input/output ports to the corresponding ports of just generated clock synthesizer
			*)
			inpClockInd := 0;
			for i := 0 to clocks.Length()-1 do

				clock := clocks.Get(i)(Clock);
				inpClock := nil;

				if clock is DerivedClock then (* derived clock *)

					if inputClocks.IndexOf(clock(DerivedClock).refClock) # -1 then
						inpClock := clock(DerivedClock).refClock;
						inputClocks.Remove(clock(DerivedClock).refClock);
					end;
					outClock := clock;

					if inpClock # nil then

						(*
							Patch input clock
						*)
						p := clockSynthesizer.GetPortByAcName("input[" & inpClockInd & "]"); assert(p # nil);
						if inpClock.source is ClockOutputPort then (* internal clock *)

							if inpClock.source(ClockOutputPort).channel # nil then (* clock source port has only one connection *)
								chan := inpClock.source(ClockOutputPort).channel;
								if ~HasChild(chan.outPort.GetCell()) then
									ErrorNotImplemented("non top-level clock connection is unsupported!"); return false;
								end;
							elsif  inpClock.source(ClockOutputPort).channels # nil then (* clock source port has multiple connections, remove all but leave and patch first *)
								chans := inpClock.source(ClockOutputPort).channels;
								assert(chans # nil); assert(channels.Length()>0);
								if ~HasChild(chans.GetChannel(0).outPort.GetCell()) then
									ErrorNotImplemented("non top-level clock connection is unsupported!"); return false;
								end;
								inpClock.source(ClockOutputPort).channels := nil;
								for j := 1 to chans.Length()-1 do
									chan := chans.GetChannel(j);
									assert(channels.IndexOf(chan) # -1);
									channels.Remove(chan);
								end;
								chan := chans.GetChannel(0);
								chans.Clear;
								inpClock.source(ClockOutputPort).channel := chan;
							else
								pp := inpClock.source(ClockOutputPort).delegateOf;
								assert(pp # nil);
								while pp.delegateOf # nil do pp := pp.delegateOf; end;
								chan := pp.channel;
								if ~HasChild(pp.GetCell()) then
									ErrorNotImplemented("non top-level clock connection is unsupported!"); return false;
								end;
							end;
							chan.inPort := p;
							p.channel := chan;
							assert(channels.IndexOf(chan) # -1);
						else (* external clock *)

							assert(inpClock.source is PldIo);
							if inpClock = GetTarget().systemClock.refClock then (* system clock source *)
								DoDelegate(mainClockInput,p);
							else (* an external clock source *)
								ErrorNotImplemented("external clock sources are not supported"); return false;
							end;

						end;

						(*
							Patch output clock
						*)
						p := clockSynthesizer.GetPortByAcName("output[" & i & "]"); assert(p # nil);
						if outClock.source # nil then

							(*!
								remove built-in clock components
							*)
							clockComp := outClock.source(ClockOutputPort).GetCell();
							assert((clockComp.acName^ = SystemClockName) or (clockComp.acName^ = ExternalClockName) or (clockComp.acName^ = ClockGenName));
							children.Remove(clockComp);

							if outClock.source(ClockOutputPort).channel # nil then
								assert(outClock.source(ClockOutputPort).channels = nil);
								chan := outClock.source(ClockOutputPort).channel;
								chan.outPort := p;
								p.channel := chan;
							else (* clock source port has multiple connections *)
								chans := outClock.source(ClockOutputPort).channels;
								if chans # nil then
									assert(chans # nil);
									for j := 0 to chans.Length()-1 do
										chan := chans.GetChannel(j);
										chan.outPort := p;
									end;
								else
									assert(outClock.name^ = SystemClockName);
								end;
								p.channels := chans;
							end;

							if clockComp.acName^ = SystemClockName then (* SystemClock component *)
							 	(*!
							 		distribute the system clock all over the architecture cells by connecting
							 		SystemClock output to all unconnected main clock inputs of all cells
							 	*)
								assert(outClock is DerivedClock);
								assert(mainClockInput # nil);
								assert(mainClockInput.channel = nil);
								assert(mainClockInput.channels = nil);
								assert(mainClockInput(CellnetPort).delegatedTo # nil);
								for j := 0 to mainClockInput(CellnetPort).delegatedTo.Length()-1 do
									DoConnect(p,mainClockInput(CellnetPort).delegatedTo.GetPort(j),0);
								end;
								RemovePort(mainClockInput);
								assert(mainClockInput = nil);
								children.Remove(clockComp);
							end;

						else
							assert(outClock.name^ = SystemClockName);

							(*! patch and remove all delegates of the mainClockInput except the last one which is an input of the clock synthesizer *)
							while mainClockInput(CellnetPort).delegatedTo.Length() > 1 do
								DoConnect(p,mainClockInput(CellnetPort).delegatedTo.GetPort(0),0);
								mainClockInput(CellnetPort).delegatedTo.RemoveFirst;
							end;
						end;

					else
						ErrorUnexpected; return false;
					end;

				else (* internal clock without deriving *)

					assert(clock.source is ClockOutputPort);

					chan := nil;
					chans := nil;

					if clock.source(ClockOutputPort).channel # nil then (* clock source port has only one connection *)
						chan := clock.source(ClockOutputPort).channel;
						clock.source(ClockOutputPort).channel := nil;
					else (* clock source port has multiple connections *)
						assert(clock.source(ClockOutputPort).channels # nil);
						chans := clock.source(ClockOutputPort).channels;
						clock.source(ClockOutputPort).channels := nil;
					end;

					(*
						Patch input clock
					*)
					if inputClocks.IndexOf(clock) # -1 then
						inpClock := clock;
						inputClocks.Remove(clock);
						p := clockSynthesizer.GetPortByAcName("input[" & inpClockInd & "]"); assert(p # nil);
						DoConnect(clock.source(ClockOutputPort),p,0);
					end;

					(*
						Patch output clock
					*)
					p := clockSynthesizer.GetPortByAcName("output[" & i & "]");
					if chan # nil then
						chan.outPort := p;
						p.channel := chan;
					else
						assert(chans # nil);
						for j := 0 to chans.Length()-1 do
							chan := chans.GetChannel(j);
							chan.outPort := p;
						end;
						p.channels := chans;
					end;

				end;

				if inpClock # nil then inc(inpClockInd); end;

			end;

			return ctx.res = 0;

		finally
			ErrorUnexpected; return false;
		end PatchClocks;

		(* Create clock synthesizer, which generates all required architecture clocks

			generateReady: TRUE for generating signal, which indicates that all clock are ready
		*)
		procedure CreateClockSynthesizer(inputClocks, outputClocks: ObjectList; generateReady: boolean; var synthesizer: Cell): boolean;
		var
			i: size;
			clock: Clock;
			str: LongString;
			file: Files.File;
			fw: Files.Writer;
			dep: Dependency;
		begin
			str := acName^ & "Clocks";
			new(synthesizer,str,str);
			str[0] := Strings.LOW(str[0]);
			synthesizer.acInstName := Strings.NewString(str);
			synthesizer.hdlInstName := synthesizer.acInstName;

			(*
				Define component's inputs
			*)
			for i := 0 to inputClocks.Length()-1 do
				clock := inputClocks.Get(i)(Clock);
				assert(~(clock is DerivedClock));
				str := "input" & "[" & i & "]";
				synthesizer.NewClockInput(str,"input" & i); synthesizer.GetPortByAcName(str)(ClockInputPort).clock := clock;
			end;
			(*
				Define component's outputs
			*)
			for i := 0 to outputClocks.Length()-1 do
				clock := outputClocks.Get(i)(Clock);
				assert(clock is DerivedClock);
				str := "output" & "[" & i & "]";
				synthesizer.NewClockOutput(str,"output" & i); synthesizer.GetPortByAcName(str)(ClockOutputPort).clock := clock;
			end;
			if generateReady then
				synthesizer.NewHdlPort("ready","ready",Out,1);
			end;

			Files.JoinPath(ctx(HdlProject).path^,synthesizer.acName^ & ".v",str);
			file := Files.New(str); assert(file # nil);
			Files.Register(file);
			Files.OpenWriter(fw,file,0);

			if ~ctx(HdlProject).GenerateClocks(fw,synthesizer) then
				file.Close;
				return false;
			end;
			fw.Update;
			file.Close;
			
			(*
			new(dep,synthesizer.acName^ & ".v",true,false);
			dep.pathName := Strings.NewString(str);
			synthesizer.AddDependency(dep); *)
			(*dependency does not need to get added to the hdlsources, it's done automatically in ACXilinx. Could be done from here, but only with absolute path*)
			return ctx.res = 0;
		end CreateClockSynthesizer;

		(* traverse for finding an instane of SystemReset component *)
		procedure FindSystemReset(var systemResetComp: Cell): boolean;
		var
			i, n: size;
			c: Cell;
		begin
			n := children.Length();
			for i := 0 to n-1 do

				c := children.GetCell(i);

				if ~(c is Cellnet) then
					if c.acName^ = SystemResetName then
						if systemResetComp # nil then
							Error(ErrAlreadyExists,"SystemReset is defined multiple times");
							return false;
						end;
						systemResetComp := c;
					end;
				else
					if ~c(Cellnet).FindSystemReset(systemResetComp) then return false; end;
				end;
			end;

			return true;
		end FindSystemReset;

		procedure PatchSystemReset(): boolean;
		var
			i, n: size;
			systemResetComp: Cell;
			p, p1: Port;
		begin
			if mainResetInput = nil then return true; end; (* system reset is not used at all *)

			(* first try to find system reset component *)
			if ~FindSystemReset(systemResetComp) then return false; end;
			if systemResetComp # nil then (* user has defined system reset using the built-in SystemReset component *)

				if systemResetComp.GetCellnet() # self then (* move system reset component to the top level *)
					ErrorNotImplemented("system reset can be defined only at the top level of the architecture"); return false;
				end;

				(* connect all delegates of mainResetInput to the output of SystemReset component *)
				p := systemResetComp.outputs.GetPort(0);
				while mainResetInput(CellnetPort).delegatedTo.Length() > 0 do
					p1 := mainResetInput(CellnetPort).delegatedTo.GetPort(0);
					mainResetInput(CellnetPort).delegatedTo.RemoveFirst;
					p1.delegateOf := nil;
					DoConnect(p,p1,0);
				end;

				p := systemResetComp.inputs.GetPort(0);
				if p.channel = nil then (* SystemReset component input is left unconnected *)
					if GetTarget().systemReset = nil then
						ErrorNotImplemented("system reset is not defined");
						return false;
					end;

					DoDelegate(mainResetInput,p);
				else (* SystemReset component input is connected to an internal port *)
					RemovePort(mainResetInput);
					assert(mainResetInput = nil);
				end;

			elsif GetTarget().systemReset # nil then (* system reset is defined in the target specification *)

				systemResetComp := hwLibrary.NewCellByAcNameAndTarget(SystemResetName,GetTarget());
				if systemResetComp = nil then
					Error(ErrNotFound,'could not find HDL component with name "' & SystemResetName);
					return false;
				end;
				systemResetComp.SetContext(ctx);
				systemResetComp.hdlInstName := Strings.NewString("inst_" & SystemResetName);
				systemResetComp.acInstName := systemResetComp.hdlInstName;

				if GetTarget().systemReset.signalPolarity = ActiveHigh then
					i := 1;
				else
					assert(GetTarget().systemReset.signalPolarity = ActiveLow);
					i := 0;
				end;
				assert(systemResetComp.GetPropertyByAcName("InputPolarity").SetValue(NewInteger(i)));
				assert(systemResetComp.GetPropertyByAcName("OutputPolarity").SetValue(NewInteger(0)));
				AddChild(systemResetComp);

				n := mainResetInput(CellnetPort).delegatedTo.Length();
				for i := 0 to n-1 do
					p := mainResetInput(CellnetPort).delegatedTo.GetPort(i);
					p.delegateOf := nil;
					DoConnect(systemResetComp.outputs.GetPort(0),p,0);
				end;
				mainResetInput(CellnetPort).delegatedTo.Clear;

				DoDelegate(mainResetInput,systemResetComp.inputs.GetPort(0));
				DoDelegate(mainClockInput,systemResetComp.mainClockInput);

				new(mainResetInput(CellnetPort).ios,"",1);
				mainResetInput(CellnetPort).ios.Add(GetTarget().systemReset);

			else (* system reset is not defined *)
				ErrorNotImplemented("system reset is not defined");
				return false;
			end;

			return true;
		end PatchSystemReset;

		procedure IdentifyUnusedPorts(): boolean;
		var i, n: size;
		begin

			n := children.Length();
			for i := 0 to n-1 do
				if ~children.GetCell(i).IdentifyUnusedPorts() then
					return false;
				end;
			end;

			if ~IdentifyUnusedPorts^() then return false; end;

			return true;
		end IdentifyUnusedPorts;

		procedure RemoveUnusedCellnetPorts();
		var
			i, j, m: size;
			p: CellnetPort;
			pp: Port;
			c: Cell;
		begin
			if inputs # nil then
				i := 0;
				while i < inputs.Length() do
					p := inputs.GetPort(i)(CellnetPort);
					if p.unused then
						assert(p.delegateOf = nil);
						assert(p.channel = nil);
						assert(p.channels = nil);
						if p.delegatedTo # nil then
							m := p.delegatedTo.Length();
							for j := 0 to m-1 do
								pp := p.delegatedTo.GetPort(j);
								assert(pp.delegateOf = p);
								pp.delegateOf := nil;
							end;
							p.delegatedTo := nil;
						end;
						RemovePort(inputs.GetPort(i));
					else
						inc(i);
					end;
				end;
			end;

			if outputs # nil then
				i := 0;
				while i < outputs.Length() do
					p := outputs.GetPort(i)(CellnetPort);
					if p.unused then
						assert(p.delegateOf = nil);
						assert(p.channel = nil);
						assert(p.channels = nil);
						if p.delegatedTo # nil then
							assert(p.delegatedTo.Length() = 1);
							pp := p.delegatedTo.GetPort(0);
							assert(pp.delegateOf = p);
							pp.delegateOf := nil;
							p.delegatedTo := nil;
						end;
						RemovePort(outputs.GetPort(i));
					else
						inc(i);
					end;
				end;
			end;

			m := children.Length();
			for i := 0 to m-1 do
				c := children.GetCell(i);
				if c is Cellnet then c(Cellnet).RemoveUnusedCellnetPorts; end;
			end;
		end RemoveUnusedCellnetPorts;

		procedure PostAssemblySetup(): boolean;
		var k, n: size;
		begin
			n := children.Length();
			k := 0;
			while (k < n) & children.GetCell(k).PostAssemblySetup() do inc(k); end;
			return k = n;
		finally
			return false;
		end PostAssemblySetup;

		(**
			Traverse all cells in the architecture
		*)
		procedure TraverseCells*(traverseProc: procedure{DELEGATE}(c: Cell; param: any): boolean; includeCellnets: boolean; param: any): boolean;
		var
			k, n: size;
			c: Cell;
		begin
			n := children.Length();
			for k := 0 to n-1 do
				c := children.GetCell(k);
				with c : Cellnet do
					if includeCellnets then
						if ~traverseProc(c,param) then return false; end;
					end;
					if ~c.TraverseCells(traverseProc,includeCellnets,param) then return false; end;
				else
					if ~traverseProc(c,param) then return false; end;
				end;
			end;
			return true;
		finally
			return false;
		end TraverseCells;

	end Cellnet;

	(**
		Programming Logic Device (PLD) part description
	*)
	PldPart* = object(Object)
	var
		(*! Not to be changed by the user! *)
		vendor*: Strings.String; (** device vendor *)
		family*: Strings.String; (** device family *)
		device*: Strings.String; (** device name *)
		package*: Strings.String; (** device package *)
		speedGrade*: Strings.String; (** device speed grade *)

		jtagChainIndex-: size; (** index of the PLD in the JTAG chain *)

		projectFactory*: HdlProjectFactory;
		defaultProjectType*: Strings.String;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : PldPart do
				cpy.vendor := vendor; (*! copy by reference *)
				cpy.family := family; (*! copy by reference *)
				cpy.device := device; (*! copy by reference *)
				cpy.package := package; (*! copy by reference *)
				cpy.speedGrade := speedGrade; (*! copy by reference *)
				cpy.jtagChainIndex := jtagChainIndex;
				cpy.projectFactory := projectFactory; (*! copy by reference *)
				cpy.defaultProjectType := defaultProjectType; (*! copy by reference *)
			end;
		end CopyContent;

		(**
			Setup the location of PLD in the JTAG chain (from 0 to NumChainDevices-1)
		*)
		procedure SetJtagChainIndex*(index: size);
		begin
			jtagChainIndex := index;
		end SetJtagChainIndex;

	end PldPart;

	(**
		IO setup used for specifying IO constraint assignments
	*)
	IoSetup* = object(Object)
	var
		name-: Strings.String; (** IO setup name *)
		ioPorts-: ObjectList; (** list of PldIoList objects *)

		procedure &InitIoSetup*(const setupName: array of char);
		begin
			InitObject;
			name := Strings.NewString(setupName);
		end InitIoSetup;

		procedure GetIoPortByName*(const portName: array of char): PldIoList;
		var
			p: PldIoList;
			i, n: size;
		begin
			if ioPorts # nil then
				i := 0; n := ioPorts.Length();
				while (i < n) & (ioPorts.Get(i)(PldIoList).name^ # portName) do inc(i); end;
				if i < n then
					p := ioPorts.Get(i)(PldIoList);
				else
					p := nil;
				end;
			else
				p := nil;
			end;
			return p;
		end GetIoPortByName;

		(**
			Add an IO specification given its corresponding port name and a PldIo object
		*)
		procedure AddIo*(const portName: array of char; io: PldIo);
		var
			p: PldIoList;
		begin
			assert(io # nil);
			p := GetIoPortByName(portName);
			if p = nil then (* if port does not exist - add it automatically *)
				new(p,portName,4);
				if ioPorts = nil then new(ioPorts,4); end;
				ioPorts.Add(p);
			end;
			assert(p.IndexOf(io) = -1);
			if io is IoPin then
				assert(p.GetIoByLocation(io(IoPin).location^) = nil);
			else
				assert(p.GetIoByLocation(io(IoDiffPair).pinP.location^) = nil);
				assert(p.GetIoByLocation(io(IoDiffPair).pinN.location^) = nil);
			end;
			p.Add(io);
		end AddIo;

		(**
			Get an IO for a given port

			index: index of the IO in the port definition
		*)
		procedure GetIo*(const portName: array of char; index: size): PldIo;
		var
			p: PldIoList;
		begin
			p := GetIoPortByName(portName);
			if p # nil then
				return p.GetIo(index);
			else return nil;
			end;
		end GetIo;

		(**
			Get an IO pin for a given port

			index: index of the pin in the port definition
		*)
		procedure GetPin*(const portName: array of char; index: size): IoPin;
		var io: PldIo;
		begin
			io := GetIo(portName,index);
			if io is IoPin then return io(IoPin); else return nil; end;
		end GetPin;

		(**
			Define a new single ended IO
		*)
		procedure NewPin*(
									const portName: array of char;
									pinDirection: integer;
									const pinLocation: array of char;
									const pinIoStandard: array of char
									);
		var io: IoPin;
		begin
			new(io,pinDirection,pinLocation,pinIoStandard);
			AddIo(portName,io);
		end NewPin;

		(**
			Define a new differential IO
		*)
		procedure NewDiffPair*(
									const portName: array of char;
									pairDirection: integer;
									const pinLocationP, pinLocationN: array of char;
									const pairIoStandard: array of char
									);
		var io: IoDiffPair;
		begin
			new(io,pairDirection,pinLocationP,pinLocationN,pairIoStandard);
			AddIo(portName,io);
		end NewDiffPair;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : IoSetup do
				cpy.name := Strings.NewString(name^);
				if ioPorts # nil then
					cpy.ioPorts := ioPorts.Copy()(ObjectList); ioPorts.parent := cpy;
				end;
			end;
		end CopyContent;

	end IoSetup;

	(**
		Target device description
	*)
	TargetDevice* = object(Object)
	var
		name-: Strings.String;
		pldPart-: PldPart;

		systemClock-: DerivedClock; (**  System clock *)
		systemReset-: PldIo; (** external system reset source *)

		clocks-: ClockList; (** list of clocks available on the target *)

		ioSetups-: ObjectList; (** list of IO setups *)

		spiCfgWidth-: size; (** SPI configuration width *)

		procedure &InitTargetDevice*(const targetName: array of char; targetPldPart: PldPart);
		begin
			InitObject;
			name := Strings.NewString(targetName);
			pldPart := targetPldPart;
			spiCfgWidth := 0;
		end InitTargetDevice;

		(**
			Define a new external clock signal

			sourceInput: source input pin
			frequency: frequency in Hz
			dutyCycle: duty cycle in %; (dutyCycle > 0) & (dutyCycle < 100)
			jitter: clock jitter in % of unit interval
		*)
		procedure NewExternalClock*(
												sourceInput: PldIo;
												frequency: float64;
												dutyCycle: float64;
												jitter: float64
												);
		var clock: Clock;
		begin
			assert(frequency > 0);
			assert((dutyCycle > 0) & (dutyCycle < 100));
			assert((jitter >= 0) & (jitter < 100));
			assert((sourceInput is IoPin) or (sourceInput is IoDiffPair));

			if clocks = nil then new(clocks,4); end;

			new(clock,ExternalClockName & clocks.Length());
			clock.source := sourceInput;
			clock.frequency := frequency;
			clock.dutyCycle := dutyCycle;
			clock.jitter := jitter;

			clocks.Add(clock);
		end NewExternalClock;

		(**
			Setup target system (main) clock
		*)
		procedure SetSystemClock*(
											clock: Clock;
											mulFactor, divFactor: float64
											);
		begin
			assert(~(clock is DerivedClock) & (clock.source is PldIo));
			assert(mulFactor > 0);
			assert(divFactor > 0);
			new(systemClock,SystemClockName,clock,mulFactor,divFactor);
			systemClock.SetDutyCycle(clock.dutyCycle); (*! use the ducty cycle setting from the reference clock *)
		end SetSystemClock;

		(**
			Setup system clock duty cycle, in %
		*)
		procedure SetSystemClockDutyCycle*(dutyCycle: float64);
		begin
			systemClock.SetDutyCycle(dutyCycle);
		end SetSystemClockDutyCycle;

		(**
			Setup the phase shift of the system clock relative to the external reference clock, in degrees (0 to 360)
		*)
		procedure SetSystemClockPhaseShift*(phaseShift: float64);
		begin
			systemClock.SetPhaseShift(phaseShift);
		end SetSystemClockPhaseShift;

		(**
			Setup the system reset signal
		*)
		procedure SetSystemReset*(sourceInput: PldIo; activeHigh: boolean);
		begin
			assert(sourceInput.direction = In);
			if activeHigh then
				sourceInput.signalPolarity := ActiveHigh;
			else
				sourceInput.signalPolarity := ActiveLow;
			end;
			systemReset := sourceInput;
		end SetSystemReset;

		(**
			Add an IO setup specification
		*)
		procedure AddIoSetup*(setup: IoSetup);
		var
			i, n: size;
		begin
			if ioSetups # nil then
				n := ioSetups.Length();
				i := 0;
				while (i < n) & (ioSetups.Get(i)(IoSetup).name^ # setup.name^) do inc(i); end;
				assert(i = n);
			else
				new(ioSetups,4);
			end;

			ioSetups.Add(setup);
		end AddIoSetup;

		(**
			Get an IO setup by its name
		*)
		procedure GetIoSetupByName*(const name: array of char): IoSetup;
		var i, n: size;
		begin
			if ioSetups = nil then return nil; end;
			n := ioSetups.Length();
			while (i < n) & (ioSetups.Get(i)(IoSetup).name^ # name) do inc(i); end;
			if i < n then return ioSetups.Get(i)(IoSetup);
			else return nil;
			end;
		end GetIoSetupByName;

		(**
			Setup SPI configuration width (e.g. for an SPI flash used for configuration of the PLD)

			<= 0 for default setting
		*)
		procedure SetSpiCfgWidth*(width: size);
		begin
			spiCfgWidth := width;
		end SetSpiCfgWidth;

		procedure CopyContent(cpy: Object);
		begin
			CopyContent^(cpy);
			with cpy : TargetDevice do
				cpy.name := name; (*! copy by reference *)
				cpy.pldPart := pldPart.Copy()(PldPart); cpy.pldPart.parent := cpy;
				if systemClock # nil then
					cpy.systemClock := systemClock.Copy()(DerivedClock); cpy.systemClock.parent := cpy;
				end;
				if systemReset # nil then
					cpy.systemReset := systemReset.Copy()(PldIo); cpy.systemReset.parent := cpy;
				end;
				if clocks # nil then
					cpy.clocks := clocks.Copy()(ClockList); cpy.clocks.parent := cpy;
				end;
				if ioSetups # nil then
					cpy.ioSetups := ioSetups.Copy()(ObjectList); cpy.ioSetups.parent := cpy;
				end;

				cpy.spiCfgWidth := spiCfgWidth;
			end;
		end CopyContent;

	end TargetDevice;

	(**
		HDL code generator
	*)
	HdlCodeGenerator* = object(Object)
	var
		w-: Streams.Writer;
		indentLevel-: size;

		(** Get module file extension in the format ".ext" *)
		procedure GetModuleFileExt*(var ext: array of char);
		begin
			halt(100);
		end GetModuleFileExt;

		(**
			Setup the current code writer
		*)
		procedure SetWriter*(writer: Streams.Writer);
		begin
			w := writer;
		end SetWriter;

		(**
			Increment indentation level (has an effect only in case of use of Format)
		*)
		procedure IncIndentLevel*();
		begin
			inc(indentLevel);
		end IncIndentLevel;

		(**
			Decrement indentation level (has an effect only in case of use of Format)
		*)
		procedure DecIndentLevel*();
		begin
			if indentLevel > 0 then dec(indentLevel); end;
		end DecIndentLevel;

		(**
			Fomatted output
		*)
		procedure Format*(const str: array of char);
		var n: size;
		begin
			n := indentLevel;
			while n > 0 do w.Char(Tab); dec(n); end;
			WriteMultilineString(w,str);
		end Format;

		(** block comment *)
		procedure BlockComment*(const comment: array of char);
		begin
			halt(100);
		end BlockComment;

		(** line comment *)
		procedure LineComment*(const comment: array of char);
		begin
			halt(100);
		end LineComment;

		(**
			Generate HDL code for a cellnet
		*)
		procedure GenerateCellnetCode*(c: Cellnet): boolean;
		begin
			halt(100);
		end GenerateCellnetCode;

	end HdlCodeGenerator;

	HdlProjectFactory* = procedure(const projectType: array of char; const architectureName: array of char; targetDev: TargetDevice; codeGenerator: HdlCodeGenerator; const projectPath: array of char; diag: Diagnostics.Diagnostics): HdlProject;

	(**
		HDL project
	*)
	HdlProject* = object(Context)
	var
		architecture-: Cellnet; (** ActiveCells architecture *)
		target-: TargetDevice; (** target device *)
		path-: Strings.String; (** project path *)
		codeGen-: HdlCodeGenerator; (** code generator *)

		hdlSources-: FoxBasic.List; (** list of all distinct HDL source dependencies *)
		hdlSourcesFingerprint-: FingerprintStr; (** fingerprint of the project sources *)
		hdlSourcesUnchanged-: boolean; (** TRUE if HDL sources remained unchanged relative to the last project implementation *)

		constraintsFingerprint*: FingerprintStr; (** fingerprint of the project constraints *)
		constraintsUnchanged*: boolean; (** TRUE if project constraints remained unchanged relative to the last project implementation *)

		fingerprintWriter-: FingerprintWriter;

		engineCount: size; (* number of engines in the project *)
		processorCount: size; (* number of processors in the project *)

		procedure &InitHdlProject*(const architectureName: array of char; targetDev: TargetDevice; codeGenerator: HdlCodeGenerator; const projectPath: array of char; diag: Diagnostics.Diagnostics);
		var
			runtimeContext: RuntimeContext;
		begin
			InitContext(diag);
			target := targetDev;
			codeGen := codeGenerator;
			path := Strings.NewString(projectPath);

			engineCount := 0;
			processorCount := 0;

			new(runtimeContext, self);
			ActiveCellsRuntime.Execute(architectureName, runtimeContext, diag);
			if (runtimeContext.topNet # nil) & (self.res = 0)  then
				architecture := runtimeContext.topNet(Cellnet)
			else
				architecture := nil
			end;

			if architecture = nil then
				Error("",Streams.Invalid,ErrInvalidValue,"a failure to generate architecture");
				return;
			end;

			new(fingerprintWriter,FingerprintAlgo,4096);

			if ~architecture.CheckForUnconnectedPorts() then
				Error("",Streams.Invalid,ErrInvalidValue,"a failure while checking for unconnected ports");
				return;
			end;

			if ~architecture.PatchProcessors() then
				Error("",Streams.Invalid,ErrInvalidValue,"a failure while processing architecture processors");
				return;
			end;

			if ~architecture.PatchProcessorLogicalPorts() then
				Error("",Streams.Invalid,ErrInvalidValue,"a failure to process processor ports");
				return;
			end;

			if ~architecture.PatchMultipleOutputConnections() then
				Error("",Streams.Invalid,ErrInvalidValue,"a failure to process architecture connections");
				return;
			end;

			if ~architecture.PatchMultipleInputDelegations() then
				Error("",Streams.Invalid,ErrInvalidValue,"a failure to process port delegations");
				return;
			end;

			if ~architecture.PatchChannels() then
				Error("",Streams.Invalid,ErrInvalidValue,"a failure to port connections");
				return;
			end;

			if ~architecture.PatchMainClockInputPorts() then
				Error("",Streams.Invalid,ErrInvalidValue,"a failure to process main clock input ports");
				return;
			end;

			if ~architecture.PatchMainResetInputPorts() then
				Error("",Streams.Invalid,ErrInvalidValue,"a failure to process main reset input ports");
				return;
			end;

			if ~architecture.PatchExternalPorts() then
				Error("",Streams.Invalid,ErrInvalidValue,"a failure to process external ports of the architecture");
				return;
			end;

			if ~architecture.PatchSystemReset() then
				Error("",Streams.Invalid,ErrNotFound,"a failure to process main reset");
				return;
			end;

			if ~architecture.PatchClocks() then
				Error("",Streams.Invalid,ErrNotFound,"a failure to process architecture clock signals");
				return;
			end;

			if ~architecture.IdentifyUnusedPorts() then
				Error("",Streams.Invalid,ErrInvalidValue,"a failure to identify unused ports");
				return;
			end;

			architecture.RemoveUnusedCellnetPorts;

			if ~architecture.PostAssemblySetup() then
				Error("",Streams.Invalid,ErrInvalidValue,"a failure to perform architecture post assembly setup");
				return;
			end;

		finally
		end InitHdlProject;

		(*
			Traversive (cellnet-wise) generation of HDL code
		*)
		procedure GenerateHdlCode0(net: Cellnet): boolean;
		var
			file: Files.File;
			fw: Files.Writer;
			ext: array 8 of char;
			str: LongString;
			k, n: size;
			c: Cell;
			dep: Dependency;
		begin
			codeGen.GetModuleFileExt(ext);
			str := net.hdlName^ & ext;

			(*! Do no generate HDL code
				for multiple cellnet instances of same type
				and same parameterization
			*)
			n := hdlSources.Length();
			while (k < n) & (hdlSources.Get(k)(Dependency).name^ # str) do
				inc(k);
			end;

			if k = n then
				PathTools.JoinPath(path^,str,str);
				file := Files.New(str); assert(file # nil);
				Files.Register(file);
				Files.OpenWriter(fw,file,0);
				codeGen.SetWriter(fw);
				assert(~(FlagSkipImplementation in net.flags));
				assert(codeGen.GenerateCellnetCode(net));
				fw.Update;
				file.Close;
				(*add a dependency for the generated top level hdl*)
				new(dep,net.hdlName^ & ext, true, false);
				dep.SetTop();
				assert(PathTools.FileExists(str, str)); (* get the full file name *)
				dep.pathName := Strings.NewString(str);
				net.AddDependency(dep);
				hdlSources.Add(dep); (* required for fingerprinting *)
			end;			

			n := net.children.Length();
			for k := 0 to n-1 do
				c := net.children.GetCell(k);
				if (c is Cellnet) & ~(FlagSkipImplementation in c.flags) then
					if ~GenerateHdlCode0(c(Cellnet)) then return false; end;
				end;
			end;

			return true;
		finally
			file.Close;
			fw.Update;
			return false;
		end GenerateHdlCode0;

		procedure GetCellnetTypes(c: Cell; param: any): boolean;
		var
			cellnets: FoxBasic.List;
			i, n: size;
		begin
			if c is Cellnet then
				cellnets := param(FoxBasic.List);
				n := cellnets.Length();
				i := 0;
				while (i < n) & (cellnets.Get(i)(Cell).acName^ # c.acName^) do
					inc(i);
				end;
				if i = n then
					cellnets.Add(c);
				end;
			end;
			return true;
		end GetCellnetTypes;

		procedure GenerateCellnetHdlNames(c: Cell; param: any): boolean;
		var
			cellnets: FoxBasic.List;
			c0: Cell;
			i, j, m, n: size;
			prop0, prop: Property;
		begin
			cellnets := param(FoxBasic.List);
			c0 := cellnets.Get(0)(Cell);
			if (c # c0) & (c is Cellnet) & (c.acName^ = c0.acName^) then
				n := cellnets.Length();
				for i := 0 to n-1 do
					c0 := cellnets.Get(i)(Cell);
					if c.acInstType^ = c0.acInstType^ then (* same type in AC code *)
						if (c0.props = nil) & (c.props = nil) then (* no properties at all *)
							c.hdlName := c0.hdlName;
							return true;
						elsif c.props.Length() = c0.props.Length() then (* compare properties *)
							m := c0.props.Length();
							j := 0;
							while j < m do
								prop0 := c0.props.GetProperty(j);
								prop := c.props.GetProperty(j);
								if (prop.acName^ # prop0.acName^) or ~prop.value.SameAs(prop0.value) then
									j := m;
								end;
								inc(j);
							end;
							if j = m then (* found a cellnet, which has same HDL code *)
								c.hdlName := c0.hdlName;
								return true;
							end;
						end;
					end;
				end;
				(* generate a separate HDL code for this cellnet *)
				c.hdlName := Strings.NewString(c.acName^ & cellnets.Length());
				cellnets.Add(c);
			end;
			return true;
		end GenerateCellnetHdlNames;

		(**
			Generate HDL code for the project's architecture
		*)
		procedure GenerateHdlCode*(): boolean;
		var
			cellnetTypes: FoxBasic.List;
			cellnetInsts: FoxBasic.List;
			i: size;
		begin
			(* find distinct cellnet types *)
			new(cellnetTypes,8);
			assert(architecture.TraverseCells(GetCellnetTypes,true,cellnetTypes));

			if EnableTrace then trace(cellnetTypes.Length()); end;

			(*! avoid cellnet type instances with same type name but different parameterization *)
			new(cellnetInsts,8);
			for i := 0 to cellnetTypes.Length()-1 do
				(*if EnableTrace then trace(cellnetTypes.Get(i)(Cell).acName^); end;*)
				cellnetInsts.Clear;
				cellnetInsts.Add(cellnetTypes.Get(i));
				cellnetInsts.Get(0)(Cell).hdlName := Strings.NewString(cellnetInsts.Get(0)(Cell).acName^ & "0");
				assert(architecture.TraverseCells(GenerateCellnetHdlNames,true,cellnetInsts));
				if EnableTrace then trace(cellnetInsts.Length()); end;
			end;

			architecture.hdlName := architecture.acName;

			new(hdlSources,32);
			if ~GenerateHdlCode0(architecture) then return false; end;

			if ~architecture.TraverseCells(GatherArchitectureDependencies,true,hdlSources) then
				Error("",Streams.Invalid,ErrInvalidValue,"a failure to process architecture dependencies");
				return false;
			end;

			return true;
		finally
			return false;
		end GenerateHdlCode;

		(**
			Generate code for architecture clock synthesis
		*)
		procedure GenerateClocks*(w: Streams.Writer; synthesizer: Cell): boolean;
		begin
			Error("",Streams.Invalid,ErrNotImplemented,"clock synthesis code generation is not implemented");
			return false;
		end GenerateClocks;

		(**
			Generate project constraints
		*)
		procedure GenerateConstraints*(): boolean;
		begin
			Error("",Streams.Invalid,ErrNotImplemented,"project constraints generation is not implemented");
			return false;
		end GenerateConstraints;

		(**
			Generate HDL project
		*)
		procedure GenerateProject*(): boolean;
		begin
			Error("",Streams.Invalid,ErrNotImplemented,"project generation is not implemented");
			return false;
		end GenerateProject;

		(**
			Generate Software code
		*)
		procedure GenerateCode*(): boolean;
		var
			linker: FoxIntermediateLinker.Linker;
			objectFileFormat: FoxFormats.ObjectFileFormat;
			context: Commands.Context;
			integerType: SyntaxTree.Type;

			procedure PatchPorts(c: Processor; list: PortList);
			var name: FoxIntermediateLinker.SectionName; portNum: size; p: Port; n: size; portArray : PortArray; index: size;
				BasePortAddress: unsigned64;
			
			begin
				if list # nil then
					BasePortAddress:=c.BasePortAddress;
					trace(BasePortAddress);
					portNum := 0; n := list.Length()-1;
					while (portNum <= n) do
						p := list.GetPort(portNum);
						assert(p.acName # nil); (*! must be a processor logical port *)
						if p.inArray # nil then
							portArray := p.inArray;
							if EnableTrace then trace(portArray, portArray.length); end;
							copy(c.acInstType^ & "." & portArray.acName^, name);
							for index := 0 to portArray.length-1 do
								if EnableTrace then trace(name, index); end;
								assert(linker.PatchIntegerValue(name, index, size(BasePortAddress + portNum + index), integerType));
							end;
							(* patch length array for semidynamic arrays *)
							if portArray.lenArray # nil then
								copy(name & ".@len", name);
								for index := 0 to len(portArray.lenArray)-1 do
									if EnableTrace then trace(name, index); end;
									assert(linker.PatchIntegerValue(name, index, portArray.lenArray[index], linker.backend.system.integerType));
								end;
							end;
							inc(portNum, portArray.length);
						else
							copy(c.acInstType^ & "." & p.acName^, name);
							assert(linker.PatchIntegerValue(name, 0, size(BasePortAddress + portNum), integerType));
							if EnableTrace then trace(portNum, p, p.acName^, name); end;
							inc(portNum);
						end;
					end;
				end;
			end PatchPorts;

			procedure PatchProperty(c: Cell; property: Property);
			var value: Value; name: FoxIntermediateLinker.SectionName;
			begin
				value := property.value;
				if EnableTrace then
					trace(value, property.acName);
					if property.acName # nil then trace(property.acName^); end;
				end;
				if (value # nil) & (property.acName # nil) then
					copy(c.acInstType^ & "." & property.acName^, name);
					with
					value: String do
						trace(name, value.val^);
						if ~linker.PatchStringValue(name, value.val^) then
							trace("warning: could not set property ", name);
						end;
					| Integer do
						trace(name, value.val);
						if ~linker.PatchIntegerValue(name, 0, value.val, integerType) then
							trace("warning: could not set property ", name);
						end;
					| Real do
						trace(name, value.val);
						halt(200);
						(*! implement this
						linker.PatchRealValue(name, value.val);
						*)
					| Boolean do
						trace(name, value.val);
						if ~linker.PatchBooleanValue(name, 0, value.val) then
							trace("warning: could not set property ", name);
						end;
					else
						halt(200);
					end;
				end;
			end PatchProperty;

			procedure Generate(c: Processor): boolean;
			var backend: FoxBackend.Backend;
				instructionMemorySize, dataMemorySize: size;
				instructionWidth: size;
				i: size;
				modName, str: Files.FileName;
				
				procedure Log2(s: size): size;
				var l: size;
				begin
					l := 0;
					while (s > 0) do
						inc(l);
						s := s div 2;
					end;								
					return l;
				end Log2;
				
			begin

				(*!
					currently only TRM is supported
				*)
				if EnableTrace then trace(c.acInstType^,c.isa^); end;
				if c.isa^ # "TRM" then return true; end;
				backend := FoxBackend.GetBackendByName(c.isa^); (*! todo: choose correct backend *)
				backend.Initialize(diag, nil, {}, nil, backend.GetSystem());
				integerType := backend.system.addressType;
				objectFileFormat := FoxFormats.GetObjectFileFormat("Generic");
				new(linker, diag, backend);
				linker.objectFile.SetExtension("IroT");
				if ~linker.LinkPrefixed(c.acInstType^) then halt(100); return false end;
				(* patch port values and fill in property values *)
				PatchPorts(c, c.logicalInputs);
				PatchPorts(c, c.logicalOutputs);
				if c.props # nil then
					if EnableTrace then trace(c); end;
					for i := 0 to c.props.Length()-1 do
						PatchProperty(c, c.props.GetProperty(i));
					end;
				end;
				linker.PrearrangeReachableDataSections;
				if c.GetPropertyByAcName("InstructionWidth") # nil then
					instructionWidth := c.GetPropertyByAcName("InstructionWidth").value.ToInteger().val;
					trace(instructionWidth);
				else
					instructionWidth := 18;
					trace(instructionWidth);
				end; 
				linker.SetInstructionWidth(instructionWidth);
				if ~linker.GenerateObjectFile(objectFileFormat, context.out, c.acInstName^) then halt(101); return false end;
				instructionMemorySize := size(c.GetPropertyByAcName("CodeMemorySize").value.ToInteger().val);
				dataMemorySize := size(c.GetPropertyByAcName("DataMemorySize").value.ToInteger().val);
				
				assert(c.GetPropertyByAcName("IAW").SetValue(NewInteger(Log2(instructionMemorySize))));
				assert(	c.GetPropertyByAcName("DAW").SetValue(NewInteger(Log2(dataMemorySize))));
				
				(*! todo: get info about instruction and data memory size *)
				if ~FoxIntermediateLinker.WriteCodeAndDataFiles(c.acInstName^,"code","data",objectFileFormat, instructionMemorySize, dataMemorySize, backend, diag, context.out) then halt(103); return false end;

				(*!
					The commented code below is functional for ARM but
					generates a patched (properties and port addresses) Gof file which
					cannot be loaded by GenericLoader due to an assert failure in
					GenericLoader.Arrangement.Preallocate: "ASSERT(section.type # ObjectFile.InitCode);"
				*)
(*
				if EnableTrace then trace(c.acInstType^,c.isa^); end;
				if (c.isa^ # "TRM") & (c.isa^ # "ARM") then return true; end; (*! currently only TRM is supported  *)
				backend := FoxBackend.GetBackendByName(c.isa^); (*! todo: choose correct backend *)
				trace(backend);
				backend.Initialize(diag, nil, {}, nil, backend.GetSystem());
				integerType := backend.system.addressType;
				objectFileFormat := FoxFormats.GetObjectFileFormat("Generic");
				new(linker, diag, backend);
				if c.isa^ = "TRM" then
					linker.objectFile.SetExtension("IroT");
				else
					assert(c.isa^ = "ARM");
					linker.objectFile.SetExtension("IroA");
				end;
				if c.isa^ = "TRM" then
					if ~linker.LinkPrefixed(c.acInstType^) then return false end;
				else
					Files.SplitExtension(c.acInstType^,modName,str);
					trace(modName);
					if ~linker.LoadModule(modName,false) then return false end;
					linker.MarkReachabilityOfAll(true);
				end;
				(*! todo: patch port values and fill in property values *)
				PatchPorts(c, c.logicalInputs);
				PatchPorts(c, c.logicalOutputs);
				if c.props # nil then
					if EnableTrace then trace(c); end;
					for i := 0 to c.props.Length()-1 do
						PatchProperty(c, c.props.GetProperty(i));
					end;
				end;
				if c.isa^ = "TRM" then
					linker.PrearrangeReachableDataSections;
				end;
				if ~linker.GenerateObjectFile(objectFileFormat, context.out, c.acInstName^) then return false end;
				if c.isa^ = "TRM" then
					instructionMemorySize := c.GetPropertyByAcName("CodeMemorySize").value.ToInteger().val;
					dataMemorySize := c.GetPropertyByAcName("DataMemorySize").value.ToInteger().val;
					(*! todo: get info about instruction and data memory size *)
					if ~FoxIntermediateLinker.WriteCodeAndDataFiles(c.acInstName^,"code","data",objectFileFormat, instructionMemorySize, dataMemorySize, backend, diag, context.out) then return false end;
				end;
*)
				return true;
			end Generate;

			procedure Traverse(c: Cell): boolean;
			var
				k, n: size;
			begin
				if c = nil then return true end;
				with c : Cellnet do
					n := c.children.Length();
					for k := 0 to n-1 do
						if ~Traverse(c.children.GetCell(k)) then return false; end;
					end;
				else
					if c is Processor then
						if ~Generate(c(Processor)) then return false end;
					end;
				end;

				return true;
			finally
				return false;
			end Traverse;

		begin
			context := Commands.GetContext();
			return Traverse(architecture);
		end GenerateCode;

		procedure GatherArchitectureDependencies(c: Cell; param: any): boolean;
		var
			i, j, m, n: size;
			dep: Dependency;
			sources: FoxBasic.List;
		begin
			sources := param(FoxBasic.List);
			if c.dependencies # nil then
				n := c.dependencies.Length();
				for i := 0 to n-1 do
					dep := c.dependencies.GetDependency(i);
					m := sources.Length();
					j := 0;
					while (j < m) & (sources.Get(j)(Dependency).name^ # dep.name^) do
						inc(j);
					end;
					if j = m then
						if dep.pathName = nil then
							dep.resource := hwLibrary.FindResourceByName(dep.name^);
							if dep.resource # nil then
								dep.pathName := dep.resource.pathName;
							else
								Error("",Streams.Invalid,ErrNotFound,'resource not found for dependency "' & dep.name^ & '"');
								return false;
							end;
						end;
						sources.Add(dep);
					end;
				end;
			end;
			return true; (* continue with traversal *)
		end GatherArchitectureDependencies;

		(** Check the project sources for possible changes *)
		procedure CheckForSourcesModifications*(): boolean;
		var
			file: Files.File;
			fr: Files.Reader;
			fileName: Files.FileName;
			fingerprint0: FingerprintStr;
			i, n: size;
			dep: Dependency;
		begin

			assert((hdlSources # nil) & (hdlSources.Length() # 0));

			fingerprintWriter.Reset;

			n := hdlSources.Length();
			for i := 0 to n-1 do
				dep := hdlSources.Get(i)(Dependency);
				(*! compute fingerprint on the file name and on its content *)
				fingerprintWriter.String(dep.name^);
				trace("fingerprinting",dep.name^,dep.pathName^);
				if ~fingerprintWriter.WriteFile(dep.pathName^) then
					return false;
				end;
			end;

			fingerprintWriter.GetFingerprintStr(hdlSourcesFingerprint);

			Files.JoinPath(path^,architecture.acName^ & "-src.fng",fileName);
			file := Files.Old(fileName);
			if file # nil then
				Files.OpenReader(fr,file,0);
				fr.String(fingerprint0);
				file.Close;
				hdlSourcesUnchanged := hdlSourcesFingerprint = fingerprint0;
			else
				hdlSourcesUnchanged := false;
			end;

			if EnableTrace then trace(hdlSourcesFingerprint,fingerprint0,hdlSourcesUnchanged); end;

			return true;

		finally
			if file # nil then file.Close; end;
			return false;
		end CheckForSourcesModifications;

		(** Check the project constraints for possible changes *)
		procedure CheckForConstraintsModifications*(): boolean;
		begin
			Error("",Streams.Invalid,ErrNotImplemented,"checking for project constraints modifications is not implemented");
			return false;
		end CheckForConstraintsModifications;

		(** Generate all project relevant fingerprints to files *)
		procedure GenerateFingerprintFiles*(): boolean;
		var
			file: Files.File;
			fw: Files.Writer;
			fileName: Files.FileName;
			d: integer;
		begin
			(*
				HDL sources fingerprint
			*)
			Files.JoinPath(path^,architecture.acName^ & "-src.fng",fileName);
			file := Files.New(fileName); assert(file # nil);
			Files.Register(file);
			Files.OpenWriter(fw,file,0);

			fw.String(hdlSourcesFingerprint); fw.Update;
			file.Close;

			(*
				project constraints fingerprint
			*)
			Files.JoinPath(path^,architecture.acName^ & "-constr.fng",fileName);
			if constraintsFingerprint # "" then
				file := Files.New(fileName); assert(file # nil);
				Files.Register(file);
				Files.OpenWriter(fw,file,0);

				fw.String(constraintsFingerprint); fw.Update;
				file.Close;
			else
				Files.Delete(fileName,d);
			end;

			return true;
		finally
			if file # nil then file.Close; end;
			return false;
		end GenerateFingerprintFiles;

		(**
			Implement architecture
		*)
		procedure ImplementArchitecture*(): boolean;
		begin
			Error("",Streams.Invalid,ErrNotImplemented,"project implementation is not implemented");
			return false;
		end ImplementArchitecture;

		(*!TODO: define an interface for deployment mechanism specification *)
		procedure DeployArchitecture*(): boolean;
		begin
			Error("",Streams.Invalid,ErrNotImplemented,"project deployment is not implemented");
			return false;
		end DeployArchitecture;

		(**
			Close HDL project
		*)
		procedure CloseProject*();
		begin

		end CloseProject;

	end HdlProject;

	(*
		A shell application
	*)
	Shell* = object(HostOsApps.Application)
	var
		shOutPipe, shInPipe, shErrPipe: Pipes.Pipe;
		shInOut, shErrOut: Streams.Writer;
		shOutIn: Streams.Reader;
		shOut-: Streams.Writer;
		shIn-, shErr-: Streams.Reader;

		procedure &InitShell*(
									const shellAppPathName: array of char;
									outBufSize, inBufSize, errBufSize: size
									);
		begin
			InitApplication(shellAppPathName);

			new(shOutPipe,outBufSize);
			new(shInPipe,inBufSize);
			new(shErrPipe,errBufSize);

			new(shOut,shOutPipe.Send,4096);
			new(shOutIn,shOutPipe.Receive,4096);

			new(shIn,shInPipe.Receive,4096);
			new(shInOut,shInPipe.Send,4096);

			new(shErr,shErrPipe.Receive,4096);
			new(shErrOut,shErrPipe.Send,4096);

			assert(SetStdOut(shInOut,HostOsApps.UpdateAny));
			assert(SetStdIn(shOutIn));
			assert(SetStdErr(shErrOut,HostOsApps.UpdateAny));
		end InitShell;

	end Shell;

	Fingerprint* = array FingerprintSize of char;
	FingerprintStr* = array 2*FingerprintSize+1 of char;

	FingerprintWriter* = object(Streams.Writer)
	const
		FileBufSize = 4096;
	var
		hashAlgo: CryptoHashes.Hash;
		buf: array FileBufSize of char;

		procedure &InitFingerprintWriter*(const hashModName: array of char; bufSize: size);
		begin
			hashAlgo := CryptoHashes.NewHash(hashModName);
			assert(hashAlgo # nil);
			hashAlgo.Initialize;
			InitWriter(Send,bufSize);
		end InitFingerprintWriter;

		procedure Send*(const buf: array of char; offset, length: size; propagate: boolean; var res: integer);
		begin
			hashAlgo.Update(buf,offset,length);
			res := Streams.Ok;
		end Send;

		procedure Reset*();
		begin
			Update;
			hashAlgo.Initialize;
		end Reset;

		procedure GetFingerprint*(var fingerprint: array of char);
		begin
			Update;
			hashAlgo.GetHash(fingerprint,0);
		end GetFingerprint;

		procedure GetFingerprintStr*(var fingerprintStr: array of char);
		var fingerprint: array MaxFingerprintSize of char;
		begin
			Update;
			hashAlgo.GetHash(fingerprint,0);
			CryptoUtils.Bin2Hex(fingerprint,0,fingerprintStr,0,hashAlgo.size);
			fingerprintStr[2*hashAlgo.size] := 0X;
		end GetFingerprintStr;

		procedure WriteFile*(const fileName: array of char): boolean;
		var
			file: Files.File;
			fr: Files.Reader;
			m, n: size;
		begin
			file := Files.Old(fileName);
			if file = nil then return false; end;

			Files.OpenReader(fr,file,0);
			n := fr.Available();
			while (fr.res = 0) & (n > 0) do
				if n >= len(buf) then
					fr.Bytes(buf,0,len(buf),m); assert(m = len(buf));
				else
					fr.Bytes(buf,0,n,m); assert(m = n);
				end;

				Bytes(buf,0,m);

				n := fr.Available();
			end;

			return (fr.res = 0) & (res = 0);
		end WriteFile;

	end FingerprintWriter;

	ResourceItem* = pointer to record
		pathName-: Strings.String;
		fingerprint: Fingerprint;
		nameOffset: size;
	end;

	(**
		ActiveCells hardware library
	*)
	HardwareLibrary* = object
	var
		resourceItems: FoxBasic.List;
		resourceCount: size;

		components: CellList;
		targets: ObjectList;

		fingerprintWriter: FingerprintWriter;

		lock: Locks.RWLock;

		procedure &InitHardwareLibrary();
		begin
			new(resourceItems,2048);
			resourceCount := 0;

			new(components,1024);
			new(targets,8);

			new(fingerprintWriter,FingerprintAlgo,4096);

			new(lock);
		end InitHardwareLibrary;

		(*
			Split a path name into the path and name

			pathName: full path name
			nameOffset: offset pointing to the beginning of the name
		 *)
		procedure SplitPath(const pathName: array of char; var nameOffset: size);
		var i: size;
		begin
			i := 0; nameOffset := -1;
			while pathName[i] # 0X do
				if (pathName[i] = Files.PathDelimiter) or (pathName[i] = ":") then nameOffset := i; end;
				inc(i);
			end;
			inc(nameOffset);
		end SplitPath;

		(* returns TRUE if two names are equal *)
		procedure NameEqual(const pathName1: array of char; nameOffset1: size; const pathName2: array of char; nameOffset2: size): boolean;
		var n: size;
		begin
			n := Strings.Length(pathName1) - nameOffset1;
			if Strings.Length(pathName2) - nameOffset2 # n then
				return false;
			end;
			while (n > 0) & (pathName1[nameOffset1] = pathName2[nameOffset2]) do
				inc(nameOffset1);
				inc(nameOffset2);
				dec(n);
			end;
			return n = 0;
		end NameEqual;

		procedure ComputeFingerprint(const pathName: array of char; nameOffset: size; var fingerprint: Fingerprint);
		begin{EXCLUSIVE}(*! protection for shared fingerprint writer *)
			fingerprintWriter.Reset;
			fingerprintWriter.Bytes(pathName,nameOffset,Strings.Length(pathName)-nameOffset);
			fingerprintWriter.GetFingerprint(fingerprint);
		end ComputeFingerprint;

		procedure FindItemByFingerprint(items: FoxBasic.List; count: size; const fingerprint: Fingerprint): size;
		var
			i: size;
			item: ResourceItem;
		begin
			i := 0;
			while i < count do
				item := items.Get(i)(ResourceItem);
				if FingerprintEqual(item.fingerprint,fingerprint) then return i; end;
				inc(i);
			end;
			return -1;
		end FindItemByFingerprint;

		procedure AddResource0(const fullPathName: array of char; ctx: Context): boolean;
		var
			nameOffset, j: size;
			fingerprint: Fingerprint;
			item: ResourceItem;
			b: boolean;
		begin
			SplitPath(fullPathName,nameOffset);
			ComputeFingerprint(fullPathName,nameOffset,fingerprint);

			j := FindItemByFingerprint(resourceItems,resourceCount,fingerprint);
			if j = -1 then (* a new resource item to add *)
				new(item);
				item.pathName := Strings.NewString(fullPathName);
				item.nameOffset := nameOffset;
				item.fingerprint := fingerprint;
				resourceItems.Add(item);
				inc(resourceCount);
				b := true;
				ctx.Information("",Streams.Invalid,Streams.Invalid,'registered resource "' & fullPathName & '"');
			else
				item := resourceItems.Get(j)(ResourceItem);
				(*assert(NameEqual(item.pathName^,item.nameOffset,fullPathName,nameOffset));
				ctx.Error("",Streams.Invalid,ErrAlreadyExists,'file "' & fullPathName & '" refers to an already registered resource name');*)
				item.pathName := Strings.NewString(fullPathName);
				item.nameOffset := nameOffset;
				b := true;
				ctx.Information("",Streams.Invalid,Streams.Invalid,'reregister resource "' & fullPathName & '"');
			end;

		finally
			return b;
		end AddResource0;

		(**
			Add a resource used as a dependency of a component

			pathName: resource path name
			ctx: reference to the context for error reporting; has to be locked outside

			Returns TRUE in case of success
		*)
		procedure AddResource*(const pathName: array of char; ctx: Context): boolean;
		var
			fullPathName: Files.FileName;
			b: boolean;
		begin
			if PathTools.FileExists(pathName,fullPathName) then (* check that the file exists at all *)
				lock.AcquireWrite;
				b := AddResource0(fullPathName,ctx);
				lock.ReleaseWrite;
			else
				ctx.Error("",Streams.Invalid,ErrNotFound,'file "' & pathName & '" could not be found');
			end;
		finally
			return b;
		end AddResource;

		(**
			Returns TRUE if resource with given name is present in the resource list
		*)
		procedure HasResource*(const name: array of char): boolean;
		var
			resource: ResourceItem;
			file: Files.File;
			b: boolean;
		begin
			lock.AcquireRead;
			resource := FindResourceByName0(name);
			if resource # nil then
				file := Files.Old(resource.pathName^);
				if file # nil then b := true; file.Close; end;
			end;
		finally
			lock.ReleaseRead;
			return b;
		end HasResource;

		(* Find a resource by its name *)
		procedure FindResourceByName0(const name: array of char): ResourceItem;
		var
			fingerprint: Fingerprint;
			i: size;
			item: ResourceItem;
		begin
			i := -1;
			ComputeFingerprint(name,0,fingerprint);
			i := FindItemByFingerprint(resourceItems,resourceCount,fingerprint);
			if i >= 0 then item := resourceItems.Get(i)(ResourceItem); end;
		finally
			return item;
		end FindResourceByName0;

		(* Find a resource by its name *)
		procedure FindResourceByName(const name: array of char): ResourceItem;
		begin
			return FindResourceByName0(name);
		end FindResourceByName;

		procedure ScanPathTraversalProc(const pathName: array of char; param: any): boolean;
		var
			name: Files.FileName;
			ext: array 32 of char;
			b: boolean;
		begin
			Files.SplitExtension(pathName,name,ext);
			b := AddResource0(pathName,param(Context));
		finally
			return b;
		end ScanPathTraversalProc;

		(**
			Scan a path for available resources and executables

			path: path where to perform scanning for resources and executables
			scanRecursively: TRUE for scanning recursively
			ctx: reference to the context for error reporting; has to be locked outside

			Returns TRUE in case of success
		*)
		procedure ScanPath*(const path: array of char; scanRecursively: boolean; ctx: Context): boolean;
		var
			fullPath: Files.FileName;
			flags: set;
			b: boolean;
		begin
			lock.AcquireWrite;
			if FSTools.Exists(path,fullPath,flags) & (Files.Directory in flags) then
				flags := {PathTools.TraverseFiles};
				if scanRecursively then incl(flags,PathTools.TraverseRecursive); end;
				b := PathTools.TraversePath(fullPath,"*.*",ScanPathTraversalProc,flags,ctx);
			else
				ctx.Error("",Streams.Invalid,ErrNotFound,'directory "'& path & '" could not be found');
			end;
		finally
			lock.ReleaseWrite;
			return b;
		end ScanPath;

		(**
			Clear the library
		*)
		procedure Clear*();
		begin
			lock.AcquireWrite;
			components.Clear;
			resourceCount := 0;
		finally
			lock.ReleaseWrite;
		end Clear;

		(**
			Register a component specification
		*)
		procedure AddComponent*(c: Cell);
		begin
			lock.AcquireWrite;
			components.Add(c);
		finally
			lock.ReleaseWrite;
		end AddComponent;

		(**
			Returns TRUE if component is present in the component list
		*)
		procedure HasComponent*(c: Cell): boolean;
		var
			i, n: size;
			b: boolean;
		begin
			lock.AcquireRead;
			i := 0; n := components.Length();
			while (i < n) & (components.Get(i) # c) do
				inc(i);
			end;
			b := i < n;
		finally
			lock.ReleaseRead;
			return b;
		end HasComponent;

		(**
			Register a target device specification
		*)
		procedure AddTarget*(target: TargetDevice);
		begin
			lock.AcquireWrite;
			targets.Add(target);
		finally
			lock.ReleaseWrite;
		end AddTarget;

		(**
			Returns TRUE if a target is present in the component list
		*)
		procedure HasTarget*(t: TargetDevice): boolean;
		var
			i, n: size;
			b: boolean;
		begin
			lock.AcquireRead;
			i := 0; n := targets.Length();
			while (i < n) & (targets.Get(i) # t) do
				inc(i);
			end;
			b := i < n;
		finally
			lock.ReleaseRead;
			return b;
		end HasTarget;

		(**
			Get a target by its name
		*)
		procedure GetTargetByName*(const name: array of char): TargetDevice;
		var
			t: TargetDevice;
			i, n: size;
		begin
			lock.AcquireRead;
			i := 0; n := targets.Length();
			while (i < n) & (targets.Get(i)(TargetDevice).name^ # name) do inc(i); end;
			if i < n then
				t := targets.Get(i)(TargetDevice);
			else t := nil;
			end;
		finally
			lock.ReleaseRead;
			return t;
		end GetTargetByName;

		(*
			Get a cell by its ActiveCells type name and supported target
		*)
		procedure GetCellByAcNameAndTarget(const name: array of char; target: TargetDevice): Cell;
		var
			c: Cell;
			i, n: size;
		begin
			lock.AcquireRead;
			i := 0; n := components.Length();
			while (i < n) & (components.GetCell(i).acName^ # name) do inc(i); end;
			if i < n then c := components.GetCell(i); else c := nil; end;
		finally
			lock.ReleaseRead;
			return c;
		end GetCellByAcNameAndTarget;

		(*
			Get a cell by its HDL type name and supported target
		*)
		procedure GetCellByHdlNameAndTarget(const name: array of char; target: TargetDevice): Cell;
		var
			c: Cell;
			i, n: size;
		begin
			lock.AcquireRead;
			i := 0; n := components.Length();
			while (i < n) & (components.GetCell(i).hdlName^ # name) do inc(i); end;
			if i < n then c := components.GetCell(i); else c := nil; end;
		finally
			lock.ReleaseRead;
			return c;
		end GetCellByHdlNameAndTarget;

		(**
			Create a new instance of a cell specified by its name in ActiveCells
		*)
		procedure NewCellByAcNameAndTarget*(const name: array of char; target: TargetDevice): Cell;
		var c: Cell;
		begin
			c := GetCellByAcNameAndTarget(name,target);
			if c # nil then c := c.CopyCell(); end;
		finally
			return c;
		end NewCellByAcNameAndTarget;

		(**
			Create a new instance of a cell specified by its name in HDL
		*)
		procedure NewCellByHdlName*(const name: array of char; target: TargetDevice): Cell;
		var c: Cell;
		begin
			c := GetCellByHdlNameAndTarget(name,target);
			if c # nil then c := c.CopyCell(); end;
		finally
			return c;
		end NewCellByHdlName;

	end HardwareLibrary;

	RuntimeContext = object (ActiveCellsRuntime.Context)
	var
		res: integer;
		ctx: Context;

		procedure & Init(cx: Context);
		begin
			res := 0;
			ctx := cx;
		end Init;

		procedure Allocate*(scope: any; var c: any; t: Modules.TypeDesc; const name: array of char; isCellNet, isEngine: boolean);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoAllocate(system.val(Cell, scope), system.val(Cell, c), t, name, isCellNet, isEngine, self);
		end Allocate;

		procedure AddPort*(c: any; var p: any; const name: array of char; inout: set; width: WidthType);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoAddPort(c(Cell), p, name, inout, width, nil);
		end AddPort;

		procedure AddPortArray*(c: any; var ports: any; const name: array of char; inout: set; width: WidthType; const lens: array of LengthType);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoAddPortArray(c(Cell), ports, name, inout, width, lens);
		end AddPortArray;

		procedure AddStaticPortArray*(c: any; var ports: array of any; const name: array of char; inout: set; width: WidthType);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoAddStaticPortArray(c(Cell), ports, name, inout, width);
		end AddStaticPortArray;

		procedure AddPortIntegerProperty*(p: any; const name: array of char; value: signed32);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoAddPortIntegerProperty(p(Port), name, value);
		end AddPortIntegerProperty;

		procedure AddFlagProperty*(c: any; const name: array of char);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoAddFlagProperty(c(Cell), name);
		end AddFlagProperty;
		
		procedure AddBooleanProperty*(c: any; const name: array of char; value: boolean);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoAddBooleanProperty(c(Cell),name,value);
		end AddBooleanProperty;

		procedure AddStringProperty*(c: any; const name: array of char; const value: array of char);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoAddStringProperty(c(Cell), name, value);
		end AddStringProperty;

		procedure AddIntegerProperty*(c: any; const name: array of char; value: signed32);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoAddIntegerProperty(c(Cell),name,value);
		end AddIntegerProperty;

		procedure AddRealProperty*(c: any; const name: array of char; value: float64);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoAddRealProperty(c(Cell),name,value);
		end AddRealProperty;

		procedure AddSetProperty*(c: any; const name: array of char; value: set);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoAddSetProperty(c(Cell),name,value);
		end AddSetProperty;

		procedure FinishedProperties*(var c: any);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoFinishedProperties(c(Cell));
		end FinishedProperties;

		procedure Connect*(outPort, inPort: any; depth: DepthType);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoConnect(outPort(Port), inPort(Port), depth);
		end Connect;

		procedure Delegate*(netPort: any; cellPort: any);
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoDelegate(netPort(Port), cellPort(Port));
		end Delegate;

		procedure Start*(c: any; proc: procedure{DELEGATE});
		begin
			if ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
			DoStart(c(Cell), proc);
		end Start;

	end RuntimeContext;

var
	globalContext-: Context; (** global context *)
	hwLibrary-: HardwareLibrary; (* ActiveCells hardware library *)

	(** Allocation of a cell: required by the compiler *)
	procedure DoAllocate*(scope: Cell; var c: Cell; typeInfo: Modules.TypeDesc; const name: array of char; isCellnet: boolean; isEngine: boolean; runtimeContext: RuntimeContext);
	var
		processor: Processor;
		net: Cellnet;
		prev, parent: Cell;
		str,ostr: LongString;
		cPrev: Cell;
		ctx: Context;
		id: signed32;
		int: Integer;
		property: Property;
	begin

		ctx := runtimeContext.ctx;
		net := nil;

		parent := scope;
		while parent # nil do
			prev := parent;
			parent := parent.GetCellnet();
		end;
		parent := prev;

		if parent # nil then
			copy(parent.acInstType^, ostr);
		else
			copy(name, ostr);
		end;

		GetDottedStringEnding(typeInfo.name,str);

		if c # nil then
			cPrev := c;
		end;

		if isCellnet then
			new(net,str);
			if scope # nil then
				net.level := scope(Cellnet).level+1;
			end;
			c := net;
		elsif isEngine then
			(*! limit the number of engine cells in a demo version of ActiveCells *)
			with ctx : HdlProject do
				if (EngineCountLimit > 0) & (ctx.engineCount >= EngineCountLimit) then
					ctx.Error("",Streams.Invalid,ErrInvalidValue,"the number of engine cells exceeds the limit!");
					return;
				end;
				inc(ctx.engineCount);
			else
			end;
			c := hwLibrary.NewCellByAcNameAndTarget(str,ctx(HdlProject).target);
			if c = nil then
				scope.Error(ErrNotFound,'could not find HDL component with name "' & str & '"');
				return;
			end;
			assert(c is Engine);
		else
			(*! limit the number of processor cells in a demo version of ActiveCells *)
			with ctx : HdlProject do
				if (ProcessorCountLimit > 0) & (ctx.processorCount >= ProcessorCountLimit) then
					ctx.Error("",Streams.Invalid,ErrInvalidValue,"the number of processor cells exceeds the limit!");
					return;
				end;
				inc(ctx.processorCount);
			else
			end;

			(*!
				we do not yet know what kind of processor it is;
				therefore, create a temporary cell and wait until
				we get enough information about the processor type
				(latest at first "FinishedProperties" call)
			*)
			new(processor,str,"","");
			processor.acCellInd := ctx.cellCounter;
			new(int,ctx(HdlProject).processorCount);
			new(property,"Inst","",int,nil);
			processor.AddProperty(property);
			c := processor;
		end;

		ostr := ostr & "." & c.acName^;
		c.acInstType := Strings.NewString(typeInfo.mod.name & "."  & typeInfo.name);

		if (scope # nil) then
			id := -1;
			repeat
				inc(id);
				str := ostr (* & "_" & typeInfo.mod.name & "." & typeInfo.name & "_" *) & id;
			until scope(Cellnet).FindChildByAcInstName(str,true) = nil;
		else
			str := ostr & (* "_" & typeInfo.mod.name & "." & typeInfo.name;*) id;
		end;

		if EnableTrace then trace(str, scope); end;
		(*
		if (scope # nil) & (cPrev # nil) then (* the case of an array of cells, c is the previous array element *)
			c.arrayInd := cPrev.arrayInd + 1;
			str := name & "_" & c.arrayInd;
			c.acInstName := Strings.NewString(str);

			assert(scope(Cellnet).FindChildByAcInstName(c.acInstName^,true) = nil);
		else
			c.acInstName := Strings.NewString(name);
		end;
		*)
		c.acInstName := Strings.NewString(str);
		c.instId := id;

		GetHdlInstanceName(c,str); c.hdlInstName := Strings.NewString(str);
		if scope # nil then
			scope(Cellnet).AddChild(c);
		end;

		c.SetContext(ctx);

		inc(ctx.cellCounter);
	end DoAllocate;

	procedure DoFinishedProperties*(var c: Cell);
	var
		str: LongString;
		prop, prop1: Property;
		props: PropertyList;
		processor: Cell;
		k, n: size;
	begin

		if c is Processor then

			prop := c.GetPropertyByAcName("Processor");
			if prop # nil then
				assert(prop.value is String);
				copy(prop.value(String).val^,str);
			else
				copy(DefaultProcessorType,str);
			end;
			processor := hwLibrary.NewCellByAcNameAndTarget(str,c.ctx(HdlProject).target);
			if processor = nil then
				Strings.Concat("could not find HDL processor component with name ",prop.value(String).val^,str);
				c.Error(ErrInvalidValue,str);
				return;
			end;



			(*
				replace Processor placeholder by a float32 processor instance
			*)
			processor.SetContext(c.ctx);
			processor.acInstType := c.acInstType;
			processor.acInstName := c.acInstName;
			processor.hdlInstName := c.hdlInstName;

			c.GetCellnet().ReplaceChild(c,processor);
			assert(processor.GetCellnet() = c.GetCellnet());
			props := c.props;
			(*c.props := nil;
			processor.CopyContent(c);*)
			c := processor;

			(* check properties *)
			if props # nil then
				n := props.Length();
				for k := 0 to n-1 do
					prop := props.GetProperty(k);
					if prop.acName^ # "Processor" then

						if c.props # nil then
							prop1 := c.props.GetPropertyByAcName(prop.acName^);
						else
							prop1 := nil;
						end;
						if prop1 # nil then
							if ~prop1.SetValue(prop.value) then
								return;
							end;
						else
							(*! this warning is obsolete: it can happen quite often that properties are unkown in advance
								only not for engines (not addressed here)
							*)
							Strings.Concat('cell property "',prop.acName^,str);
							Strings.Concat(str,'" is not defined in the HDL specification',str);
							c.Warning(str); (*c.Error(ErrNotDefined,str);
							return;*)
							c.AddProperty(prop);
						end;
					end;
				end;
			end;

		end;

		if c.PostParamSetup() then end;
	end DoFinishedProperties;

	procedure AddProcessorPort(c: Processor; var p: Port; const name: array of char; inout: set; width: WidthType; inPortArray: PortArray);
	var logPort: LogicalPort;
	begin

		if c.clockInputs # nil then p := c.clockInputs.GetPortByAcName(name); end;
		if p # nil then return; end;
		if c.clockOutputs # nil then p := c.clockOutputs.GetPortByAcName(name); end;
		if p # nil then return; end;

		if c.inputs # nil then p := c.inputs.GetPortByAcName(name) else p := nil end;
		if (p # nil) & ~(FlagCommPort in p.flags) then return; end;
		if c.outputs # nil then p := c.outputs.GetPortByAcName(name) else p := nil end;
		if (p # nil) & ~(FlagCommPort in p.flags) then return; end;

		if inout = {1} then (* input *)
			new(logPort,name,name,In,width);
			logPort.InArray(inPortArray);
		elsif inout = {0} then (* output *)
			new(logPort,name,name,Out,width);
			logPort.InArray(inPortArray);
		else halt(100);
		end;
		logPort.acPortInd := c.ctx.portCounter;

		c.AddLogicalPort(logPort);
		p := logPort;
	end AddProcessorPort;

	(** Add a port: required by the compiler *)
	procedure DoAddPort*(c: Cell; var res: any; const name: array of char; inout: set; width: WidthType; inPortArray: PortArray);
	var
		str: LongString;
		pnet: CellnetPort;
		p: Port;
	begin

		assert(res = nil);
		GetDottedStringEnding(name,str);

		if ~(c is Cellnet) & (str = MainClockInputName) then
			if c.mainClockInput = nil then
				Strings.Concat('main clock input port ("',MainClockInputName,str);
				Strings.Concat(str,'") is not defined in HDL cell specification',str);
				c.Error(ErrInvalidValue,str);
				return;
			elsif inout # {1} then
				Strings.Concat('main clock port ("',MainClockInputName,str);
				Strings.Concat(str,'") must have input direction',str);
				c.Error(ErrInvalidValue,str);
				return;
			end;
			p := c.mainClockInput;

		elsif ~(c is Cellnet) & (str = MainResetInputName) then
			if c.mainResetInput = nil then
				Strings.Concat('main reset input port ("',MainResetInputName,str);
				Strings.Concat(str,'") is not defined in HDL cell specification',str);
				c.Error(ErrInvalidValue,str);
				return;
			elsif inout # {1} then
				Strings.Concat('main reset port ("',MainResetInputName,str);
				Strings.Concat(str,'") must have input direction',str);
				c.Error(ErrInvalidValue,str);
				return;
			end;
			p := c.mainResetInput;
			res := p;
		elsif c is Engine then

			p := c.GetPortByAcName(str);
			res := p;
			if p # nil then
				if ((p.direction = Out) & (inout # {0})) or ((p.direction = In) & (inout # {1}))(* or ((p.direction = Inout) & (inout # {0,1}))*) then
					Strings.Concat('direction of port "',str,str);
					Strings.Concat(str,'" does not match with the corresponding port direction in HDL cell specification',str);
					c.Error(ErrInvalidValue,str);
					return;
				end;
			else
				Strings.Concat('port "',str,str);
				Strings.Concat(str,'" is not defined in HDL cell specification',str);
				c.Error(ErrInvalidValue,str);
				return;
			end;

		elsif c is Processor then
			AddProcessorPort(c(Processor),p,str,inout,width, inPortArray);
			res := p;
		else
			assert(c is Cellnet);
			if inout = {0} then new(pnet,str,Out,width);
			elsif inout = {1} then new(pnet,str,In,width);
			else halt(100);
			end;
			c.AddPort(pnet);
			p := pnet;
			res := p;
		end;

		assert(p.acName # nil);
		p.SetContext(c.ctx);
		if EnableTrace then trace(p, p.acName^, name, str); end;
		res := p;

		inc(c.ctx.portCounter);
	end DoAddPort;

	(** Add a port array: required by the compiler *)
	procedure DoAddPortArray*(c: Cell; var ports: any; const name: array of char; inout: set; width: WidthType; const lens: array of LengthType);
	type
		Ports1d = array of any;
		Ports2d = array of Ports1d;
		Ports3d = array of Ports2d;
	var
		p1d: pointer to Ports1d;
		p2d: pointer to Ports2d;
		p3d: pointer to Ports3d;
		i, i0, i1, i2: size;
		lenArray: pointer to array of size;
		portArray: PortArray;
		length: size;
	begin
		new(lenArray, len(lens));
		length := 1;
		for i := 0 to len(lens)-1 do
			lenArray[i] := lens[i];
			length := length * lens[i];
		end;
		new(portArray, name, length, lenArray);
		(*
			There is a slot in the respective cell that can hold a pointer to an n-dimensional array of ports.
			This slot is used for the pointer but is not directly accessible any more by the runtime.
			So, if information about the array of ports is further required, some metadata should be kept
			here. The following is the absolute minimal.
		*)
		case len(lens,0) of
			|1:
				new(p1d,lens[0]);
				for i0 := 0 to lens[0]-1 do
					DoAddPort(c,p1d[i0],name & "[" & (i0) & "]",inout,width,portArray);
				end;
				ports := p1d;
			|2:
				new(p2d,lens[0],lens[1]);
				for i0 := 0 to lens[0]-1 do
					for i1 := 0 to lens[1]-1 do
						DoAddPort(c,p2d[i0,i1],name & "[" & (i0) & "," & (i1) & "]",inout,width,portArray);
					end;
				end;
				ports := p2d;
			|3:
				new(p3d,lens[0],lens[1],lens[2]);
				for i0 := 0 to lens[0]-1 do
					for i1 := 0 to lens[1]-1 do
						for i2 := 0 to lens[2]-1 do
							DoAddPort(c,p3d[i0,i1,i2],name & "[" & (i0) & "," & (i1) & "," & (i2) & "]",inout,width,portArray);
						end;
					end;
				end;
				ports := p3d;
		else
			halt(777);
		end;
	end DoAddPortArray;


	(** Add a port array: required by the compiler *)
	procedure DoAddStaticPortArray*(c: Cell; var ports: array of any; const name: array of char; inout: set; width: WidthType);
	var i, n: size; portArray: PortArray;
	begin

		(*
			There is a slot in the respective cell that can hold a pointer to an n-dimensional array of ports.
			This slot is used for the pointer but is not directly accessible any more by the runtime.
			So, if information about the array of ports is further required, some metadata should be kept
			here. The following is the absolute minimal.
		*)
		n := len(ports);
		new(portArray, name, n, nil);
		for i := 0 to n-1 do
			DoAddPort(c, ports[i] ,name & "[" & (i) & "]",inout,width,portArray);
		end;

	end DoAddStaticPortArray;

	(** Add a flag property: required by the compiler *)
	procedure DoAddFlagProperty*(c: Cell; const name: array of char);
	var
		prop: Property;
		str: LongString;
		bool: Boolean;
	begin

		if c is Engine then
			if name = "Engine" then return; end;
			prop := c.GetPropertyByAcName(name);
			if prop = nil then
				c.Error(ErrNotDefined,'property "' & name & '" is not defined in HDL cell specification');
				return;
			elsif ~(prop.value is Boolean) then
				prop.value.GetTypeName(str);
				c.Error(ErrInvalidValue,'property "' & name & '" is specified as "Boolean" while in the component specification it has type "' & str & '"');
				return;
			else
				new(bool,true);
				if ~prop.SetValue(bool) then return; end;
			end;
		else (* same for both Processor and Cellnet *)
			new(bool,true);
			new(prop,name,"",bool,nil);
			if c is Cellnet then prop.hdlName := prop.acName; end; (*! since at this time moment processor type is unknown - leave HDL property name NIL to account for properties defined only in AC code *)
			c.AddProperty(prop);
		end;
	end DoAddFlagProperty;
	
	(** Add an integer property: required by the compiler *)
	procedure DoAddBooleanProperty*(c: Cell; const name: array of char; value: boolean);
	var
		prop: Property;
		str: LongString;
		bool: Boolean;
	begin

		if c is Engine then
			prop := c.GetPropertyByAcName(name);
			if prop = nil then
				c.Error(ErrNotDefined,'property "' & name & '" is not defined in HDL cell specification');
				return;
			elsif ~(prop.value is Boolean) then
				prop.value.GetTypeName(str);
				c.Error(ErrInvalidValue,'property "' & name & '" is specified as "Integer" while in the component specification it has type "' & str & '"');
				return;
			else
				new(bool,value);
				if ~prop.SetValue(bool) then return; end;
			end;
		else
			(* same for both Processor and Cellnet *)
			new(bool,value);
			new(prop,name,"",bool,nil);
			if c is Cellnet then prop.hdlName := prop.acName; end; (*! since at this time moment processor type is unknown - leave HDL property name NIL to account for properties defined only in AC code *)
			if EnableTrace then trace(c, name, value,prop, bool); end;
			c.AddProperty(prop);
		end;
	end DoAddBooleanProperty;

	(** Add a string property: required by the compiler *)
	procedure DoAddStringProperty*(c: Cell; const name: array of char; const value: array of char);
	var
		prop: Property;
		str: LongString;
		s: String;
		bin: BinaryValue;
	begin

		if c is Engine then
			prop := c.GetPropertyByAcName(name);
			if prop = nil then
				c.Error(ErrNotDefined,'property "' & name & '" is not defined in HDL cell specification');
				return;
			elsif prop.value is String then
				new(s,value);
				if ~prop.SetValue(s) then return; end;
			elsif prop.value is BinaryValue then
				new(bin,value);
				if bin.val # nil then
					if ~prop.SetValue(bin) then return; end;
				else
					c.Error(ErrInvalidValue,'binary property "' & name & '" has invalid value');
					return;
				end;
			else
				prop.value.GetTypeName(str);
				c.Error(ErrInvalidValue,'property "' & name & '" is specified as "String" while in the component specification it has type "' & str & '"');
				return;
			end;
		else (* same for both Processor and Cellnet *)
			new(s,value);
			new(prop,name,"",s,nil);
			if c is Cellnet then prop.hdlName := prop.acName; end; (*! since at this time moment processor type is unknown - leave HDL property name NIL to account for properties defined only in AC code *)
			c.AddProperty(prop);
		end;

	end DoAddStringProperty;

	(** Add an integer property: required by the compiler *)
	procedure DoAddIntegerProperty*(c: Cell; const name: array of char; value: signed32);
	var
		prop: Property;
		str: LongString;
		int: Integer;
	begin

		if c is Engine then
			prop := c.GetPropertyByAcName(name);
			if prop = nil then
				c.Error(ErrNotDefined,'property "' & name & '" is not defined in HDL cell specification');
				return;
			elsif ~(prop.value is Integer) then
				prop.value.GetTypeName(str);
				c.Error(ErrInvalidValue,'property "' & name & '" is specified as "Integer" while in the component specification it has type "' & str & '"');
				return;
			else
				new(int,value);
				if ~prop.SetValue(int) then return; end;
			end;
		else
			(* same for both Processor and Cellnet *)
			new(int,value);
			new(prop,name,"",int,nil);
			if c is Cellnet then prop.hdlName := prop.acName; end; (*! since at this time moment processor type is unknown - leave HDL property name NIL to account for properties defined only in AC code *)
			if EnableTrace then trace(c, name, value,prop, int); end;
			c.AddProperty(prop);
		end;
	end DoAddIntegerProperty;

	(** Add a float32 property: required by the compiler *)
	procedure DoAddRealProperty*(c: Cell; const name: array of char; value: float64);
	var
		prop: Property;
		str: LongString;
		r: Real;
	begin

		if c is Engine then
			prop := c.GetPropertyByAcName(name);
			if prop = nil then
				c.Error(ErrNotDefined,'property "' & name & '" is not defined in HDL cell specification');
				return;
			elsif ~(prop.value is Real) then
				prop.value.GetTypeName(str);
				c.Error(ErrInvalidValue,'property "' & name & '" is specified as "Real" while in the component specification it has type "' & str & '"');
				return;
			else
				new(r,value);
				if ~prop.SetValue(r) then return; end;
			end;
		else
			(* same for both Processor and Cellnet *)
			new(r,value);
			new(prop,name,"",r,nil);
			if c is Cellnet then prop.hdlName := prop.acName; end; (*! since at this time moment processor type is unknown - leave HDL property name NIL to account for properties defined only in AC code *)
			if EnableTrace then trace(c, name, value,prop, r); end;
			c.AddProperty(prop);
		end;
	end DoAddRealProperty;

	(** Add a float32 property: required by the compiler *)
	procedure DoAddSetProperty*(c: Cell; const name: array of char; value: set);
	var
		prop: Property;
		str: LongString;
		s: Set;
	begin

		if c is Engine then
			prop := c.GetPropertyByAcName(name);
			if prop = nil then
				c.Error(ErrNotDefined,'property "' & name & '" is not defined in HDL cell specification');
				return;
			elsif ~(prop.value is Set) then
				prop.value.GetTypeName(str);
				c.Error(ErrInvalidValue,'property "' & name & '" is specified as "Set" while in the component specification it has type "' & str & '"');
				return;
			else
				new(s,value);
				if ~prop.SetValue(s) then return; end;
			end;
		else
			(* same for both Processor and Cellnet *)
			new(s,value);
			new(prop,name,"",s,nil);
			if c is Cellnet then prop.hdlName := prop.acName; end; (*! since at this time moment processor type is unknown - leave HDL property name NIL to account for properties defined only in AC code *)
			if EnableTrace then trace(c, name, value,prop, s); end;
			c.AddProperty(prop);
		end;
	end DoAddSetProperty;

	procedure DoAddPortProperty(p: Port; const name: array of char; value: Value);
	var
		processor: Processor;
		prop: Property;
	begin
		if (name = PropFrequency) or (name = PropPeriod) or (name = PropDutyCycle) or (name = PropJitter) then
			if p is ClockOutputPort then
				value := value.ToReal();
				with p : ClockOutputPort do
					if p.clock = nil then
						new(p.clock,p.GetCell().hdlInstName^ & "_" & p.acName^); p.clock.source := p;
					end;
					if name = PropFrequency then
						p.clock.frequency := value(Real).val;
					elsif name = PropPeriod then
						p.clock.frequency := 1/value(Real).val;
					elsif name = PropDutyCycle then
						p.clock.dutyCycle := value(Real).val;
					else
						assert(name = PropJitter);
						p.clock.jitter := value(Real).val;
					end;
				end;
			else
				p.Error(ErrNotDefined,'usupported property "' & name & '"');
				return;
			end;
		elsif (name = PropGroupId) & (p.GetCell() is Processor) then
			processor := p.GetCell()(Processor);
			if ((processor.inputs # nil) & (processor.inputs.GetPortByAcName(name) # nil)) or ((processor.outputs # nil) & (processor.outputs.GetPortByAcName(name) # nil)) then
				p.Error(ErrNotDefined,'usupported property "' & name & '"');
				return;
			end;
		else
			p.Error(ErrNotDefined,'unknown property "' & name & '"');
			return;
		end;

		new(prop,name,"",value,nil);
		if p.props = nil then new(p.props,4); end;
		p.props.Add(prop);
	end DoAddPortProperty;

	procedure DoAddPortIntegerProperty*(p: Port; const name: array of char; value: signed32);
	var int: Integer;
	begin
		new(int,value);
		DoAddPortProperty(p,name,int);

		if EnableTrace then trace(name,value); end;
	end DoAddPortIntegerProperty;

	(** Connect an output port with an input port: required by the compiler *)
	procedure DoConnect*(outPort, inPort: Port; depth: size);
	var
		outCell, inCell: Cell;
		chan: Channel;
		outPort1, inPort1: Port;
		str1, str2: LongString;
		p: Port;
	begin

		outCell := outPort.GetCell();
		inCell := inPort.GetCell();

		if inPort.channel # nil then
			outCell.Error(ErrAlreadyExists,'port "' & inPort.acName^ & '" is driven by multiple outputs: "' & inPort.channel.outPort.GetCell().acInstName^ & '.' & inPort.channel.outPort.acName^ & '" and "' & outCell.acInstName^ & '.' & outPort.acName^ & '"');
			return;
		end;

		(*
			Check port compatibility using port type names
		*)
		assert((outPort.direction = Out) or (outPort.direction = Inout));
		assert((inPort.direction = In) or (inPort.direction = Inout));

		with outPort : HdlPort do (*! make port as internal if connected to another HDL port  *)
			(*!TODO: handle cases when some ports cannot be changed from external to internal; this requires an additional boolean port field *)
			if outPort.isExternal then outPort.MakeExternal(false); end;
		else end;
		with inPort : HdlPort do
			assert(~inPort.isExternal);
		else end;

		(*! take into account cellnet ports - take their prototypes for checking port compatibility *)
		if outPort is CellnetPort then outPort1 := outPort(CellnetPort).protoPort; else outPort1 := outPort; end;
		if inPort is CellnetPort then inPort1 := inPort(CellnetPort).protoPort; else inPort1 := inPort; end;
		outPort1.GetTypeName(str1);
		inPort1.GetTypeName(str2);

		if str1 = "LogicalPort" then (* output is a logical port *)
			assert((outCell is Processor) or (outCell is Cellnet));
			if (str2 # "LogicalPort") & (str2 # "AxisPort") then
				outCell.Error(ErrTypeMismatch,'port type mismatch: logical output port "' & outPort.acName^ & '" is connected to input port "' & inCell.acInstName^ & "." & inPort.acName^ & '" of type "' & str2 & '"');
				return;
			end;
		elsif str2 = "LogicalPort" then (* input is a logical port *)
			assert((inCell is Processor) or (inCell is Cellnet));
			if (str1 # "LogicalPort") & (str1 # "AxisPort") then
				inCell.Error(ErrTypeMismatch,'port type mismatch: logical input port "' & inPort.acName^ & '" is driven by output port "' & outCell.acInstName^ & "." & outPort.acName^ & '" of type "' & str1 & '"');
				return;
			end;
		elsif
			((outPort1 is AxiWritePort) & ~(inPort1 is AxiWritePort)) or
			(~(outPort1 is AxiWritePort) & (inPort1 is AxiWritePort)) or
			((outPort1 is AxiReadPort) & ~(inPort1 is AxiReadPort)) or
			(~(outPort1 is AxiReadPort) & (inPort1 is AxiReadPort)) or
			((outPort1 is AxisPort) & ~(inPort1 is AxisPort)) or
			(~(outPort1 is AxisPort) & (inPort1 is AxisPort)) or
			((outPort1 is ClockOutputPort) & ~(inPort1 is ClockInputPort)) or
			(~(outPort1 is ClockOutputPort) & (inPort1 is ClockInputPort)) then
			outCell.Error(ErrTypeMismatch,'port type mismatch: output port "' & outPort.acName^ & '" of type "' & str1 & '" is connected to input port "' & inCell.acInstName^ & "." & inPort.acName^ & '" of type "' & str2 & '"');
			return;
		end;

		if ((outPort1 is AxiWritePort) or (outPort is AxiReadPort)) & (depth # -1) then
			outCell.Error(ErrInvalidValue,'unsupported non-zero channel depth between AXI output port "' & outPort.acName^ & '" and AXI input port "' & inPort.acName^);
			return;
		end;

		if depth < 0 then (* channel depth is not specified in the ActiveCells code *)
			p := outPort;
			if p is CellnetPort then p := p(CellnetPort).protoPort; end;
			if p is HdlPort then depth := 0;
			else depth := DefaultChanDepth;
			end;
		end;

		new(chan,outPort,inPort,depth);
		outCell.GetCellnet().channels.Add(chan);
	end DoConnect;

	(** Delegate a cellnet port to a port: required by the compiler *)
	procedure DoDelegate*(netPort: Port; cellPort: Port);
	var
		c: Cell;
		net: Cellnet;
	begin
		if EnableTrace then trace(netPort.acName^,cellPort.acName^); end;
		c := cellPort.GetCell();
		net := netPort.GetCell()(Cellnet);
		if ~netPort(CellnetPort).DelegateTo(cellPort) then return; end;
	end DoDelegate;

	(** Start execution of a cell: required by the compiler *)
	procedure DoStart*(c: Cell; proc: procedure{DELEGATE});
	begin
		if c is Cellnet then
			proc;
		end;
	end DoStart;

	(**
		Round a float32 number
	*)
	procedure Round*(x: RealType): IntegerType;
	begin
		if x >= 0 then
			return entierh(x+(RealType(1)/RealType(2)));
		else
			return -entierh(-x+(RealType(1)/RealType(2)));
		end;
	end Round;

	(** Computes ceiling of the log2(x), i.e. the number of bits required to hold x values within the interval [0,x-1] *)
	procedure NumBits*(x: IntegerType): size;
	var n: size;
	begin
		dec(x); n := 0;
		while x > 0 do
			x := x div 2; inc(n);
		end;
		return n;
	end NumBits;

	(**
		Convert Integer to string
	*)
	procedure IntegerToStr*(x: IntegerType; var str: array of char);
	begin
		Strings.FloatToStr(x,0,0,0,str); str[Strings.Length(str)-1] := 0X; Strings.TrimWS(str);
	end IntegerToStr;

	(**
		Convert Real to string
	*)
	procedure RealToStr*(x: RealType; var str: array of char);
	begin
		Strings.FloatToStr(x,0,17,0,str); Strings.TrimWS(str);
	end RealToStr;

	procedure FingerprintEqual(const fingerprint1, fingerprint2: Fingerprint): boolean;
	var k: size;
	begin
		k := 0;
		while (k < sizeof(Fingerprint)) & (fingerprint1[k] = fingerprint2[k]) do inc(k); end;
		return k = sizeof(Fingerprint);
	end FingerprintEqual;

	(** Write a multiline string; new line is defined by presence of "\\" *)
	procedure WriteMultilineString*(w: Streams.Writer; const str: array of char);
	var
		i: size;
	begin
		i := 0;
		while (i < len(str)-2) & (str[i] # 0X) do
			if str[i] # '\' then w.Char(str[i]);
			elsif (str[i+1] = '\') then
				if str[i+2] # '\' then
					w.Ln; if str[i+2] # 0X then w.Char(str[i+2]); end;
					inc(i,2);
				else
					w.String("\\");
				end;
			else w.Char('\');
			end;
			inc(i);
		end;

		while (i < len(str)) & (str[i] # 0X) do (* process boundary *)
			w.Char(str[i]); inc(i);
		end;
	end WriteMultilineString;

	(**
		Create a new BinaryValue value
	*)
	procedure NewBinaryValue*(const x: array of char): BinaryValue;
	begin
		new(result,x);
		assert(result.val # nil);
		return result;
	end NewBinaryValue;

	(**
		Create a new Boolean value
	*)
	procedure NewBoolean*(x: boolean): Boolean;
	begin
		new(result,x); return result;
	end NewBoolean;

	(**
		Create a new Integer value
	*)
	procedure NewInteger*(x: IntegerType): Integer;
	begin
		new(result,x); return result;
	end NewInteger;

	(**
		Create a new Set value
	*)
	procedure NewSet*(x: SetType): Set;
	begin
		new(result,x); return result;
	end NewSet;

	(**
		Create a new Real value
	*)
	procedure NewReal*(x: RealType): Real;
	begin
		new(result,x); return result;
	end NewReal;

	procedure NewString*(const str: array of char): String;
	begin
		new(result,str); return result;
	end NewString;

	(**
		Returns procedure that checks that the value of an integer property is within the specified range
	*)
	procedure IntegerPropertyRangeCheck*(minValue, maxValue: IntegerType): CheckPropertyValueProc;
	var checker: IntegerPropertyRangeChecker;
	begin
		new(checker,minValue,maxValue);
		return checker.CheckValue;
	end IntegerPropertyRangeCheck;

	(**
		Returns procedure that sets up the width of a port to the value of a property

		portNameInHdl: port name in HDL
		propNameInHdl: property name in HDL
	*)
	procedure SetPortWidthFromProperty*(const portNameInHdl, propNameInHdl: array of char): ObjectHandlerProc;
	var setter: PortFromPropertySetter;
	begin
		new(setter,portNameInHdl,propNameInHdl);
		return setter.SetPortWidth;
	end SetPortWidthFromProperty;

	(*
		Get HDL name for a cell instance (will be used in HDL code generation)
	*)
	procedure GetHdlInstanceName(c: Cell; var name: array of char);
	begin
		GetDottedStringEnding(c.acInstName^,name);
		(* get rid of forbidden symbols *)
		GetHdlNormalizedName(name,name);
		if name[0] # "_" then
			Strings.Concat("inst_",name,name);
		else
			Strings.Concat("inst",name,name);
		end;
		return;
	end GetHdlInstanceName;

	(**
		Normalize a name by removing all symbols forbidden in HDL
	*)
	procedure GetHdlNormalizedName*(const name: array of char; var normalizedName: array of char);
	var k, m, n: size;
	begin
		n := Strings.Length(name);
		m := 0;
		for k := 0 to n-1 do
			case name[k] of
				|"@",",","/","\": normalizedName[m] := "_"; inc(m);
				|"[","]":
			else
				normalizedName[m] := name[k]; inc(m);
			end;
		end;
		normalizedName[m] := 0X;
	end GetHdlNormalizedName;

	procedure GetDottedStringEnding(const dottedName: array of char; var ending: array of char);
	var k: size;
	begin
		k := Strings.LastIndexOfByte2(".",dottedName);
		if k > 0 then
			Strings.Copy(dottedName,k+1,Strings.Length(dottedName)-k-1,ending);
		else
			copy(dottedName,ending);
		end;
	end GetDottedStringEnding;

	(**
		Add resources located at a given path to ActiveCells hardware library
	*)
	procedure AddPathToLibrary*(context: Commands.Context);
	var
		path: Files.FileName;
	begin
		if context.arg.GetString(path) then
			if hwLibrary.ScanPath(path,true,globalContext) then
				context.out.String('resources from path "'); context.out.String(path); context.out.String('" have been successfully added to the ActiveCells hardware library');  context.out.Ln;
			end;
		else
			context.result := 1;
			context.error.String("path name is expected!"); context.error.Ln;
		end;

	end AddPathToLibrary;

	(**
		Load component and target specifications given a file with a list of specification module names
	*)
	procedure LoadSpecs*(context: Commands.Context);
	var
		name: Files.FileName;
		file: Files.File;
		fr: Files.Reader;
		m: Modules.Module;
		res: integer;
		msg: array 256 of char;
		n: size;
	begin
		if context.arg.GetString(name) then
			file := Files.Old(name);
			if file = nil then
				context.error.String('failed to open file "'); context.error.String(name); context.error.String('"!'); context.error.Ln;
				context.result := 1;
				return;
			end;
			Files.OpenReader(fr,file,0);
			fr.SkipWhitespace;
			while fr.Available() > 0 do
				if fr.GetString(name) then
					context.out.String('loading "'); context.out.String(name); context.out.String('" ... ');
					m := Modules.ThisModule(name,res,msg);
					if res = 0 then
						inc(n);
						context.out.String("Ok"); context.out.Ln;
					else
						context.error.String('failed to load module "'); context.error.String(name); context.error.String('"');
						if msg # "" then context.error.String(": "); context.error.String(msg); end;
						context.error.Ln;
						context.result := res;
						return;
					end;
				else
					context.error.String("file format error"); context.error.Ln;
					context.result := 1;
					return;
				end;
				fr.SkipWhitespace;
			end;
		else
			context.error.String("filename with specification list is expected!"); context.error.Ln;
		end;

		context.out.Int(n,0); context.out.String(" specifications have been loaded"); context.out.Ln;

	finally
		if file # nil then file.Close; end;
	end LoadSpecs;

	(**
		Clear ActiveCells hardware library
	*)
	procedure ClearLibrary*(context: Commands.Context);
	begin
		hwLibrary.Clear;
		context.out.String("ActiveCells hardware library has been cleared!"); context.out.Ln;
	end ClearLibrary;

	(**
		Get a string representation of an integer in decimal format
	*)
	procedure IntToStr*(x: signed64; var str: array of char);
	var
		i, j: size;
		ch: char;
		negative: boolean;
	begin
		if x < 0 then
			if x = min(signed64) then
				str := "-9223372036854775808";
				return;
			else
				x := -x;
				negative := true;
			end;
		else negative := false;
		end;
		i := 0;
		repeat
			str[i] := chr((x mod 10)+48);
			x := x div 10;
			inc(i);
		until x = 0;
		(* reverse the output string *)
		if ~negative then dec(i); else str[i] := "-"; end;
		for j := 0 to (i div 2) by 1 do
			ch := str[j];
			str[j] := str[i-j];
			str[i-j] := ch;
		end;
		str[i+1] := 0X;
	end IntToStr;

	(**
		Get a string representation of an integer in hexadecimal format

		numDigits: number of used hexadecimal digits; <=0 for automatic determination of the number of digits required for representation of the number
	*)
	procedure IntToHexStr*(x: signed64; numDigits: size; var str: array of char);
	var
		ch: char;
		k, m: size;

		procedure NextDigit(var x: signed64): char;
		begin
			ch := chr(x mod 10H + ord("0"));
			if ch > "9" then ch := chr((x mod 10H - 10) + ord("A")) end;
			x := x div 10H;
			return ch;
		end NextDigit;

	begin
		if numDigits > 0 then
			str[numDigits] := 0X;
			dec(numDigits);
			while (x # 0) & (numDigits >= 0) do
				str[numDigits] := NextDigit(x);
				dec(numDigits);
			end;
			while numDigits >= 0 do
				str[numDigits] := "0";
				dec(numDigits);
			end;
		else
			k := 0;
			repeat
				str[k] := NextDigit(x);
				inc(k);
			until x = 0;
			str[k] := 0X;
			(* reverse the string *)
			for m := 0 to (k div 2) -1 do
				ch := str[m];
				str[m] := str[k-m-1];
				str[k-m-1] := ch;
			end;
		end;
	end IntToHexStr;

	(**
		Check the correctness of the format of a binary value
	*)
	procedure CheckBinaryValueFormat*(const value: array of char): boolean;
	var
		n: size;

		procedure CheckHex(k0, k1: size): boolean;
		var k: size;
		begin
			k := k0;
			while (k <= k1) & (value[k] # 0X) & ( ((cap(value[k]) >= 'A') & (cap(value[k]) <= 'F')) or ((value[k] >= '0') & (value[k] <= '9')) ) do
				inc(k);
			end;
			return k > k1;
		end CheckHex;

	begin
		n := Strings.Length(value);
		if cap(value[n-1]) = "H" then
			return CheckHex(0,n-2);
		elsif (n >= 3) & (value[0] = "0") & (cap(value[1]) = "X") then
			return CheckHex(2,n-1);
		else (* currently only hexadecimal format is supported *)
			return false;
		end;

		return true;
	end CheckBinaryValueFormat;

	operator "&"*(const x, y: StringType): LongString;
	var str: LongString;
	begin
		Strings.Concat(x,y,str);
		return str;
	end "&";

	operator "&"*(const x: StringType; y: signed64): LongString;
	var str: LongString;
	begin
		IntToStr(y,str);
		Strings.Concat(x,str,str);
		return str;
	end "&";

	operator "&"*(x: signed64; const y: StringType): LongString;
	var str: LongString;
	begin
		IntToStr(x,str);
		Strings.Concat(str,y,str);
		return str;
	end "&";

	procedure InitMod;
	begin
		new(globalContext,nil);
		new(hwLibrary);
	end InitMod;

type
	(* Parameter for up-call execution of ActiveCellsRuntime.GenerateArchitecture; used to allow load GenerateArchitecture via GETprocedure *)
	ArchitectureGenParam* = record
		architectureName*: Files.FileName;
		ctx*: Context;
	end;



	(**
		Building an FPGA architecture

		syntax:

			Build options architectureName ~

		where:
			architectureName: acrhitecture name in the format ModuleName.CellnetTypeName, where CellnetTypeName is the type name of the cellnet defining the architecture
			options:
				g [generateOnly]: only generate HDL project without its implementation
				o [outputPath]: output path
				p [projType]: project type (e.g. "ISE" or "Vivado" in case of a Xilinx device)
				t [target]: target device name; either the name in the library or a name of file with target device specification

	*)
	procedure Build*(context: Commands.Context);
	var
		i: size;
		targetName: Files.FileName;
		architectureName, outputPath, str: Files.FileName;
		projType: array 256 of char;
		proc: procedure(): any;
		codeGen: HdlCodeGenerator;
		target: TargetDevice;
		hdlProject: HdlProject;
		sdiag: TracingDiagnostics;
		options: Options.Options;
	type
		TracingDiagnostics = object (Diagnostics.StreamDiagnostics)
		var errorTrace: boolean;
		procedure Error(const source : array of char; position : Streams.Position; const message : array of char);
		begin
			Error^(source, position, message);
			KernelLog.String("AcHdlBackend ERROR: "); KernelLog.String(source); KernelLog.String(" "); KernelLog.String(message); KernelLog.Ln;
			if errorTrace then Debugging.TraceBack end;
		end Error;
		end TracingDiagnostics;
	begin
		new(options);
		options.Add("g","generateOnly",Options.Flag);
		options.Add("o","outputPath",Options.String);
		options.Add("p","projType",Options.String);
		options.Add("t","target",Options.String);
		options.Add("d","deploy",Options.Flag);
		options.Add("f","forceReimplement",Options.Flag);
		options.Add("e","errorTrace",Options.Flag);

		if ~options.Parse(context.arg,context.error) then return; end;

		if ~options.GetString("outputPath",outputPath) then
			outputPath := "WORK";
			context.out.String("output path is not specified -> using WORK directory!"); context.out.Ln; context.out.Update;
		end;

		(* determine full path to the project location *)
		if ~PathTools.DirectoryExists(outputPath,outputPath) & ~PathTools.CreateDirectory(outputPath,outputPath) then
			context.result := 1;
			context.error.String('failed to create directory "' & outputPath & '"!');
			context.error.Ln;
			return;
		end;

		if ~options.GetString("target",targetName) then
			context.error.String("target device name is expected!"); context.error.Ln; return;
		end;

		target := hwLibrary.GetTargetByName(targetName);
		if target = nil then
			context.result := 1;
			context.error.String('target device with name "'); context.error.String(targetName); context.error.String('" could not be found!');  context.error.Ln;
			return;
		end;
		target := target.Copy()(TargetDevice);

		if ~options.GetString("projType",projType) then
			assert(target.pldPart.defaultProjectType # nil);
			assert(target.pldPart.projectFactory # nil);
			copy(target.pldPart.defaultProjectType^,projType);
		end;

		(*! "architectureName" is actually misleading *)
		if ~context.arg.GetString(architectureName) then
			context.result := 1;
			context.error.String("architecture name is expected!"); context.error.Ln;
			return;
		end;

		i := Strings.Find(architectureName,0,".");
		if i # -1 then
			Strings.Copy(architectureName,i+1,Strings.Length(architectureName)-i,str);
			PathTools.JoinPath(outputPath,str,outputPath);
			if ~PathTools.CreateDirectory(outputPath,outputPath) then
				context.result := 1;
				context.error.String('failed to create directory "' & outputPath & '"!');
				context.error.Ln;
				return;
			end;
		else
			context.result := 1;
			context.error.String("architecture name has invalid format!"); context.error.Ln;
			return;
		end;

		new(sdiag,context.out);
		sdiag.errorTrace := options.GetFlag("errorTrace");
		getprocedure("AcVerilogCodeGen","GetGenerator",proc);
		codeGen := proc()(HdlCodeGenerator);

		hdlProject := target.pldPart.projectFactory(projType,architectureName,target,codeGen,outputPath,sdiag);

		if hdlProject = nil then
			context.result := 1;
			context.error.String('failed to create project of type "' & projType & '"'); context.error.Ln;
			return;
		elsif hdlProject.res # 0 then
			context.result := hdlProject.res;
			context.error.String("failed to initialize project, error: " & hdlProject.res); context.error.Ln;
			return;
		end;

		if ~hdlProject.GenerateCode() then
			context.result := hdlProject.res;
			hdlProject.CloseProject;
			context.error.String("failed to generate HDL software code, error:" & hdlProject.res); context.error.Ln;
			return;
		end;

		if ~hdlProject.GenerateHdlCode() then
			context.result := hdlProject.res;
			hdlProject.CloseProject;
			context.error.String("failed to generate HDL code, error: " & hdlProject.res); context.error.Ln;
			return;
		end;

		if ~hdlProject.GenerateConstraints() then
			context.result := hdlProject.res;
			hdlProject.CloseProject;
			context.error.String("failed to generate project constraints, error: " & hdlProject.res); context.error.Ln;
			return;
		end;

		if ~options.GetFlag("forceReimplement") & ~options.GetFlag("generateOnly") then
			if ~hdlProject.CheckForSourcesModifications() or ~hdlProject.CheckForConstraintsModifications() then
				context.result := hdlProject.res;
				hdlProject.CloseProject;
				context.error.String("failed to check the project for modifications, error: " & hdlProject.res); context.error.Ln;
				return;
			end;
		end;

		if ~hdlProject.GenerateProject() then
			context.result := hdlProject.res;
			hdlProject.CloseProject;
			context.error.String("failed to generate HDL project, error: " & hdlProject.res); context.error.Ln;
			return;
		end;

		if ~options.GetFlag("generateOnly") then
			if ~hdlProject.ImplementArchitecture() then
				context.result := hdlProject.res;
				hdlProject.CloseProject;
				context.error.String("failed to implement the architecture, error: " & hdlProject.res); context.error.Ln;
				return;
			end;

			if ~hdlProject.GenerateFingerprintFiles() then
				context.result := hdlProject.res;
				hdlProject.CloseProject;
				context.error.String("failed to generate project fingerprint files, error: " & hdlProject.res); context.error.Ln;
				return;
			end;

			if options.GetFlag("deploy") then
				if ~hdlProject.DeployArchitecture() then
					context.result := hdlProject.res;
					hdlProject.CloseProject;
					context.error.String("failed to deploy the architecture, error: " & hdlProject.res); context.error.Ln;
					return;
				end;
			end;
		end;

		hdlProject.CloseProject;

		context.out.String("Success!"); context.out.Ln;
		return;

	finally
		context.result := hdlProject.res;
		context.error.String("unknown error, error: " & hdlProject.res); context.error.Ln;
		return;
	end Build;

begin
	InitMod;
end AcHdlBackend.

SystemTools.FreeDownTo AcHdlBackend ~


