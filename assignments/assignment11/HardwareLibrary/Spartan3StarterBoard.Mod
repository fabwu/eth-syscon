module Spartan3StarterBoard;
(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
		Stephan Koster, ETH Zurich 2016
	PURPOSE: Target specification for Xilinx Spartan-3 starter board from Digilent
*)

import
	Hdl := AcHdlBackend, AcXilinx;

var
	t: Hdl.TargetDevice;
	pldPart: AcXilinx.PldPart;
	pin: Hdl.IoPin;
	ioSetup: Hdl.IoSetup;
begin
	new(pldPart,"XC3S200-4FT256");
	new(t,"Spartan3StarterBoard",pldPart);

	new(pin,Hdl.In,"T9","LVCMOS25");
	t.NewExternalClock(pin,50000000,50,0); (* ExternalClock0 *)

	t.SetSystemClock(t.clocks.GetClockByName("ExternalClock0"),1,1);

	new(pin,Hdl.In,"L14","LVCMOS25"); (*leftmost button serves as reset*)
	t.SetSystemReset(pin,true);

	new(ioSetup,"Gpo_0"); (*definition gpo engine finds this io setup by name and connects its output wires to these pins*)
	(*gpo leds*)
	ioSetup.NewPin("gpo",Hdl.Out,"K12","LVCMOS25");
	ioSetup.NewPin("gpo",Hdl.Out,"P14","LVCMOS25");
	ioSetup.NewPin("gpo",Hdl.Out,"L12","LVCMOS25");
	ioSetup.NewPin("gpo",Hdl.Out,"N14","LVCMOS25");
	ioSetup.NewPin("gpo",Hdl.Out,"P13","LVCMOS25");
	ioSetup.NewPin("gpo",Hdl.Out,"N12","LVCMOS25");
	ioSetup.NewPin("gpo",Hdl.Out,"P12","LVCMOS25");
	ioSetup.NewPin("gpo",Hdl.Out,"P11","LVCMOS25");
	t.AddIoSetup(ioSetup);
	
	new(ioSetup,"LEDDigits_0");
	(*led digit selection left to right, active low*)
	ioSetup.NewPin("ds",Hdl.Out,"D14","LVCMOS25");
	ioSetup.NewPin("ds",Hdl.Out,"G14","LVCMOS25");
	ioSetup.NewPin("ds",Hdl.Out,"F14","LVCMOS25");
	ioSetup.NewPin("ds",Hdl.Out,"E13","LVCMOS25");
	
	(*led segment selection a b c d e f g dp  active low*)
	ioSetup.NewPin("ss",Hdl.Out,"P16","LVCMOS25");	
	ioSetup.NewPin("ss",Hdl.Out,"N16","LVCMOS25");	
	ioSetup.NewPin("ss",Hdl.Out,"F13","LVCMOS25");
	ioSetup.NewPin("ss",Hdl.Out,"R16","LVCMOS25");
	ioSetup.NewPin("ss",Hdl.Out,"P15","LVCMOS25");
	ioSetup.NewPin("ss",Hdl.Out,"N15","LVCMOS25");
	ioSetup.NewPin("ss",Hdl.Out,"G13","LVCMOS25");
	ioSetup.NewPin("ss",Hdl.Out,"E14","LVCMOS25");





	
	t.AddIoSetup(ioSetup);
	
	new(ioSetup,"Gpi_0"); (*definition of gpi engine finds this io setup by name*)
	
	(*buttons left to right. Note leftmost button is the reset input*)
	ioSetup.NewPin("gpi",Hdl.In,"L13","LVCMOS25");
	ioSetup.NewPin("gpi",Hdl.In,"M14","LVCMOS25");
	ioSetup.NewPin("gpi",Hdl.In,"M13","LVCMOS25");
	(*big dip switches*)
	ioSetup.NewPin("gpi",Hdl.In,"F12","LVCMOS25");
	ioSetup.NewPin("gpi",Hdl.In,"G12","LVCMOS25");
	ioSetup.NewPin("gpi",Hdl.In,"H14","LVCMOS25");
	ioSetup.NewPin("gpi",Hdl.In,"H13","LVCMOS25");
	ioSetup.NewPin("gpi",Hdl.In,"J14","LVCMOS25");
	ioSetup.NewPin("gpi",Hdl.In,"J13","LVCMOS25");
	ioSetup.NewPin("gpi",Hdl.In,"K14","LVCMOS25");
	ioSetup.NewPin("gpi",Hdl.In,"K13","LVCMOS25");
	t.AddIoSetup(ioSetup);
	

	new(ioSetup,"UartTx_0");
	ioSetup.NewPin("txd",Hdl.Out,"R13","LVCMOS25");
	ioSetup.NewPin("cts",Hdl.In,"T12","LVCMOS25");
	t.AddIoSetup(ioSetup);

	new(ioSetup,"UartRx_0");
	ioSetup.NewPin("rxd",Hdl.In,"T13","LVCMOS25");
	ioSetup.NewPin("rts",Hdl.Out,"R12","LVCMOS25");
	t.AddIoSetup(ioSetup);

	Hdl.hwLibrary.AddTarget(t);
end Spartan3StarterBoard.
