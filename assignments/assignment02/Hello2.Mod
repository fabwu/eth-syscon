MODULE Hello2;

IMPORT Out, Hello;

PROCEDURE World*;
BEGIN
    Hello.World();
END World;

PROCEDURE World2*;
BEGIN
    Out.String("Hello, World2"); Out.Ln();
END World2;

END Hello2.