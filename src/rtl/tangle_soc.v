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
 * Tangle SoC
 *
 * This module brings together all the components and is
 * expected to be the "TOP" module.
 */
module tangle_soc
	(
		input clk_i,
		input rst_i,
		output led1,
		output led2,
		output led3
	);

	wire [15:0] mem_data_i;
	wire [15:0] mem_addr_i;
	wire [15:0] mem_data_o;
	wire mem_we;
	wire f1, f2, f3;

	/* Memory. */
	memory memory_unit(
		.clk_i(clk_i),
		.data_i(mem_data_i),
		.addr_i(mem_addr_i[`RAM_SIZE_LOG-1:0]),
		.we_i(mem_we),
		.data_o(mem_data_o)
	);

	/* CPU. */
	cpu cpu_unit(
		.clk_i(clk_i),
		.rst_i(rst_i),
		.mem_data_o(mem_data_o),
		.mem_addr_i(mem_addr_i),
		.mem_data_i(mem_data_i),
		.mem_we(mem_we),
		.dbg_zf(f1),
		.dbg_sf(f2),
		.dbg_cf(f3)
	);

	assign led1 = !f1;
	assign led2 = !f2;
	assign led3 = !f3;

endmodule


/* SoC Unit testbench, define 'ENABLE_TESTSOC' in order to test this unit. */
`ifdef ENABLE_TESTSOC
module testbench_soc;

	reg  clk_i;
	reg  rst_i;
	wire led1;
	wire led2;
	wire led3;

	tangle_soc soc_unit(
		.clk_i(clk_i),
		.rst_i(rst_i),
		.led1(led1),
		.led2(led2),
		.led3(led3)
	);

	initial begin
		$dumpfile("soc.vcd");
		$dumpvars;
	end

	initial begin
			clk_i = 1'b0;
			rst_i = 1'b1;
		#5 	rst_i = 1'b0;
	end

	always
		#5 clk_i = !clk_i;

	initial
		#3000 $finish;

endmodule
`endif
