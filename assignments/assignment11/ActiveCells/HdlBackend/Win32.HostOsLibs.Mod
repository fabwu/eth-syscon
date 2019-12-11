(**
	AUTHOR: "Alexey Morozov, 2015";
	PURPOSE: "Dynamic library tools for Win32 platforms";
*)
MODULE HostOsLibs;

IMPORT
	Kernel32;

CONST
	NilLibHandle* = Kernel32.NULL; (** invalid library handle *)

TYPE
	LibHandle* = Kernel32.HANDLE; (** dynamic library handle type *)

	(**
		Load a dynamic library

		fileName: library file name
		lib: returned loaded library handle; NilLibHandle in case of an error

		Returns TRUE in case of success
	*)
	PROCEDURE LoadLibrary*(CONST fileName: ARRAY OF CHAR; VAR lib: LibHandle): BOOLEAN;
	BEGIN
		lib := Kernel32.LoadLibrary(fileName);
		RETURN lib # NilLibHandle;
	FINALLY
		RETURN FALSE;
	END LoadLibrary;

	(** Free a loaded dynamic library *)
	PROCEDURE FreeLibrary*(VAR lib: LibHandle);
	VAR ok: Kernel32.BOOL;
	BEGIN
		IF lib # NilLibHandle THEN
			ok := Kernel32.FreeLibrary(lib); lib := NilLibHandle;
		END;
	FINALLY
	END FreeLibrary;

	(**
		Get a procedure from a loaded dynamic library

		lib: library handle
		name: name of the procedure to load
		proc: address of the exported procedure

		Returns TRUE in case of success
	*)
	PROCEDURE GetProcedure*(CONST lib: LibHandle; CONST name: ARRAY OF CHAR; VAR proc: ADDRESS): BOOLEAN;
	BEGIN
		IF lib # NilLibHandle THEN
			Kernel32.GetProcAddress(lib,name,proc);
			RETURN proc # NIL;
		END;
	FINALLY
		RETURN FALSE;
	END GetProcedure;

END HostOsLibs.
