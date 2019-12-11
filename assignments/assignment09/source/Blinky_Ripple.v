// Blinky.v  PDR 7.7.19 / 14.11.19

module DFF (
  input d,
  input clk,
  output reg q);

always @(posedge clk) begin
  q <= d;
end

endmodule

module top (
  input OSCIN, // 100MHz
  output LED);

reg [24:0] cnt;

assign LED = cnt[24];

genvar i;
generate for (i = 0; i < 24; i = i + 1)
  DFF dff(.d(~cnt[i+1]), .clk(cnt[i]), .q(cnt[i+1]));
endgenerate

always @(posedge OSCIN) begin
  cnt[0] <= ~cnt[0];
end

endmodule

/*
$ yosys -q -p 'synth_ice40 -blif blinky.blif' Blinky.v
$ arachne-pnr -d 8k -P tq144:4k -p Blinky.pcf \
    -o blinky.asc blinky.blif
...
$ icetime -d hx8k -P tq144:4k -p Blinky.pcf blinky.asc
...
$ icepack -s blinky.asc blinky.bin
$ cat 64xFF.bin blinky.bin 8xFF.bin > blinky.dfu \
    && dfu-suffix -a blinky.dfu
...
$ dfu-util -D blinky.dfu
...
$
*/
