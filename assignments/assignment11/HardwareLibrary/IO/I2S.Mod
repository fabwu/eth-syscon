MODULE I2S;

IMPORT
	Hdl := AcHdlBackend;

VAR
	c: Hdl.Engine;

BEGIN
	NEW(c,"I2S","I2S");
	c.SetDescription("I2S driver");
	
	(*
		Define component's ports
	*)
	(* hardware ports internal *)
	c.SetMainClockInput("aclk"); (* main component's clock *)
	c.SetMainResetInput("aresetn",Hdl.ActiveLow); (* active-low reset *)
	(* hardware ports external *)
	c.NewExternalHdlPort("clk","clk",Hdl.Out,1); 
	c.NewExternalHdlPort("data","data",Hdl.In,1);
	c.NewExternalHdlPort("ws","ws",Hdl.Out,1);
	c.NewExternalHdlPort("enable","enable",Hdl.Out,1);
	(* software (axis) ports *)
	c.NewAxisPort("output","out",Hdl.Out,24);


	(*
		Define component's dependencies
	*)
	c.NewDependency("I2S.v",TRUE,FALSE);

	
	Hdl.hwLibrary.AddComponent(c);
END I2S.
