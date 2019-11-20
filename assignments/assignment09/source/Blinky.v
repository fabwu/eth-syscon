// Blinky.v  PDR 7.7.19 / 14.11.19
module top (
  input OSCIN, // 100MHz
  output LED);

reg [24:0] cnt;

assign LED = cnt[24];

always @(posedge OSCIN) begin
  cnt <= cnt + 1;
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
