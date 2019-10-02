(* ported version of Minos to work with the ARM backend of the Fox Compiler Suite *)
MODULE Modules;

IMPORT SYSTEM, Kernel, Platform, OFS, Strings, Tools, Heaps, Log;
	
	CONST
		OK*= 0; NOTFOUND* = 1; NOTARM* = 2;  WRONGKEY*=3; NOMEMORY* = 4;

TYPE Name = ARRAY 32 OF CHAR;

	Command* = POINTER TO CommandDesc;
	CommandDesc = RECORD
		next*: Command;
		offset: SIZE;
		name*: Name
	END;
	
	EntryTable = POINTER TO EntryTableDesc;
	EntryTableDesc = RECORD
		entry: ARRAY 256 OF SIZE
	END;

	Module* = POINTER TO ModuleDesc;
	ModuleDesc = RECORD 
		next*: Module;
		key-: SIZE;				(* Unique key of Module *)
		dbase, pbase*: ADDRESS;		(* dbase : Base address of Module Variables, pbase: Base address of code *)
		size*, refcnt*: SIZE;		(* size: code size in bytes, rofcnt: reference counter *)
		command*: Command;		(* First command *)
		entrytable: EntryTable;		(* Array containing the offset rel to pbase for each exported function *)
		name*: Name				(* Name of module *)
	END;

	(*! STUDENT:
		Although a part of the information necessary for unloading a module is already weaved-in in ModuleDesc above,
		we need a bit more information.
		But: The static linker relies on the fact that a module has the form of the record above. Therefore we cannot add further
		fields in the ModuleDesc. Trick: use extension of a module. (This will also help to distinguish modules linked into the kernel from
		those that are dynamically loaded. I suggest the following extension:
	*)

	DynamicModule* = POINTER TO DynamicModuleDesc;
	DynamicModuleDesc = RECORD(ModuleDesc)
		(*!STUDENT fill in fields here *)
		loaded*: LoadedModule;
	END;
	
	LoadedModule* = POINTER TO LoadedModuleDesc;
	LoadedModuleDesc = RECORD
		next*: LoadedModule;
		module*: Module;
	END;

VAR root*: Module;
	res: SIZE; errstring*: ARRAY 32 OF CHAR;

PROCEDURE GetRes*(VAR err: ARRAY OF CHAR): SIZE;
BEGIN
	Strings.Copy(errstring, err);
	RETURN res
END GetRes;

PROCEDURE JoinExtension (CONST name, extension: ARRAY OF CHAR; VAR fullname: ARRAY OF CHAR);
VAR i, j: SIZE;
BEGIN
	i := 0; WHILE name[i] # 0X DO fullname[i] := name[i]; INC(i) END;
	j := 0; WHILE extension[j] # 0X DO fullname[i] := extension[j]; INC(i); INC(j) END;
	fullname[i] := 0X
END JoinExtension;

PROCEDURE MakeName (CONST name: ARRAY OF CHAR; VAR fullname: ARRAY OF CHAR);
BEGIN JoinExtension (name, ".arm", fullname)
END MakeName;

PROCEDURE ReadString (VAR r: OFS.Rider; VAR string: ARRAY OF CHAR);
VAR ch: CHAR; i: SIZE;
BEGIN i := 0;
	REPEAT OFS.Read (r, ch); string[i] := ch; INC (i) UNTIL ch = 0X;
END ReadString;

PROCEDURE Fixup(pbase, fixloc, offset, base: SIZE; CONST entry: ARRAY OF SIZE);
	VAR instr, next, pno: SIZE;
BEGIN
	WHILE fixloc # 0 DO
		SYSTEM.GET (pbase + fixloc*4, instr); next := instr MOD 10000H;
		pno := instr DIV 10000H MOD 100H;
		IF instr DIV 1000000H MOD 100H = 0EBH THEN  (* case  BL *)
			instr := instr DIV 1000000H * 1000000H + (entry[pno] + offset - fixloc - 2) MOD 1000000H
		(*ELSIF instr DIV 1000000H = 0 THEN (*indir. variable address*) instr := entry[pno] + base*)
		ELSE (*indir. proc. address*) instr := entry[pno]*4 + base
		END ;
		SYSTEM.PUT (pbase + fixloc*4, instr); fixloc := next
	END
END Fixup;

PROCEDURE FixSelf (pbase, fixloc, base: SIZE);
	VAR instr, next: SIZE;
BEGIN
	WHILE fixloc # 0 DO
		SYSTEM.GET (pbase+fixloc*4, instr); next := instr MOD 10000H;
		SYSTEM.PUT (pbase+fixloc*4, instr DIV 10000H * 4 + base); fixloc := next
	END
END FixSelf;

PROCEDURE FindModule*(CONST name: ARRAY OF CHAR; VAR m: Module);
BEGIN m := root;
	WHILE (m # NIL) & ~Strings.EqualIgnoreCase(m.name, name) DO m := m.next END;
END FindModule;

PROCEDURE Call (m: Module; entry: SIZE);
VAR p: PROCEDURE;
BEGIN 
	SYSTEM.PUT (ADDRESSOF (p), m.pbase + entry * 4); p
END Call;

PROCEDURE CallP*(m: Module; CONST pname: ARRAY OF CHAR): BOOLEAN;
VAR cmd: Command;
BEGIN cmd := m.command;
	WHILE (cmd # NIL) & (cmd.name # pname) DO cmd := cmd.next END;
	IF cmd # NIL THEN Call (m, cmd.offset) END;
	RETURN cmd # NIL
END CallP;

PROCEDURE PrintModuleInfo*(m: Module);
BEGIN
	IF m # NIL THEN
		Log.S("Module: "); Log.SL(m.name);
		Log.SI("size", m.size);
		Log.S("dbase: "); Log.H( m.dbase); Log.L;
		Log.S("pbase: "); Log.H( m.pbase); Log.L;
		Log.MFlush(Log.normal);
	END;
END PrintModuleInfo;

(* Remove a module from the free module list *)
PROCEDURE RemoveMod(mod: Module);
VAR
	m, prevMod: Module;
BEGIN
	m := mod;
	IF m = root THEN
		root := root.next;
	ELSE
		m := root;
		REPEAT
			prevMod := m;
			m := m.next;
		UNTIL (m = NIL) OR (m = mod);
		
		IF m = mod THEN prevMod.next := m.next; END;
	END;
END RemoveMod;

(*! STUDENT: procedure to load a module. You need to change something here in order to support module unloading *)
PROCEDURE ThisMod* (CONST modname: ARRAY OF CHAR; VAR mod: Module);
VAR imp: Module; cmd: Command;
	nofimp, nofentries, codelen, fix, fixself, i, j, base: SIZE;
	f: OFS.File; r: OFS.Rider; err: BOOLEAN;
	name: ARRAY 32 OF CHAR;
	key, offset, datasize: SIZE;
	fixroot: ARRAY 32 OF SIZE;
	import: ARRAY 32 OF Module;
	dynMod: DynamicModule;
	loadMod: LoadedModule;
BEGIN 
	mod := root; res := OK;
	WHILE (mod # NIL) & (mod.name # modname) DO mod := mod.next; END;
	IF mod = NIL THEN  (*load*)
		MakeName (modname, name);
		f := OFS.Old(name);
		IF f = NIL THEN f:= Tools.RemoteReadFile(name); END;
		IF f = NIL THEN
			mod:=NIL; res := NOTFOUND; Strings.Copy (name, errstring);
		ELSE
			OFS.Set(r, f, 0);

			NEW(dynMod);
			dynMod.loaded := NIL;
			mod := dynMod;

			(*NEW(mod);*)
			
			mod.next := root; mod.refcnt := 0; root := mod;
			ReadString (r, mod.name);
			OFS.ReadInt (r, mod.key);
			OFS.ReadInt (r, fixself);
			ReadString (r, name); err := FALSE; i := 0;
			WHILE (name[0] # 0X) & (res = OK) DO
				OFS.ReadInt (r, key); OFS.ReadInt (r, fix);
				ThisMod (name, imp);
				IF imp # NIL THEN
					IF key = imp.key THEN
						NEW(loadMod);
						loadMod.module := imp;

						loadMod.next := dynMod.loaded;
						dynMod.loaded := loadMod;

						import[i] := imp; INC (imp.refcnt); fixroot[i] := fix; INC(i)
					ELSE 
						res := WRONGKEY; Strings.Copy (name, errstring); (* RemoveMod(mod); *) mod := NIL;
					END
				END;
				ReadString (r, name);
			END;
			nofimp := i;
			IF res = OK THEN
				i := 0;
				mod.command := NIL;
				ReadString (r, name);
				WHILE name[0] # 0X DO
					NEW (cmd); cmd.next := mod.command; mod.command := cmd;
					OFS.ReadInt (r, cmd.offset); cmd.name := name; 
					ReadString (r, name);
				END;
				OFS.ReadInt (r,  nofentries); NEW (mod.entrytable); OFS.ReadInt (r, mod.entrytable.entry[0]); i := 0;
				WHILE i < nofentries DO INC(i); OFS.ReadInt(r,  mod.entrytable.entry[i]); 
				END ;
				OFS.ReadInt (r, datasize); 
				Heaps.Alloc(mod.dbase, datasize);
				base := mod.dbase; WHILE datasize # 0 DO SYSTEM.PUT (base, 0); DEC (datasize, 4); INC (base, 4) END;
				OFS.ReadInt (r, codelen); mod.size := codelen * 4; 
				Heaps.Alloc(mod.pbase, mod.size);
				base := mod.pbase; WHILE codelen # 0 DO OFS.ReadInt (r, i); SYSTEM.PUT (base, i); DEC (codelen); INC (base, 4) END;
				FixSelf(mod.pbase, fixself, mod.pbase); i := 0;
				WHILE i < nofimp DO
					offset := import[i].pbase - mod.pbase;
					Fixup(mod.pbase, fixroot[i], (import[i].pbase - mod.pbase) DIV 4, import[i].pbase, import[i].entrytable.entry); INC(i);
				END;
				FOR i := 0 TO mod.size-1 BY 4 DO
					SYSTEM.GET(mod.pbase+i*4, j);
				END;
				Kernel.CleanCache();	(* tt: Make sure the data cache is flushed *)
				Call (mod, mod.entrytable.entry[0]);
			ELSE
				(* Failed to load module, therefore remove it from the list of loaded modules *)
				RemoveMod(mod);
 			END;
			OFS.Close (f);
		END;
	END;
END ThisMod;

(* Unload a module *)
PROCEDURE Unload*(CONST name: ARRAY OF CHAR );
VAR
	m: Module;
	i: SIZE;
	n: LoadedModule;
BEGIN
	(* find the module by name *)
	m := root;
	WHILE (m # NIL) & ~Strings.EqualIgnoreCase(m.name, name) DO m := m.next END;

	IF m # NIL THEN
		(* Module found *)

		(*! STUDENT FILL IN CODE HERE *)
		(* can we unload it ? *)
		IF m.refcnt = 0 THEN
			(* If yes, unload, remove from module list  *)
			WITH m: DynamicModule DO
				n := m.loaded;
				(* hint: do not forget the reference counts *)
				WHILE n # NIL DO
					n.module.refcnt := n.module.refcnt - 1;
					n := n.next;
				END;
			ELSE  
			END;
			RemoveMod(m);
		ELSE
			Log.S("module "); Log.S(name); Log.SL(" refcnt not zero");
		END;

	ELSE
		Log.S("module "); Log.S(name); Log.SL(" not found");
	END;
END Unload;

PROCEDURE PatchModuleTypes;
VAR m: Module;
BEGIN
	m := root;
	WHILE (m # NIL) DO
		SYSTEM.PUT(ADDRESS(m)-4, SYSTEM.TYPECODE(ModuleDesc));
		m := m.next;
	END; 	
END PatchModuleTypes;


BEGIN
	SYSTEM.GET (Platform.ModRoot, root);
	PatchModuleTypes();
	
END Modules.
