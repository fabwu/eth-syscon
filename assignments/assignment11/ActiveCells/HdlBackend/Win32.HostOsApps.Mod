(**
	AUTHOR "Alexey Morozov";
	PURPOSE "Tools for running applications of the host OS (Win32)";
*)
MODULE HostOsApps;

IMPORT
	SYSTEM, Kernel32, User32, Streams, Files, Strings, Commands, Modules, HostOsLibs, Options, KernelLog;

CONST

	(** Application IO stream types *)
	StdOut* = 0; (** Standard output *)
	StdIn* = 1; (** Standard input *)
	StdErr* = 2; (** Standard error output *)

	(** Error codes *)
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

	(* Window show states *)
	SW_FORCEMINIMIZE* = 11; (* Minimizes a window, even if the thread that owns the window is not responding. This flag should only be used when minimizing windows from a different thread. *)
	SW_HIDE* = 0; (* Hides the window and activates another window. *)
	SW_MAXIMIZE* = 3; (* Maximizes the specified window. *)
	SW_MINIMIZE* = 6; (* Minimizes the specified window and activates the next top-level window in the Z order. *)
	SW_RESTORE* = 9; (* Activates and displays the window. If the window is minimized or maximized, the system restores it to its original startupInfoze and postartupInfotion. An application should specify this flag when restoring a minimized window. *)
	SW_SHOW* = 5; (* Activates the window and displays it in its current startupInfoze and postartupInfotion. *)
	SW_SHOWDEFAULT* = 10; (* Sets the show state based on the SW_ value specified in the STARTUPINFO structure passed to the CreateProcess function by the program that started the application. *)
	SW_SHOWMAXIMIZED* = 3; (* Activates the window and displays it as a maximized window. *)
	SW_SHOWMINIMIZED* = 2; (* Activates the window and displays it as a minimized window. *)
	SW_SHOWMINNOACTIVE* = 7; (* Displays the window as a minimized window. This value is startupInfomilar to SW_SHOWMINIMIZED, except the window is not activated. *)
	SW_SHOWNA* = 8; (* Displays the window in its current startupInfoze and postartupInfotion. This value is startupInfomilar to SW_SHOW, except that the window is not activated. *)
	SW_SHOWNOACTIVATE* = 4; (* Displays a window in its most recent startupInfoze and postartupInfotion. This value is startupInfomilar to SW_SHOWNORMAL, except that the window is not activated. *)
	SW_SHOWNORMAL* = 1; (* Activates and displays a window. If the window is minimized or maximized, the system restores it to its original startupInfoze and postartupInfotion. An application should specify this flag when displaying the window for the first time. *)

	StartFUseStdHandles = 8;

	(* values returned by Kernel32.WaitForSingleObject *)
	WAIT_TIMEOUT = 0x00000102; (* The time-out interval elapsed, and the object's state is nonsignaled. *)
	WAIT_OBJECT_0 = 0x00000000; (* The state of the specified object is signaled. *)

	DefaultStdOutBufSize = 16384; (* default buffer size for StdOut stream *)
	DefaultStdInBufSize = 16384; (* default buffer size for StdIn stream *)
	DefaultStdErrBufSize = 16384; (* default buffer size for StdErr stream *)

	StreamDataCheckInterval = 30; (* interval in ms for checking availability of data from StdOut and StdErr streams *)

	CR = 0DX;
	LF = 0AX;

TYPE

	DWORD = Kernel32.DWORD;

	SecurityAttributes = RECORD
		nLength: DWORD;
		lpSecurityDescriptor: ADDRESS;
		bInheritHandle: Kernel32.BOOL;
	END;

	(**
		Host OS application object.

		A single object instance can be reused for executing multiple applications.
	*)
	Application* = OBJECT
	VAR
		isRunning-: BOOLEAN; (** TRUE if the application is currently running *)
		exitCode-: SIGNED32; (** application exit code *)

		res-: INTEGER; (** result code *)
		hostOsRes-: SIGNED32; (** host OS result code in case if res = HostOsError *)

		executable: Files.FileName; (* application executable file name *)
		params: Strings.String; (* application execution parameters  *)
		paramsSize: SIZE; (* size of the parameters *)

		redirectedStreams: SET; (* streams to redirect (StdOut, StdIn, StdErr) *)
		stdIn: Streams.Reader;
		stdOut, stdErr: Streams.Writer;
		stdOutUpdateSetting, stdErrUpdateSetting: SIGNED32;
		stdOutBufSize, stdInBufSize, stdErrBufSize: SIGNED32;
		stdOutCount, stdErrCount: SIZE;
		stdOutFoundCR, stdErrFoundCR: BOOLEAN;
		workingDirectory: Files.FileName; (* working directory of the application *)

		(* Windows specific structures *)
		startupInfo: Kernel32.StartupInfo;
		processInformation: Kernel32.ProcessInformation;
		hStdOutputRd, hStdInputWr, hStdErrorRd: Kernel32.HANDLE;

		isObjAlive: BOOLEAN; (* TRUE if the object is alive *)
		finalizeOnExit: BOOLEAN; (* TRUE for finalization of the object on application exit *)
		initFlag: BOOLEAN;

		buf: ARRAY 65536 OF CHAR; (* data buffer *)

		(**
			Initialize Application object
		*)
		PROCEDURE &InitApplication*(CONST executableName: ARRAY OF CHAR);
		BEGIN
			IF initFlag & ~isObjAlive THEN res := ObjIsFinalized; RETURN; END;
			IF isRunning THEN res := CannotDoWhileRunning; RETURN; END;

			SetExecutable(executableName);

			paramsSize := 0; (* empty the parameter list *)

			stdOutBufSize := DefaultStdOutBufSize;
			stdInBufSize := DefaultStdInBufSize;
			stdErrBufSize := DefaultStdErrBufSize;

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
		VAR i, j, n: SIZE;
		BEGIN
			n := Strings.Length(parameter);
			IF params = NIL THEN NEW(params,MAX(1024,n+2)); END;

			j := 0;
			FOR i := paramsSize TO paramsSize+n-1 DO params[i] := parameter[j]; INC(j); END;
			params[i] := 0X;
			params[i+1] := 0X;
			INC(paramsSize,n+1);
		END AddParameter;

		(**
			Clear the list of application parameters
		*)
		PROCEDURE ClearParameters*();
		BEGIN
			paramsSize := 0;
		END ClearParameters;

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
			stdOut := writer;
			stdOutUpdateSetting := writerUpdateSetting;
			IF stdOut # NIL THEN INCL(redirectedStreams,StdOut); ELSE EXCL(redirectedStreams,StdOut); END;
			res := Ok;
			RETURN TRUE;
		END SetStdOut;

		(**
			Setup standard input redirection

			reader: standard input data source

			Returns TRUE in case of success. In case of an error returns FALSE and stores the error code in res.
		*)
		PROCEDURE SetStdIn*(CONST reader: Streams.Reader): BOOLEAN;
		BEGIN
			IF isRunning THEN res := CannotDoWhileRunning; RETURN FALSE; END;
			stdIn := reader;
			IF stdIn # NIL THEN INCL(redirectedStreams,StdIn); ELSE EXCL(redirectedStreams,StdIn); END;
			res := Ok;
			RETURN TRUE;
		END SetStdIn;

(*
		(**
			Setup standard input redirection

			enableRedirection: TRUE for enabling the redirection of the standard input

			Returns TRUE in case of success. In case of an error returns FALSE and stores the error code in res.
		*)
		PROCEDURE SetStdIn*(enableRedirection: BOOLEAN): BOOLEAN;
		BEGIN
			IF isRunning THEN res := CannotDoWhileRunning; RETURN FALSE; END;
			IF enableRedirection THEN INCL(redirectedStreams,StdIn); ELSE EXCL(redirectedStreams,StdIn); END;
			res := Ok;
			RETURN TRUE;
		END SetStdIn;

		(**
			Procedure used for sending data to the standard input of the application; compatible with Streams.Sender and pluggable to Streams.Writer
		*)
		PROCEDURE StdInSender*(CONST data: ARRAY OF CHAR; offset, length: SIGNED32; propagate: BOOLEAN; VAR res: SIGNED32);
		TYPE Sender = PROCEDURE(len, addr: ADDRESS; VAR res: SIGNED32);
		VAR send: Sender;
		BEGIN
			IF (StdIn IN redirectedStreams) & isRunning THEN
				ASSERT((offset >= 0) & (offset+length <= LEN(data)));
				(* avoid data movement *)
				send := SYSTEM.VAL(Sender,StdInSender0);
				TRACE(ADDRESSOF(data[0]),ADDRESSOF(data[offset]));
				send(length,ADDRESSOF(data[offset]),res);
			ELSIF ~isRunning THEN
				res := AppNotRunning; RETURN;
			ELSE
				res := InvalidStream; RETURN;
			END;
		END StdInSender;

		PROCEDURE StdInSender0(CONST data: ARRAY OF CHAR; VAR res: SIGNED32);
		VAR
			bool: Kernel32.BOOL;
			n, result: DWORD;
		BEGIN
			result := Kernel32.WaitForSingleObject(processInformation.hProcess,0);
			TRACE(result);
			TRACE(LEN(data),ADDRESSOF(data[0]));
			(*!TODO: handle cases when an error is returned by WriteFile *)
			bool := Kernel32.WriteFile(hStdInputWr,data,LEN(data),n,NIL);
			IF bool # 1 THEN
				TRACE(Kernel32.GetLastError());
			END;
			ASSERT(n = LEN(data));
			res := 0;
		END StdInSender0;
*)

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
			stdErr := writer;
			stdErrUpdateSetting := writerUpdateSetting;
			IF stdErr # NIL THEN INCL(redirectedStreams,StdErr); ELSE EXCL(redirectedStreams,StdErr); END;
			res := Ok;
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

			IF StdOut IN selectedStreams THEN stdOutBufSize := bufferSize;  END;
			IF StdIn IN selectedStreams THEN stdInBufSize := bufferSize; END;
			IF StdErr IN selectedStreams THEN stdErrBufSize := bufferSize; END;

			res := Ok;
			RETURN TRUE;
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
			result: DWORD;
			lpProcessAttributes, lpThreadAttributes, lpEnvironment: ANY;
			bInheritHandles: Kernel32.BOOL;
			dwCreationFlags: DWORD;
			securityAttributes: SecurityAttributes;
		BEGIN
			IF ~isObjAlive THEN res := ObjIsFinalized; RETURN FALSE; END;
			IF isRunning THEN res := CannotDoWhileRunning; RETURN FALSE; END;

			finalizeOnExit := finalizeObjectOnExit;

			startupInfo.cb := SIZEOF(Kernel32.StartupInfo);
			startupInfo.dwFlags := {Kernel32.StartFUseShowWindow};
			startupInfo.wShowWindow := SW_HIDE(*SW_SHOWNORMAL*);

			lpProcessAttributes := NIL;
			lpThreadAttributes := NIL;
			bInheritHandles := Kernel32.True;
			dwCreationFlags := 0;
			lpEnvironment := NIL; (* inherit the environment from the current process *)

			(*IF params # NIL THEN TRACE(params^); END;*)

			IF redirectedStreams = {} THEN (* no stream redirection is used *)

				startupInfo.hStdInput := 0;
				startupInfo.hStdOutput := 0;
				startupInfo.hStdError := 0;

			ELSE

				startupInfo.dwFlags := startupInfo.dwFlags + {StartFUseStdHandles};

				securityAttributes.nLength := SIZEOF(SecurityAttributes);
				securityAttributes.bInheritHandle := Kernel32.True;
				securityAttributes.lpSecurityDescriptor := NIL;

				IF StdOut IN redirectedStreams THEN ASSERT(CreatePipe(hStdOutputRd,startupInfo.hStdOutput,securityAttributes,stdOutBufSize) = Kernel32.True); END;
				IF StdIn IN redirectedStreams THEN ASSERT(CreatePipe(startupInfo.hStdInput,hStdInputWr,securityAttributes,stdInBufSize) = Kernel32.True); END;
				IF StdErr IN redirectedStreams THEN ASSERT(CreatePipe(hStdErrorRd,startupInfo.hStdError,securityAttributes,stdErrBufSize) = Kernel32.True); END;

				stdOutCount := 0;
				stdErrCount := 0;
				stdOutFoundCR := FALSE;
				stdErrFoundCR := FALSE;
			END;

			IF workingDirectory = "" THEN
				IF params # NIL THEN
					result := Kernel32.CreateProcess(executable,params^,lpProcessAttributes,lpThreadAttributes,bInheritHandles,dwCreationFlags,lpEnvironment,NIL,startupInfo,processInformation);
				ELSE
					result := Kernel32.CreateProcess(executable,NIL,lpProcessAttributes,lpThreadAttributes,bInheritHandles,dwCreationFlags,lpEnvironment,NIL,startupInfo,processInformation);
				END;
			ELSE
				IF params # NIL THEN
					result := Kernel32.CreateProcess(executable,params^,lpProcessAttributes,lpThreadAttributes,bInheritHandles,dwCreationFlags,lpEnvironment,workingDirectory,startupInfo,processInformation);
				ELSE
					result := Kernel32.CreateProcess(executable,NIL,lpProcessAttributes,lpThreadAttributes,bInheritHandles,dwCreationFlags,lpEnvironment,workingDirectory,startupInfo,processInformation);
				END;
			END;

			IF result # 0 THEN
				BEGIN{EXCLUSIVE}
					isRunning := TRUE;
				END;
				res := Ok;
				RETURN TRUE;
			ELSE
				res := HostOsError;
				hostOsRes := Kernel32.GetLastError();
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
		VAR result: DWORD;
		BEGIN{EXCLUSIVE}
			IF ~isRunning THEN res := AppNotRunning; RETURN FALSE; END;
(*
			TRACE(processInformation.dwProcessId,processInformation.dwThreadId);
			User32.EnumWindows(TerminateAppEnum,processInformation.dwProcessId);
			(*result := Kernel32.WaitForSingleObject(processInformation.hProcess,StreamDataCheckInterval);*)
*)
			IF redirectedStreams # {} THEN (* close streams *)
				IF hStdOutputRd # NIL THEN ASSERT(Kernel32.CloseHandle(hStdOutputRd) = Kernel32.True); END;
				IF hStdInputWr # NIL THEN ASSERT(Kernel32.CloseHandle(hStdInputWr) = Kernel32.True); END;
				IF hStdErrorRd # NIL THEN ASSERT(Kernel32.CloseHandle(hStdErrorRd) = Kernel32.True); END;
				IF startupInfo.hStdInput # 0 THEN ASSERT(Kernel32.CloseHandle(startupInfo.hStdInput) = Kernel32.True); END;
				IF startupInfo.hStdOutput # 0 THEN ASSERT(Kernel32.CloseHandle(startupInfo.hStdOutput) = Kernel32.True); END;
				IF startupInfo.hStdError # 0 THEN ASSERT(Kernel32.CloseHandle(startupInfo.hStdError) = Kernel32.True); END;
			END;

			result := TerminateProcess(processInformation.hProcess,0);
			IF result = 0 THEN
				res := HostOsError;
				hostOsRes := Kernel32.GetLastError();
				RETURN FALSE;
			END;

			ASSERT(Kernel32.CloseHandle(processInformation.hProcess) = Kernel32.True);
			ASSERT(Kernel32.CloseHandle(processInformation.hThread) = Kernel32.True);

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
		VAR result: DWORD;
		BEGIN

			result := Kernel32.WaitForSingleObject(processInformation.hProcess,Kernel32.Infinite);
			result := Kernel32.GetExitCodeProcess(processInformation.hProcess,exitCode);
			ASSERT(Kernel32.CloseHandle(processInformation.hProcess) = Kernel32.True);
			ASSERT(Kernel32.CloseHandle(processInformation.hThread) = Kernel32.True);

			IF redirectedStreams # {} THEN (* close pipes *)
				IF hStdOutputRd # NIL THEN ASSERT(Kernel32.CloseHandle(hStdOutputRd) = Kernel32.True); END;
				IF hStdInputWr # NIL THEN ASSERT(Kernel32.CloseHandle(hStdInputWr) = Kernel32.True); END;
				IF hStdErrorRd # NIL THEN ASSERT(Kernel32.CloseHandle(hStdErrorRd) = Kernel32.True); END;
				IF startupInfo.hStdInput # 0 THEN ASSERT(Kernel32.CloseHandle(startupInfo.hStdInput) = Kernel32.True); END;
				IF startupInfo.hStdOutput # 0 THEN ASSERT(Kernel32.CloseHandle(startupInfo.hStdOutput) = Kernel32.True); END;
				IF startupInfo.hStdError # 0 THEN ASSERT(Kernel32.CloseHandle(startupInfo.hStdError) = Kernel32.True); END;
			END;

			BEGIN{EXCLUSIVE}
				IF finalizeOnExit THEN isObjAlive := FALSE; END;
				isRunning := FALSE;
			END;

		FINALLY
		END WaitForTerminationInternal;

		(* Returns TRUE if a new line sequence was found in the stream data *)
		PROCEDURE FindLn(CONST data: ARRAY OF CHAR; VAR offs, len: SIZE; VAR foundCR: BOOLEAN): BOOLEAN;
		BEGIN

			WHILE (len > 0) & (data[offs] # CR) & (data[offs] # LF) DO
				INC(offs); DEC(len);
			END;

			IF len # 0 THEN
				INC(offs,len); len := 0;
				RETURN TRUE;
			ELSE RETURN FALSE;
			END;
(*
			IF foundCR THEN
				IF data[offs] = LF THEN
					INC(offs,1); DEC(len,1); (* include LF character *)
				END;
				foundCR := FALSE;
				RETURN TRUE;
			END;

			WHILE len > 0 DO
				IF data[offs] = CR THEN
					IF len > 1 THEN
						IF data[offs+1] = LF THEN
							INC(offs,2); DEC(len,2); (* include CR+LF characters *)
						ELSE
							INC(offs); DEC(len); (* include CR character *)
						END;
						RETURN TRUE;
					ELSE
						foundCR := TRUE;
					END;
				ELSIF  data[offs] = LF THEN
					INC(offs); DEC(len); (* include LF character *)
					RETURN TRUE;
				END;
				INC(offs); DEC(len);
			END;
			RETURN FALSE;
*)
		END FindLn;

		PROCEDURE ProcessStreams;
		VAR
			k, m, n: SIZE;
			ndw: Kernel32.DWORD;
			result: INTEGER;
			bool: Kernel32.BOOL;
		BEGIN

			result := Kernel32.WaitForSingleObject(processInformation.hProcess,0);
			WHILE result = WAIT_TIMEOUT DO

				IF StdIn IN redirectedStreams THEN
					m := stdIn.Available();
					IF m > 0 THEN
						stdIn.Bytes(buf,0,m,n); ASSERT(n = m);
						bool := Kernel32.WriteFile(hStdInputWr,buf,DWORD(m),ndw,NIL); ASSERT(ndw = m);
					END;
				END;

				IF StdOut IN redirectedStreams THEN
					bool := PeekNamedPipe(hStdOutputRd,NIL,0,NIL,ndw,NIL); m := ndw;
					IF (bool = 1) & (m > 0) THEN
						m := MIN(m,LEN(buf));
						(*!TODO: handle cases when an error is returned by ReadFile *)
						bool := Kernel32.ReadFile(hStdOutputRd,buf,DWORD(m),ndw,NIL); ASSERT(ndw = m); n := ndw;
						(* Update logic *)
						IF stdOutUpdateSetting >= UpdateNone THEN
							stdOut.Bytes(buf,0,n);
							IF stdOutUpdateSetting = UpdateAny THEN
								stdOut.Update;
							ELSIF stdOutUpdateSetting > UpdateAny THEN
								INC(stdOutCount,n);
								IF stdOutCount >= stdOutUpdateSetting THEN
									stdOutCount := 0;
									stdOut.Update;
								END;
							END;
						ELSE (* new line based update *)
							k := 0; m := 0;
							WHILE FindLn(buf,m,n,stdOutFoundCR) DO
								(*TRACE(k,m,n,stdOutFoundCR);*)
								stdOut.Bytes(buf,k,m-k); INC(k,m);
								stdOut.Update;
							END;
							ASSERT(n = 0);
							IF m-k > 0 THEN stdOut.Bytes(buf,k,m-k); END;
						END;

					END;
				END;

				IF StdErr IN redirectedStreams THEN
					bool := PeekNamedPipe(hStdErrorRd,NIL,0,NIL,ndw,NIL); m := ndw;
					IF (bool = 1) & (m > 0) THEN
						m := MIN(m,LEN(buf));
						(*!TODO: handle cases when an error is returned by ReadFile *)
						bool := Kernel32.ReadFile(hStdErrorRd,buf,DWORD(m),ndw,NIL); ASSERT(ndw = m); n := ndw;
						IF stdErrUpdateSetting >= UpdateNone THEN
							stdErr.Bytes(buf,0,n);
							IF stdErrUpdateSetting = UpdateAny THEN stdErr.Update;
							ELSIF stdErrUpdateSetting > UpdateAny THEN
								INC(stdErrCount,n);
								IF stdErrCount >= stdErrUpdateSetting THEN
									stdErrCount := 0;
									stdErr.Update;
								END;
							END;
						ELSE (* new line based update *)
							k := 0; m := 0;
							WHILE FindLn(buf,m,n,stdErrFoundCR) DO
								stdErr.Bytes(buf,k,m-k); INC(k,m);
								stdErr.Update;
							END;
							ASSERT(n = 0);
							IF m-k > 0 THEN stdErr.Bytes(buf,k,m-k); END;
						END;

					END;
				END;

				result := Kernel32.WaitForSingleObject(processInformation.hProcess,StreamDataCheckInterval);
			END;

			BEGIN{EXCLUSIVE}
				IF finalizeOnExit THEN isObjAlive := FALSE; END;
				isRunning := FALSE;
			END;

		END ProcessStreams;

	BEGIN{ACTIVE}

		WHILE isObjAlive DO

			BEGIN{EXCLUSIVE}
				AWAIT(isRunning OR ~isObjAlive);
			END;

			IF isObjAlive THEN
				IF redirectedStreams = {} THEN
					WaitForTerminationInternal;
				ELSE
					ProcessStreams;
				END;
			END;

		END;

		BEGIN{EXCLUSIVE}
			res := ObjIsFinalized; (*! tell the user that the object is already invalid *)
		END;

		TRACE("Application object exited!");
	END Application;
	
	(*todo: move stream redirection to 3 soparate rediroctor processes that each use blocking io!*)


	(*HWND = Kernel32.HANDLE;
	EnumWindowsProc = PROCEDURE{WINAPI}(hwnd: HWND; lParam: ADDRESS);*)

VAR
	lib, lib1: HostOsLibs.LibHandle;

	(* Retrieves the environment variables for the current process. *)
	GetEnvironmentStrings: PROCEDURE{WINAPI}(): ANY;

	(* Terminates the specified process and all of its threads. *)
	TerminateProcess: PROCEDURE{WINAPI}(hProcess: Kernel32.HANDLE; uExitCode: INTEGER): Kernel32.BOOL;

	(* Creates an anonymous pipe, and returns handles to the read and write ends of the pipe. *)
	CreatePipe: PROCEDURE{WINAPI}(VAR hReadPipe: Kernel32.HANDLE; VAR hWritePipe: Kernel32.HANDLE; VAR lpPipeAttributes: SecurityAttributes; nSize: DWORD): Kernel32.BOOL;

	GetNamedPipeInfo: PROCEDURE{WINAPI}(hNamedPipe: Kernel32.HANDLE; VAR lpFlags: DWORD; VAR lpOutBufSize: DWORD; VAR lpInBufSize: DWORD; VAR lpMaxInstances: DWORD): Kernel32.BOOL;

	PeekNamedPipe: PROCEDURE{WINAPI}(hNamedPipe: Kernel32.HANDLE; VAR lpBuffer: ARRAY OF CHAR; nBufSize: DWORD; VAR lpBytesRead: DWORD; VAR lpTotalBytesAvail: DWORD; VAR lpBytesLeftThisMessage: DWORD): Kernel32.BOOL;

	(*EnumWindows: PROCEDURE{WINAPI}(lpEnumFunc: EnumWindowsProc; lParam: ADDRESS);*)

	GetWindowThreadProcessId: PROCEDURE{WINAPI}(hWnd: User32.HWND; VAR dwProcessId: DWORD): DWORD;

	PROCEDURE{WINAPI} TerminateAppEnum(hWnd: User32.HWND; lParam: User32.LParam): Kernel32.BOOL;
	VAR 
		dwThreadId, dwProcessId: DWORD;
	BEGIN
		dwThreadId := GetWindowThreadProcessId(hWnd,dwProcessId);
		TRACE(dwThreadId,dwProcessId);
		IF dwProcessId = DWORD(lParam) THEN
			ASSERT(User32.PostMessage(hWnd,User32.WMClose,0,0) = Kernel32.True);
			TRACE(dwProcessId,lParam);
		END;
		RETURN 1;
	END TerminateAppEnum;

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
		IF context.arg.GetString(parameters) THEN
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

	PROCEDURE InitMod;
	BEGIN
		IF ~HostOsLibs.LoadLibrary("Kernel32.dll",lib) THEN
			KernelLog.String("Failed to load Kernel32 library!"); KernelLog.Ln;
		END;
		IF ~HostOsLibs.GetProcedure(lib,"GetEnvironmentStringsA",SYSTEM.VAL(ADDRESS,GetEnvironmentStrings)) THEN
			KernelLog.String("Failed to load GetEnvironmentStringsA method from Kernel32 library!"); KernelLog.Ln;
		END;
		IF ~HostOsLibs.GetProcedure(lib,"TerminateProcess",SYSTEM.VAL(ADDRESS,TerminateProcess)) THEN
			KernelLog.String("Failed to load TerminateProcess method from Kernel32 library!"); KernelLog.Ln;
		END;
		IF ~HostOsLibs.GetProcedure(lib,"CreatePipe",SYSTEM.VAL(ADDRESS,CreatePipe)) THEN
			KernelLog.String("Failed to load CreatePipe method from Kernel32 library!"); KernelLog.Ln;
		END;
		IF ~HostOsLibs.GetProcedure(lib,"GetNamedPipeInfo",SYSTEM.VAL(ADDRESS,GetNamedPipeInfo)) THEN
			KernelLog.String("Failed to load GetNamedPipeInfo method from Kernel32 library!"); KernelLog.Ln;
		END;
		IF ~HostOsLibs.GetProcedure(lib,"PeekNamedPipe",SYSTEM.VAL(ADDRESS,PeekNamedPipe)) THEN
			KernelLog.String("Failed to load PeekNamedPipe method from Kernel32 library!"); KernelLog.Ln;
		END;
(*
		IF ~HostOsLibs.GetProcedure(lib,"EnumWindows",SYSTEM.VAL(ADDRESS,EnumWindows)) THEN
			KernelLog.String("Failed to load EnumWindows method from Kernel32 library!"); KernelLog.Ln;
		END;
*)

		IF ~HostOsLibs.LoadLibrary("User32.dll",lib1) THEN
			KernelLog.String("Failed to load User32 library!"); KernelLog.Ln;
		END;
		IF ~HostOsLibs.GetProcedure(lib1,"GetWindowThreadProcessId",SYSTEM.VAL(ADDRESS,GetWindowThreadProcessId)) THEN
			KernelLog.String("Failed to load GetWindowThreadProcessId method from Kernel32 library!"); KernelLog.Ln;
		END;

		Modules.InstallTermHandler(TerminateMod);
	END InitMod;

	PROCEDURE TerminateMod;
	BEGIN
		HostOsLibs.FreeLibrary(lib);
		HostOsLibs.FreeLibrary(lib1);
	END TerminateMod;

BEGIN
	InitMod;
END HostOsApps.

SystemTools.FreeDownTo HostOsApps ~

HostOsApps.ExecuteApp --redirectStdOut --redirectStdErr "C:\Windows\System32\cmd.exe" "/c temp.bat" ~


