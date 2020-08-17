/*
 * MIT License
 *
 * Copyright (c) 2020 Davidson Francis <davidsondfgl@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

`include "tangle_config.v"

/*
 * Memory Unit
 *
 * This memory is supposed to be inferred as BRAM by the synthesizer,
 * otherwise, this will eats all the LUTs from your board.
 *
 * On Sipeed Tang Nano, it is possible to use up to 8kB (2 bytes * 2^12
 * elements, RAM_SIZE_LOG = 12).
 */
module memory
	(
		input clk_i,
		input [`RAM_WIDTH-1:0] data_i,
		input [`RAM_SIZE_LOG-1:0] addr_i,
		input we_i,
		output reg [`RAM_WIDTH-1:0] data_o
	);

	/* RAM memory. */
	reg [`RAM_WIDTH-1:0] ram[(1 << `RAM_SIZE_LOG)-1:0];

	/* Initial values. */
	initial begin
		$readmemh("ram.hex", ram);
	end

	/* Output. */
	always @ (posedge clk_i)
	begin
		if (we_i)
		begin
			ram[addr_i] <= data_i;
			data_o <= data_i;
		end
		else
		begin
			data_o <= ram[addr_i];
		end
	end

endmodule


/* Memory testbench, define 'ENABLE_TESTBENCHS' in order to test this unit. */
`ifdef ENABLE_TESTBENCHS
module testbench_memory;
	reg  clk_i;
	reg  [`RAM_WIDTH-1:0]    data_i;
	wire [`RAM_WIDTH-1:0]    data_o;
	reg  [`RAM_SIZE_LOG-1:0] addr_i;
	reg  we_i;

	initial  begin
		$dumpfile("ram.vcd");
		$dumpvars;
	end

	memory memory_ram(
		.clk_i(clk_i),
		.data_i(data_i),
		.addr_i(addr_i),
		.we_i(we_i),
		.data_o(data_o)
	);

	initial begin
		$monitor(
			{"(time: %d) clk: %d / addr_i: %d / data_i: %x / data_o: %x",
			" / we_i: %d"},
			$time, clk_i, addr_i, data_i, data_o, we_i
		);

		clk_i = 1'b0;

	/* Writes. */
	#5	addr_i = 6'h0; data_i = 16'hbeef; we_i = 1'b1;
	#10	addr_i = 6'h1; data_i = 16'hdead;
	#10	addr_i = 6'h2; data_i = 16'hc0fe;
	#10	addr_i = 6'h3; data_i = 16'hc001;

	/* Reads. */
	#10	addr_i = 6'h0; we_i = 1'b0;
	#10	addr_i = 6'h1;
	#10	addr_i = 6'h2;
	#10	addr_i = 6'h3;
	end

	always
		#5 clk_i = !clk_i;

	initial
		#85 $finish;

endmodule
`endif
