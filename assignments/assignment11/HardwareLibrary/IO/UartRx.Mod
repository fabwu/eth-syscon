(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: UART receiver
*)
module UartRx;

import
	Hdl := AcHdlBackend;

var
	c: Hdl.Engine;

	procedure CheckPropertyValue(prop: Hdl.Property; value: Hdl.Value): boolean;
	var
		p_InitClkDivisor, p_ClkDivisorWidth: Hdl.Property;
		maxClkDivider: Hdl.IntegerType;
		c: Hdl.Cell;
		i: Hdl.Integer;
	begin
		c := prop.GetCell();
		p_ClkDivisorWidth := c.GetPropertyByHdlName("ClkDivisorWidth");
		p_InitClkDivisor := c.GetPropertyByAcName("InitClkDivisor");

		maxClkDivider := lsh(Hdl.IntegerType(1),p_ClkDivisorWidth.value.ToInteger().val)-1;

		i := value.ToInteger(); (* integer value is expected *)

		if prop = p_InitClkDivisor then
			if i.val > 1 then
				if i.val  <= maxClkDivider then
					return true;
				else
					prop.Error(Hdl.ErrInvalidValue,"InitClkDivisor value (" & i.val & ") exceeds the maximal value (" & maxClkDivider & ") determined by ClkDivisorWidth (" & p_ClkDivisorWidth.value.ToInteger().val & ")" );
					return false;
				end;
			else
				prop.Error(Hdl.ErrInvalidValue,"InitClkDivisor value cannot be less than 1");
			end;
		else
			prop.Error(Hdl.ErrInvalidName,"unknown property");
		end;

		return false;
	end CheckPropertyValue;

	procedure PostParamSetup(obj: Hdl.Object; param: any): boolean;
	var
		c: Hdl.Cell;
		p_RtsPortUnused: Hdl.Property;
		p: Hdl.Port;
	begin
		c := obj(Hdl.Cell);
		p_RtsPortUnused := c.GetPropertyByHdlName("RtsPortUnused");
		p := c.outputs.GetPortByAcName("rts");
		assert(~p.unused);
		if p_RtsPortUnused.value.ToInteger().val = 1 then
			p.SetUnused(true);
			p.SetOptional(true); (*! only optional port can be unused! *)
		end;

		return true;
	end PostParamSetup;

begin
	new(c,"UartRx","UartRx");
	c.SetDescription("UART receiver component");

	(*
		Define component's parameters
	*)
	c.NewProperty("ClkDivisorWidth","ClkDivisorWidth",Hdl.NewInteger(16),Hdl.IntegerPropertyRangeCheck(1,Hdl.MaxInteger));
	c.NewProperty("InitClkDivisor","InitClkDivisor",Hdl.NewInteger(868),CheckPropertyValue);
	c.NewProperty("RtsPortUnused","RtsPortUnused",Hdl.NewInteger(1),nil);

	(*
		Define component's ports
	*)
	c.SetMainClockInput("aclk"); (* main component's clock *)
	c.SetMainResetInput("aresetn",Hdl.ActiveLow); (* active-low reset *)
	c.NewAxisPort("output","out",Hdl.Out,8);
	c.NewAxisPort("cfg","cfg",Hdl.In,16); c.GetPortByAcName("cfg").SetOptional(true);
	c.NewExternalHdlPort("rxd","rxd",Hdl.In,1);
	c.NewExternalHdlPort("rts","rts",Hdl.Out,1);

	(*
		Define component's dependencies
	*)
	c.NewDependency("UartRx.v",true,false);

	c.AddPostParamSetter(PostParamSetup);
	
	Hdl.hwLibrary.AddComponent(c);
end UartRx.
