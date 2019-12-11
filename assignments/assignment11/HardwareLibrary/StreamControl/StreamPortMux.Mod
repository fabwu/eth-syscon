(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: Stream port multiplexor with parameterizable data width and number of inputs
*)
module StreamPortMux;

import
	HdlBackend := AcHdlBackend, AcVerilogCodeGen, Strings, Files, Streams;

var
	c: HdlBackend.Engine;

	procedure PostParamSetup(obj: HdlBackend.Object; param: any): boolean;
	var
		c: HdlBackend.Cell;
		str1, str2: array 64 of char;
		strNum: array 32 of char;
		fileName: Files.FileName;
		p_DataWidth, p_NumInputs: HdlBackend.Property;
		dataWidth, numInputs: signed32;
		i, n: size;
		file: Files.File;
		fw: Files.Writer;
		codeGen: AcVerilogCodeGen.VerilogCodeGenerator;
	begin
		c := obj(HdlBackend.Cell);
		p_DataWidth := c.GetPropertyByHdlName("DataWidth");
		p_NumInputs := c.GetPropertyByAcName("NumInputs");

		dataWidth := signed32(p_DataWidth.value.ToInteger().val);
		numInputs := signed32(p_NumInputs.value.ToInteger().val);

		(* set width of the output port *)
		c.outputs.GetPort(0).SetWidth(dataWidth);
		c.outputs.GetPort(0)(HdlBackend.AxisPort).SetRouting(numInputs,false);

		n := c.inputs.Length()-numInputs;
		if n < 0 then (* need to add more ports *)

			(* set width for already existing input ports *)
			for i := 0 to c.inputs.Length()-1 do c.inputs.GetPort(i).SetWidth(dataWidth); end;

			i := c.inputs.Length();
			while n < 0 do
				Strings.IntToStr(i,strNum);
				Strings.Concat("input[",strNum,str1);
				Strings.Concat(str1,"]",str1);
				Strings.Concat("i",strNum,str2);
				c.NewAxisPort(str1,str2,HdlBackend.In,dataWidth);
				inc(i); inc(n);
			end;

		elsif n > 0  then (* need to remove some ports *)

			while n > 0 do c.inputs.RemoveLast(); dec(n); end;

			(* set width for input ports *)
			for i := 1 to numInputs do c.inputs.GetPort(i).SetWidth(dataWidth); end;

		end;

		(* Generate the code *)
		assert((c.ctx # nil) & (c.ctx is HdlBackend.HdlProject));

		(* modify the name according to the number of outputs *)
		Strings.IntToStr(numInputs,strNum);
		Strings.Concat("AxisPortMux",strNum,str1);
		c.SetAcName(str1); c.SetHdlName(str1);

		Strings.Concat(c.acName^,".v",fileName);
		c.RemoveDependencies;
		c.NewDependency(fileName,true,false);
		if ~HdlBackend.hwLibrary.HasResource(fileName) then
			Files.JoinPath(c.ctx(HdlBackend.HdlProject).path^,fileName,fileName);
			file := Files.New(fileName); assert(file # nil);
			Files.Register(file);
			Files.OpenWriter(fw,file,0);

			new(codeGen);
			codeGen.SetWriter(fw);
			if ~GenerateCode(codeGen,c) then
				fw.Update; file.Close;
				return false;
			end;
			file.Close;

			assert(HdlBackend.hwLibrary.AddResource(fileName,c.ctx));
		end;

		return true;

	finally
		return false;
	end PostParamSetup;

	procedure GenerateCode(codeGen: AcVerilogCodeGen.VerilogCodeGenerator; c: HdlBackend.Cell): boolean;
	var
		i: size;
		po, pi: HdlBackend.AxisPort;
		w: Streams.Writer;
	begin
		codeGen.DeclareModule(c);
		codeGen.w.Update;

		w := codeGen.w;

		po := c.outputs.GetPort(0)(HdlBackend.AxisPort);

		(* input selection signals *)
		for i := 0 to c.inputs.Length()-1 do
			pi := c.inputs.GetPort(i)(HdlBackend.AxisPort);
			w.String("wire sel"); w.Int(i,0); w.String(" = "); w.String(po.tdest.hdlName^); w.String(" == "); w.Int(po.tdest.width,0); w.String("'d"); w.Int(i,0); w.String(";"); w.Ln;
		end;
		w.Ln;

		(* demultiplexing of TREADY *)
		for i := 0 to c.inputs.Length()-1 do
			pi := c.inputs.GetPort(i)(HdlBackend.AxisPort);
			w.String("assign "); w.String(pi.tready.hdlName^); w.String(" = sel"); w.Int(i,0); w.String(" ? "); w.String(po.tready.hdlName^); w.String(" : 1'b0;"); w.Ln;
		end;

		w.Ln;

		(* multiplexing of TVALID and TDATA *)
		if po.tvalid # nil then
			w.String("assign "); w.String(po.tvalid.hdlName^); w.String(" = ");
			for i := 0 to c.inputs.Length()-2 do
				pi := c.inputs.GetPort(i)(HdlBackend.AxisPort);
				w.String("sel"); w.Int(i,0); w.String(" ? "); w.String(pi.tvalid.hdlName^); w.String(" : ");
			end;
			pi := c.inputs.GetPort(c.inputs.Length()-1)(HdlBackend.AxisPort);
			w.String(pi.tvalid.hdlName^); w.String(";"); w.Ln;

			w.String("assign "); w.String(po.tdata.hdlName^); w.String(" = ");
			for i := 0 to c.inputs.Length()-2 do
				pi := c.inputs.GetPort(i)(HdlBackend.AxisPort);
				w.String("sel"); w.Int(i,0); w.String(" ? "); w.String(pi.tdata.hdlName^); w.String(" : ");
			end;
			pi := c.inputs.GetPort(c.inputs.Length()-1)(HdlBackend.AxisPort);
			w.String(pi.tdata.hdlName^); w.String(";"); w.Ln;
		end;

		w.Ln;
		codeGen.EndModule;

		w.Update;
		return w.res = 0;
	finally
		return false;
	end GenerateCode;

begin
	new(c,"StreamPortMux","AxisPortMux");
	c.SetDescription("Stream port multiplexor with parameterizable data width and number of inputs");

	(*
		Define component's parameters
	*)
	c.NewProperty("DataWidth","DataWidth",HdlBackend.NewInteger(32),HdlBackend.IntegerPropertyRangeCheck(1,HdlBackend.MaxInteger));
	c.NewProperty("NumInputs","",HdlBackend.NewInteger(2),HdlBackend.IntegerPropertyRangeCheck(2,HdlBackend.MaxInteger));

	(*
		Define component's ports
	*)
	c.NewAxisPort("output","o",HdlBackend.Out,32);
	c.outputs.GetPort(0)(HdlBackend.AxisPort).SetRouting(2,false);
	c.NewAxisPort("input[0]","i0",HdlBackend.In,32);
	c.NewAxisPort("input[1]","i1",HdlBackend.In,32);

	(*
		Define the activities performed after parameterization of the component
	*)
	c.AddPostParamSetter(PostParamSetup);
	
	HdlBackend.hwLibrary.AddComponent(c);
end StreamPortMux.
