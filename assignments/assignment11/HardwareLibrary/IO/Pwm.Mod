module Pwm;

import
	Hdl := AcHdlBackend;

var
	c: Hdl.Engine;

begin
	new(c,"Pwm","Pwm");
	c.SetDescription("Simple Pulse Width Modulator component");

	(*
		Define component's parameters
	*)
	c.NewProperty("DataWidth","DW",Hdl.NewInteger(16),Hdl.IntegerPropertyRangeCheck(1,Hdl.MaxInteger));

	(*
		Define component's ports
	*)
	c.SetMainClockInput("aclk"); (* main component's clock *)
	c.SetMainResetInput("aresetn",Hdl.ActiveLow); (* active-low reset *)
	c.NewAxisPort("input","inp",Hdl.In,16);
	c.NewExternalHdlPort("out","out",Hdl.Out,3);

	(*
		Define component's dependencies
	*)
	c.NewDependency("Pwm.v",true,false);

	(*
		Define the activities performed after parameterization of the component
	*)
	c.AddPostParamSetter(Hdl.SetPortWidthFromProperty("inp","DW"));
	
	Hdl.hwLibrary.AddComponent(c);
end Pwm.
