1. (ONCE) Release.Tool --> Build Win32G and Linux32G and command line versions (A2 release 7072)
	
		System.DoCommands	
		Release.Build --build --path=assignment11/linux64/ Linux64 ~
		Linker.Link -p=Linux64 --path=assignment11/linux64/  --fileName=oberon64
			Builtins Trace Glue Unix Machine Heaps Modules Objects Kernel KernelLog Streams Commands Pipes StdIO
			TrapWriters Reflection Traps Files UnixFiles Clock Dates Reals Strings Diagnostics BitSets StringPool ObjectFile GenericLinker Loader System StdIOShell
			Shell ~
		Release.Build --build --path=assignment11/linux32/ Linux32~
		Linker.Link -p=Linux32 --path=assignment11/linux32/ --fileName=oberon32
			Builtins Trace Glue Unix Machine Heaps Modules Objects Kernel KernelLog Streams Commands Pipes StdIO
			TrapWriters Reflection Traps Files UnixFiles Clock Dates Reals Strings Diagnostics BitSets StringPool ObjectFile GenericLinker Loader System StdIOShell
			Shell ~
		Release.Build --build --path=assignment11/win64/ Win64 ~
		Linker.Link --path=assignment11/win64/ --fileFormat=PE64CUI --fileName=oberon64.exe --extension=GofWw --displacement=401000H
			Builtins Trace Kernel32 Heaps Modules Objects Kernel KernelLog Streams Commands Files WinFS Clock Dates Reals Strings Diagnostics BitSets
			StringPool ObjectFile GenericLinker Reflection Traps Loader Shell StdIOShell System ~
		Release.Build --build --path=assignment11/win32/ Win32 ~
		Linker.Link --path=assignment11/win32/ --fileFormat=PE32CUI --fileName=oberon32.exe --extension=GofW --displacement=401000H
			Builtins Trace Kernel32 Heaps Modules Objects Kernel KernelLog Streams Commands Files WinFS Clock Dates Reals Strings Diagnostics BitSets
			StringPool ObjectFile GenericLinker Reflection Traps Loader Shell StdIOShell System ~
		~ 

2. (ONCE) Compile HWCompiler and HWLib 

System.DoFile assignment11/BuildTools.txt ~ 

3. (EACH SYSTEM START) Load HW Lib

System.DoFile assignment11/LoadHWL.txt ~ 

4. (EACH APPLICATION CHANGE) Compile Application Code

Example: 

System.DoCommands
	Compiler.Compile  -p=TRMI
	assignment11/Application/PWMTest.Mod
	~
	Compiler.Compile  --cellsAreObjects	
	assignment11/Application/PWMTest.Mod
	~
	AcHdlBackend.Build --deploy --target="OPALBoard" --outputPath="Ac3Projects"  "PWMTest.Network" ~
~ 


(* ---- PWM Test ---- *)

System.DoFile assignment11/BuildPWMTest.txt ~ 

(* --- Candle ----- *)

System.DoFile assignment11/BuildCandle.txt ~ 

(* --- SoundSampler ----- *)

System.DoFile assignment11/BuildSoundSampler.txt ~ 

V24.Map 9 /dev/ttyUSB0  ~ 

SoundStream.Record 9 audio.txt ~ 

(* --- Tuner ----- *)

System.DoFile assignment11/BuildTuner.txt ~ 

5. (EACH APPLICATION CHANGE) Build it

command line parameters for AcHdlBackend.Build 
	--deploy Deploy the hardware
	-f Force rebuild
	- 

