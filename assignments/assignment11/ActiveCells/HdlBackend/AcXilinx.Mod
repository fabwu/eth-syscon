(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: XILINX specific functionalities used by ActiveCells HDL backend
*)
module AcXilinx;

import
	HdlBackend := AcHdlBackend, AcVerilogCodeGen, FoxTRMTools, Strings, Diagnostics, Files, PathTools, FSTools, Streams, KernelLog, Commands,
	Kernel, Machine;

const
	DefaultProjectType* = "ISE";

	InfoMsg = 0;
	WarningMsg = 1;
	ErrorMsg = 2;
	Windows=false;
	Linux=true;

type

	(**
		XILINX PLD part description
	*)
	PldPart* = object(HdlBackend.PldPart)

		(*
			Construct a part given its full part name

			PLD part naming is explained in Figure 1 "Ordering Information" in "7 Series FPGAs Overview" document (DS180 (v1.17) May 27, 2015)
		*)
		procedure &InitPldPart*(const partName: array of char);
		var

			procedure ParseDevicePackageSpeedGrade(pos: size): boolean;
			var
				j, m, n: size;
				str: array 8 of char;
			begin
				n := Strings.Length(partName);
				j := pos; while (j < n) & (partName[j] # "-") do inc(j); end;
				if j = pos then
					Error(HdlBackend.ErrInvalidValue,"invalid Xilinx part name specification: string is too short");
					return false;
				elsif j = n then
					Error(HdlBackend.ErrInvalidValue,"invalid Xilinx part name specification: speed grade specification not present");
					return false;
				end;
				device := Strings.Substring(0,j,partName);
				assert(partName[j] = "-");
				pos := j; inc(j);
				if n - j < 1 then
					Error(HdlBackend.ErrInvalidValue,"invalid Xilinx part name specification: incomplete speed grade specification");
					return false;
				end;
				if ~IsDecDigit(partName[j]) then
					m := 0;
					while (j < n) & ~IsDecDigit(partName[j]) do str[m] := partName[j]; inc(j); inc(m); end;
					if j = n then
						Error(HdlBackend.ErrInvalidValue,"invalid Xilinx part name specification: incomplete speed grade specification");
						return false;
					end;
					pos := j;
					while (j < n) & IsDecDigit(partName[j]) do inc(j); end;
					if (j = pos) or (j = n) then
						Error(HdlBackend.ErrInvalidValue,"invalid Xilinx part name specification: invalid speed grade specification");
						return false;
					end;
					new(speedGrade,1+m+j-pos+1);
					speedGrade[0] := "-";
					Strings.Move(partName,pos,j-pos,speedGrade^,1); (* the digits are first *)
					Strings.Append(speedGrade^,str); (* then add the letters *)
				else
					while (j < n) & IsDecDigit(partName[j]) do inc(j); end;
					speedGrade := Strings.Substring(pos,j,partName);
				end;
				if j = n then
					Error(HdlBackend.ErrInvalidValue,"invalid Xilinx part name specification: package specification not present");
					return false;
				end;
				package := Strings.Substring(j,Strings.Length(partName),partName);
				return true;
			end ParseDevicePackageSpeedGrade;

		begin
			if partName = "nil" then return; end;

			InitObject;
			vendor := Strings.NewString("Xilinx");

			(* Parse the part name *)
			if (cap(partName[0]) # "X") or ((cap(partName[1]) # "A") & (cap(partName[1]) # "C") &  (cap(partName[1]) # "Q")) then
				Error(HdlBackend.ErrInvalidValue,"invalid Xilinx part name specification: invalid device prefix"); return;
			end;

			case cap(partName[2]) of (* generation code *)
				|"3": (* gen 3 *)
					case cap(partName[3]) of (* family code *)
						|"S":
							if ~ParseDevicePackageSpeedGrade(4) then return; end;
							if device[Strings.Length(device^)-1] = "E" then
								family := Strings.NewString("Spartan3E");
							elsif (device[Strings.Length(device^)-2] = "A") or (device[Strings.Length(device^)-1] = "A") then
								family := Strings.NewString("Spartan3A");
							else
								family := Strings.NewString("Spartan3");
							end;
					else
						Error(HdlBackend.ErrInvalidValue,"invalid Xilinx 3 part name specification (unknown device family)"); return;
					end;

				|"5": (* gen 5 *)
					case cap(partName[3]) of (* family code *)
						|"V":
							family := Strings.NewString("Virtex5");
							if ~ParseDevicePackageSpeedGrade(4) then return; end;
					else
						Error(HdlBackend.ErrInvalidValue,"invalid Xilinx 5 part name specification (unknown device family)"); return;
					end;

				|"6": (* gen 6 *)
					case cap(partName[3]) of (* family code *)
						|"S":
							family := Strings.NewString("Spartan6");
							if ~ParseDevicePackageSpeedGrade(4) then return; end;
						|"V":
							family := Strings.NewString("Virtex6");
							if ~ParseDevicePackageSpeedGrade(4) then return; end;
					else
						Error(HdlBackend.ErrInvalidValue,"invalid Xilinx 6 part name specification (unknown device family)"); return;
					end;

				|"7": (* gen 7 *)
					case cap(partName[3]) of (* family code *)
						|"A": (* Artix *)
							family := Strings.NewString("Artix7");
							if ~ParseDevicePackageSpeedGrade(4) then return; end;
						|"K": (* Kintex *)
							family := Strings.NewString("Kintex7");
							if ~ParseDevicePackageSpeedGrade(4) then return; end;
						|"V": (* Virtex *)
							family := Strings.NewString("Virtex7");
							if ~ParseDevicePackageSpeedGrade(4) then return; end;
						|"Z": (* Zynq *)
							family := Strings.NewString("Zynq");
							if ~ParseDevicePackageSpeedGrade(4) then return; end;
					else
						Error(HdlBackend.ErrInvalidValue,"invalid Xilinx 7 part name specification (unknown device family)"); return;
					end;
			else
				Error(HdlBackend.ErrInvalidValue,"invalid Xilinx part name specification (invalid generation)"); return;
			end;

			trace(family^,device^,speedGrade^,package^);

			projectFactory := NewProject;
			defaultProjectType := Strings.NewString(DefaultProjectType);
		end InitPldPart;

		procedure CopyContent(cpy: HdlBackend.Object);
		begin
			CopyContent^(cpy);
			with cpy : PldPart do

			end;
		end CopyContent;

	end PldPart;

	(*
		Xilinx ISE TCL shell application
	*)
	IseTclShell = object(HdlBackend.Shell)
	var
		ctx: HdlBackend.Context;
		sleep: Kernel.Timer;

		procedure &InitIseTclShell(
										const shellAppPathName: array of char;
										context: HdlBackend.Context;
										outBufSize, inBufSize, errBufSize: size
										);
		begin
			ctx := context;
			InitShell(shellAppPathName,outBufSize,inBufSize,errBufSize);
			new(sleep);
		end InitIseTclShell;

		procedure ProcessMessage(var str: array of char; var lastMsgType: signed32);
		begin
			(*! message is completed if it ends with "." *)
			if Strings.StartsWith2("INFO:",str) then
				Strings.Delete(str,0,5);
				ctx.Information("",Streams.Invalid,Streams.Invalid,str);
				if str[Strings.Length(str)-1] # "." then lastMsgType := InfoMsg; else lastMsgType := -1; end;
			elsif Strings.StartsWith2("WARNING:",str) then
				Strings.Delete(str,0,8);
				ctx.Warning("",Streams.Invalid,Streams.Invalid,str);
				if str[Strings.Length(str)-1] # "." then lastMsgType := WarningMsg; else lastMsgType := -1; end;
			elsif Strings.StartsWith2("ERROR:",str) then
				Strings.Delete(str,0,6);
				(*! handle non-critical errors *)
				if str # " Failed to retrieve the list of boards for ISim Hardware Co-Simulation." then
					ctx.Error("",Streams.Invalid,HdlBackend.ErrExternal,str);
					if str[Strings.Length(str)-1] # "." then lastMsgType := ErrorMsg; else lastMsgType := -1; end;
				else
					ctx.Warning("",Streams.Invalid,Streams.Invalid,str);
				end;
			else
				if (str[0] = " ") & (lastMsgType >= 0) then (* non-completed message *)
					case lastMsgType of
						|InfoMsg:
							ctx.Information("",Streams.Invalid,Streams.Invalid,str);
							if str[Strings.Length(str)-1] = "." then lastMsgType := -1; end;
						|WarningMsg:
							ctx.Warning("",Streams.Invalid,Streams.Invalid,str);
							if str[Strings.Length(str)-1] = "." then lastMsgType := -1; end;
						|ErrorMsg:
							ctx.Error("",Streams.Invalid,HdlBackend.ErrExternal,str);
							if str[Strings.Length(str)-1] = "." then lastMsgType := -1; end;
					end;
				else
					lastMsgType := -1;
					KernelLog.String(str); KernelLog.Ln;
				end;
			end;
		end ProcessMessage;

		(* Execute a TCL command *)
		procedure Cmd(const cmd: array of char): boolean;
		var resultStr: array 1 of char;
		begin
			return CmdRet(cmd,resultStr);
		end Cmd;

		(* Execute a TCL command that returns a string value *)
		procedure CmdRet(const cmd: array of char; var retStr: array of char): boolean;
		var
			i: size;
			str: HdlBackend.LongString;
			continue: boolean;
			lastMsgType: signed32;

			procedure ProcessOutputStream(): boolean;
			begin
				while shIn.Available() > 0 do
					shIn.Ln(str);
					(*KernelLog.String("OUT:"); KernelLog.String(str); KernelLog.Ln;*)
					if Strings.StartsWith2("TCL_",str) then
						return false;
					else
						ProcessMessage(str,lastMsgType);
						(*KernelLog.String(str); KernelLog.Ln;*)
					end;
				end;
				return true;
			end ProcessOutputStream;

			procedure ProcessErrorStream;
			begin
				while shErr.Available() > 0 do
					shErr.Ln(str);
					(*KernelLog.String("ERR:"); KernelLog.String(str); KernelLog.Ln;*)
					ProcessMessage(str,lastMsgType);
				end;
			end ProcessErrorStream;

		begin
			KernelLog.String('executing TCL command "'); KernelLog.String(cmd); KernelLog.Char('"'); KernelLog.Ln;

			shOut.String("if {[catch {");
			shOut.String(cmd);
			shOut.String("} ret]} {puts TCL_ERROR:$ret} else {puts TCL_OK:$ret}");
			shOut.Ln; shOut.Update;

			continue := true;
			while (ctx.res = 0) & (res = 0) & continue do
				ProcessErrorStream;
				continue := ProcessOutputStream();
				if continue then sleep.Sleep(10); end;
			end;

			if (ctx.res # 0) or (res # 0)  then
				ctx.ErrorUnexpected; return false;
			end;

			if Strings.StartsWith2("TCL_OK",str) then
				if len(retStr) > 1 then
					Strings.Delete(str,0,7);
					copy(str,retStr);
				end;
			else
				i := Strings.IndexOfByte(":",10,str);
				if i = -1 then i := 9; end;
				Strings.Delete(str,0,i+1);
				ctx.Error("",Streams.Invalid,HdlBackend.ErrExternal,str);
				return false;
			end;

			return ctx.res = 0;

		finally
			ctx.ErrorUnexpected; return false;
		end CmdRet;

	end IseTclShell;

	(**
		Xilinx ISE project
	*)
	IseProject* = object(HdlBackend.HdlProject)
	var
		opened: boolean;

		bmmw: Streams.Writer;
		patchedBitstreamIndex: size;

		xilProjPath: Files.FileName;

		tcl: IseTclShell;
		impact: HdlBackend.Shell;

		sleep: Kernel.Timer;

		procedure &InitIseProject*(const architectureName: array of char; targetDev: HdlBackend.TargetDevice; codeGenerator: HdlBackend.HdlCodeGenerator; const projectPath: array of char; diag: Diagnostics.Diagnostics);
		var
			str: Files.FileName;
		begin
			InitHdlProject(architectureName,targetDev,codeGenerator,projectPath,diag);
			if res # 0 then return; end;

			(*
				Open xtclsh for executing TCL project-specific commands
			*)
			if hostOS=Windows then
				PathTools.JoinPath(iseBinPath,"xtclsh.exe",str);
			else
				PathTools.JoinPath(iseBinPath,"xtclsh",str);
			end;
			new(tcl,str,self,4096,4096,4096);
			if ~tcl.Execute(true) then
				tcl := nil;
				Error("",Streams.Invalid,HdlBackend.ErrUnexpected,'failed to start Xilinx ISE TCL shell');
				return;
			end;

			PathTools.JoinPath(path^,"ISE",xilProjPath);
			if ~PathTools.DirectoryExists(xilProjPath,xilProjPath) & ~PathTools.CreateDirectory(xilProjPath,xilProjPath) then
				Error("",Streams.Invalid,HdlBackend.ErrUnexpected,'failed to create directory "' & xilProjPath & '"!');
				return;
			end;

			new(sleep);

			return;

		finally
			ErrorUnexpected;
		end InitIseProject;

		procedure GenerateClocks(w: Streams.Writer; synthesizer: HdlBackend.Cell): boolean;
		begin
			return ProjGenerateClocks(self,w,synthesizer);
		end GenerateClocks;

		procedure GenerateProject(): boolean;
		var
			i: size;
			dep: HdlBackend.Dependency;
			str: HdlBackend.LongString;
		begin
			(*
				Create ISE project
			*)

			if ~tcl.Cmd("cd " & xilProjPath) then return false; end;

			if ~hdlSourcesUnchanged or ~constraintsUnchanged then

				if ~tcl.Cmd("set projectName " & architecture.acName^) then return false; end;
				if ~tcl.Cmd("file delete -force $projectName.ise") then return false; end;
				if ~tcl.Cmd("file delete -force $projectName.xise") then return false; end;
				if ~tcl.Cmd("project new $projectName.xise") then return false; end;
				opened := true;
				if ~tcl.Cmd("project set family " & target.pldPart.family^) then return false; end;
				if ~tcl.Cmd("project set device " & target.pldPart.device^) then return false; end;
				if ~tcl.Cmd("project set package " & target.pldPart.package^) then return false; end;
				if ~tcl.Cmd("project set speed " & target.pldPart.speedGrade^) then return false; end;

				(*
					add the top level source
				*)
				str := architecture.acName^ & ".v";
				if ~tcl.Cmd("file delete -force " & str) then return false; end; (*! remove old file version *)
				if ~tcl.Cmd("xfile add ../" & str & " -copy") then return false; end;

				(*
					add generated clocks
				*)
				if ~tcl.Cmd("file delete -force " & architecture.acName^ &"Clocks.v") then return false; end;
				if ~tcl.Cmd("xfile add ../"& architecture.acName^&"Clocks.v -copy") then return false; end;

				(*
					add all other project files
				*)
				for i := 0 to hdlSources.Length()-1 do
					dep := hdlSources.Get(i)(HdlBackend.Dependency);
					if dep.included & ~dep.topLevel then
						if ~tcl.Cmd("file delete -force " & dep.name^) then return false; end; (*! remove old file version *)
						str := "xfile add " & dep.pathName^;
						if dep.makeLocalCopy or Strings.StartsWith2(path^,dep.pathName^) then str := str & " -copy"; end;
						if ~tcl.Cmd(str) then return false; end;
					end;
				end;

				(*
					add the constraints file
				*)
				if constraintsFingerprint # "" then
					str := architecture.acName^ & ".ucf";
					if ~tcl.Cmd("file delete -force " & str) then return false; end; (*! remove old file version *)
					if ~tcl.Cmd("xfile add ../" & str & " -copy") then return false; end;
				end;

				(*
					setup the project properties
				*)
				if ~tcl.Cmd('project set "Top" ' & architecture.acName^) then return false; end;
				if ~tcl.Cmd('project set "Optimization Goal" Speed') then return false; end;
				if ~tcl.Cmd('project set "Optimization Effort" High') then return false; end;
				if ~tcl.Cmd('project set "Keep Hierarchy" No') then return false; end;
				if ~tcl.Cmd('project set "Placer Effort Level" High') then return false; end;
				if ~tcl.Cmd('project set "Placer Extra Effort" Normal') then return false; end;
				if ~tcl.Cmd('project set "Register Duplication" "true" -process "Synthesize - XST"') then return false; end;
				if ~tcl.Cmd('project set "Optimization Strategy (Cover Mode)" Speed') then return false; end;
				if Strings.StartsWith2("Spartan3",target.pldPart.family^) then
					if ~tcl.Cmd('project set "Place And Route Mode" "Normal Place and Route"') then return false; end;
				else
					if ~tcl.Cmd('project set "Place And Route Mode" "Route Only"') then return false; end;
				end;
				if ~tcl.Cmd('project set "Place & Route Effort Level (Overall)" High') then return false; end;
				if ~tcl.Cmd('project set "Extra Effort(Highest PAR level only)" Normal') then return false; end;

				if target.spiCfgWidth > 0 then
					if ~tcl.Cmd('project set "Set SPI Configuration Bus Width" ' & target.spiCfgWidth) then return false; end;
				end;

				(*
					Enable multi-threading
				*)
				if Machine.NumberOfProcessors() > 1 then
					if ~tcl.Cmd('project set "Enable Multi-Threading" 2 -process Map') then return false; end;
					if ~tcl.Cmd('project set "Enable Multi-Threading" ' & min(4,Machine.NumberOfProcessors()) & ' -process "Place & Route"') then return false; end;
				end;

				if ~GenerateBmmFile() then
					return false;
				end;

			end;

			return true;

		finally
			ErrorUnexpected; return false;
		end GenerateProject;

		procedure DefineIo(w: Streams.Writer; const portName: array of char; index: size; expectedDirection: integer; io: HdlBackend.PldIo): boolean;
		begin
			with io : HdlBackend.IoPin do
				if (io.direction # HdlBackend.Inout) & (expectedDirection # io.direction) then
					Error("",Streams.Invalid,HdlBackend.ErrInvalidValue,'IO "' & portName & '" direction (' & io.direction &  ') does not match with the corresponding port direction (' & expectedDirection & ')');
					return false;
				end;
				if index >= 0 then
					w.String('NET "' & portName & "<" & index & ">" & '" LOC="' & io.location^ & '" | IOSTANDARD="' & io.ioStandard^ & '"');
				else
					w.String('NET "' & portName & '" LOC="' & io.location^ & '" | IOSTANDARD="' & io.ioStandard^ & '"');
				end;
				if io.pullType = HdlBackend.PullUp then w.String(' | PULLUP');
				elsif io.pullType = HdlBackend.PullDown then w.String(' | PULLDOWN');
				end;
				w.Char(";"); w.Ln;
			else
				Error("",Streams.Invalid,HdlBackend.ErrNotImplemented,"handling of differential pairs is not yet implemented");
				return false;
			end;

			return true;
		end DefineIo;

		procedure DefineClock(w: Streams.Writer; const clockName, portName: array of char; clock: HdlBackend.Clock): boolean;
		var
			io: HdlBackend.PldIo;
			period, dutyCycle: array 128 of char;
		begin
			Strings.FloatToStr(1.0D9/clock.frequency,0,3,0,period); Strings.TrimWS(period);
			Strings.FloatToStr(clock.dutyCycle,0,3,0,dutyCycle); Strings.TrimWS(dutyCycle);

			if clock.source is HdlBackend.PldIo then
				io := clock.source(HdlBackend.PldIo);
				if ~DefineIo(w,portName,-1,HdlBackend.In,io) then return false; end;
			end;

			w.String('NET "' & portName & '" TNM_NET = "' & portName & '";'); w.Ln;
			w.String('TIMESPEC "TS_' & clockName & '" = PERIOD "' & portName & '" ' & period & "ns HIGH " & dutyCycle & "%;");

			return true;
		end DefineClock;

		(*
			Generate constraints (.UCF) file
		*)
		procedure GenerateConstraints(): boolean;
		begin
			return ProjGenerateConstraints(self,DefineIo,DefineClock);
		end GenerateConstraints;

		procedure CheckForConstraintsModifications(): boolean;
		begin
			return ProjCheckForConstraintsModifications(self);
		end CheckForConstraintsModifications;

		procedure ImplementArchitecture(): boolean;
		begin

			if ~hdlSourcesUnchanged then

				if ~tcl.Cmd('process run "Synthesize - XST"') then return false; end;
				if ~tcl.Cmd('if {([process get "Synthesize - XST" status] != "up_to_date") && ([process get "Synthesize - XST" status] != "warnings")} {error "ERROR: failed to synthesize the design"}') then
					return false;
				end;

			end;

			if ~hdlSourcesUnchanged or ~constraintsUnchanged then

				if ~tcl.Cmd('process run "Implement Design"') then return false; end;
				if ~tcl.Cmd('if {([process get "Implement Design" status] != "up_to_date") && ([process get "Implement Design" status] != "warnings")} {error "ERROR: failed to implement the design"}') then
					return false;
				end;

				if ~tcl.Cmd('process run "Generate Programming File"') then return false; end;
				if ~tcl.Cmd('if {([process get "Generate Programming File" status] != "up_to_date") && ([process get "Generate Programming File" status] != "warnings")} {error "ERROR: failed to generate programming file"}') then
					return false;
				end;

			end;

			if ~PatchBitstream() then return false; end;

			return true;

		finally
			ErrorUnexpected; return false;
		end ImplementArchitecture;

		procedure TraverseWriteProcessorBmm(c: HdlBackend.Cell; param: any): boolean;
		begin
			with c : HdlBackend.Processor do
				if (c.acName^ = "TRM") or (c.acName^ = "TRMNIO") then
					return WriteTrmBmm(self, bmmw, c);
				else
					return true;
				end;
			else
				return true;
			end;
		end TraverseWriteProcessorBmm;

		procedure GenerateBmmFile(): boolean;
		var
			file: Files.File;
			fw: Files.Writer;
			emptyBmm: boolean;
			fileName: Files.FileName;
			str: HdlBackend.LongString;
		begin
			Files.JoinPath(path^,architecture.acName^ & ".bmm",fileName);
			file := Files.New(fileName); assert(file # nil);
			Files.Register(file);
			Files.OpenWriter(fw,file,0);
			bmmw := fw;

			if ~architecture.TraverseCells(TraverseWriteProcessorBmm,false,nil) then
				return false;
			end;

			emptyBmm := file.Length() = 0;
			file.Close;

			if ~emptyBmm then
				str := architecture.acName^ & ".bmm";
				if ~tcl.Cmd("file delete -force " & str) then return false; end; (*! remove old file version *)
				if ~tcl.Cmd("xfile add ../" & str & " -copy") then return false; end;
				if ~tcl.Cmd('project set "Other Ngdbuild Command Line Options" "-bm ' & architecture.acName^ & '.bmm' & '"') then return false; end;
			end;

			return true;

		finally
			if file # nil then file.Close; end;
			return false;
		end GenerateBmmFile;

		procedure TraversePatchBitstream(c: HdlBackend.Cell; param: any): boolean;
		begin
			with c : HdlBackend.Processor do
				if (c.acName^ = "TRM") or (c.acName^ = "TRMNIO") then
					return PatchTrmMemories(self,c,patchedBitstreamIndex,tcl.Cmd);
				else
					return true;
				end;
			else
				return true;
			end;
		end TraversePatchBitstream;

		procedure PatchBitstream(): boolean;
		var
			str: HdlBackend.LongString;
		begin

			patchedBitstreamIndex := 0;
			if ~tcl.Cmd("file copy -force " & architecture.acName^ & ".bit ../" & architecture.acName^ & "0.bit") then return false; end;
			if ~architecture.TraverseCells(TraversePatchBitstream,false,nil) then
				return false;
			end;
			if ~tcl.Cmd("file copy -force ../" & architecture.acName^ & patchedBitstreamIndex & ".bit ../" & architecture.acName^ & ".bit") then return false; end;

			if Strings.StartsWith2("Spartan3",target.pldPart.family^) then
				str := "exec promgen -w -p bin -data_width 8 -b -u 0x0 " & "../" & architecture.acName^ & ".bit";
			else
				str := "exec promgen -w -p bin -data_width 32 -b -u 0x0 " & "../" & architecture.acName^ & ".bit";
			end;
			if ~tcl.Cmd(str) then
				ClearError;
				(*return false;*)
			end;

			return true;

		finally
			return false;
		end PatchBitstream;

		procedure ImpactCmd(const cmd: array of char; timeout: signed32): boolean;
		var
			t: signed32;
			str: HdlBackend.LongString;
			lastMsgType: signed32;

			procedure ProcessOutputStream(): boolean;
			begin
				while impact.shIn.Available() > 0 do
					if impact.shIn.Available() > 1 then
						impact.shIn.Ln(str);
						(*KernelLog.Enter; KernelLog.String(str); KernelLog.Ln; KernelLog.Exit;*)
					elsif (impact.shIn.Available() = 1) & (impact.shIn.Peek() = ">") then (*! command processing is finished *)
						str[0] := impact.shIn.Get();
						ProcessErrorStream;
						return false;
					end;
				end;

				return true;
			end ProcessOutputStream;

			procedure ProcessErrorStream;
			begin
				while impact.shErr.Available() > 0 do
					impact.shErr.Ln(str);
					(*KernelLog.Enter; KernelLog.String("ERR:"); KernelLog.String(str); KernelLog.Ln; KernelLog.Exit;*)
					if Strings.StartsWith2("INFO:",str) then
						Strings.Delete(str,0,5);
						Information("",Streams.Invalid,Streams.Invalid,str);
						lastMsgType := InfoMsg;
					elsif Strings.StartsWith2("WARNING:",str) then
						Strings.Delete(str,0,8);
						Warning("",Streams.Invalid,Streams.Invalid,str);
						lastMsgType := WarningMsg;
					elsif Strings.StartsWith2("ERROR:",str) then
						Strings.Delete(str,0,6);
						Error("",Streams.Invalid,Streams.Invalid,str);
						lastMsgType := ErrorMsg;
					else
						case lastMsgType of
							|InfoMsg: Information("",Streams.Invalid,Streams.Invalid,str);
							|WarningMsg: Warning("",Streams.Invalid,Streams.Invalid,str);
							|ErrorMsg: Error("",Streams.Invalid,Streams.Invalid,str);
						end;
					end;
				end;
			end ProcessErrorStream;

		begin
			KernelLog.String('executing iMPACT command: "' & cmd & '"'); KernelLog.Ln;
			if cmd # "" then
				impact.shOut.String(cmd); impact.shOut.Ln; impact.shOut.Update;
			end;
			t := Kernel.GetTicks();
			lastMsgType := -1;
			while Kernel.GetTicks() - t < timeout do
				if ~ProcessOutputStream() then return res = 0; end;
				ProcessErrorStream;
				sleep.Sleep(10);
			end;

			Error("",Streams.Invalid,HdlBackend.ErrTimeoutExpired,"timeout (" & timeout & " ms) " & 'expired while executing iMPACT command "' & cmd & '"');
			return false;

		finally
			return false;
		end ImpactCmd;

		procedure DeployViaJtag(): boolean;
		var
			str: Files.FileName;

			procedure QuitImpact;
			begin
				impact.shOut.String("quit"); impact.shOut.Ln; impact.shOut.Update;
			end QuitImpact;

		begin
			if impact = nil then
				PathTools.JoinPath(iseBinPath,"impact.exe -batch",str);
				new(impact,shellBinPath,4096,4096,4096);
				impact.AddParameter("/c " & str);
				if ~impact.Execute(true) then
					Error("",Streams.Invalid,HdlBackend.ErrUnexpected,'failed to start Xilinx ISE iMPACT shell');
					return false;
				end;
			end;

			new(sleep);
			(*! wait until iMPACT starts and prints ">" *)
			if ~ImpactCmd("",5000) then QuitImpact; return false; end;

			if ~ImpactCmd("setMode -bscan",3000) then QuitImpact; return false; end;
			if ~ImpactCmd("setCable -p auto",10000) then QuitImpact; return false; end;
			if ~ImpactCmd("identify",10000) then QuitImpact; return false; end;

			Files.JoinPath(path^,architecture.acName^ & ".bit",str);
			if ~ImpactCmd("assignfile -p " & (target.pldPart.jtagChainIndex+1) & " -file " & str,5000) then QuitImpact; return false; end;
			if ~ImpactCmd("program -p " & (target.pldPart.jtagChainIndex+1),30000) then QuitImpact; return false; end;

			QuitImpact;

			return true;
		finally
			return false;
		end DeployViaJtag;

		procedure DeployArchitecture(): boolean;
		begin
			return DeployViaJtag();
		finally
			return false;
		end DeployArchitecture;

		procedure CloseProject();
		begin
			if opened then
				if ~tcl.Cmd("project close") then end;
				opened := false;
			end;
			if tcl # nil then
				tcl.shOut.String("exit"); tcl.shOut.Ln; tcl.shOut.Update;
			end;
			return;
		finally
			ErrorUnexpected;
		end CloseProject;

	end IseProject;

	(*
		Xilinx ISE TCL shell application
	*)
	VivadoTclShell = object(HdlBackend.Shell)
	var
		ctx: HdlBackend.Context;
		sleep: Kernel.Timer;

		procedure &InitIseTclShell(
										const shellAppPathName: array of char;
										context: HdlBackend.Context;
										outBufSize, inBufSize, errBufSize: size
										);
		begin
			ctx := context;
			InitShell(shellAppPathName,outBufSize,inBufSize,errBufSize);
			new(sleep);
		end InitIseTclShell;

		procedure ProcessMessage(var str: array of char);
		begin
			if Strings.StartsWith2("INFO:",str) then
				Strings.Delete(str,0,5);
				ctx.Information("",Streams.Invalid,Streams.Invalid,str);
			elsif Strings.StartsWith2("WARNING:",str) then
				Strings.Delete(str,0,8);
				ctx.Warning("",Streams.Invalid,Streams.Invalid,str);
			elsif Strings.StartsWith2("ERROR:",str) then
				Strings.Delete(str,0,6);
				ctx.Error("",Streams.Invalid,HdlBackend.ErrExternal,str);
			else
				KernelLog.String(str); KernelLog.Ln;
			end;
		end ProcessMessage;

		(* Execute a TCL command *)
		procedure Cmd(const cmd: array of char): boolean;
		var resultStr: array 1 of char;
		begin
			return CmdRet(cmd,resultStr);
		end Cmd;

		(* Execute a TCL command that returns a string value *)
		procedure CmdRet(const cmd: array of char; var retStr: array of char): boolean;
		var
			i: size;
			str: HdlBackend.LongString;
			continue: boolean;

			procedure ProcessOutputStream(): boolean;
			begin
				while shIn.Available() > 0 do
					shIn.Ln(str);
					KernelLog.String("OUT:"); KernelLog.String(str); KernelLog.Ln;
					if Strings.StartsWith2("TCL_",str) then
						return false;
					else
						ProcessMessage(str);
					end;
				end;
				return true;
			end ProcessOutputStream;

			procedure ProcessErrorStream;
			begin
				while shErr.Available() > 0 do
					shErr.Ln(str);
					KernelLog.String("ERR:"); KernelLog.String(str); KernelLog.Ln;
					ProcessMessage(str);
				end;
			end ProcessErrorStream;

		begin
			KernelLog.String('executing TCL command "'); KernelLog.String(cmd); KernelLog.Char('"'); KernelLog.Ln;

			shOut.String("if {[catch {");
			shOut.String(cmd);
			shOut.String("} ret]} {puts TCL_ERROR:$ret} else {puts TCL_OK:$ret}");
			shOut.Ln; shOut.Update;

			continue := true;
			while (ctx.res = 0) & continue do
				ProcessErrorStream;
				continue := ProcessOutputStream();
				if continue then sleep.Sleep(10); end;
			end;

			if ctx.res # 0 then
				ctx.ErrorUnexpected; return false;
			end;

			if Strings.StartsWith2("TCL_OK",str) then
				if len(retStr) > 1 then
					Strings.Delete(str,0,7);
					copy(str,retStr);
				end;
			else
				i := Strings.IndexOfByte(":",10,str);
				if i = -1 then i := 9; end;
				Strings.Delete(str,0,i+1);
				ctx.Error("",Streams.Invalid,HdlBackend.ErrExternal,str);
				return false;
			end;

			return ctx.res = 0;

		finally
			ctx.ErrorUnexpected; return false;
		end CmdRet;

	end VivadoTclShell;

	(**
		Xilinx VIVADO project
	*)
	VivadoProject* = object(HdlBackend.HdlProject)
	var
		opened: boolean;

		bmmw: Streams.Writer;
		patchedBitstreamIndex: size;

		xilProjPath: Files.FileName;

		tcl: VivadoTclShell;

		procedure &InitVivadoProject*(const architectureName: array of char; targetDev: HdlBackend.TargetDevice; codeGenerator: HdlBackend.HdlCodeGenerator; const projectPath: array of char; diag: Diagnostics.Diagnostics);
		var
			str: Files.FileName;
		begin
			InitHdlProject(architectureName,targetDev,codeGenerator,projectPath,diag);
			if res # 0 then return; end;

			(*
				Open vivado for executing TCL project-specific commands
			*)
			
			
			if hostOS = Windows then
				PathTools.JoinPath(vivadoBinPath,"vivado.bat -mode tcl",str);   (*on windows it's .bat, not just vivado*)
				new(tcl,shellBinPath,self,4096,4096,4096);
				tcl.AddParameter("/c " & str);  (*does windows really need this?*)
			else
				new(tcl,shellBinPath,self,4096,4096,4096);
				PathTools.JoinPath(vivadoBinPath,"vivado",str);
				tcl.AddParameter(str);
				tcl.AddParameter("-mode");
				tcl.AddParameter("tcl");
			end;
			
			if ~tcl.Execute(true) then
				tcl := nil;
				Error("",Streams.Invalid,HdlBackend.ErrUnexpected,'failed to start Xilinx Vivado TCL shell');
				return;
			end;

			PathTools.JoinPath(path^,"Vivado",xilProjPath);
			if ~PathTools.DirectoryExists(xilProjPath,xilProjPath) & ~PathTools.CreateDirectory(xilProjPath,xilProjPath) then
				Error("",Streams.Invalid,HdlBackend.ErrUnexpected,'failed to create directory "' & xilProjPath & '"!');
				return;
			end;

			return;

		finally
			ErrorUnexpected;
		end InitVivadoProject;

		procedure GenerateClocks(w: Streams.Writer; synthesizer: HdlBackend.Cell): boolean;
		begin
			return ProjGenerateClocks(self,w,synthesizer);
		end GenerateClocks;

		procedure GenerateProject(): boolean;
		var
			i: size;
			dep: HdlBackend.Dependency;
			str: HdlBackend.LongString;
		begin

			if ~tcl.Cmd("set_param general.maxThreads " & min(Machine.NumberOfProcessors(),8)) then return false; end; (*vivado doesn't allow over 8 hw threads*)

			(*
				Create VIVADO project
			*)
			if ~tcl.Cmd("cd " & xilProjPath) then return false; end;

			if ~hdlSourcesUnchanged or ~constraintsUnchanged then

				if ~tcl.Cmd("create_project -force " & architecture.acName^) then return false; end;
				opened := true;
				if ~tcl.Cmd("set_property part " & target.pldPart.device^ & target.pldPart.package^ & target.pldPart.speedGrade^ & " [current_project]") then return false; end;

				(*
					add the top level source
				*)
				if ~tcl.Cmd("add_files -force ../" & architecture.acName^ & ".v -copy_to ./") then return false; end;
				
				(*
					add generated clocks
				*)
				if ~tcl.Cmd("add_files -force ../"&architecture.acName^&"Clocks.v -copy_to ./") then return false; end;

				(*
					add all other project files
				*)
				for i := 0 to hdlSources.Length()-1 do
					dep := hdlSources.Get(i)(HdlBackend.Dependency);
					if dep.included (*& ~Strings.StartsWith2("Ac3Projects",dep.pathName^)*) then   (*todo: do properly or better still don't add the top level source to the dependencies in the first place*)
						str := "add_files -force ";
						str := str & dep.pathName^;
						if dep.makeLocalCopy or Strings.StartsWith2(path^,dep.pathName^) then
							str := str & " -copy_to ./";
						end;
						if ~tcl.Cmd(str) then return false; end;
					end;
				end;

				(*
					add the constraints file
				*)
				if constraintsFingerprint # "" then
					if ~tcl.Cmd("add_files -force ../" & architecture.acName^ & ".xdc -copy_to ./") then return false; end;
				end;

				if ~tcl.Cmd("set_property top " & architecture.acName^ & " [current_fileset]") then return false; end;

			end;

			return true;

		finally
			ErrorUnexpected; return false;
		end GenerateProject;

		procedure DefineIo(w: Streams.Writer; const portName: array of char; index: size; expectedDirection: integer; io: HdlBackend.PldIo): boolean;
		var pName: HdlBackend.LongString;
		begin
			with io : HdlBackend.IoPin do
				if (io.direction # HdlBackend.Inout) & (expectedDirection # io.direction) then
					Error("",Streams.Invalid,HdlBackend.ErrInvalidValue,'IO "' & portName & '" direction (' & io.direction &  ') does not match with the corresponding port direction (' & expectedDirection & ')');
					return false;
				end;
				if index >= 0 then pName := portName & "[" & index & "]";
				else copy(portName,pName);
				end;
				w.String("set_property PACKAGE_PIN " & io.location^ & " [get_ports " & pName & "]"); w.Ln;
				w.String("set_property IOSTANDARD " & io.ioStandard^ & " [get_ports " & pName & "]"); w.Ln;
				if io.pullType = HdlBackend.PullUp then
					w.String("set_property PULLUP TRUE " & "[get_ports " & pName & "]"); w.Ln;
				elsif io.pullType = HdlBackend.PullDown then
					w.String("set_property PULLDOWN TRUE " & "[get_ports " & pName & "]"); w.Ln;
				end;
			else
				Error("",Streams.Invalid,HdlBackend.ErrNotImplemented,"handling of differential pairs is not yet implemented");
				return false;
			end;

			return true;
		end DefineIo;

		procedure DefineClock(w: Streams.Writer; const clockName, portName: array of char; clock: HdlBackend.Clock): boolean;
		var
			io: HdlBackend.PldIo;
			period, pulseWidth: array 128 of char;
		begin
			Strings.FloatToStr(1.0D9/clock.frequency,0,3,0,period); Strings.TrimWS(period);
			Strings.FloatToStr((clock.dutyCycle/100)*(1.0D9/clock.frequency),0,3,0,pulseWidth); Strings.TrimWS(pulseWidth);
			if clock.source is HdlBackend.PldIo then
				io := clock.source(HdlBackend.PldIo);
				if ~DefineIo(w,portName,-1,HdlBackend.In,io) then return false; end;
				w.String("create_clock -name " & clockName & " -period " & period & " [get_ports " & portName & "] -waveform {0.000 " & pulseWidth & "}"); w.Ln;
			else
				w.String("create_clock -name " & clockName & " -period " & period & " [get_nets " & portName & "] -waveform {0.000 " & pulseWidth & "}"); w.Ln;
			end;

			return true;
		end DefineClock;

		procedure GenerateConstraints(): boolean;
		begin
			return ProjGenerateConstraints(self,DefineIo,DefineClock);
		end GenerateConstraints;

		procedure CheckForConstraintsModifications(): boolean;
		begin
			return ProjCheckForConstraintsModifications(self);
		end CheckForConstraintsModifications;

		procedure ImplementArchitecture(): boolean;
		begin

			if ~hdlSourcesUnchanged or ~constraintsUnchanged then (*!TODO: implement conditional resynthesis and reimplementation *)

				if ~tcl.Cmd("launch_runs [current_run] -to_step write_bitstream") then return false; end;
				if ~tcl.Cmd("wait_on_run [current_run]") then return false; end;

				if ~tcl.Cmd('if {[get_property PROGRESS [get_runs [current_run]]] != "100%"} {error "ERROR: [get_property CURRENT_STEP [get_runs [current_run]]] failed"}') then
					return false;
				end;


				if ~tcl.Cmd("open_run impl_1") then return false; end;

				(* setup SPI configuration width if required *)
				if target.spiCfgWidth > 0 then
					if ~tcl.Cmd("set_property BITSTREAM.CONFIG.SPI_BUSWIDTH " &  target.spiCfgWidth & " [current_design]") then return false; end;
				end;

				(* generate BMM file required for patching with data2mem *)
				if ~GenerateBmmFile() then return false; end;

			end;

			if ~PatchBitstream() then return false; end;

			return true;

		finally
			ErrorUnexpected; return false;
		end ImplementArchitecture;

		procedure TraverseWriteProcessorBmm(c: HdlBackend.Cell; param: any): boolean;
		begin
			with c : HdlBackend.Processor do
				if (c.acName^ = "TRM") or (c.acName^ = "TRMNIO") then
					return WriteTrmBmm(self, bmmw, c);
				else
					return true;
				end;
			else
				return true;
			end;
		end TraverseWriteProcessorBmm;

		procedure GenerateBmmFile(): boolean;
		var
			file: Files.File;
			fw: Files.Writer;
			fileName: Files.FileName;
		begin
			Files.JoinPath(xilProjPath,architecture.acName^ & "_bd.bmm",fileName);
			file := Files.New(fileName); assert(file # nil);
			Files.Register(file);
			Files.OpenWriter(fw,file,0);
			bmmw := fw;

			if ~architecture.TraverseCells(TraverseWriteProcessorBmm,false,nil) then
				return false;
			end;

			file.Close;

			return true;

		finally
			if file # nil then file.Close; end;
			return false;
		end GenerateBmmFile;

		procedure TraversePatchBitstream(c: HdlBackend.Cell; param: any): boolean;
		begin
			with c : HdlBackend.Processor do
				if (c.acName^ = "TRM") or (c.acName^ = "TRMNIO") then
					return PatchTrmMemories(self,c,patchedBitstreamIndex,tcl.Cmd);
				else
					return true;
				end;
			else
				return true;
			end;
		end TraversePatchBitstream;

		procedure PatchBitstream(): boolean;
		begin

			patchedBitstreamIndex := 0;
			if ~tcl.Cmd("file copy -force " & architecture.acName^ & ".runs/impl_1/" & architecture.acName^ & ".bit ../" & architecture.acName^ & "0.bit") then return false; end;

			if ~architecture.TraverseCells(TraversePatchBitstream,false,nil) then
				return false;
			end;

			if ~tcl.Cmd("file copy -force ../" & architecture.acName^ & patchedBitstreamIndex & ".bit ../" & architecture.acName^ & ".bit") then return false; end;

			(*if ~tcl.Cmd("exec promgen -w -p bin -data_width 32 -b -u 0x0 " & "../" & architecture.acName^ & ".bit") then
				ClearError;
				(*return false;*)
			end;*)
			if ~tcl.Cmd('write_cfgmem -force -format bin -disablebitswap -interface SMAPx32 -loadbit "up 0x0 ../' & architecture.acName^ & '.bit" ../' & architecture.acName^ & ".bin") then
				return false;
			end;

			if ~tcl.Cmd("file delete -force ../" & architecture.acName^ & "0.bit") or ~tcl.Cmd("file delete -force ../" & architecture.acName^ & "1.bit") then
				return false;
			end;

			return true;

		finally
			return false;
		end PatchBitstream;

		procedure DeployViaJtag(): boolean;
		begin

			if ~tcl.Cmd("open_hw") then return false; end;
			if ~tcl.Cmd("connect_hw_server") then return false; end;
			(* open HW target with index 0 *)
			if ~tcl.Cmd("open_hw_target [lindex [get_hw_targets] 0]") then return false; end;
			if ~tcl.Cmd("set_property PROGRAM.FILE {../" & architecture.acName^ & ".bit" & "} [lindex [get_hw_devices] " & target.pldPart.jtagChainIndex & "]") then return false; end;
			if ~tcl.Cmd("program_hw_devices " & "[lindex [get_hw_devices] " & target.pldPart.jtagChainIndex & "]") then return false; end;
			return true;
		finally
			return false;
		end DeployViaJtag;

		procedure DeployArchitecture(): boolean;
		begin
			return DeployViaJtag();
		finally
			return false;
		end DeployArchitecture;

		procedure CloseProject();
		begin
			if opened then
				if ~tcl.Cmd("close_project") then end;
				opened := false;
			end;
			if tcl # nil then
				tcl.shOut.String("exit"); tcl.shOut.Ln; tcl.shOut.Update;
			end;
			return;
		finally
			ErrorUnexpected;
		end CloseProject;

	end VivadoProject;

	procedure ProjGenerateClocks(proj: HdlBackend.HdlProject; w: Streams.Writer; synthesizer: HdlBackend.Cell): boolean;
	var
		derivedClock: HdlBackend.DerivedClock;
		cgen: AcVerilogCodeGen.VerilogCodeGenerator;
		pIn: HdlBackend.ClockInputPort;
		pOutList: HdlBackend.PortList;
		pOut: HdlBackend.ClockOutputPort;
		i, j: size;
		pInName: HdlBackend.LongString;
	begin
		new(cgen);
		cgen.SetWriter(w);

		assert(synthesizer.inputs = nil);
		assert((synthesizer.outputs = nil) or (synthesizer.outputs.Length() = 1));

		cgen.DeclareModule(synthesizer);
		cgen.w.Update;

		new(pOutList,4);

		for i := 0 to synthesizer.clockInputs.Length()-1 do

			pIn := synthesizer.clockInputs.GetPort(i)(HdlBackend.ClockInputPort);

			if pIn.clock.source is HdlBackend.PldIo then (* external clock *)
				copy(pIn.hdlName^,pInName);
			else (* internal clock *)
				assert(pIn.clock.source is HdlBackend.ClockOutputPort);

				(*
					Bufferize the internal clock signal
				*)
				pInName := pIn.hdlName^ & "_buf";
				cgen.Format('(* keep = "soft" *) wire ' & pIn.hdlName^ & "_net = " & pIn.hdlName^ & ";\\");
				cgen.Format("wire " & pInName & ";\\");
				cgen.Format("BUFG buf_" & pIn.hdlName^ & "(.I(" & pIn.hdlName^ & "_net),.O(" & pInName & "));\\");
			end;

			pOutList.Clear;
			for j := 0 to synthesizer.clockOutputs.Length()-1 do
				pOut := synthesizer.clockOutputs.GetPort(j)(HdlBackend.ClockOutputPort);
				derivedClock := pOut(HdlBackend.ClockOutputPort).clock(HdlBackend.DerivedClock);
				if derivedClock.refClock = pIn.clock then
					pOutList.Add0(pOut);
				end;
			end;

			if pOutList.Length() = 1 then (* 1 input clock -> 1 output clock *)
				pOut := pOutList.GetPort(0)(HdlBackend.ClockOutputPort);
				derivedClock := pOut(HdlBackend.ClockOutputPort).clock(HdlBackend.DerivedClock);
				assert(derivedClock.refClock = pIn(HdlBackend.ClockInputPort).clock);
				if (derivedClock.mulFactor = 1) & (derivedClock.divFactor = 1) & (derivedClock.phase = 0) then
					cgen.Format("assign " & pOut.hdlName^ & " = " & pInName & ";\\");
				else
					proj.Error("",Streams.Invalid,HdlBackend.ErrNotImplemented,"generation of derived clocks is not yet implemented");
					return false;
				end;
			else
				proj.Error("",Streams.Invalid,HdlBackend.ErrNotImplemented,"generation of multiple clock outputs is not yet implemented");
				return false;
			end;

		end;

		cgen.w.Ln;
		cgen.EndModule;
		cgen.w.Update;

		return proj.res = 0;

	finally
		proj.ErrorUnexpected; return false;
	end ProjGenerateClocks;

	procedure DefineExternalPorts(
											proj: HdlBackend.HdlProject;
											w: Streams.Writer;
											ports: HdlBackend.PortList;
											defineIo: procedure{DELEGATE}(w: Streams.Writer; const portName: array of char; index: size; expectedDirection: integer; io: HdlBackend.PldIo): boolean
											): boolean;
	var
		i, j, n: size;
		p, p1: HdlBackend.Port;

		procedure DefinePort(const portName: array of char; p: HdlBackend.Port): boolean;
		var
			ioSetup: HdlBackend.IoSetup;
			ioPort: HdlBackend.PldIoList;
			c: HdlBackend.Cell;
		begin
			with p : HdlBackend.CellnetPort do (*! hierarchical handling of external ports *)
				assert(p.delegatedTo.Length()=1); (*! each port must be delegated to only one component port  *)
				(*if p.GetCell()(HdlBackend.Cellnet).level > 0 then assert(p.ios = nil); end;*)
				return DefinePort(portName,p.delegatedTo.GetPort(0));
			else

				with p : HdlBackend.HdlPort do

					assert(p.isExternal);

					c := p.GetCell();
					if c.acName^ # "ZynqPs7" then (*! do not define the constraints for dedicated IOs of ZynqPs7 *)

						ioSetup := proj.target.GetIoSetupByName(c.acName^ & "_" & c.instId);
						if ioSetup = nil then
							proj.Error("",Streams.Invalid,HdlBackend.ErrNotDefined,'IO setup with name "' & c.acName^ & "_" & c.instId & '" is not defined');
							return false;
						end;
						ioPort := ioSetup.GetIoPortByName(p.acName^);
						if ioPort = nil then
							proj.Error("",Streams.Invalid,HdlBackend.ErrNotDefined,'IO port with name "' & p.acName^ & '" is not defined in IO setup "' & ioSetup.name^ & '"');
							return false;
						end;
						if ioPort.Length() < p.width then
							proj.Error("",Streams.Invalid,HdlBackend.ErrNotDefined,'IO port "' & p.acName^ & '" has width smaller than the corresponding HDL port "' & c.acName^ & "." & p.acName^ & '"');
							return false;
						end;
						w.String("# " & ioSetup.name^ & "." & ioPort.name^); w.Ln;
						if p.width > 1 then
							for j := 0 to p.width-1 do
								if ~defineIo(w,portName,j,p.direction,ioPort.GetIo(j)) then return false; end;
							end;
						else
							if ~defineIo(w,portName,-1,p.direction,ioPort.GetIo(0)) then return false; end;
						end;
						w.Ln;
					end;

				else
					halt(100);
				end;

			end;

			return true;
		end DefinePort;

	begin
		n := ports.Length();
		for i := 0 to n-1 do
			p := ports.GetPort(i);

			if (p.hdlName^ # HdlBackend.MainClockInputName) & ((p.hdlName^ # HdlBackend.MainResetInputName)) then
				if ~DefinePort(p.hdlName^,p) then
					return false;
				end;
			end;

		end;

		return true;
	end DefineExternalPorts;

	procedure ProjGenerateConstraints(
													proj: HdlBackend.HdlProject;
													defineIo: procedure{DELEGATE}(w: Streams.Writer; const portName: array of char; index: size; expectedDirection: integer; io: HdlBackend.PldIo): boolean;
													defineClock: procedure{DELEGATE}(w: Streams.Writer; const clockName, portName: array of char; clock: HdlBackend.Clock): boolean
													): boolean;
	var
		file: Files.File;
		fw: Files.Writer;
		emptyFile: boolean;
		fileName: Files.FileName;
		clockInput: HdlBackend.ClockInputPort;
		i: size;
	begin
		if proj is IseProject then (* ISE *)
			Files.JoinPath(proj.path^,proj.architecture.acName^ & ".ucf",fileName);
		else (* Vivado *)
			Files.JoinPath(proj.path^,proj.architecture.acName^ & ".xdc",fileName);
		end;

		file := Files.New(fileName); assert(file # nil);
		Files.Register(file);
		Files.OpenWriter(fw,file,0);

		if proj.architecture.mainResetInput # nil then
			fw.String("# External system reset"); fw.Ln;
			if ~defineIo(fw,proj.architecture.mainResetInput.acName^,-1,HdlBackend.In,proj.architecture.mainResetInput(HdlBackend.CellnetPort).ios.GetIo(0)) then return false; end;
			fw.Ln;
		end;

		if proj.architecture.ports # nil then
			if ~DefineExternalPorts(proj,fw,proj.architecture.ports,defineIo) then return false; end;
		end;

		if proj.architecture.clockSynthesizer # nil then
			fw.String("# clock signals"); fw.Ln;
			for i := 0 to proj.architecture.clockSynthesizer.clockInputs.Length()-1 do
				clockInput := proj.architecture.clockSynthesizer.clockInputs.GetPort(i)(HdlBackend.ClockInputPort);
				if clockInput.clock.source is HdlBackend.PldIo then (* external clock *)
					if ~defineClock(fw,clockInput.clock.name^,clockInput.delegateOf.acName^,clockInput.clock) then return false; end;
				else (* internal clock *)
						if ~defineClock(fw,proj.architecture.clockSynthesizer.hdlInstName^ & "_" & clockInput.hdlName^,proj.architecture.clockSynthesizer.hdlInstName^ & "/" & clockInput.hdlName^ & "_net",clockInput.clock) then return false; end;
				end;
			end;
		end;

		fw.Update;

		emptyFile := file.Length() = 0;
		file.Close;

		if ~emptyFile then
			proj.fingerprintWriter.Reset;
			if ~proj.fingerprintWriter.WriteFile(fileName) then return false; end;
			proj.fingerprintWriter.GetFingerprintStr(proj.constraintsFingerprint);
		else
			proj.constraintsFingerprint := "";
		end;

		return true;

	finally
		if file # nil then file.Close; end;
		return false;
	end ProjGenerateConstraints;

	procedure ProjCheckForConstraintsModifications(proj: HdlBackend.HdlProject): boolean;
	var
		file: Files.File;
		fr: Files.Reader;
		fileName: Files.FileName;
		fingerprint0: HdlBackend.FingerprintStr;
	begin

		if proj.constraintsFingerprint = "" then proj.constraintsUnchanged := true; return true; end;

		Files.JoinPath(proj.path^,proj.architecture.acName^ & "-constr.fng",fileName);
		file := Files.Old(fileName);
		if file # nil then
			Files.OpenReader(fr,file,0);
			fr.String(fingerprint0);
			file.Close;
			proj.constraintsUnchanged := proj.constraintsFingerprint = fingerprint0;
		else
			proj.constraintsUnchanged := false;
		end;

		trace(proj.constraintsFingerprint,fingerprint0,proj.constraintsUnchanged);

		return true;

	finally
		if file # nil then file.Close; end;
		return false;
	end ProjCheckForConstraintsModifications;

	procedure GenerateMemFiles(proj: HdlBackend.HdlProject; const source, dest: array of char; const insBlockWords, dataBlockWords: size; const imb, dmb: size; patchSpartan6: boolean): boolean;
	var instanceName: Files.FileName;
	begin
		(*read input with one integer per line, generate BaseMem files with 36 bits per line each*)
		(*
			source & ".code" --> source & ".code" & <index> (where currently only <index> = 0) --> dest & "_code" & <index> & ".mem"
		*)
		(*! todo: get info about data sizes *)
		Files.JoinExtension(source,"code",instanceName);
		if ~FoxTRMTools.SplitColumns(instanceName,instanceName,18,1,2,proj.diag) then (* will generate one file only in this particular setup *)
				return false;
		end;

		Strings.Append(instanceName, "0");
		if ~FoxTRMTools.DoSplitFiles(instanceName, dest & "_code", "mem", signed32(imb), signed32(insBlockWords), false, false, patchSpartan6, proj.diag) then
			return false;
		end;

		Files.JoinExtension(source,"data",instanceName);
		if ~FoxTRMTools.DoSplitFiles(instanceName, dest & "_data", "mem", signed32(dmb), signed32(dataBlockWords), false, false, false, proj.diag) then
			return false;
		end;
		return true;
	end GenerateMemFiles;

	(*
		Determine location of a BRAM in a Vivado project
	*)
	procedure GetBramLocation(proj: VivadoProject; const bramInstName: array of char; const bramType: array of char; var site: array of char): boolean;
	begin
		if ~proj.tcl.CmdRet("get_property SITE [get_cells " & bramInstName & "]",site) then return false; end;
		assert(Strings.StartsWith2(bramType & "_",site));
		Strings.Delete(site,0,Strings.Length(bramType)+1);
		return true;
	finally
		return false;
	end GetBramLocation;

	(*
		Get TRM instruction and data block sizes
	*)
	procedure GetInsAndDataBlockSize(trm: HdlBackend.Processor; var insBlockSize, dataBlockSize: size);
	var target: HdlBackend.TargetDevice;
	begin
		target := trm.ctx(HdlBackend.HdlProject).target;

		if (target.pldPart.family^ = "Virtex5") or
			(target.pldPart.family^ = "Virtex6") or
			(target.pldPart.family^ = "Artix7") or
			(target.pldPart.family^ = "Kintex7") or
			(target.pldPart.family^ = "Virtex7") or
			(target.pldPart.family^ = "Zynq") then

			insBlockSize := 2048; dataBlockSize := 1024;
		elsif Strings.StartsWith2("Spartan",target.pldPart.family^) then
			insBlockSize := 1024; dataBlockSize := 512;
		else
			trm.ctx.Error("",Streams.Invalid,HdlBackend.ErrNotImplemented,'unsupported PLD family "' & target.pldPart.family^);
			return;
		end;
	end GetInsAndDataBlockSize;

	(*
		Get number of BRAMs for a given memory size

		memorySize: memory size in some elements (instructions in case of code and words in case of data)
		blockSize: BRAM size in the same elements
	*)
	procedure GetNumBrams(memorySize: size; blockSize: size): size;
	begin
		return (memorySize + blockSize-1) div blockSize;
	end GetNumBrams;

	(* Get full hierarchical name of an instance up to the given cellnet scope *)
	procedure GetFullInstanceName(net: HdlBackend.Cellnet; c: HdlBackend.Cell): HdlBackend.LongString;
	var str: HdlBackend.LongString;
	begin
		str := "";
		repeat
			if str # "" then str := c.hdlInstName^ & "/" & str;
			else copy(c.hdlInstName^,str);
			end;
			c := c.GetCellnet();
		until (c =  net) or (c = nil);
		assert(c = net);
		return str;
	end GetFullInstanceName;

	(*
		Write to BMM file for TRM memories implemented based on RAMB36 Block RAM primitives
	*)
	procedure WriteTrmBmmRAMB36(proj: HdlBackend.HdlProject; w: Streams.Writer; trm: HdlBackend.Processor): boolean;
	const
		InsBlockSize = 2048;
		DataBlockSize = 1024;
	var
		i, imb, dmb: size;
		p_CodeMemorySize, p_DataMemorySize: HdlBackend.Property;
		site: array 256 of char;
		trmInstName, trmInstName1: HdlBackend.LongString;
	begin
		assert(trm.acName^ = "TRM");
		p_CodeMemorySize := trm.GetPropertyByAcName("CodeMemorySize");
		p_DataMemorySize := trm.GetPropertyByAcName("DataMemorySize");
		imb := GetNumBrams(size(p_CodeMemorySize.value.ToInteger().val),InsBlockSize);
		dmb := GetNumBrams(size(p_DataMemorySize.value.ToInteger().val),DataBlockSize);

		site := "";

		trmInstName := GetFullInstanceName(proj.architecture,trm);
		HdlBackend.GetHdlNormalizedName(trmInstName,trmInstName1);

		for i := 0 to imb-1 do
			if proj is VivadoProject then (*! determine the location of the BRAM *)
				if ~GetBramLocation(proj(VivadoProject),trmInstName & "/trm/imx/ram[" & i & "].RAMB36_inst","RAMB36",site) then return false; end;
			else
			end;
			w.String("ADDRESS_SPACE "); w.String(trmInstName1 & "_code");
			w.Int(i,1); w.String(" RAMB36 [0x00000000:0x000011FF]");
			w.Ln;
			w.String("BUS_BLOCK"); w.Ln;
			w.String(trmInstName); w.String("/trm"); w.String("/imx/ram["); w.Int(i,1);
			w.String("].RAMB36_inst [35:0]");
			if site # "" then w.String(" PLACED = " & site); end;
			w.Char(";");
			w.Ln;
			w.String("END_BUS_BLOCK;"); w.Ln;
			w.String("END_ADDRESS_SPACE;"); w.Ln; w.Ln;
		end;

		for i := 0 to dmb-1 do
			if proj is VivadoProject then
				if ~GetBramLocation(proj(VivadoProject),trmInstName & "/trm/dmx/ram[" & i & "].RAMB36_inst","RAMB36",site) then return false; end;
			end;
			w.String("ADDRESS_SPACE "); w.String(trmInstName1 & "_data");
			w.Int(i,1); w.String(" RAMB32 [0x00000000:0x00000FFF]");
			w.Ln;
			w.String("BUS_BLOCK"); w.Ln;
			w.String(trmInstName); w.String("/trm"); w.String("/dmx/ram["); w.Int(i,1);
			w.String("].RAMB36_inst [31:0]");
			if site # "" then w.String(" PLACED = " & site); end;
			w.Char(";");
			w.Ln;
			w.String("END_BUS_BLOCK;"); w.Ln;
			w.String("END_ADDRESS_SPACE;"); w.Ln; w.Ln;
		end;

		w.Update;

		return true;

	finally
		return false;
	end WriteTrmBmmRAMB36;

	(*
		Write to BMM file for TRM memories implemented based on RAMB16BWER block RAM primitives
	*)
	procedure WriteTrmBmmRAMB16BWER(proj: HdlBackend.HdlProject; w: Streams.Writer; trm: HdlBackend.Processor): boolean;
	const
		InsBlockSize = 1024;
		DataBlockSize = 512;
	var
		i, imb, dmb: size;
		p_CodeMemorySize, p_DataMemorySize: HdlBackend.Property;
		trmInstName, trmInstName1: HdlBackend.LongString;
	begin
		assert(proj is IseProject); (*! this type of BRAM is not supported in Vivado *)

		assert((trm.acName^ = "TRM") or (trm.acName^ = "TRMNIO"));
		p_CodeMemorySize := trm.GetPropertyByAcName("CodeMemorySize");
		p_DataMemorySize := trm.GetPropertyByAcName("DataMemorySize");
		imb := GetNumBrams(size(p_CodeMemorySize.value.ToInteger().val),InsBlockSize);
		dmb := GetNumBrams(size(p_DataMemorySize.value.ToInteger().val),DataBlockSize);

		trmInstName := GetFullInstanceName(proj.architecture,trm);
		HdlBackend.GetHdlNormalizedName(trmInstName,trmInstName1);

		for i := 0 to imb-1 do
			w.String("ADDRESS_SPACE "); w.String(trmInstName1 & "_code");
			w.Int(i,1); w.String(" RAMB18 [0x00000000:0x000008FF]");
			w.Ln;
			w.String("BUS_BLOCK"); w.Ln;
			w.String(trmInstName); w.String("/trm"); w.String("/imx/ram["); w.Int(i,1);
			w.String("].RAMB16BWER_inst [35:0];");
			w.Ln;
			w.String("END_BUS_BLOCK;"); w.Ln;
			w.String("END_ADDRESS_SPACE;"); w.Ln; w.Ln;
		end;

		for i := 0 to dmb-1 do
			w.String("ADDRESS_SPACE "); w.String(trmInstName1 & "_data");
			w.Int(i,1); w.String(" RAMB32 [0x00000000:0x00000FFF]");
			w.Ln;
			w.String("BUS_BLOCK"); w.Ln;
			w.String(trmInstName); w.String("/trm"); w.String("/dmx/ram["); w.Int(i,1);
			w.String("].RAMB36_inst [31:0];");
			w.Ln;
			w.String("END_BUS_BLOCK;"); w.Ln;
			w.String("END_ADDRESS_SPACE;"); w.Ln; w.Ln;
		end;

		w.Update;

		return true;

	finally
		return false;
	end WriteTrmBmmRAMB16BWER;

	(*
		Write to BMM file for memories implemented based on RAMB16_S36_S36 block RAM primitives
	*)
	procedure WriteTrmBmmRAMB16_S36_S36(proj: HdlBackend.HdlProject; w: Streams.Writer; trm: HdlBackend.Processor): boolean;
	const
		InsBlockSize = 1024;
		DataBlockSize = 512;
	var
		i, imb, dmb: size;
		p_CodeMemorySize, p_DataMemorySize: HdlBackend.Property;
		trmInstName, trmInstName1: HdlBackend.LongString;
	begin
		assert(proj is IseProject); (*! this type of BRAM is not supported in Vivado *)

		assert(	(trm.acName^ = "TRM") or (trm.acName^ = "TRMNIO"));
		p_CodeMemorySize := trm.GetPropertyByAcName("CodeMemorySize");
		p_DataMemorySize := trm.GetPropertyByAcName("DataMemorySize");
		imb := GetNumBrams(size(p_CodeMemorySize.value.ToInteger().val),InsBlockSize);
		dmb := GetNumBrams(size(p_DataMemorySize.value.ToInteger().val),DataBlockSize);

		trmInstName := GetFullInstanceName(proj.architecture,trm);
		HdlBackend.GetHdlNormalizedName(trmInstName,trmInstName1);

		for i := 0 to imb-1 do
			w.String("ADDRESS_SPACE "); w.String(trmInstName1 & "_code");
			w.Int(i,1); w.String(" RAMB18 [0x00000000:0x000008FF]");
			w.Ln;
			w.String("BUS_BLOCK"); w.Ln;
			if trm.acName^="TRM" then (*todo: add a feature to AcHdlBackend.Proecessro to construct this path*)
				w.String(trmInstName); w.String("/trm"); w.String("/imx/RAMB_insts["); w.Int(i,1); (*Old TRM has the wrapper*)
			elsif trm.acName^="TRMNIO"then				
				w.String(trmInstName);  w.String("/imx/RAMB_insts["); w.Int(i,1); (*new TRM doesn't have a wrapper to converto to AXI, so the path is shorter*)
			end;
			w.String("].RAMB16_S36_S36_inst [35:0];");
			w.Ln;
			w.String("END_BUS_BLOCK;"); w.Ln;
			w.String("END_ADDRESS_SPACE;"); w.Ln; w.Ln;
		end;

		for i := 0 to dmb-1 do
			w.String("ADDRESS_SPACE "); w.String(trmInstName1 & "_data");
			w.Int(i,1); w.String(" RAMB16 [0x00000000:0x000007FF]");
			w.Ln;
			w.String("BUS_BLOCK"); w.Ln;
			(* *) (*temporary*)
			if trm.acName^="TRM" then (*todo: add a feature to AcHdlBackend.Proecessro to construct this path*)
				w.String(trmInstName); w.String("/trm"); w.String("/dmx/RAMB_insts["); w.Int(i,1);
			elsif trm.acName^="TRMNIO" then
				w.String(trmInstName);  w.String("/dmx/RAMB_insts["); w.Int(i,1);
			end;			
			w.String("].RAMB16_S36_S36_inst [31:0];");
			w.Ln;
			w.String("END_BUS_BLOCK;"); w.Ln;
			w.String("END_ADDRESS_SPACE;"); w.Ln; w.Ln;
		end;

		w.Update;

		return true;

	finally
		return false;
	end WriteTrmBmmRAMB16_S36_S36;

	procedure WriteTrmBmm(proj: HdlBackend.HdlProject; w: Streams.Writer; trm: HdlBackend.Processor): boolean;
	begin
		if (proj.target.pldPart.family^ = "Virtex5") or
			(proj.target.pldPart.family^ = "Virtex6") or
			(proj.target.pldPart.family^ = "Artix7") or
			(proj.target.pldPart.family^ = "Kintex7") or
			(proj.target.pldPart.family^ = "Virtex7") or
			(proj.target.pldPart.family^ = "Zynq") then

			return WriteTrmBmmRAMB36(proj, w, trm);
		elsif proj.target.pldPart.family^ = "Spartan6" then

			return WriteTrmBmmRAMB16BWER(proj, w, trm);
		elsif Strings.StartsWith2("Spartan3",proj.target.pldPart.family^) then

			return WriteTrmBmmRAMB16_S36_S36(proj, w, trm);
		else
			proj.Error("",Streams.Invalid,HdlBackend.ErrNotImplemented,'unsupported PLD family "' & proj.target.pldPart.family^ & '" for memory patching');
			return false;
		end;
	end WriteTrmBmm;

	procedure PatchTrmMemories(
											proj: HdlBackend.HdlProject;
											trm: HdlBackend.Processor;
											var patchedBitstreamIndex: size;
											tclCmd: procedure{DELEGATE}(const cmd: array of char): boolean
											): boolean;
	var
		i, insBlockSize, dataBlockSize, imb, dmb: size;
		str: HdlBackend.LongString;
		p_CodeMemorySize, p_DataMemorySize: HdlBackend.Property;
		destPathName: Files.FileName;
	begin
		assert((trm.acName^ = "TRM") or (trm.acName^ = "TRMNIO"));

		GetInsAndDataBlockSize(trm,insBlockSize,dataBlockSize);
		p_CodeMemorySize := trm.GetPropertyByAcName("CodeMemorySize");
		p_DataMemorySize := trm.GetPropertyByAcName("DataMemorySize");
		imb := GetNumBrams(size(p_CodeMemorySize.value.ToInteger().val),insBlockSize);
		dmb := GetNumBrams(size(p_DataMemorySize.value.ToInteger().val),dataBlockSize);

		(*
			Prepare code and data mem files for each BRAM instance
		*)
		PathTools.JoinPath(proj.path^,trm.hdlInstName^,destPathName);
		if ~GenerateMemFiles(proj, trm.acInstName^, destPathName, insBlockSize div 2, dataBlockSize, imb, dmb, false) then return false end;

		for i := 0 to imb-1 do
			str := "exec data2mem -bm " & proj.architecture.acName^ & "_bd.bmm -bt ../" & proj.architecture.acName^ & patchedBitstreamIndex & ".bit";
			patchedBitstreamIndex := (patchedBitstreamIndex+1) mod 2;
			str := str & " -bd ../" & trm.hdlInstName^ & "_code" & i & ".mem tag " & trm.hdlInstName^ & "_code" & i & " -o b ";
			str := str & "../" & proj.architecture.acName^ & patchedBitstreamIndex & ".bit";

			if ~tclCmd(str) then return false; end;
			(*
			data2mem -bm TestRing_bd.bmm -bt TestRing.bit -bd ../../inst_TestRing1_code0.mem tag inst_TestRing1_code0 -o b TestRing1.bit
			if {[catch {data2mem -bm TestRing_bd.bmm -bt TestRing.bit -bd ../../inst_TestRing1_code0.mem tag inst_TestRing1_code0 -o b TestRing1.bit} err]} {puts TCL_ERROR:$err} else {puts TCL_OK}
			*)
		end;

		for i := 0 to dmb-1 do
			str := "exec data2mem -bm " & proj.architecture.acName^ & "_bd.bmm -bt ../" & proj.architecture.acName^ & patchedBitstreamIndex & ".bit";
			patchedBitstreamIndex := (patchedBitstreamIndex+1) mod 2;
			str := str & " -bd ../" & trm.hdlInstName^ & "_data" & i & ".mem tag " & trm.hdlInstName^ & "_data" & i & " -o b ";
			str := str & "../" & proj.architecture.acName^ & patchedBitstreamIndex & ".bit";

			if ~tclCmd(str) then return false; end;
		end;

		return true;
	finally
		return false;
	end PatchTrmMemories;

	(* Returns TRUE if a given character represents a decimal digit *)
	procedure IsDecDigit(ch: char): boolean;
	begin
		return (ord(ch) >= ord('0')) & (ord(ch) <= ord('9'));
	end IsDecDigit;

	(**
		Create a new Xilinx project
	*)
	procedure NewProject*(const projectType: array of char; const architectureName: array of char; targetDev: HdlBackend.TargetDevice; codeGenerator: HdlBackend.HdlCodeGenerator; const projectPath: array of char; diag: Diagnostics.Diagnostics): HdlBackend.HdlProject;
	var
		iseProject: IseProject;
		vivadoProject: VivadoProject;
	begin
		if projectType = "ISE" then
			new(iseProject,architectureName,targetDev,codeGenerator,projectPath,diag);
			return iseProject;
		elsif projectType = "Vivado" then
			new(vivadoProject,architectureName,targetDev,codeGenerator,projectPath,diag);
			return vivadoProject;
		end;
		return nil;
	end NewProject;

	(**
		Setup the path of ISE binaries
	*)
	procedure SetIseBinPath*(context: Commands.Context);
	begin
		if ~context.arg.GetString(iseBinPath) then
			context.result := 1;
			context.error.String("path to ISE binaries is expected"); context.error.Ln;
		end;
	end SetIseBinPath;

	(**
		Setup the path of Vivado binaries
	*)
	procedure SetVivadoBinPath*(context: Commands.Context);
	begin
		if ~context.arg.GetString(vivadoBinPath) then
			context.result := 1;
			context.error.String("path to Vivado binaries is expected"); context.error.Ln;
		end;
	end SetVivadoBinPath;
	
	
	(**
		Setup the path to the shell applicati0on
	*)
	procedure SetShellPath*(context: Commands.Context);
	begin
		if ~context.arg.GetString(shellBinPath) then
			context.result := 1;
			context.error.String("path to Shell application is expected, such as cmd.exe or /bin/bash"); context.error.Ln;
		end;
	end SetShellPath;
	
	(**
		Tell the application wether we're on windows or Linux.
		there are better solutions, but this works for now
	*)
	procedure SetHostOs*(context: Commands.Context);
	var
		res: array 20 of char;
	begin
		if ~context.arg.GetString(res) then
			context.result :=1;
		else
			if res="linux" then
				hostOS:=Linux;
			else
				if res="windows" then
					hostOS:=Windows;
				else				
					context.error.String("must be windows or linux"); context.error.Ln;
				end
			end
		end;
		
		
		
	end SetHostOs;

var
	iseBinPath: Files.FileName;
	vivadoBinPath: Files.FileName;
	shellBinPath: Files.FileName;
	hostOS: boolean;

begin
	hostOS:= Windows;
	iseBinPath := "c:/Xilinx/14.7/ISE_DS/ISE/bin/nt/";
	vivadoBinPath := "c:/Xilinx/Vivado/2014.4/bin/";
end AcXilinx.

HostOsApps.ExecuteApp "C:/Windows/System32/cmd.exe" "/c c:/Xilinx/Vivado/2014.4/bin/vivado.bat -mode tcl" ~
HostOsApps.ExecuteApp "/bin/bash" "/opt/Xilinx/Vivado/2014.4/bin/vivado" "-mode" "tcl" ~

