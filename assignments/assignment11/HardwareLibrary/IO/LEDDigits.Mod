(**
	Stephan Koster
	purpose: torture students
*)

MODULE LEDDigits;

IMPORT
	Hdl := AcHdlBackend;

VAR
	c: Hdl.Engine;

BEGIN
	NEW(c,"LEDDigits","LEDDigits");
	c.SetDescription("Same as GPO, but for LED digits on the spartan3 board");

	
	(*
		Define component's ports
	*)
	c.SetMainClockInput("aclk"); (* main component's clock *)
	c.SetMainResetInput("aresetn",Hdl.ActiveLow); (* active-low reset *)
	c.NewAxisPort("input","inp",Hdl.In,12);
	c.NewExternalHdlPort("ds","ds",Hdl.Out,4);
	c.NewExternalHdlPort("ss","ss",Hdl.Out,8);

	(*
		Define component's dependencies
	*)
	c.NewDependency("LEDDigits.v",TRUE,FALSE);

	
	Hdl.hwLibrary.AddComponent(c);
END LEDDigits.
