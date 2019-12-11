
//
// Computes ceiling of the log base 2 - i.e. the number of bits required to hold N values.
//
function integer NumBits;
input [31:0] N;
reg   [31:0] k;
begin	
	k = N - 1;
	for(NumBits = 0; k > 0; NumBits = NumBits + 1)
		k = k >> 1;
end
endfunction
