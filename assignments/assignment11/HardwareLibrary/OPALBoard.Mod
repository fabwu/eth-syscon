MODULE OPALBoard; (* Oberon Picl and Lola Board *)
(**
	AUTHOR: Felix Friedrich, Paul Reed, ETH Zurich 2019
	PURPOSE: Target specification for OPAL board
*)

IMPORT
	Hdl := AcHdlBackend, AcLattice;

VAR
	t: Hdl.TargetDevice;
	pldPart: AcLattice.PldPart;
	pin: Hdl.IoPin;
	ioSetup: Hdl.IoSetup;
BEGIN
	NEW(pldPart,"iCE40HX4K-tq144");
	NEW(t,"OPALBoard",pldPart);

	NEW(pin,Hdl.In,"21","LVCMOS25");
	t.NewExternalClock(pin,100000000,50,0); (* ExternalClock0 *)

	t.SetSystemClock(t.clocks.GetClockByName("ExternalClock0"),1,2); (* 100 MHz / 2 = 50 MHz *)

	NEW(pin,Hdl.In,"62","LVCMOS33");
	t.SetSystemReset(pin,FALSE); (* active low reset pin *)

	NEW(ioSetup,"Gpo_0"); (*definition gpo engine finds this io setup by name and connects its output wires to these pins*)
	(*gpo leds*)
	ioSetup.NewPin("gpo",Hdl.Out,"37","LVCMOS33");
	ioSetup.NewPin("gpo",Hdl.Out,"2","LVCMOS25");
	ioSetup.NewPin("gpo",Hdl.Out,"4","LVCMOS25");
	ioSetup.NewPin("gpo",Hdl.Out,"8","LVCMOS25");
	ioSetup.NewPin("gpo",Hdl.Out,"12","LVCMOS25");
	ioSetup.NewPin("gpo",Hdl.Out,"26","LVCMOS25");
	ioSetup.NewPin("gpo",Hdl.Out,"29","LVCMOS25");
	ioSetup.NewPin("gpo",Hdl.Out,"34","LVCMOS25");
	t.AddIoSetup(ioSetup);

	NEW(ioSetup,"Pwm_0"); 
	(* B *)  
	ioSetup.NewPin("out",Hdl.Out,"37","LVCMOS33"); 
	(* G *) 
	ioSetup.NewPin("out",Hdl.Out,"39","LVCMOS33"); 
	(* R *) 
	ioSetup.NewPin("out",Hdl.Out,"42","LVCMOS33"); 
	t.AddIoSetup(ioSetup);	

	NEW(ioSetup,"UartTx_0");
	ioSetup.NewPin("txd",Hdl.Out,"45","LVCMOS25");
	t.AddIoSetup(ioSetup);

	NEW(ioSetup,"UartRx_0");
	ioSetup.NewPin("rxd",Hdl.In,"44","LVCMOS25");
	t.AddIoSetup(ioSetup);
	
	NEW(ioSetup,"I2S_0");
	ioSetup.NewPin("clk",Hdl.Out,"106","LVCMOS25");
	ioSetup.NewPin("data",Hdl.In,"105","LVCMOS25");
	ioSetup.NewPin("ws",Hdl.Out,"98","LVCMOS25");
	ioSetup.NewPin("enable",Hdl.Out,'97',"LVCMOS25");
	t.AddIoSetup(ioSetup);
	
	Hdl.hwLibrary.AddTarget(t);
END OPALBoard.
