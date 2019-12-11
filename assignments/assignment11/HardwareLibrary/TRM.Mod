(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: Tiny Register Machine (TRM) soft processor core
*)
module TRM;

import
	Hdl := AcHdlBackend, Strings;

var
	c: Hdl.Processor;

	procedure PostParamSetup(obj: Hdl.Object; param: any): boolean;
	var
		c: Hdl.Cell;
	begin
		c := obj(Hdl.Cell);

		(*! setup the appropriate dependencies *)
		if c.ctx(Hdl.HdlProject).target.pldPart.vendor^ = "Xilinx" then
			if Strings.StartsWith2("Spartan3",c.ctx(Hdl.HdlProject).target.pldPart.family^) then
				c.dependencies.Clear;
				c.NewDependency("XC3S.Multiplier.v",true,false);
				c.NewDependency("XC3S.IM.v",true,false);
				c.NewDependency("XC3S.DM.v",true,false);
				c.NewDependency("XC3S.TRM0.v",true,false);
			elsif c.ctx(Hdl.HdlProject).target.pldPart.family^ = "Spartan6" then
				c.dependencies.Clear;
				c.NewDependency("XC6S.MulDSP.ngc",true,false);
				c.NewDependency("XC6S.MulDSP.v",true,false);
				c.NewDependency("XC6S.Multiplier.v",true,false);
				c.NewDependency("XC6S.RegFile.ngc",true,false);
				c.NewDependency("XC6S.RegFile.v",true,false);
				c.NewDependency("XC6S.IM.v",true,false);
				c.NewDependency("XC6S.DM.v",true,false);
				c.NewDependency("XC6S.TRM0.v",true,false);
			elsif Strings.StartsWith2("XC7",c.ctx(Hdl.HdlProject).target.pldPart.device^) then
				c.dependencies.Clear;
				c.NewDependency("XC7.Multiplier.v",true,false);
				c.NewDependency("XC7.IM.v",true,false);
				c.NewDependency("XC7.DM.v",true,false);
				c.NewDependency("XC7.TRM0.v",true,false);
			end;
		elsif c.ctx(Hdl.HdlProject).target.pldPart.vendor^ = "Lattice" then
			if Strings.StartsWith2("iCE40",c.ctx(Hdl.HdlProject).target.pldPart.family^) then
				c.dependencies.Clear;
				c.NewDependency("iCE40.Multiplier.v",true,false);
				c.NewDependency("iCE40.IM.v",true,false);
				c.NewDependency("iCE40.DM.v",true,false);
				c.NewDependency("iCE40.TRM0.v",true,false);
			end;			
		else (* generic version of TRM *)
			c.NewProperty("","CodeMemoryFile",Hdl.NewString(c.hdlInstName^ & ".code0"),nil);
			c.NewProperty("","DataMemoryFile",Hdl.NewString(c.hdlInstName^ & ".data0"),nil);
		end;

		c.NewDependency("TRM.v",true,false);

		return true;
	finally
		return false;
	end PostParamSetup;

begin
	new(c,"TRM","TRM","TRM");

	c.SetDescription("Tiny Register Machine (TRM) soft processor core");

	(*
		Define component's parameters
	*)
	(* only ActiveCells-specific parameters *)
	c.NewProperty("CodeMemorySize","CodeMemorySize",Hdl.NewInteger(1024),Hdl.IntegerPropertyRangeCheck(1,Hdl.MaxInteger));
	c.NewProperty("DataMemorySize","DataMemorySize",Hdl.NewInteger(1024),Hdl.IntegerPropertyRangeCheck(1,Hdl.MaxInteger));
	c.NewProperty("IAW","IAW",Hdl.NewInteger(10),Hdl.IntegerPropertyRangeCheck(1,Hdl.MaxInteger));
	c.NewProperty("DAW","DAW",Hdl.NewInteger(10),Hdl.IntegerPropertyRangeCheck(1,Hdl.MaxInteger));
	c.NewProperty("Inst","Inst",Hdl.NewInteger(0),Hdl.IntegerPropertyRangeCheck(1,Hdl.MaxInteger));
	c.NewProperty("FloatingPoint","",Hdl.NewBoolean(false),nil);
	

	(*
		Define component's ports
	*)
	c.SetMainClockInput("aclk"); (* main component's clock *)
	c.SetMainResetInput("aresetn",Hdl.ActiveLow); (* active-low reset *)
	c.NewCommAxisPort("inp",Hdl.In,32); c.GetPortByHdlName("inp").SetOptional(true);
	c.GetPortByHdlName("inp")(Hdl.AxisPort).SetRouting(16,true);
	c.NewCommAxisPort("out",Hdl.Out,32); c.GetPortByHdlName("out").SetOptional(true);
	c.GetPortByHdlName("out")(Hdl.AxisPort).SetRouting(16,true);
	(*
		Define component's dependencies
	*)
	c.NewDependency("Multiplier.v",true,false);
	c.NewDependency("IM.v",true,false);
	c.NewDependency("DM.v",true,false);
	c.NewDependency("TRM0.v",true,false);
	c.NewDependency("TRM.v",true,false);

	(*
		Define the activities performed after parameterization of the component
	*)
	c.AddPostParamSetter(PostParamSetup);

	Hdl.hwLibrary.AddComponent(c);
end TRM.
