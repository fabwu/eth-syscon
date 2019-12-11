MODULE BiasCorrector;

IMPORT
	Hdl := AcHdlBackend;

VAR
	c: Hdl.Engine;

BEGIN
	NEW(c,"BiasCorrector","BiasCorrector");
	c.SetDescription("Bias Corrector");
	
	(*
		Define component's ports
	*)
	(* hardware ports internal *)
	c.SetMainClockInput("aclk"); (* main component's clock *)
	c.SetMainResetInput("aresetn",Hdl.ActiveLow); (* active-low reset *)
	(* software (axis) ports *)
	c.NewAxisPort("output","out",Hdl.Out,24);
	c.NewAxisPort("input","in",Hdl.In,24);

	(*
		Define component's dependencies
	*)
	c.NewDependency("BiasCorrector.v",TRUE,FALSE);

	
	Hdl.hwLibrary.AddComponent(c);
END BiasCorrector.
