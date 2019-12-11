(**
	AUTHOR "Stephan Kost4er";
	PURPOSE "Tools for running applications of the host OS (Unix)";
*)
MODULE HostOsApps;

IMPORT
	Streams, Files, Strings, Commands,  Options,  Unix;

CONST

	(** Application IO stream types *)
	StdIn* = 0; (** Standard input *)
	StdOut* = 1; (** Standard output *)
	StdErr* = 2; (** Standard error output *)

	MAXPARAM=1024; (*max number of arguments*)
	
	(** in this module Error codes *)
	Ok* = 0;
	InvalidStream* = 1; (** invalid stream type was specified *)
	CannotDoWhileRunning* = 2; (** operation cannot be done while the application is running *)
	AppNotRunning* = 3; (** operation cannot be done because the application is not running *)
	ObjIsFinalized* =  4; (** the app object is finalized - cannot perform any operation on the object *)
	HostOsError* = 5; (** an error reported in host OS result code *)

	UnknownError* = 256; (** An unexpectedly occurred error *)

	(** output stream update rules *)
	UpdateNone* = 0; (** no Update is used for the output streams provided by the user *)
	UpdateAny* = 1; (** Update is called for any amount of available data *)
	UpdateLn* = -1; (** Update is called whenever Ln sequence is detected (CR or LF or CR+LF) *)

	CR = 0DX; (*carriadge return symbol*)
	LF = 0AX;  (*line feed symbol*)

VAR
	posix_spawn_file_actions_init- 	: PROCEDURE{C}(file_actions: ADDRESS): SIGNED32;
	posix_spawn_file_actions_destroy- 	: PROCEDURE{C}(file_actions: ADDRESS): SIGNED32;
	posix_spawn_file_actions_adddup2- 	: PROCEDURE{C}(file_actions: ADDRESS; fildes,newfildes: SIGNED32): SIGNED32;
