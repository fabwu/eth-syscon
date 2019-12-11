(**
	AUTHOR: D. Shulga, HighDim GmbH, 2015
	PURPOSE: Timer with incrementing or decrementing counter with configurable width
*)
module Timer;

import Hdl := AcHdlBackend;

var c: Hdl.Engine;

begin
	new(c,"Timer","Timer");
	c.SetDescription("Timer with incrementing or decrementing counter of configurable width");

	c.NewProperty("CounterWidth","CW",Hdl.NewInteger(32),Hdl.IntegerPropertyRangeCheck(1,Hdl.MaxInteger));
	c.NewProperty("Inc","Inc",Hdl.NewInteger(1),Hdl.IntegerPropertyRangeCheck(0,1));
	
	
	c.SetMainClockInput("aclk"); 
	c.SetMainResetInput("aresetn",Hdl.ActiveLow); (* active-low reset *)
	
	c.NewAxisPort("cmd","cmd",Hdl.In,32);
	c.NewAxisPort("output","out",Hdl.Out,32);

	c.NewDependency("Timer.v",true,false);
	
	Hdl.hwLibrary.AddComponent(c);
end Timer.

