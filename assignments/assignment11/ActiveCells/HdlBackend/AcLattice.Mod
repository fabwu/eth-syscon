(* Active Cells Lattice Backend. Felix Friedrich, ETH Zurich, 2019*)
MODULE AcLattice;

IMPORT
	HdlBackend := AcHdlBackend, AcVerilogCodeGen, Strings, Diagnostics, Files, PathTools, Streams, Commands, HostOsApps, Trace, Out;

CONST
	DefaultProjectType* = "Any";

TYPE

	PldPart* = OBJECT(HdlBackend.PldPart)

		(*
			Construct a part given its full part name
		*)
		PROCEDURE &InitPldPart*(CONST partName: ARRAY OF CHAR);
		BEGIN
			InitObject;
			projectFactory := NewProject;
			vendor := Strings.NewString("Lattice");
			IF Strings.StartsWith("iCE40",0,partName) THEN
				family := Strings.NewString("iCE40");
			ELSE HALT(200)
			END;
			IF Strings.EndsWith("HX4K-tq144",partName) THEN
				device := Strings.NewString("hx8k");
				package := Strings.NewString("tq144:4k");
			ELSE HALT(200)
			END; 
			speedGrade := Strings.NewString(""); (* unused *)
			defaultProjectType := Strings.NewString(DefaultProjectType);
		END InitPldPart;

		PROCEDURE CopyContent(cpy: HdlBackend.Object);
		BEGIN
			CopyContent^(cpy);
			WITH  cpy : PldPart DO
			END;
		END CopyContent;

	END PldPart;


	Project* = OBJECT(HdlBackend.HdlProject)
	VAR 
		projPath: Files.FileName;

		PROCEDURE &InitProject*(CONST architectureName: ARRAY OF  CHAR; targetDev: HdlBackend.TargetDevice; codeGenerator: HdlBackend.HdlCodeGenerator; CONST projectPath: ARRAY OF  CHAR; diag: Diagnostics.Diagnostics);
		BEGIN
			ShowPhase("hdl project start: runtime execution");
			InitHdlProject(architectureName,targetDev,codeGenerator,projectPath,diag);
			IF res # 0 THEN RETURN; END;

			PathTools.JoinPath(path^,"Lattice",projPath);
			IF ~PathTools.DirectoryExists(projPath,projPath) & ~PathTools.CreateDirectory(projPath,projPath) THEN
				Error("",Streams.Invalid,HdlBackend.ErrUnexpected,'failed TO create directory "' & projPath & '"!');
			END;
			RETURN;
		FINALLY
			ErrorUnexpected;
		END InitProject;
		
		PROCEDURE GenerateCode(): BOOLEAN;
		BEGIN
			ShowPhase("generate software code");
			RETURN GenerateCode^()
		END GenerateCode; 

		PROCEDURE GenerateHdlCode(): BOOLEAN;
		BEGIN
			ShowPhase("generate hdl code");
			RETURN GenerateHdlCode^()
		END GenerateHdlCode; 
		
		PROCEDURE GenerateConstraints(): BOOLEAN;
		VAR 
			file: Files.File;
			fw: Files.Writer;
			emptyFile: BOOLEAN;
			fileName: Files.FileName;
			clockInput: HdlBackend.ClockInputPort;
			i: SIZE;
		BEGIN
			ShowPhase("GenerateConstraints");
			Files.JoinExtension(architecture.acName^, "pcf",fileName);
			TRACE(fileName); 
			file := Files.New(fileName); ASSERT(file # NIL);
			Files.Register(file);
			Files.OpenWriter(fw,file,0);

			IF architecture.mainResetInput # NIL THEN
				fw.String("# External system reset"); fw.Ln;
				IF ~DefineIo(fw,architecture.mainResetInput.acName^,-1,HdlBackend.In,architecture.mainResetInput(HdlBackend.CellnetPort).ios.GetIo(0)) THEN 
					RETURN FALSE; 
				END;
				fw.Ln;
			END;

			IF architecture.ports # NIL THEN
				IF ~DefineExternalPorts(SELF,fw,architecture.ports,DefineIo) THEN 
					RETURN FALSE; 
				END;
			END;
			IF architecture.clockSynthesizer # NIL THEN
				fw.String("# clock signals"); fw.Ln;
				FOR i := 0 TO architecture.clockSynthesizer.clockInputs.Length()-1 DO
					clockInput := architecture.clockSynthesizer.clockInputs.GetPort(i)(HdlBackend.ClockInputPort);
					IF clockInput.clock.source IS HdlBackend.PldIo THEN (* external clock *)
						IF ~DefineClock(fw,clockInput.clock.name^,clockInput.delegateOf.acName^,clockInput.clock) THEN 
								RETURN FALSE; 
						END;
					ELSE (* internal clock *)
							IF ~DefineClock(fw,architecture.clockSynthesizer.hdlInstName^ & "_" & clockInput.hdlName^,architecture.clockSynthesizer.hdlInstName^ & "/" & clockInput.hdlName^ & "_net",clockInput.clock) THEN 
								RETURN FALSE; 
							END;
					END;
				END;
			END;
			fw.Update;
			emptyFile := file.Length() = 0;
			file.Close;
			IF ~emptyFile THEN
				fingerprintWriter.Reset;
				IF ~fingerprintWriter.WriteFile(fileName) THEN RETURN FALSE; END;
				fingerprintWriter.GetFingerprintStr(constraintsFingerprint);
			ELSE
				constraintsFingerprint := "";
			END;
			RETURN TRUE;
		FINALLY
			IF file # NIL THEN file.Close; END;
			RETURN FALSE;
		END GenerateConstraints;
		
		PROCEDURE CheckForSourcesModifications(): BOOLEAN;
		VAR fingerprint0: HdlBackend.FingerprintStr;
			file: Files.File;
			fr: Files.Reader;
			fileName: Files.FileName;		
		BEGIN
			ShowPhase("check for sources modifications");
			RETURN CheckForSourcesModifications^();
		END CheckForSourcesModifications;
		
		PROCEDURE CheckForConstraintsModifications(): BOOLEAN;
		VAR
			file: Files.File;
			fr: Files.Reader;
			fileName: Files.FileName;
			fingerprint0: HdlBackend.FingerprintStr;
		BEGIN
			ShowPhase("CheckForModifiedConstraints");
			IF constraintsFingerprint = "" THEN constraintsUnchanged := TRUE; RETURN TRUE END;

			Files.JoinPath(path^,architecture.acName^ & "-constr.fng",fileName);
			file := Files.Old(fileName);
			IF file # NIL THEN
				Files.OpenReader(fr,file,0);
				fr.String(fingerprint0);
				file.Close;
				constraintsUnchanged := constraintsFingerprint = fingerprint0;
			ELSE
				constraintsUnchanged := FALSE;
			END;
			RETURN TRUE;
		FINALLY
			IF file # NIL THEN file.Close END;
			RETURN FALSE;
		END CheckForConstraintsModifications;

		PROCEDURE GenerateProject(): BOOLEAN;
		BEGIN
			ShowPhase("GenerateProject"); (* nothing to do *)
			RETURN TRUE;
		END GenerateProject;

		PROCEDURE ImplementArchitecture(): BOOLEAN;
		CONST 
			RamPrefix = ".ram_data ";
			FeedCode = "feedc0de0000";
			FeedDataLow = "feedda7a0123";
			FeedDataHigh = "feedda7a4567";
		VAR 
			row, col: SIZE;
			i: SIZE;
			dep: HdlBackend.Dependency;
			res: SIGNED32;
			
			application: HostOsApps.Application;
			memoryFile: MemoryFile;
			line: ARRAY 4096 OF CHAR;
			file: Files.File;
			reader: Files.Reader;
			fwriter: Files.Writer;
			instanceNumber, blockNumber: SIZE;
		BEGIN
			IF res # 0 THEN RETURN FALSE END;
			IF ~hdlSourcesUnchanged THEN (* synthesize *)
				ShowPhase("ImplementArchitecture:Synthesis (yosys)");
				NEW(application,"yosys");
				application.AddParameter("-q");
				application.AddParameter("-p read_verilog " & path^ & "/" & architecture.acName^ & "Clocks.v");
(*				application.AddParameter("-p read_verilog " & path^ & "/" & architecture.acName^ & ".v"); *)

				FOR i := 0 TO hdlSources.Length()-1 DO
					dep := hdlSources.Get(i)(HdlBackend.Dependency);
					IF dep.included THEN
						IF ~dep.makeLocalCopy THEN
							application.AddParameter("-p read_verilog " & dep.pathName^);
						END;
					END;
				END;
				application.AddParameter("-p synth_ice40 -json " & architecture.acName^ & ".json -top " & architecture.acName^);
				IF ~RunApplication(application) THEN 
					Error("",Streams.Invalid,HdlBackend.ErrUnexpected,"yosys failed");
					RETURN FALSE;
				END; 
			END;

			IF ~hdlSourcesUnchanged OR ~constraintsUnchanged THEN
				ShowPhase("ImplementArchitecture:PlaceAndRoute (nextpnr)");
				NEW(application,"nextpnr-ice40"); 				
				application.AddParameter("--" & target.pldPart.device^);
				application.AddParameter("--package");
				application.AddParameter(target.pldPart.package^);
				application.AddParameter("--asc");
				application.AddParameter(architecture.acName^ & ".asc");
				application.AddParameter("--pcf");
				application.AddParameter(architecture.acName^ & ".pcf");
				application.AddParameter("--json");
				application.AddParameter(architecture.acName^ & ".json");
				application.AddParameter("--freq");
				application.AddParameter("50");
				application.AddParameter("--opt-timing"); 
				application.AddParameter("--seed");
				application.AddParameter("1"); 
								
				IF ~RunApplication(application) THEN 
					Error("",Streams.Invalid,HdlBackend.ErrUnexpected,"nextpnr failed");
					RETURN FALSE;
				END; 
			END;

			IF ~architecture.TraverseCells(TraverseWriteProcessorMemory,FALSE,NIL) THEN
				RETURN FALSE;
			END;

			ShowPhase("ExtractRAM Files"); 
			file := Files.Old(architecture.acName^ & ".asc");
			VAR patched := Files.New(architecture.acName^ & ".patched.asc");
			NEW(reader, file, 0);
			NEW(fwriter, patched, 0); 
			WHILE reader.Available()>0 DO
				reader.Ln(line);
				fwriter.String(line); fwriter.Ln();
				IF Strings.StartsWith(RamPrefix,0,line) THEN
					reader.Ln(line);
					TRACE(line);
					VAR numberStr := Strings.Substring(12,16,line); 
					Strings.HexStrToSize(numberStr^,instanceNumber,res); 
					numberStr := Strings.Substring(28,32,line); 
					Strings.HexStrToSize(numberStr^,blockNumber,res);
					
					IF Strings.StartsWith(FeedCode,0,line) THEN
						TRACE(instanceNumber, "code", blockNumber); 
						memoryFile := GetMemoryFile(instanceNumber,TRUE);
						FOR row := blockNumber*1024 TO blockNumber*1024+1023 BY 64 DO
							FOR col := 64 - 4 TO 0 BY -4 DO
								fwriter.Bytes(memoryFile.data^,row+col,4);
							END;
							fwriter.Ln();
							reader.Ln(line);
						END; 
						fwriter.Ln();
					ELSIF Strings.StartsWith(FeedDataLow,0,line) THEN
						TRACE(instanceNumber, "data low", blockNumber); 
						memoryFile := GetMemoryFile(instanceNumber,FALSE);
						FOR row := blockNumber*1024 TO blockNumber*1024+1023 BY 64 DO
							FOR col := 64 - 4 TO 0 BY -4 DO
								fwriter.Bytes(memoryFile.data^,2*row+2*col+4,4);
							END;
							fwriter.Ln();
							reader.Ln(line);
						END; 
						fwriter.Ln();
					ELSIF Strings.StartsWith(FeedDataHigh,0,line) THEN
						TRACE(instanceNumber, "data high", blockNumber); 
						memoryFile := GetMemoryFile(instanceNumber,FALSE);
						FOR row := blockNumber*1024 TO blockNumber*1024+1023 BY 64 DO
							FOR col := 64 - 4 TO 0 BY -4 DO
								fwriter.Bytes(memoryFile.data^,2*row+2*col,4);
							END;
							fwriter.Ln();
							reader.Ln(line);
						END; 
						fwriter.Ln();
					ELSE
							fwriter.String(line); fwriter.Ln();
					END; 
				END;
			END;
			fwriter.Update();
			Files.Register(patched);			
			
			ShowPhase("Generate Bitstream (icepack)"); 
			NEW(application,"icepack"); 				
			application.AddParameter("-s");
			application.AddParameter(architecture.acName^ & ".patched.asc");
			application.AddParameter(architecture.acName^ & ".bin");
			IF ~RunApplication(application) THEN
				Error("",Streams.Invalid,HdlBackend.ErrUnexpected,"icepack failed");
				RETURN FALSE;
			END; 
			RETURN TRUE;
		FINALLY
			ErrorUnexpected; RETURN FALSE;
		END ImplementArchitecture;

		PROCEDURE GenerateFingerprintFiles(): BOOLEAN;
		BEGIN
			ShowPhase("Generate Fingerprint Files"); 
			RETURN GenerateFingerprintFiles^();
		END GenerateFingerprintFiles;

		PROCEDURE DeployArchitecture*(): BOOLEAN;
		VAR application: HostOsApps.Application;
		BEGIN
			IF res # 0 THEN RETURN FALSE END;				
			ShowPhase("Deploy (dfu)");
			PadDfuFile(architecture.acName^ & ".bin", architecture.acName^ & ".dfu");

			NEW(application,"dfu-suffix"); 				
			application.AddParameter("-a");
			application.AddParameter(architecture.acName^ & ".dfu");
							
			IF ~RunApplication(application) THEN 
				Error("",Streams.Invalid,HdlBackend.ErrUnexpected,"dfu-suffix failed");
				RETURN FALSE;
			END; 

			NEW(application,"dfu-util"); 				
			application.AddParameter("-D");
			application.AddParameter(architecture.acName^ & ".dfu");

			IF ~RunApplication(application) THEN
				Error("",Streams.Invalid,HdlBackend.ErrUnexpected,"dfu-util failed");
				RETURN FALSE;
			END; 
			RETURN TRUE;
		END DeployArchitecture;

		(**
			Close HDL project
		*)
		PROCEDURE CloseProject*();
		VAR application: HostOsApps.Application;
		BEGIN
			IF res # 0 THEN RETURN END;
			IF ~hdlSourcesUnchanged OR ~constraintsUnchanged THEN
				ShowPhase("timing report (icetime)"); 
				NEW(application,"icetime"); 				
				application.AddParameter("-d");
				application.AddParameter("hx8k");
				application.AddParameter("-P");
				application.AddParameter("tq144:4k");
				application.AddParameter("-p");
				application.AddParameter(architecture.acName^ & ".pcf");
				application.AddParameter("-tr");
				application.AddParameter(architecture.acName^ & ".rpt");
				application.AddParameter(architecture.acName^ & ".patched.asc");
				IF ~RunApplication(application) THEN
					Error("",Streams.Invalid,HdlBackend.ErrUnexpected,"timing report failed");
				END;
				ShowFile(architecture.acName^ & ".rpt");
			END;
			ShowPhase("finished");
		END CloseProject;
				
		TYPE
			MemoryFile = POINTER TO RECORD
				fileName: Strings.String;
				code: BOOLEAN;
				id, wordBits, words: SIZE;
				data: POINTER TO ARRAY OF CHAR;
				next: MemoryFile;
			END; 
			
		PROCEDURE GetMemoryFile(id: SIZE; code: BOOLEAN): MemoryFile;
		VAR memoryFile: MemoryFile;
		BEGIN
			memoryFile := memoryFiles;
			WHILE (memoryFile # NIL) & ((memoryFile.id # id) OR (memoryFile.code # code)) DO
				memoryFile := memoryFile.next;
			END; 
			RETURN memoryFile; 
		END GetMemoryFile;
		
		VAR memoryFiles: MemoryFile;
		
		PROCEDURE AddMemoryFile(CONST fileName: ARRAY OF CHAR; code: BOOLEAN; id, wordBits, words: SIZE);
		VAR memoryFile: MemoryFile; file: Files.File; reader: Files.Reader; i: SIZE; ch: CHAR;
		BEGIN
					NEW(memoryFile); memoryFile.code := TRUE;
					memoryFile.id := id;
					memoryFile.fileName := Strings.NewString(fileName);
					memoryFile.wordBits := wordBits;
					memoryFile.words := words;
					memoryFile.code := code;
					file := Files.Old(memoryFile.fileName^);
					NEW(memoryFile.data, memoryFile.wordBits*memoryFile.words DIV 4 + 1);
					NEW(reader, file, 0);
					FOR i := 0 TO LEN(memoryFile.data)-2 DO
						IGNORE reader.GetChar(ch); 
						IF ('A' <= ch) & (ch <= "F") THEN 
							ch := CHR(ORD(ch) - ORD('A') + ORD('a'));
						END;
						memoryFile.data[i] := ch;
					END;				
					memoryFile.next :=  memoryFiles;
					memoryFiles := memoryFile;			
		END AddMemoryFile;
		
				
		PROCEDURE TraverseWriteProcessorMemory(c: HdlBackend.Cell; param: ANY): BOOLEAN;
		VAR instructionWidth: SIZE;
		BEGIN
			WITH c : HdlBackend.Processor DO
				IF (c.acName^ = "TRM") OR (c.acName^ = "TRMNIO") THEN
				
					IF c.GetPropertyByAcName("InstructionWidth") # NIL THEN
						instructionWidth := c.GetPropertyByAcName("InstructionWidth").value(HdlBackend.Integer).val;
					ELSE
						instructionWidth := 16;
					END;
					VAR id := c.GetPropertyByAcName("Inst").value(HdlBackend.Integer).val;
					AddMemoryFile(c.acInstName^ & ".code", TRUE,id, instructionWidth, 
					c.GetPropertyByAcName("CodeMemorySize").value(HdlBackend.Integer).val);
					AddMemoryFile(c.acInstName^ & ".data", FALSE, id, 32,
					c.GetPropertyByAcName("DataMemorySize").value(HdlBackend.Integer).val);

					(*
					
						assert(	(trm.acName^ = "TRM") or (trm.acName^ = "TRMNIO"));
		p_CodeMemorySize := trm.GetPropertyByAcName("CodeMemorySize");
		p_DataMemorySize := trm.GetPropertyByAcName("DataMemorySize");
		imb := GetNumBrams(size(p_CodeMemorySize.value.ToInteger().val),InsBlockSize);
		dmb := GetNumBrams(size(p_DataMemorySize.value.ToInteger().val),DataBlockSize);
			*)
				
					RETURN TRUE; 				
				ELSE
					RETURN TRUE;
				END;
			ELSE
				RETURN TRUE;
			END;
		END TraverseWriteProcessorMemory;
		
		PROCEDURE GenerateClocks(w: Streams.Writer; synthesizer: HdlBackend.Cell): BOOLEAN;
		BEGIN
			RETURN ProjGenerateClocks(SELF,w,synthesizer);
		END GenerateClocks;

		PROCEDURE DefineIo(w: Streams.Writer; CONST portName: ARRAY OF  CHAR; index: SIZE; expectedDirection: INTEGER; io: HdlBackend.PldIo): BOOLEAN;
		BEGIN
			WITH  io : HdlBackend.IoPin DO
				IF (io.direction # HdlBackend.Inout) & (expectedDirection # io.direction) THEN
					Error("",Streams.Invalid,HdlBackend.ErrInvalidValue,'IO "' & portName & '" direction (' & io.direction &  ') DOes not match WITH  the corresponding port direction (' & expectedDirection & ')');
					RETURN FALSE;
				END;
				IF index >= 0 THEN
					w.String('set_io ' & portName & "[" & index & "] " & io.location^);
				ELSE
					w.String('set_io ' & portName & ' ' & io.location^);
				END;
				w.Ln;
			ELSE
				Error("",Streams.Invalid,HdlBackend.ErrNotImplemented,"handling OF  differential pairs IS not yet implemented");
				RETURN FALSE;
			END;

			RETURN TRUE;
		END DefineIo;

		PROCEDURE DefineClock(w: Streams.Writer; CONST clockName, portName: ARRAY OF  CHAR; clock: HdlBackend.Clock): BOOLEAN;
		VAR 
			io: HdlBackend.PldIo;
			period, dutyCycle: ARRAY 128 OF  CHAR;
		BEGIN
			Strings.FloatToStr(1.0D9/clock.frequency,0,3,0,period); Strings.TrimWS(period);
			Strings.FloatToStr(clock.dutyCycle,0,3,0,dutyCycle); Strings.TrimWS(dutyCycle);

			IF clock.source IS HdlBackend.PldIo THEN
				io := clock.source(HdlBackend.PldIo);
				IF ~DefineIo(w,portName,-1,HdlBackend.In,io) THEN RETURN FALSE; END;
			END;

			RETURN TRUE;
		END DefineClock;

		PROCEDURE ShowPhase(CONST text: ARRAY OF CHAR);
		VAR count,i: SIZE;
		BEGIN
			count := 120;
			DEC(count, Strings.Length(text));
			FOR i := 0 TO count DIV 2 -1 DO
				Trace.Char("-"); Out.Char("-");
			END;
			Trace.String(text); Out.String(text); 
			FOR i := 0 TO count - count DIV 2 -1 DO
				Trace.Char("-");Out.Char("-");
			END;
			Trace.Ln; Out.Ln; Out.Update;
		END ShowPhase;
	END Project;
	

	PROCEDURE RunApplication(application: HostOsApps.Application): BOOLEAN;
	BEGIN
			IF  application.Execute(TRUE) THEN 
				application.WaitForTermination;
				IF application.exitCode # 0 THEN
					RETURN FALSE
				END;
				application.Finalize();
			ELSE
				RETURN FALSE
			END; 
			RETURN TRUE;
	END RunApplication;

	PROCEDURE PadDfuFile(CONST binFile, dfuFile: ARRAY OF CHAR);
	VAR bin, dfu: Files.File; i: SIZE; R: Files.Reader; W: Files.Writer; res: SIGNED32;
	BEGIN
		bin := Files.Old(binFile); 
		ASSERT(bin # NIL);
		Files.Delete(dfuFile, res);
		dfu := Files.New(dfuFile); 
		
		IF dfu = NIL THEN dfu := Files.New(dfuFile) END;
		
		NEW(W,dfu,0); 
		NEW(R,bin,0); 
		FOR i := 0 TO 63 DO
			W.Char(0FFX);
		END;
		WHILE R.Available() > 0 DO
			W.Char(R.Get());
		END; 
		FOR i := 0 TO 7 DO
			W.Char(0FFX);
		END;
		W.Update;
		Files.Register(dfu);
		dfu.Close;
	END PadDfuFile;
	
	(** Display the content of the specified file *)
	PROCEDURE ShowFile(CONST filename: ARRAY OF CHAR);
	VAR file : Files.File; reader : Files.Reader; ch : CHAR;
	BEGIN
		file := Files.Old(filename);
		IF (file # NIL) THEN
			Files.OpenReader(reader, file, 0);
			REPEAT
				reader.Char(ch);
				Trace.Char(ch);
			UNTIL (reader.res # Streams.Ok);
		ELSE
			Trace.String("Could not open file ");Trace.String(filename); Trace.Ln;
		END;
	END ShowFile;

	

	PROCEDURE ProjGenerateClocks(proj: HdlBackend.HdlProject; w: Streams.Writer; synthesizer: HdlBackend.Cell): BOOLEAN;
	VAR 
		derivedClock: HdlBackend.DerivedClock;
		cgen: AcVerilogCodeGen.VerilogCodeGenerator;
		pIn: HdlBackend.ClockInputPort;
		pOutList: HdlBackend.PortList;
		pOut: HdlBackend.ClockOutputPort;
		i, j: SIZE;
		pInName: HdlBackend.LongString;
	BEGIN
		NEW(cgen);
		cgen.SetWriter(w);

		ASSERT(synthesizer.inputs = NIL);
		ASSERT((synthesizer.outputs = NIL) OR (synthesizer.outputs.Length() = 1));

		cgen.DeclareModule(synthesizer);
		cgen.w.Update;

		NEW(pOutList,4);

		FOR i := 0 TO synthesizer.clockInputs.Length()-1 DO

			pIn := synthesizer.clockInputs.GetPort(i)(HdlBackend.ClockInputPort);

			IF pIn.clock.source IS HdlBackend.PldIo THEN (* external clock *)
				COPY(pIn.hdlName^,pInName);
			ELSE (* internal clock *)
				ASSERT(pIn.clock.source IS HdlBackend.ClockOutputPort);

				(*
					Bufferize the internal clock signal
				*)
				pInName := pIn.hdlName^ & "_buf";
				cgen.Format('(* keep = "soft" *) wire ' & pIn.hdlName^ & "_net = " & pIn.hdlName^ & ";\\");
				cgen.Format("wire " & pInName & ";\\");
				cgen.Format("BUFG buf_" & pIn.hdlName^ & "(.I(" & pIn.hdlName^ & "_net),.O(" & pInName & "));\\");
			END;

			pOutList.Clear;
			FOR j := 0 TO synthesizer.clockOutputs.Length()-1 DO
				pOut := synthesizer.clockOutputs.GetPort(j)(HdlBackend.ClockOutputPort);
				derivedClock := pOut(HdlBackend.ClockOutputPort).clock(HdlBackend.DerivedClock);
				IF derivedClock.refClock = pIn.clock THEN
					pOutList.Add0(pOut);
				END;
			END;
			IF pOutList.Length() = 1 THEN (* 1 input clock -> 1 output clock *)
				pOut := pOutList.GetPort(0)(HdlBackend.ClockOutputPort);
				derivedClock := pOut(HdlBackend.ClockOutputPort).clock(HdlBackend.DerivedClock);
				ASSERT(derivedClock.refClock = pIn(HdlBackend.ClockInputPort).clock);
				IF (derivedClock.mulFactor = 1) & (derivedClock.divFactor = 1) & (derivedClock.phase = 0) THEN
					cgen.Format("assign " & pOut.hdlName^ & " = " & pInName & ";\\");
				ELSIF (derivedClock.mulFactor = 1) & (derivedClock.divFactor = 2) & (derivedClock.phase = 0) THEN
									cgen.Format("reg " & pOut.hdlName^ & \"_r; \n always @(posedge "\ & pInName & \") \n"\
                      & pOut.hdlName^ & "_r <= ~" & pOut.hdlName^ & \"_r; \n assign "\
                      & pOut.hdlName^ & " = " & pOut.hdlName^ & "_r;"); 				
   	ELSE
					proj.Error("",Streams.Invalid,HdlBackend.ErrNotImplemented,"generation OF  derived clocks IS not yet implemented");
					RETURN FALSE;
				END;
			ELSE
				proj.Error("",Streams.Invalid,HdlBackend.ErrNotImplemented,"generation OF  multiple clock outputs IS not yet implemented");
				RETURN FALSE;
			END;

		END;

		cgen.w.Ln;
		cgen.EndModule;
		cgen.w.Update;

		RETURN proj.res = 0;

	FINALLY
		proj.ErrorUnexpected; RETURN FALSE;
	END ProjGenerateClocks;

	PROCEDURE DefineExternalPorts(
											proj: HdlBackend.HdlProject;
											w: Streams.Writer;
											ports: HdlBackend.PortList;
											defineIo: PROCEDURE {DELEGATE}(w: Streams.Writer; CONST portName: ARRAY OF  CHAR; index: SIZE; expectedDirection: INTEGER; io: HdlBackend.PldIo): BOOLEAN
											): BOOLEAN;
	VAR 
		i, j, n: SIZE;
		p: HdlBackend.Port;

		PROCEDURE DefinePort(CONST portName: ARRAY OF  CHAR; p: HdlBackend.Port): BOOLEAN;
		VAR 
			ioSetup: HdlBackend.IoSetup;
			ioPort: HdlBackend.PldIoList;
			c: HdlBackend.Cell;
		BEGIN
			WITH  p : HdlBackend.CellnetPort DO (*! hierarchical handling OF  external ports *)
				ASSERT(p.delegatedTo.Length()=1); (*! each port must be delegated TO only one component port  *)
				(*IF p.GetCell()(HdlBackend.Cellnet).level > 0 THEN ASSERT(p.ios = NIL); END;*)
				RETURN DefinePort(portName,p.delegatedTo.GetPort(0));
			ELSE
				WITH  p : HdlBackend.HdlPort DO
					ASSERT(p.isExternal);

					c := p.GetCell();

					ioSetup := proj.target.GetIoSetupByName(c.acName^ & "_" & c.instId);
					IF ioSetup = NIL THEN
						proj.Error("",Streams.Invalid,HdlBackend.ErrNotDefined,'IO setup with name "' & c.acName^ & "_" & c.instId & '" is not defined');
						RETURN FALSE;
					END;
					ioPort := ioSetup.GetIoPortByName(p.acName^);
					IF ioPort = NIL THEN
						proj.Error("",Streams.Invalid,HdlBackend.ErrNotDefined,'IO port with name "' & p.acName^ & '" is not defined in IO setup "' & ioSetup.name^ & '"');
						RETURN FALSE;
					END;
					IF ioPort.Length() < p.width THEN
						proj.Error("",Streams.Invalid,HdlBackend.ErrNotDefined,'IO port "' & p.acName^ & '" has width smaller than the corresponding HDL port "' & c.acName^ & "." & p.acName^ & '"');
						RETURN FALSE;
					END;
					w.String("# " & ioSetup.name^ & "." & ioPort.name^); w.Ln;
					IF p.width > 1 THEN
						FOR j := 0 TO p.width-1 DO
							IF ~defineIo(w,portName,j,p.direction,ioPort.GetIo(j)) THEN RETURN FALSE; END;
						END;
					ELSE
						IF ~defineIo(w,portName,-1,p.direction,ioPort.GetIo(0)) THEN RETURN FALSE; END;
					END;
					w.Ln;
				ELSE
					HALT(100);
				END;
			END;

			RETURN TRUE;
		END DefinePort;

	BEGIN
		n := ports.Length();
		FOR i := 0 TO n-1 DO
			p := ports.GetPort(i);

			IF (p.hdlName^ # HdlBackend.MainClockInputName) & ((p.hdlName^ # HdlBackend.MainResetInputName)) THEN
				IF ~DefinePort(p.hdlName^,p) THEN
					RETURN FALSE;
				END;
			END;

		END;

		RETURN TRUE;
	END DefineExternalPorts;

	(**
		Create a new Xilinx project
	*)
	PROCEDURE NewProject*(CONST projectType: ARRAY OF  CHAR; CONST architectureName: ARRAY OF  CHAR; targetDev: HdlBackend.TargetDevice; codeGenerator: HdlBackend.HdlCodeGenerator; CONST projectPath: ARRAY OF  CHAR; diag: Diagnostics.Diagnostics): HdlBackend.HdlProject;
	VAR 
		project: Project;
	BEGIN
		NEW(project,architectureName,targetDev,codeGenerator,projectPath,diag);
		RETURN project;
	END NewProject;
	
	(**
		Setup the path TO the shell applicati0on
	*)
	PROCEDURE SetShellPath*(context: Commands.Context);
	BEGIN
		IF ~context.arg.GetString(shellBinPath) THEN
			context.result := 1;
			context.error.String("path TO Shell application is expected, such as cmd.exe or /bin/bash"); context.error.Ln;
		END;
	END SetShellPath;
	
	(**
		Tell the application wether we're on windows OR Linux.
		there are better solutions, but this works FOR now
	*)
	PROCEDURE SetHostOs*(context: Commands.Context);
	VAR 
		res: ARRAY 20 OF  CHAR;
	BEGIN
		IF ~context.arg.GetString(res) THEN
			context.result :=1;
		ELSE
			IF res="linux" THEN
				hostOS:=OS.Linux;
			ELSE
				IF res="windows" THEN
					hostOS:=OS.Windows;
				ELSE				
					context.error.String("must be windows or linux"); context.error.Ln;
				END
			END
		END;
	END SetHostOs;

TYPE 
	OperatingSystem = ENUM Windows, Linux END;
	OS = OperatingSystem; 
	
VAR 
	shellBinPath: Files.FileName;
	hostOS: OperatingSystem;

BEGIN
	hostOS:= OS.Linux;
END AcLattice.

HostOsApps.ExecuteApp "C:/Windows/System32/cmd.exe" "/c c:/Xilinx/Vivado/2014.4/bin/vivado.bat -mode tcl" ~
HostOsApps.ExecuteApp "/bin/bash" "/opt/Xilinx/Vivado/2014.4/bin/vivado" "-mode" "tcl" ~

