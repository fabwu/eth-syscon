MODULE Hello;

IMPORT Out, Platform;

PROCEDURE World*;
BEGIN
    Out.String("Hello, World"); Out.Ln();
END World;

PROCEDURE Blink*;
BEGIN
    Platform.Blink(100);
END Blink;

BEGIN
END Hello.