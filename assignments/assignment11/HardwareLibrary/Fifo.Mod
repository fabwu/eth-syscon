(**
	AUTHOR: Alexey Morozov, HighDim GmbH, 2015
	PURPOSE: First Input First Output (FIFO) buffer with parameterizable data width and depth used for buffering data streams
*)
module Fifo;

import
	Hdl := AcHdlBackend;

var
	c: Hdl.Engine;

	(*
		Procedure that checks the value of a property after it was set by the user
	*)
	procedure CheckPropertyValue(prop: Hdl.Property; value: Hdl.Value): boolean;
	var
		p_InitWrPos, p_InitRdPos, p_Length: Hdl.Property;
		c: Hdl.Cell;
		i: Hdl.Integer;
	begin
		c := prop.GetCell();
		p_Length := c.GetPropertyByAcName("Length");
		p_InitWrPos := c.GetPropertyByAcName("InitWrPos");
		p_InitRdPos := c.GetPropertyByAcName("InitRdPos");

		assert((prop = p_InitWrPos) or (prop = p_InitRdPos));

		i := value.ToInteger(); (* integer value is expected *)

		if (i.val >= 0) & ((i.val < p_Length.value.ToInteger().val) or (i.val = 0)) then
			return true;
		else
			prop.Error(Hdl.ErrInvalidValue,"invalid property value");
			return false;
		end;

		return false;
	end CheckPropertyValue;

	procedure PostParamSetup(obj: Hdl.Object; param: any): boolean;
	var
		c: Hdl.Cell;
		p_Length: Hdl.Property;
		p: Hdl.Port;
	begin
		c := obj(Hdl.Cell);
		p_Length := c.GetPropertyByHdlName("Length");

		(* Set width of the command data input depending on the buffer length *)
		p := c.GetPortByAcName("cmd");
		p.SetWidth(4+max(2,Hdl.NumBits(p_Length.value.ToInteger().val)));
		
		p := c.GetPortByAcName("status");
		p.SetWidth(max(2,Hdl.NumBits(p_Length.value.ToInteger().val)));

		return true;
	end PostParamSetup;

	procedure PostAssemblySetup(obj: Hdl.Object; param: any): boolean;
	var
		c: Hdl.Cell;
		p_CmdPortUnused: Hdl.Property;
		p: Hdl.Port;
	begin
		c := obj(Hdl.Cell);
		p_CmdPortUnused := c.GetPropertyByHdlName("CmdPortUnused");

		p := c.GetPortByAcName("cmd");

		(* if "cmd" port is unused set "CmdPortUnused" property to 1 *)
		if p.unused then
			assert(p_CmdPortUnused.SetValue(Hdl.NewInteger(1)));
		end;

		return true;
	end PostAssemblySetup;

begin
	new(c,"Fifo","AxisFifo");
	c.SetDescription("Generic First Input First Output (FIFO) buffer with parameterizable data width and depth used for buffering data streams");

	(*
		Define component's parameters
	*)
	c.NewProperty("DataWidth","DataWidth",Hdl.NewInteger(32),Hdl.IntegerPropertyRangeCheck(1,Hdl.MaxInteger));
	c.NewProperty("Length","Length",Hdl.NewInteger(8),Hdl.IntegerPropertyRangeCheck(0,Hdl.MaxInteger));
	c.NewProperty("InitEnableInput","InitEnableInput",Hdl.NewInteger(1),Hdl.IntegerPropertyRangeCheck(0,1));
	c.NewProperty("InitEnableOutput","InitEnableOutput",Hdl.NewInteger(1),Hdl.IntegerPropertyRangeCheck(0,1));
	c.NewProperty("InitFullFlag","InitFullFlag",Hdl.NewInteger(0),Hdl.IntegerPropertyRangeCheck(0,1));
	c.NewProperty("InitWrPos","InitWrPos",Hdl.NewInteger(0),CheckPropertyValue);
	c.NewProperty("InitRdPos","InitRdPos",Hdl.NewInteger(0),CheckPropertyValue);
	c.NewProperty("","CmdPortUnused",Hdl.NewInteger(0),nil);

	(*
		Define component's ports
	*)
	c.SetMainClockInput("aclk"); (* main component's clock *)
	c.SetMainResetInput("aresetn",Hdl.ActiveLow); (* active-low reset *)
	c.NewAxisPort("input","i",Hdl.In,32);
	c.NewAxisPort("output","o",Hdl.Out,32);
	c.NewAxisPort("cmd","cmd",Hdl.In,32); c.GetPortByAcName("cmd").SetOptional(true);
	c.NewAxisPort("status","status",Hdl.Out,8); c.GetPortByAcName("status").SetOptional(true);

	(*
		Define component's dependencies
	*)
	c.NewDependency("UtilityMacros.vh",true,true);
	c.NewDependency("UtilityFunctions.vh",true,true);
	c.NewDependency("AxisFifo.v",true,false);

	(*
		Define the activities performed after parameterization of the component
	*)
	c.AddPostParamSetter(Hdl.SetPortWidthFromProperty("i","DataWidth"));
	c.AddPostParamSetter(Hdl.SetPortWidthFromProperty("o","DataWidth"));
	c.AddPostParamSetter(PostParamSetup);

	c.AddPostAssemblySetter(PostAssemblySetup);
	
	Hdl.hwLibrary.AddComponent(c);
end Fifo.
