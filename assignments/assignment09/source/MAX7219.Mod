MODULE* Blinky;
  IMPORT SYSTEM;

VAR z,d: INTEGER;

PROCEDURE SendCmd(cmd: INTEGER);
CONST
  spiData = -48;
  spiCtrl = -44;
BEGIN
  SYSTEM.PUT(spiCtrl, 5);
  SYSTEM.PUT(spiData, cmd);
  REPEAT UNTIL SYSTEM.BIT(spiCtrl, 0);
  SYSTEM.PUT(spiCtrl, 0);
END SendCmd;

PROCEDURE Init;
BEGIN
  SendCmd(0F00H); (* test mode off *)
  SendCmd(0A08H); (* intensity *)
  SendCmd(0B07H); (* scan limit *)
  SendCmd(0C01H); (* not shutdown *)
  SendCmd(0900H); (* no fint code B *)
END Init;

PROCEDURE Map(digit: INTEGER): INTEGER;
VAR m: INTEGER;
BEGIN
  IF (digit >= 0) & (digit <= 3) THEN m := 796D307EH
  ELSIF (digit >= 4) & (digit <= 7) THEN m := 705F5B33H
  ELSIF (digit >= 8) & (digit <= 11) THEN m := 1F777B7FH
  ELSE m := 474F3D4EH
  END;

  RETURN ROR(m, digit MOD 4 * 8) MOD 100H 
END Map;

BEGIN 
  z := 0;
  d := 0;
  Init;
  SendCmd(0100H + Map(0));
  SendCmd(0200H + Map(0));
  SendCmd(0300H + Map(0));
  SendCmd(0400H + Map(0));
  SendCmd(0500H + Map(0));
  SendCmd(0600H + Map(0));
  SendCmd(0700H + Map(0));
  SendCmd(0800H + Map(0));
  REPEAT
    IF z MOD 1000000 = 0 THEN
      d := (d + 1) MOD 10;
      SendCmd(0100H + Map(d));
    END;
    LED(ROR(z,20));
    INC(z);
  UNTIL FALSE
END Blinky.
