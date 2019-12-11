(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: system clock component providing clock signal for all components of the system
*)
module SystemClock;

import
	HdlBackend := AcHdlBackend;

var
	c: HdlBackend.Engine;

begin
	new(c,HdlBackend.SystemClockName,HdlBackend.SystemClockName);
	c.SetDescription("System clock component providing clock signal to all components of the system");

	(*
		Define component's parameters
	*)
	c.NewProperty(HdlBackend.PropMulFactor,"",HdlBackend.NewInteger(1),HdlBackend.IntegerPropertyRangeCheck(1,HdlBackend.MaxInteger));
	c.NewProperty(HdlBackend.PropDivFactor,"",HdlBackend.NewInteger(1),HdlBackend.IntegerPropertyRangeCheck(1,HdlBackend.MaxInteger));
	c.NewProperty(HdlBackend.PropDutyCycle,"",HdlBackend.NewInteger(1),HdlBackend.IntegerPropertyRangeCheck(1,99));
	c.NewProperty(HdlBackend.PropPhase,"",HdlBackend.NewInteger(0),HdlBackend.IntegerPropertyRangeCheck(0,360));

	(*
		Define component's ports
	*)
	c.NewClockInput("input","inp"); (* input clock *)
	c.NewClockOutput("output","out"); (* output clock *)

	HdlBackend.hwLibrary.AddComponent(c);
end SystemClock.
