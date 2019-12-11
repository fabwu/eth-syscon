(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: General Purpose Input (GPI) with parameterizable data width and stream control interface
*)
module Gpi;

import
	Hdl := AcHdlBackend;

var
	c: Hdl.Engine;

begin
	new(c,"Gpi","Gpi");
	c.SetDescription("General Purpose Input (GPI) with parameterizable data width and stream control interface");

	(*
		Define component's parameters
	*)
	c.NewProperty("DataWidth","DW",Hdl.NewInteger(32),Hdl.IntegerPropertyRangeCheck(1,Hdl.MaxInteger));

	(*
		Define component's ports
	*)
	c.SetMainClockInput("aclk"); (* main component's clock *)
	c.SetMainResetInput("aresetn",Hdl.ActiveLow); (* active-low reset *)
	c.NewAxisPort("output","out",Hdl.Out,8);
	c.NewExternalHdlPort("gpi","gpi",Hdl.In,8);

	(*
		Define component's dependencies
	*)
	c.NewDependency("Gpi.v",true,false);

	(*
		Define the activities performed after parameterization of the component
	*)
	c.AddPostParamSetter(Hdl.SetPortWidthFromProperty("out","DW"));
	c.AddPostParamSetter(Hdl.SetPortWidthFromProperty("gpi","DW"));
	
	Hdl.hwLibrary.AddComponent(c);
end Gpi.
