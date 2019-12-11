MODULE SoundStream;

IMPORT Streams, Commands, Serials, Out, In, Kernel, Files, Fourier;

CONST Samples = 8192;
				
	PROCEDURE Error(CONST message: ARRAY OF CHAR);
	BEGIN
		Commands.GetContext().error.String(message); 
		Commands.GetContext().error.Ln();
		Commands.GetContext().error.Update(); 
	END Error;

	PROCEDURE Swap(VAR a,b: FLOAT32);
	BEGIN
		VAR tmp := a;
		a := b;
		b := tmp;
	END Swap;

	PROCEDURE Record*;
	VAR i, j: SIZE;
		data: POINTER TO ARRAY OF SIGNED32;
		dataR,dataRT,dataI,dataIT: POINTER TO ARRAY OF FLOAT32;
		ch: CHAR; start,stop: SIGNED32;
		file: Files.File;
		filename: Files.FileName;
		writer: Files.Writer;
				portNumber, res: SIGNED32;
		R: Streams.Reader;
		port: Serials.Port; 
			uartWriter: Streams.Writer;
			uartReader: Streams.Reader;
	BEGIN
		R := In.GetArg();
		portNumber := 0;
		IF R.GetInteger(portNumber, FALSE) & R.GetString(filename) THEN
		Out.String( "Opening V24 connection on port COM" ); Out.Int( portNumber, 0 ); Out.Ln;
		port:= Serials.GetPort( portNumber );
		IF port # NIL THEN
			port.Open( 115200, 8, Serials.ParNo, Serials.Stop1, res );
			IF res = Serials.Ok THEN
				NEW(uartWriter,port.Send,1024);
				NEW(uartReader,port.Receive,1024*1024);
			ELSE
				Error("connection could not be established");
				RETURN;
			END;
		ELSE
			Error("no such port");
			RETURN;
		END;
		file := Files.New(filename);
		Files.Register(file);
		Files.OpenWriter(writer, file, 0); 
		END; 
			NEW(data, Samples);
			NEW(dataR, Samples); 
			NEW(dataI, Samples); 
			NEW(dataRT, Samples); 
			NEW(dataIT, Samples); 
			WHILE (uartReader.Available()>0) DO
				uartReader.Char(ch);
			END; 
			uartWriter.Char(30X);uartWriter.Update;
			start := Kernel.GetTicks();
			FOR i := 0 TO Samples-1 DO
				uartReader.RawLInt(data[i]);
			END; 
			stop := Kernel.GetTicks();
			
			VAR SampleRate := 1000 * Samples DIV (stop-start); 
			TRACE(stop-start, SampleRate);			

			VAR sum := 0: FLOAT32;
			FOR i := 0 TO Samples-1 DO
				data[i] := SHR(SHL(data[i],8),14);
				sum := sum + data[i];
			END; 
			sum := sum / Samples;

			VAR sumTransitions := 0: SIGNED32; 
			
			FOR i := 0 TO Samples-1 DO
				data[i] := data[i] - ENTIER(sum);
				dataR[i] := data[i];
				dataI[i] := 0; 
				IF (i>0) & ((data[i]>0) # (data[i-1] > 0)) THEN
					INC(sumTransitions)
				END;
			END; 

			TRACE(SampleRate * sumTransitions DIV Samples DIV 2);
			
			Fourier.FFT(Samples,dataR^,dataI^,dataRT^,dataIT^); 
			
			VAR dominatingFrequenciesEnergy, dominatingFrequencies: ARRAY 10 OF FLOAT32;
			
			FOR j := 0 TO LEN(dominatingFrequencies)-1 DO 
				dominatingFrequenciesEnergy[j] := 0;
			END; 
			FOR i := 0 TO Samples-1 DO
				writer.Int( i * (stop-start) DIV Samples,1); 
				writer.String(" , ");
				writer.Int(data[i],1);
				writer.String(" , "); 

				VAR energy := dataRT[i]*dataRT[i]+ dataIT[i] * dataIT[i]; 
				VAR frequency := i / Samples * SampleRate; 
				
				writer.FloatFix(frequency, 4,8,0); (* i * SampleRate / N, where SampleRate = Samples / ( (stop-start) / 1000 ) *) 
				writer.String(" , ");
				
				IF i = 0 THEN 
					writer.FloatFix(0,8,3,0);
				ELSE
					writer.FloatFix(energy,4,8,0); 
				END;
				writer.Ln; 
								
				IF (frequency > 30) & (frequency <= 4000) THEN 
					FOR j := 0 TO LEN(dominatingFrequencies)-1 DO 

						IF energy > dominatingFrequenciesEnergy[j] THEN
							Swap(dominatingFrequenciesEnergy[j], energy); 
							Swap(dominatingFrequencies[j], frequency); 
						END; 
					END; 
				END;
				
			END; 
			writer.Update;

			Out.String("done"); Out.Update;

			FOR j := 0 TO LEN(dominatingFrequencies)-1 DO
				Out.Int(j,1); Out.String(" : "); Out.Float(dominatingFrequencies[j]); Out.Ln; 
			END; 
			
			Out.String(" count frequency "); Out.Float(SampleRate * sumTransitions / Samples / 2); Out.Ln;
			
			Out.Update; 

			FINALLY
				port.Close();
	END Record;
	
END SoundStream.

System.Free SoundStream ~ 
 
V24.Map 9 /dev/ttyUSB0  ~ 
SoundStream.Record 9 audio.txt ~ 

