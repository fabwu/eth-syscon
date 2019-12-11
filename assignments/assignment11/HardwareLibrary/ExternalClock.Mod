(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: external clock component
*)
module ExternalClock;

import
	HdlBackend := AcHdlBackend;

var
	c: HdlBackend.Engine;

begin
	new(c,HdlBackend.ExternalClockName,HdlBackend.ExternalClockName);
	c.SetDescription("External clock component");

	(*
		Define component's parameters
	*)
	c.NewProperty(HdlBackend.PropSourceClock,"",HdlBackend.NewString(HdlBackend.ExternalClockName & "0"),nil);
	c.NewProperty(HdlBackend.PropMulFactor,"",HdlBackend.NewInteger(1),HdlBackend.IntegerPropertyRangeCheck(1,HdlBackend.MaxInteger));
	c.NewProperty(HdlBackend.PropDivFactor,"",HdlBackend.NewInteger(1),HdlBackend.IntegerPropertyRangeCheck(1,HdlBackend.MaxInteger));
	c.NewProperty(HdlBackend.PropDutyCycle,"",HdlBackend.NewInteger(1),HdlBackend.IntegerPropertyRangeCheck(1,99));
	c.NewProperty(HdlBackend.PropPhase,"",HdlBackend.NewInteger(0),HdlBackend.IntegerPropertyRangeCheck(0,360));

	(*
		Define component's ports
	*)
	c.NewClockOutput("output","output"); (* clock output *)

	HdlBackend.hwLibrary.AddComponent(c);
end ExternalClock.
