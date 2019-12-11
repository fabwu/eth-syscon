MODULE Fourier; (** portable *)	(* ejz \00 *)
	IMPORT Math;

	PROCEDURE IsPowerOfTwo(x: SIGNED32): BOOLEAN;
	BEGIN
		WHILE (x MOD 2) = 0 DO
			x := x DIV 2
		END;
		RETURN x = 1
	END IsPowerOfTwo;

	PROCEDURE NumberOfBitsNeeded(x: SIGNED32): SIGNED32;
		VAR n: SIGNED32;
	BEGIN
		n := 0;
		WHILE x > 1 DO
			x := x DIV 2; INC(n)
		END;
		RETURN n
	END NumberOfBitsNeeded;

	PROCEDURE ReverseBits(x, n: SIGNED32): SIGNED32;
		VAR i, rev: SIGNED32;
	BEGIN
		rev := 0; i := 0;
		WHILE i < n DO
			rev := 2*rev + (x MOD 2);
			x := x DIV 2; INC(i)
		END;
		RETURN rev
	END ReverseBits;
	
	PROCEDURE Transform(fullAngle: FLOAT32; nSamples: SIGNED32; VAR realIn, imagIn, realOut, imagOut: ARRAY OF FLOAT32);
		VAR
			angle, alpha, beta, ar, ai, tr, ti, tmp: FLOAT32;
			nBits, i, j, k, n, size, end: SIGNED32;
	BEGIN
		ASSERT((nSamples > 1) & IsPowerOfTwo(nSamples));
		nBits := NumberOfBitsNeeded(nSamples);
		i := 0;
		WHILE i < nSamples DO
			j := ReverseBits(i, nBits);
			realOut[j] := realIn[i];
			imagOut[j] := imagIn[i];
			INC(i)
		END;
		end := 1; size := 2;
		WHILE size <= nSamples DO
			angle := fullAngle / size;
      	  alpha := Math.sin(0.5 * angle);
			alpha := 2.0 * alpha * alpha;
			beta := Math.sin(angle);
			i := 0;
			WHILE i < nSamples DO
				ar := 1.0; ai := 0.0; (* cos(0) / sin(0) *)
				j := i; n := 0;
				WHILE n < end DO
					k := j + end;
					tr := ar*realOut[k] - ai*imagOut[k];
					ti := ar*imagOut[k] + ai*realOut[k];
					realOut[k] := realOut[j] - tr;
					imagOut[k] := imagOut[j] - ti;
					realOut[j] := realOut[j] + tr;
					imagOut[j] := imagOut[j] + ti;
					tmp := alpha*ar + beta*ai;
					ai := ai - (alpha*ai - beta*ar);
					ar := ar - tmp;
					INC(j); INC(n)
				END;
				i := i + size;
			END;
			end := size; size := size * 2
		END
	END Transform;

	PROCEDURE FFT*(nSamples: SIGNED32; VAR realIn, imagIn, realOut, imagOut: ARRAY OF FLOAT32);
	BEGIN
		Transform(2*Math.pi, nSamples, realIn, imagIn, realOut, imagOut)
	END FFT;

	(* frequency = index / (nSamples / SamplingRate) *)
	PROCEDURE Frequency*(nSamples, index: SIGNED32; VAR realIn, imagIn: ARRAY OF FLOAT32; realOut, imagOut: FLOAT32);
		VAR
			beta, cos1, cos2, cos3, sin1, sin2, sin3, theta: FLOAT32;
			i: SIGNED32;
	BEGIN
		realOut := 0.0; imagOut := 0.0;
		theta := 2*Math.pi * index / nSamples;
		sin1 := Math.sin(-2 * theta); sin2 := Math.sin(-theta);
		cos1 := Math.cos(-2 * theta); cos2 := Math.cos(-theta);
		beta := 2 * cos2;
		i := 0;
		WHILE i < nSamples DO
			sin3 := beta*sin2 - sin1;
			sin1 := sin2; sin2 := sin3;
			cos3 := beta*cos2 - cos1;
			cos1 := cos2; cos2 := cos3;
			realOut := realOut + realIn[i]*cos3 - imagIn[i]*sin3;
			imagOut := imagOut + imagIn[i]*cos3 + realIn[i]*sin3;
			INC(i)
		END
	END Frequency;

	PROCEDURE IFFT*(nSamples: SIGNED32; VAR realIn, imagIn, realOut, imagOut: ARRAY OF FLOAT32);
		VAR i: SIGNED32;
	BEGIN
		Transform(-2*Math.pi, nSamples, realIn, imagIn, realOut, imagOut);
		i := 0;
		WHILE i < nSamples DO
			realOut[i] := realOut[i] / nSamples;
			imagOut[i] := imagOut[i] / nSamples;
			INC(i)
		END
	END IFFT;

END Fourier.


PROCEDURE Test*;
	CONST
		SamplingRate = 44100;
		NumSamples = 1024;
	VAR
		realIn, imagIn, realOut, imagOut: ARRAY NumSamples OF FLOAT32;
		F: Files.File; R: Files.Rider; i, mxr, mxi, dot: SIGNED32; l, r: INTEGER; maxr, maxi: FLOAT32;
BEGIN
	F := Files.Old("WaveScope.Data"); Files.Set(R, F, 0 (*(*365920*) 370564*) );
	Files.ReadInt(R, l); Files.ReadInt(R, r);
	i := 0;
	WHILE i < NumSamples DO
		realIn[i] := l; imagIn[i] := r;
		Files.ReadInt(R, l); Files.ReadInt(R, r);
		INC(i)
	END;
	FFT(NumSamples, realIn, imagIn, realOut, imagOut);
	i := 0; mxr := -1; mxi := -1; maxr := 0; maxi := 0;
	WHILE i < NumSamples DO
		IF ABS(realOut[i]) > maxr THEN maxr := ABS(realOut[i]); mxr := i END;
		IF ABS(imagOut[i]) > maxi THEN maxi := ABS(imagOut[i]); mxi := i END;
		INC(i)
	END;
	Display.ReplConst(Display.BG, 0, 0, Display.Width, Display.Height, Display.replace);
	Display.ReplConst(Display.FG, 0, 450, Display.Width, 1, Display.replace);
	i := 0;
	WHILE i < NumSamples DO
		(* Frequency = i / (NumSamples / SamplingRate) *)
		dot := ENTIER(0.5+16*ABS(realOut[i])/maxr); IF dot < 2 THEN dot := 2 END;
		Display.ReplConst(1, i, ENTIER(0.5+450+400*realOut[i]/maxr), dot, dot, Display.replace);
		dot := ENTIER(0.5+16*ABS(imagOut[i])/maxi); IF dot < 2 THEN dot := 2 END;
		Display.ReplConst(2, i, ENTIER(0.5+450+400*imagOut[i]/maxi), dot, dot, Display.replace);
		INC(i)
	END
END Test;