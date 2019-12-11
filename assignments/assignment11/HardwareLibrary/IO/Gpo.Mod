(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: General Purpose Output (GPO) with parameterizable data width and stream control interface
*)
module Gpo;

import
	Hdl := AcHdlBackend;

var
	c: Hdl.Engine;

begin
	new(c,"Gpo","Gpo");
	c.SetDescription("General Purpose Output (GPO) with parameterizable data width and stream control interface");

	(*
		Define component's parameters
	*)
	c.NewProperty("DataWidth","DW",Hdl.NewInteger(32),Hdl.IntegerPropertyRangeCheck(1,Hdl.MaxInteger));
	c.NewProperty("InitState","InitState",Hdl.NewBinaryValue("0H"),nil);

	(*
		Define component's ports
	*)
	c.SetMainClockInput("aclk"); (* main component's clock *)
	c.SetMainResetInput("aresetn",Hdl.ActiveLow); (* active-low reset *)
	c.NewAxisPort("input","inp",Hdl.In,8);
	c.NewExternalHdlPort("gpo","gpo",Hdl.Out,8);

	(*
		Define component's dependencies
	*)
	c.NewDependency("Gpo.v",true,false);

	(*
		Define the activities performed after parameterization of the component
	*)
	c.AddPostParamSetter(Hdl.SetPortWidthFromProperty("inp","DW"));
	c.AddPostParamSetter(Hdl.SetPortWidthFromProperty("gpo","DW"));
	
	Hdl.hwLibrary.AddComponent(c);
end Gpo.
