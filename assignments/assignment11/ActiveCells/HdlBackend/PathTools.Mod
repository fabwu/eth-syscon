module PathTools;

import
	Files, Commands, Strings;

const
	(** Path traversal flags *)
	TraverseRecursive* = 0;
	TraverseFiles* = 1;
	TraverseDirs* = 2;

type
	(**
		Procedure used for path traversal
	*)
	PathTraversalProc* = procedure{DELEGATE}(const pathName: array of char; param: any): boolean;

	procedure JoinPath*(const path, name: array of char; var fileName: array of char);
	begin
		if path = "" then copy(name,fileName);
		else Files.JoinPath(path,name,fileName);
		end;
	end JoinPath;

	(**
		Generic path traversal

		path: root path, where the traversal will be performed
		pattern: traversal search pattern
		pathTraversalProc: path traversal procedure
		flags: path traversal flags (see CONST section)
		param: parameter passed to each call of the given path traversal procedure
	*)
	procedure TraversePath*(
									const path: array of char;
									const pattern: array of char;
									pathTraversalProc: PathTraversalProc;
									flags: set;
									param: any
									): boolean;
	var
		var enumerator: Files.Enumerator;
		name: Files.FileName;
		time, date: signed32;
		sz: Files.Size;
		eflags: set;
	begin
		new(enumerator);

		(* first find items fully matching path+pattern *)
		JoinPath(path,pattern,name);
		enumerator.Open(name,{});
		while enumerator.HasMoreEntries() do
			if enumerator.GetEntry(name,eflags,time,date,sz) then
				if Files.Directory in eflags then
					if TraverseDirs in flags then
						if ~pathTraversalProc(name,param) then return false; end;
					end;
					if TraverseRecursive in flags then
						if ~TraversePath(name,pattern,pathTraversalProc,flags,param) then return false; end;
					end;
				elsif TraverseFiles in flags then
					if ~pathTraversalProc(name,param) then return false; end;
				end;
			end;
		end;

		if (TraverseRecursive in flags) & ( (pattern = "*") or (pattern = "*.*") ) then (* search in subdirectories *)
			JoinPath(path,"*",name);
			enumerator.Open(name,{});
			while enumerator.HasMoreEntries() do
				if enumerator.GetEntry(name,eflags,time,date,sz) then
					if Files.Directory in eflags then
						if TraverseDirs in flags then
							if ~pathTraversalProc(name,param) then return false; end;
						end;
						if ~TraversePath(name,pattern,pathTraversalProc,flags,param) then return false; end;
					end;
				end;
			end;
		end;

		return true;
	finally
		return false;
	end TraversePath;

	(**
		Create a directory given a relative path name
	*)
	procedure CreateDirectory*(const pathName: array of char; var fullPathName: array of char): boolean;
	var
		str0, str: Files.FileName;
		i, j, n: size; res: integer;
		b: boolean;
	begin
		if DirectoryExists(pathName,fullPathName) then return true; end;
		copy(pathName,str0);
		Strings.TrimWS(str0);
		n := Strings.Length(str0);
		if str0[n-1] = Files.PathDelimiter then str0[n-1] := 0X; end;
		copy(str0,str);

		b := false;
		repeat
			i := Strings.LastIndexOfByte2(Files.PathDelimiter,str);
			if i # -1 then
				str[i] := 0X;
				b := DirectoryExists(str,fullPathName);
			end;
		until (i = -1) or b;

		if i = -1 then
			i := Strings.Length(str);
			if str0[i] = Files.PathDelimiter then str[i] := Files.PathDelimiter; inc(i); str[i] := 0X; end;
			Files.CreateDirectory(str,res);
			if res # 0 then return false; end;
		else
			i := Strings.Length(str);
			if str0[i] = Files.PathDelimiter then str[i] := Files.PathDelimiter; inc(i); str[i] := 0X; end;
		end;

		res := 0;
		while (i < n) & (res = 0) do
			j := i;
			i := Strings.Find(str0,j,Files.PathDelimiter);
			if i # -1 then
				while j < i do str[j] := str0[j]; inc(j); end;
				str[j] := 0X;
				inc(i,2); (* jump to the next delimiter *)
			else str := str0; i := n;
			end;
			Files.CreateDirectory(str,res)
		end;

		return (res = 0) & DirectoryExists(str,fullPathName);
	end CreateDirectory;

	(**
		Returns TRUE if a directory with given relative path name exists
	*)
	procedure DirectoryExists*(const pathName: array of char; var fullPathName: array of char): boolean;
	var
		str: Files.FileName;
		file: Files.File;
	begin
		JoinPath(pathName,"dummy.file",str);
		file := Files.New(str);
		if file # nil then
			file.GetName(str);
			file.Close;
			Files.SplitPath(str,fullPathName,str);
			return true;
		end;
		return false;
	end DirectoryExists;

	(**
		Returns TRUE if a file with given path name exists

		pathName: a valid specification of the path to the file
		fullPathName: full file path name
	*)
	procedure FileExists*(const pathName: array of char; var fullPathName: array of char): boolean;
	var flags: set;
	begin
		return Files.Exists(pathName, fullPathName, flags);
	end FileExists;

	procedure TestTraversalProc(const pathName: array of char; param: any): boolean;
	begin
		param(Commands.Context).out.String(pathName); param(Commands.Context).out.Ln;
		return true;
	end TestTraversalProc;

	procedure TestTraversePath*(context: Commands.Context);
	var
		path, pattern: Files.FileName;
	begin
		assert(context.arg.GetString(path) & context.arg.GetString(pattern));
		trace(path,pattern);
		assert(TraversePath(path,pattern,TestTraversalProc,{TraverseRecursive,TraverseFiles,TraverseDirs},context));
	end TestTraversePath;

end PathTools.

PathTools.TestTraversePath "WORK" "*.v" ~

PathTools.TestFindFile "AC3HWL" "TRM.v" ~
