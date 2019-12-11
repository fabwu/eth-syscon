(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: system reset component providing reset signal for all components of an ActiveCells architecture
*)
module SystemReset;

import
	HdlBackend := AcHdlBackend;

var
	c: HdlBackend.Engine;

begin
	new(c,HdlBackend.SystemResetName,"ResetSync");
	c.SetDescription("System reset component providing reset signal for all components of an ActiveCells architecture");

	(*
		Define component's parameters
	*)
	c.NewProperty("InputPolarity","InputPolarity",HdlBackend.NewInteger(0),HdlBackend.IntegerPropertyRangeCheck(0,1));
	c.NewProperty("OutputPolarity","OutputPolarity",HdlBackend.NewInteger(0),HdlBackend.IntegerPropertyRangeCheck(0,1));

	(*
		Define component's ports
	*)
	c.SetMainClockInput("clk"); (* main component's clock *)
	c.NewHdlPort("input","inp",HdlBackend.In,1); (* input reset signal *)
	c.NewHdlPort("output","out",HdlBackend.Out,1); (* output reset signal *)

	c.NewDependency("ResetSync.v",true,false);

	HdlBackend.hwLibrary.AddComponent(c);
end SystemReset.
