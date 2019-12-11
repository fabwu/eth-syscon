(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: ActiveCells runtime wrapper used for generation of HDL code
*)
module ActiveCellsRuntime;

import
	system, HdlBackend := AcHdlBackend, Heaps, Modules, Diagnostics, Strings;

const
	EnableTrace* = true;

type
	(* do not inherit from this object -- not supported. This object contains hidden fields instantiated by the compiler that would be lost. *)
	Cell* = object
	var
		c*: HdlBackend.Cell;
	end Cell;

	(* port can be basically anything, it is okay to inherit *)
	Port* = HdlBackend.Port;

	procedure Allocate*(scope: Cell; var c: Cell; tag: address; const name: array of char; isCellnet, isEngine: boolean);
	var
		a: any;
		ac, scp: HdlBackend.Cell;
		typeInfo: Modules.TypeDesc;
	begin
		if (scope # nil) & (scope.c.ctx.res # 0) then return; end; (*! do not do anything in case of an error *)
		if EnableTrace then trace(scope, c, tag, name, isCellnet, isEngine); end;

		(* allocation of cells must use the tag provided, it contains all internally stored metadata *)
		Heaps.NewRec(a, tag, false);

		if scope = nil then scp := nil else scp := scope.c end;
		system.get(tag-4,typeInfo);
		if c = nil then
			HdlBackend.Allocate(scp, ac, typeInfo, name, isCellnet, isEngine);
		else (* the case of an array of cells *)
			assert(c.c # nil);
			ac := c.c;
			HdlBackend.Allocate(scp, ac, typeInfo, name, isCellnet, isEngine);
		end;
		c := a(Cell);
		c.c := ac;
	end Allocate;

	procedure AddPort*(c: Cell; var p: Port; const name: array of char; inout: set; width: signed32);
	begin
		if c.c.ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
		if EnableTrace then trace(c,p,name, inout, width); end;
		HdlBackend.AddPort(c.c,p,name,inout,width,nil);
	end AddPort;

	procedure AddPortArray*(c: Cell; var ports: any; const name: array of char; inout: set; width: signed32; const lens: array of signed32);
	begin
		if c.c.ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
		if EnableTrace then trace(name, inout, width, len(lens)); end;
		HdlBackend.AddPortArray(c.c,ports,name,inout,width,lens);
	end AddPortArray;

	procedure AddStaticPortArray*(c: Cell; var ports: array of Port; const name: array of char; inout: set; width: signed32);
	begin
		if c.c.ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
		if EnableTrace then trace(name, inout, width, len(ports)); end;
		HdlBackend.AddStaticPortArray(c.c,ports,name,inout,width);
	end AddStaticPortArray;

	procedure AddPortIntegerProperty*(p: Port; const name: array of char; value: signed32);
	begin
		if p.ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
		if EnableTrace then trace(p, name, value); end;
		HdlBackend.AddPortIntegerProperty(p,name,value);
	end AddPortIntegerProperty;

	procedure AddFlagProperty*(c: Cell; const name: array of char);
	begin
		if c.c.ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
		if EnableTrace then trace(c, name); end;
		HdlBackend.AddFlagProperty(c.c,name);
	end AddFlagProperty;

	procedure AddStringProperty*(c: Cell; const name: array of char; var newValue: array of char; const value: array of char);
	begin
		if c.c.ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
		if EnableTrace then trace(c, name, newValue, value); end;
		HdlBackend.AddStringProperty(c.c,name,newValue,value);
	end AddStringProperty;

	procedure AddIntegerProperty*(c: Cell; const name: array of char; var newValue: signed32; value: signed32);
	begin
		if c.c.ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
		if EnableTrace then trace(c, name, newValue, value); end;
		HdlBackend.AddIntegerProperty(c.c,name,newValue,value);
	end AddIntegerProperty;

	procedure FinishedProperties*(c: Cell);
	begin
		if c.c.ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
		if EnableTrace then trace(c); end;
		HdlBackend.FinishedProperties(c.c);
	end FinishedProperties;

	procedure Connect*(outPort, inPort: Port; depth: signed32);
	begin
		if outPort.ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
		if EnableTrace then trace(outPort, inPort, outPort.acName^, inPort.acName^, depth); end;
		HdlBackend.Connect(outPort,inPort,depth);
	end Connect;

	procedure Delegate*(netPort: Port; cellPort: Port);
	begin
		if netPort.ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
		if EnableTrace then trace(netPort, cellPort); end;
		HdlBackend.Delegate(netPort,cellPort);
	end Delegate;

	procedure Start*(c: Cell; proc: procedure{DELEGATE});
	begin
		if c.c.ctx.res # 0 then return; end; (*! do not do anything in case of an error *)
		if EnableTrace then trace(c, proc); end;
		HdlBackend.Start(c.c,proc);
	end Start;

type
	Module = pointer to record
		next: Module;
		checked, imports: boolean;
		m: Modules.Module
	end;
		
	procedure Find(root: Module; m: Modules.Module): Module;
	begin
		while (root # nil) & (root.m # m) do root := root.next end;
		return root
	end Find;

	procedure Imports(root, m: Module; const name: array of char): boolean;
	var i: signed32;
	begin
		if ~m.checked then
			if m.m.name # name then
				i := 0;
				while i # len(m.m.module) do
					if (m.m.module[i].name = name) or Imports(root, Find(root, m.m.module[i]), name) then
						m.imports := true; i := len(m.m.module)
					else
						inc(i)
					end
				end
			else
				m.imports := true
			end;
			m.checked := true
		end;
		return m.imports
	end Imports;

	(*! caution: this is not thread safe -- must be moved to Modules.Mod *)
	procedure CopyModules(): Module;
	var firstm, lastm, c: Module; m: Modules.Module;
	begin
		new(firstm); firstm.next := nil; lastm := firstm;
		m := Modules.root;
		while m # nil do
			new(c); c.checked := false; c.imports := false; c.m := m;
			c.next := nil; lastm.next := c; lastm := c;
			m := m.next
		end;
		return firstm.next
	end CopyModules;

	procedure FreeDownTo(const modulename: array of char): signed32;
	var
		root, m: Module; res: signed32;
		nbrOfUnloadedModules : signed32;
		msg: array 32 of char;
	begin
		nbrOfUnloadedModules := 0;
		root := CopyModules();
		m := root;
		while m # nil do
			if Imports(root, m, modulename) then
				Modules.FreeModule(m.m.name, res, msg);
				if res # 0 then
					(*context.error.String(msg);*)
				else
					inc(nbrOfUnloadedModules);
				end
			end;
			m := m.next
		end;
		return nbrOfUnloadedModules;
	end FreeDownTo;
	(*
		Generate an architecture from the source code

		moduleName: source module name
		architectureName: type name of the cellnet object defining the architecture
	*)
	procedure GenerateArchitecture*(const param: HdlBackend.ArchitectureGenParam): HdlBackend.Cellnet;
	type
		StartProc = procedure{DELEGATE}();
		StartProcDesc = record proc: address; selfParam: address; end;
	var
		moduleName, typeName: array 256 of char;
		architecture: HdlBackend.Cellnet;
		m: Modules.Module;
		typeInfo: Modules.TypeDesc;
		i, res: signed32;
		str: array 256 of char;
		scope: Cell;
		startProcDesc: StartProcDesc;
		startProc: StartProc;
		unloaded: signed32;
	begin

		i := Strings.IndexOfByte2(".",param.architectureName);
		if i = -1 then
			param.ctx.Error("",Diagnostics.Invalid,HdlBackend.ErrInvalidValue,'specified architecture name "' & param.architectureName & '" has invalid format!');
			return nil;
		end;

		Strings.Copy(param.architectureName,0,i,moduleName);
		Strings.Copy(param.architectureName,i+1,Strings.Length(param.architectureName)-Strings.Length(moduleName),typeName);

		unloaded := FreeDownTo(moduleName);
		if unloaded > 0 then 
			param.ctx.Information("", Diagnostics.Invalid,Diagnostics.Invalid,"unloaded " & unloaded & " modules")
		end;
		m := Modules.ThisModule(moduleName,res,str);

		if m = nil then
			param.ctx.Error("",Diagnostics.Invalid,HdlBackend.ErrNotFound,'failed to load module "' & moduleName & '"');
			return nil;
		end;
		typeInfo := Modules.ThisType(m,typeName);
		if typeInfo = nil then
			param.ctx.Error("",Diagnostics.Invalid,HdlBackend.ErrNotFound,'failed to find cellnet type "' & param.architectureName & '" in module "' & moduleName & '"');
			return nil;
		end;

		assert(len(typeInfo.procedures) = 1);
		assert(typeInfo.procedures[0].name^ = "@Body");

		(* allocate the top level cellnet *)
		Allocate(nil,scope,typeInfo.tag,typeName,true,false);
		assert(scope # nil);
		assert(scope.c # nil);
		scope.c.SetContext(param.ctx);

		startProcDesc.selfParam := scope;
		startProcDesc.proc := typeInfo.procedures[0].address;
		system.move(addressof(startProcDesc),addressof(startProc),8); Start(scope,startProc(*SYSTEM.VAL(StartProc,startProcDesc)*)); (*! the commented code does not work for an unknown reason (compiler bug?)*)

		if param.ctx.res = 0 then
			architecture := scope.c(HdlBackend.Cellnet);
			return architecture;
		end;

	finally
		return nil;
	end GenerateArchitecture;
	
	procedure Send*(p: Port; value: signed32);
	begin
	end Send;

	procedure Receive*(p: Port; value: signed32);
	begin
	end Receive;

end ActiveCellsRuntime.