TYPE



	(**
		Host OS application object.

		A single object instance can be reused for executing multiple applications.
	*)
	Application* = OBJECT
	VAR
		isRunning-: BOOLEAN; (** TRUE if the application is currently running *)
		exitCode-: SIGNED32; (** application exit code *)

		res-: SIGNED32; (** result code *)
		hostOsRes-: SIGNED32; (** host OS result code in case if res = HostOsError *)

		executable: Files.FileName; (* application executable file name *)
		params: ARRAY MAXPARAM OF Strings.String; (* application execution parameters. must be null terminated strings *)
		numParams: SIGNED32; (* number of parameters*)

		redirectedStreams: SET; (* streams to redirect (StdOut, StdIn, StdErr) *)
		workingDirectory: Files.FileName; (* working directory of the application *)

		isObjAlive: BOOLEAN; (* TRUE if the object is alive *)
		finalizeOnExit: BOOLEAN; (* TRUE for finalization of the object on application exit *)
		initFlag: BOOLEAN;

		stdInReader: Streams.Reader;
		stdOutWriter: Streams.Writer;
		stdErrWriter: Streams.Writer;
		
		stdOutUpdateSetting, stdErrUpdateSetting: SIGNED32;

		StdInPipe: ARRAY 2 OF SIGNED32;
		StdOutPipe: ARRAY 2 OF SIGNED32;
		StdErrPipe: ARRAY 2 OF SIGNED32;
		
		posix_spawn_actions: ARRAY 50 OF CHAR;  (*determined with test program, not the documentation. May not be correct!*)
		pid: Unix.pid_t; (*unix process id of the child process*)
			
		stdInRedirector: StdInRedirector;
		stdOutRedirector: OutputRedirector;
		stdErrRedirector: OutputRedirector;
		
		(**
			Initialize Application object
		*)
		PROCEDURE &InitApplication*(CONST executableName: ARRAY OF CHAR);
		BEGIN
			IF initFlag & ~isObjAlive THEN res := ObjIsFinalized; RETURN; END;
			IF isRunning THEN res := CannotDoWhileRunning; RETURN; END;

			SetExecutable(executableName);

			numParams := 0; (* empty the parameter list *)
			finalizeOnExit := FALSE;

			initFlag := TRUE;
			isObjAlive := TRUE;

			res := Ok;
		END InitApplication;

		(**
			Setup application executable

			executableName: application executable file name
		*)
		PROCEDURE SetExecutable*(CONST executableName: ARRAY OF CHAR);
		BEGIN
			COPY(executableName,executable);
		END SetExecutable;

		(**
			Add a null-terminated parameter string passed to the application at its execution time
		*)
		PROCEDURE AddParameter*(CONST parameter: ARRAY OF CHAR);
		VAR
			p: Strings.String;
		BEGIN
			p:=Strings.NewString(parameter);
			Strings.AppendChar(p^,0X);
			params[numParams]:=p;
			INC(numParams);
			
		END AddParameter;

		(**
			Clear the list of application parameters
		*)
		PROCEDURE ClearParameters*();
		BEGIN
			numParams := 0;
		END ClearParameters;

		(**
		Setup standard input redirection

		reader: standard input data source

		Returns TRUE in case of success. In case of an error returns FALSE and stores the error code in res.
		*)
		PROCEDURE SetStdIn*(CONST reader: Streams.Reader): BOOLEAN;
		BEGIN
			IF isRunning THEN res := CannotDoWhileRunning; RETURN FALSE; END;
			stdInReader:=reader;
			IF stdInReader # NIL THEN INCL(redirectedStreams,StdIn); ELSE EXCL(redirectedStreams,StdIn); END;
			RETURN TRUE;
		END SetStdIn;

		(**
			Setup standard output redirection

			writer: stream where to redirect the standard output
			writerUpdateSetting: writer update setting; if 0 (UpdateNone) the writer is not updated at all,
										if greater than 0, the writer will be updated according to the rule numAvailableData >= writerUpdateSetting,
										that includes the case of 1 (UpdateAny) where writer is updated whenever any amount of standard output data is available;
										if negative, the writer is updated whenever a new line character is available (CR, LF or CR+LF)

			Returns TRUE in case of success. In case of an error returns FALSE and stores the error code in res.
		*)
		PROCEDURE SetStdOut*(CONST writer: Streams.Writer; writerUpdateSetting: SIGNED32): BOOLEAN;
		BEGIN
			IF isRunning THEN res := CannotDoWhileRunning; RETURN FALSE; END;
			stdOutWriter:=writer;
			stdOutUpdateSetting := writerUpdateSetting;
			IF stdOutWriter # NIL THEN INCL(redirectedStreams,StdOut); ELSE EXCL(redirectedStreams,StdOut); END;
			RETURN TRUE;
		END SetStdOut;

	


		(**
			Setup standard error output redirection

			writer: stream where to redirect the standard error output
			writerUpdateSetting: writer update setting; if 0 (UpdateNone) the writer is not updated at all,
										if greater than 0, the writer will be updated according to the rule numAvailableData >= writerUpdateSetting,
										that includes the case of 1 (UpdateAny) where writer is updated whenever any amount of standard output data is available;
										if negative, the writer is updated whenever a new line character is available (CR, LF or CR+LF)

			Returns TRUE in case of success. In case of an error returns FALSE and stores the error code in res.
		*)
		PROCEDURE SetStdErr*(CONST writer: Streams.Writer; writerUpdateSetting: SIGNED32): BOOLEAN;
		BEGIN
			IF isRunning THEN res := CannotDoWhileRunning; RETURN FALSE; END;
			stdErrWriter:=writer;
			stdErrUpdateSetting := writerUpdateSetting;
			IF stdErrWriter#NIL THEN INCL(redirectedStreams,StdErr); ELSE EXCL(redirectedStreams,StdErr);END;
			RETURN TRUE;
		END SetStdErr;

		(**
			Setup buffering of the standard streams

			selectedStreams: set of selected streams (StdIn, StdOut, StdErr)
			bufferSize: stream buffer size in bytes

			Returns TRUE in case of success. In case of an error returns FALSE and stores the error code in res.
		*)
		PROCEDURE SetStreamBuffering*(selectedStreams: SET; bufferSize: SIGNED32): BOOLEAN;
		BEGIN
			IF selectedStreams * {StdErr+1..31} # {} THEN res := InvalidStream; RETURN FALSE; END;
			IF isRunning THEN res := CannotDoWhileRunning; RETURN FALSE; END;
			(*not implemented*)
		END SetStreamBuffering;

		(**
			Setup application working directory

			directory: path to the working directory of the application

			Returns TRUE in case of success. In case of an error returns FALSE and stores the error code in res.
		*)
		PROCEDURE SetWorkingDirectory*(CONST directory: ARRAY OF CHAR): BOOLEAN;
		BEGIN
			IF isRunning THEN res := CannotDoWhileRunning; RETURN FALSE; END;
			COPY(directory,workingDirectory);
			res := Ok;
			RETURN TRUE;
		END SetWorkingDirectory;

		(**
			Execute the application

			finalizeObjectOnExit: TRUE for finalizing the object on application exit

			Returns TRUE in case of success
		*)
		PROCEDURE Execute*(finalizeObjectOnExit: BOOLEAN): BOOLEAN;
		VAR
			result,i: SIGNED32;
			argv: ARRAY MAXPARAM+2 OF ADDRESS;
			eString: Strings.String;
		BEGIN
			IF ~isObjAlive THEN res := ObjIsFinalized; RETURN FALSE; END;
			IF isRunning THEN res := CannotDoWhileRunning; RETURN FALSE; END;
			
			eString:=Strings.NewString(executable);
			Strings.AppendChar(eString^,0X);
			argv[0]:=ADDRESSOF(eString[0]);
			
			FOR i:=0 TO numParams-1 DO
				argv[i+1]:=ADDRESSOF(params[i][0]);
			END;
			argv[numParams+1]:=NIL;
			
			IF redirectedStreams = {} THEN (* no stream redirection is used *)
				(*API call to start the executable with posix_spawn. Pid is only written to if it's non-null before the call.  Return value zero means success
				first param must be path to the executable, last param must be 0, in between we have pointers to c-strings. params must be a pointer to array of pointers to strings*)
				result:= Unix.posix_spawnp(ADDRESSOF(pid), ADDRESSOF(executable), NIL,  NIL,   ADDRESSOF(argv[0]), Unix.environ);
			ELSE (*redirect streams*)
				IF StdOut IN redirectedStreams THEN
					IF Unix.pipe(ADDRESSOF(StdOutPipe[0])) #0 THEN HALT(100) END;
					IF 0#posix_spawn_file_actions_adddup2(ADDRESSOF(posix_spawn_actions[0]) , StdOutPipe[1] , StdOut) THEN HALT(100); END;(*in child process, the pipe will be used instead of StdOut*)
				END;
				
				IF StdErr IN redirectedStreams THEN 
					IF Unix.pipe(ADDRESSOF(StdErrPipe[0])) #0 THEN HALT(100) END;
					IF 0#posix_spawn_file_actions_adddup2(ADDRESSOF(posix_spawn_actions[0]) , StdErrPipe[1] , StdErr) THEN HALT(100); END;
				END;
				
				IF StdIn IN redirectedStreams THEN
					 IF Unix.pipe(ADDRESSOF(StdInPipe[0])) #0 THEN HALT(100) END;
					 IF 0#posix_spawn_file_actions_adddup2(ADDRESSOF(posix_spawn_actions[0]) , StdInPipe[0] , StdIn) THEN HALT(100); END;
				END;
				
				(*posix spawn*)
				IF 0# Unix.posix_spawnp(ADDRESSOF(pid), ADDRESSOF(executable), ADDRESSOF(posix_spawn_actions[0]),  NIL,   ADDRESSOF(argv[0]), Unix.environ) THEN HALT(100); END;
				
				IF StdOut IN redirectedStreams THEN
					IF 0#Unix.close(StdOutPipe[1]) THEN HALT(100); END;  (*close the write end since parent process is not using it *)
					NEW(stdOutRedirector,stdOutWriter,StdOutPipe[0],stdOutUpdateSetting);	
				END; 
				IF StdErr IN redirectedStreams THEN 
					IF 0#Unix.close(StdErrPipe[1]) THEN HALT(100); END;
					NEW(stdErrRedirector,stdErrWriter,StdErrPipe[0],stdErrUpdateSetting); 
				END;
				IF StdIn IN redirectedStreams THEN
					IF 0#Unix.close(StdInPipe[0]) THEN HALT(100);END;
					NEW(stdInRedirector,stdInReader,StdInPipe[1]);
				END;
			END;


			IF result = 0 THEN
				BEGIN{EXCLUSIVE}
					isRunning := TRUE;
				END;
				res := Ok;
				RETURN TRUE;
			ELSE
				res := HostOsError;
				hostOsRes:=result;
				RETURN FALSE;
			END;

		FINALLY
			res := UnknownError;
			RETURN FALSE;
		END Execute;

		(** Wait until the application terminates either by itself or after a call of Terminate *)
		PROCEDURE WaitForTermination*();
		BEGIN{EXCLUSIVE}
			AWAIT(~isRunning);
		END WaitForTermination;

		(**
			Forcedly terminate the application
		*)
		PROCEDURE Terminate*(): BOOLEAN;
		VAR result: SIGNED32;
		BEGIN{EXCLUSIVE}
			IF ~isRunning THEN res := AppNotRunning; RETURN FALSE; END;

			IF redirectedStreams # {} THEN (* close streams *)
				 (*todo: close open pipe ends, destroy pipes*)
				 IF StdOut IN redirectedStreams THEN
				 	stdOutRedirector.Kill;
				 END;
				 IF StdErr IN redirectedStreams THEN
				 	stdErrRedirector.Kill;
				 END;
				 IF StdIn IN redirectedStreams THEN
				 	stdInRedirector.Kill;
				 END;
			END;			
			result:= Unix.kill(pid,9);
			IF result # 0 THEN
				res := result;
				RETURN FALSE;
			END;


			AWAIT(~isRunning);

			res := Ok;
			RETURN TRUE;

		FINALLY
			res := UnknownError;
			RETURN FALSE;
		END Terminate;

		(**
			Finalize the object. After this the object cannot be reused for executing applications.
		*)
		PROCEDURE Finalize*();
		BEGIN
			IF ~Terminate() THEN END;
			BEGIN{EXCLUSIVE}
				isObjAlive := FALSE;
			END;
		END Finalize;

		PROCEDURE WaitForTerminationInternal;
		VAR result: SIGNED32;
			status,options: SIGNED32;
		BEGIN

			(*
				close pipes, redirect streams back to normal
			*)
			options:=0;
			REPEAT
				result:=Unix.waitpid(pid, ADDRESSOF(status), options);
				exitCode  := status DIV 256; 
				IF (result < 0) & (Unix.errno() = Unix.EINTR) THEN 
					result := 0
				END;
			UNTIL result # 0;
			
			(*todo: close pipe ends, clean up pipes*)
			IF StdIn IN redirectedStreams THEN
				stdInRedirector.Kill;
			END;
			IF StdOut IN redirectedStreams THEN
				stdOutRedirector.Kill;  
			END;
			IF StdErr IN redirectedStreams THEN
				stdErrRedirector.Kill;
			END;
			
			BEGIN{EXCLUSIVE}
				IF finalizeOnExit THEN isObjAlive := FALSE; END;
				isRunning := FALSE;
			END;

		FINALLY
		END WaitForTerminationInternal;

		

	BEGIN{ACTIVE}

		WHILE isObjAlive DO

			BEGIN{EXCLUSIVE}
				AWAIT(isRunning OR ~isObjAlive);
			END;

			IF isObjAlive THEN
				WaitForTerminationInternal;
			END;

		END;

		BEGIN{EXCLUSIVE}
			res := ObjIsFinalized; (*! tell the user that the object is already invalid *)
		END;
	END Application;


	StdInRedirector = OBJECT
	VAR
		running: BOOLEAN;
		numW: SIZE;
		ignore: SIZE; 
		reader: Streams.Reader;
		pipeEnd: SIGNED32;
		buf: ARRAY 128 OF CHAR;
	PROCEDURE &InitStdInRedirector*(reader: Streams.Reader; pipeEnd: SIGNED32);
	BEGIN
		running:=TRUE;
		SELF.reader:=reader;
		SELF.pipeEnd:=pipeEnd;
	END InitStdInRedirector;
	
	PROCEDURE Kill*;
	BEGIN
		running:=FALSE;
	END Kill;
	
	BEGIN{ACTIVE}
		WHILE running DO
			reader.Bytes(buf,0,1,ignore);		(*read stream to buffer*)
			REPEAT 
				numW := UnixWrite(pipeEnd,ADDRESSOF(buf[0]) ,1); 			(*send buffer to unix pipe *)
			UNTIL numW # 0;
			IF numW<0 THEN
				Kill;
			END;
		END;
	END StdInRedirector;



	OutputRedirector = OBJECT
	CONST
		bufSize=128;
	VAR
		running: BOOLEAN;
		updateSetting: SIGNED32;
		numR,offs: SIZE;
		writer: Streams.Writer;
		pipeEnd: SIGNED32;
		buf: ARRAY bufSize OF CHAR;

		PROCEDURE &InitStdOutRedirector*(writer: Streams.Writer; pipeEnd: SIGNED32; updateSetting: SIGNED32);
		BEGIN
			running:=TRUE;
			SELF.writer:= writer;
			SELF.pipeEnd:=pipeEnd;
			SELF.updateSetting:=updateSetting;
		END InitStdOutRedirector;
		
		PROCEDURE Kill*;
		BEGIN
			running:=FALSE;
		END Kill;
	
	BEGIN{ACTIVE}
		WHILE running DO
			IF updateSetting<UpdateNone THEN			 	(*newline*)
				offs:=0; numR:=0;
				buf[offs]:=0X;
				WHILE (offs<bufSize) & (buf[offs-numR] # CR) & (buf[offs-numR] # LF) DO
					numR := UnixRead(pipeEnd, ADDRESSOF(buf[offs]),1);
					IF numR<0 THEN 
						offs:=bufSize;
						Kill;
					ELSE
						INC(offs,numR);
					END;
				END;
				writer.Bytes(buf,0,SIGNED32(offs));
			ELSIF updateSetting>UpdateNone THEN 			(*any*)
				numR := UnixRead(pipeEnd, ADDRESSOF(buf[0]),1); (* read from pipe *)
				IF numR<0 THEN
					Kill;
				ELSE
					writer.Bytes(buf,0,SIGNED32(numR));	(*push result to writer*)
					writer.Update;
					(*updatesetting with count stuff not implemented*)
				END;
			ELSE 												(*none*)
					numR:=UnixRead(pipeEnd, ADDRESSOF(buf[0]),1); (* read from pipe *)
			END
		END;
	END OutputRedirector;

	PROCEDURE UnixRead( fd: SIGNED32; buf: ADDRESS; len: SIZE ): SIZE;
	VAR n: SIZE;
	BEGIN
		REPEAT
			n := Unix.read( fd, buf, len )
		UNTIL (n >= 0) OR (Unix.errno() # Unix.EINTR);
		RETURN n
	END UnixRead;	
	
	PROCEDURE UnixWrite( fd: SIGNED32; buf: ADDRESS; len: SIZE ): SIZE;
	VAR n: SIZE;
	BEGIN
		REPEAT
			n := Unix.write( fd, buf, len )
		UNTIL (n >= 0) OR (Unix.errno() # Unix.EINTR);
		RETURN n
	END UnixWrite;	
		

	(**
		Execute an application

		Syntaxis:

			ExecuteApp options executable param1 param2 ... ~

			options: command options
			executable: application file name
			paramX: X-th parameter passed to the application to run (parameters are to be delimited by "")
	*)
	PROCEDURE ExecuteApp*(context: Commands.Context);
	VAR
		executable, parameters: Files.FileName;
		app: Application;
		options: Options.Options;
	BEGIN
		NEW(options);
		options.Add("o","redirectStdOut",Options.Flag);
		options.Add("e","redirectStdErr",Options.Flag);
		IF ~options.Parse(context.arg,context.error) THEN
			context.result := 1;
			RETURN;
		END;
		IF ~context.arg.GetString(executable) THEN
			context.error.String("application file name is expected!"); context.error.Ln;
			context.result := 1;
			RETURN;
		END;

		NEW(app,executable);
		WHILE context.arg.GetString(parameters) DO
			app.AddParameter(parameters);
		END;

		IF options.GetFlag("redirectStdOut") THEN
			ASSERT(app.SetStdOut(context.out,UpdateLn));
		END;
		IF options.GetFlag("redirectStdErr") THEN
			ASSERT(app.SetStdErr(context.error,UpdateLn));
		END;

		IF app.Execute(TRUE) THEN
			app.WaitForTermination;
			context.result := app.exitCode;
			context.out.String('application "'); context.out.String(executable); context.out.String('" exited with result code '); context.out.Int(app.exitCode,0); context.out.Ln;
		ELSE
			context.result := 1;
			context.error.String('failed to execute the application "'); context.error.String(executable);
			context.error.String('", res: '); context.error.Int(app.res,0);
			context.error.String(" , host OS res: "); context.error.Int(app.hostOsRes,0);
			context.error.Ln;
		END;

		RETURN;

	FINALLY
		context.error.String("unexpected error occurred!"); context.error.Ln;
		context.result := 1;
	END ExecuteApp;



BEGIN
	Unix.Dlsym( Unix.libc, "posix_spawn_file_actions_init", ADDRESSOF(posix_spawn_file_actions_init));
	Unix.Dlsym( Unix.libc, "posix_spawn_file_actions_destroy", ADDRESSOF(posix_spawn_file_actions_destroy));
	Unix.Dlsym( Unix.libc, "posix_spawn_file_actions_adddup2", ADDRESSOF(posix_spawn_file_actions_adddup2));
END HostOsApps.

SystemTools.FreeDownTo HostOsApps ~

HostOsApps.ExecuteApp --redirectStdOut --redirectStdErr "C:\Windows\System32\cmd.exe" "/c temp.bat" ~

HostOsApps.ExecuteApp  "/bin/ls" ~
HostOsApps.ExecuteApp  "/bin/ls" "-l" "oberon" ~





HostOsApps.ExecuteApp  --redirectStdErr --redirectStdOut "/bin/ls" "oberon" ~


HostOsApps.ExecuteApp "C:/Windows/System32/cmd.exe" "/c c:/Xilinx/Vivado/2014.4/bin/vivado.bat -mode tcl" ~

HostOsApps.ExecuteApp "/bin/bash" "/opt/Xilinx/Vivado/2014.4/bin/vivado" "-mode" "tcl" ~
