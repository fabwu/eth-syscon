(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: stream port demultiplexor with parameterizable data width and number of outputs
*)
module StreamPortDemux;

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
		p_DataWidth, p_NumOutputs: HdlBackend.Property;
		dataWidth, numOutputs: signed32;
		i, n, res: size;
		file: Files.File;
		fw: Files.Writer;
		codeGen: AcVerilogCodeGen.VerilogCodeGenerator;
	begin
		c := obj(HdlBackend.Cell);
		p_DataWidth := c.GetPropertyByHdlName("DataWidth");
		p_NumOutputs := c.GetPropertyByAcName("NumOutputs");

		dataWidth := signed32(p_DataWidth.value.ToInteger().val);
		numOutputs := signed32(p_NumOutputs.value.ToInteger().val);

		(* set width of the input port *)
		c.inputs.GetPort(0).SetWidth(dataWidth);
		c.inputs.GetPort(0)(HdlBackend.AxisPort).SetRouting(numOutputs,false);

		n := c.outputs.Length()-numOutputs;
		if n < 0 then (* need to add more ports *)

			(* set width for already existing output ports *)
			for i := 0 to c.outputs.Length()-1 do c.outputs.GetPort(i).SetWidth(dataWidth); end;

			i := c.outputs.Length();
			while n < 0 do
				Strings.IntToStr(i,strNum);
				Strings.Concat("output[",strNum,str1);
				Strings.Concat(str1,"]",str1);
				Strings.Concat("o",strNum,str2);
				c.NewAxisPort(str1,str2,HdlBackend.Out,dataWidth);
				inc(i); inc(n);
			end;

		elsif n > 0  then (* need to remove some ports *)

			while n > 0 do c.outputs.RemoveLast(); dec(n); end;

			(* set width for output ports *)
			for i := 1 to numOutputs do c.outputs.GetPort(i).SetWidth(dataWidth); end;

		end;

		(* Generate the code *)
		assert((c.ctx # nil) & (c.ctx is HdlBackend.HdlProject));

		(* modify the name according to the number of outputs *)
		Strings.IntToStr(numOutputs,strNum);
		Strings.Concat("AxisPortDemux",strNum,str1);
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

		pi := c.inputs.GetPort(0)(HdlBackend.AxisPort);

		(* output selection signals *)
		for i := 0 to c.outputs.Length()-1 do
			po := c.outputs.GetPort(i)(HdlBackend.AxisPort);
			w.String("wire sel"); w.Int(i,0); w.String(" = "); w.String(pi.tdest.hdlName^); w.String(" == "); w.Int(pi.tdest.width,0); w.String("'d"); w.Int(i,0); w.String(";"); w.Ln;
		end;
		w.Ln;

		(* demultiplexing of TVALID and TDATA *)
		for i := 0 to c.outputs.Length()-1 do
			po := c.outputs.GetPort(i)(HdlBackend.AxisPort);
			w.String("assign "); w.String(po.tvalid.hdlName^); w.String(" = sel"); w.Int(i,0); w.String(" ? "); w.String(pi.tvalid.hdlName^); w.String(" : 1'b0;"); w.Ln;
			if po.tdata # nil then
				w.String("assign "); w.String(po.tdata.hdlName^); w.String(" = "); w.String(pi.tdata.hdlName^); w.String(";"); w.Ln;
			end;
			w.Ln;
		end;

		(* multiplexing of TREADY *)
		if pi.tready # nil then
			w.String("assign "); w.String(pi.tready.hdlName^); w.String(" = ");
			for i := 0 to c.outputs.Length()-2 do
				po := c.outputs.GetPort(i)(HdlBackend.AxisPort);
				w.String("sel"); w.Int(i,0); w.String(" ? "); w.String(po.tready.hdlName^); w.String(" : ");
			end;
			po := c.outputs.GetPort(c.outputs.Length()-1)(HdlBackend.AxisPort);
			w.String(po.tready.hdlName^); w.String(";"); w.Ln;
		end;

		w.Ln;
		codeGen.EndModule;

		w.Update;
		return w.res = 0;
	finally
		return false;
	end GenerateCode;

begin
	new(c,"StreamPortDemux","AxisPortDemux");
	c.SetDescription("Stream port demultiplexor with parameterizable data width and number of outputs");

	(*
		Define component's parameters
	*)
	c.NewProperty("DataWidth","DataWidth",HdlBackend.NewInteger(32),HdlBackend.IntegerPropertyRangeCheck(1,HdlBackend.MaxInteger));
	c.NewProperty("NumOutputs","",HdlBackend.NewInteger(2),HdlBackend.IntegerPropertyRangeCheck(2,HdlBackend.MaxInteger));

	(*
		Define component's ports
	*)
	c.NewAxisPort("input","i",HdlBackend.In,32);
	c.inputs.GetPort(0)(HdlBackend.AxisPort).SetRouting(2,false);
	c.NewAxisPort("output[0]","o0",HdlBackend.Out,32);
	c.NewAxisPort("output[1]","o1",HdlBackend.Out,32);

	(*
		Define the activities performed after parameterization of the component
	*)
	c.AddPostParamSetter(PostParamSetup);
	
	HdlBackend.hwLibrary.AddComponent(c);
end StreamPortDemux.
