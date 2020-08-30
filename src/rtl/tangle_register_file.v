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

/*
 * Register File Unit.
 *
 * Tangle register file, 8 (16-bit) registers. Please note that this
 * register file is not supposed to use BRAM and thus, consumes a certain
 * amount of registers from the board. The benefits of using this approach
 * is that a clock pulse is only required for writings, not readings!,
 * meaning the reads may happen at any time.
 */
module register_file
	(
		input clk_i,
		input rst_i,
		input we_i,
		input  [2:0]  reg1_i,
		input  [2:0]  reg2_i,
		input  [15:0] data_i,
		output [15:0] data1_o,
		output [15:0] data2_o
	);

	/*
	 * Registers.
	 *
	 * Note: Seems that Gowin is not inferring BRAM here.
	 * If things get tight, it might be worth it to
	 * 'waste memory' and (try to) 'force' an inference to
	 * BRAM here.
	 */
	reg [15:0] registers[0:7];

	/* Write and/or reset. */
	always @ (posedge clk_i, `RESET_EDGE rst_i)
	begin
		if (`IS_RESET(rst_i)) begin
			registers[0] <= 16'd0;
			registers[1] <= 16'd0;
			registers[2] <= 16'd0;
			registers[3] <= 16'd0;
			registers[4] <= 16'd0;
			registers[5] <= 16'd0;
			registers[6] <= 16'd0;
			registers[7] <= 16'd0;
		end
		else begin
			/* Writes available 1-clock later. */
			if (we_i) begin
				/* Prohibits writings in r0. */
				if (reg1_i != 0) begin
					registers[reg1_i] <= data_i;
				end
			end
		end
	end

	/*
	 * Reads available immediately.
	 * It also saves us a few valuable registers, this
	 * resource is limited too =).
	 */
	assign data1_o = registers[reg1_i];
	assign data2_o = registers[reg2_i];

endmodule


/*
 * Register File testbench, define 'ENABLE_TESTBENCHS' in order to test this
 * unit.
 */
`ifdef ENABLE_TESTBENCHS
module testbench_register_file;
	reg  clk_i;
	reg  rst_i;
	reg  we_i;
	reg  [2:0]  reg1_i;
	reg  [2:0]  reg2_i;
	reg  [15:0] data_i;
	wire [15:0] data1_o;
	wire [15:0] data2_o;

	initial  begin
		$dumpfile("register_file.vcd");
		$dumpvars;
	end

	register_file register_file_unit(
		.clk_i(clk_i),
		.rst_i(rst_i),
		.we_i(we_i),
		.reg1_i(reg1_i),
		.reg2_i(reg2_i),
		.data_i(data_i),
		.data1_o(data1_o),
		.data2_o(data2_o)
	);

	initial begin
		$monitor(
			{"(time: %d) clk: %d / rst_i: %d / we_i: %d / reg1_i: %d",
			" / reg2_i: %d / data_i: %x / data1_o: %x / data2_o: %x"},
			$time, clk_i, rst_i, we_i, reg1_i, reg2_i, data_i, data1_o,
			data2_o
		);

		clk_i  =  1'b0;
		reg1_i =  3'h0;
		reg2_i =  3'h0;
		data_i = 16'h0;

		#5 rst_i = 1'b1; we_i = 1'b0;

	/* Writes. */
	#5	reg1_i = 3'd0; data_i = 16'hbeef; // Attempt to write in r0
		we_i   = 1'b1; rst_i  = 1'b0;

	#10	reg1_i = 3'd1; data_i = 16'hc001; // r1
	#10	reg1_i = 3'd2; data_i = 16'h2020; // r2
	#10	reg1_i = 3'd3; data_i = 16'h3333; // r3
	#10	reg1_i = 3'd4; data_i = 16'h4444; // r4
	#10	reg1_i = 3'd5; data_i = 16'h5555; // r5
	#10	reg1_i = 3'd6; data_i = 16'h6666; // r6
	#10	reg1_i = 3'd7; data_i = 16'h7777; // r7

	/* Reads. */
	#10	we_i   = 1'b0;
	#10	reg1_i = 3'd0;                // R0 should be 0!.
	#10	reg1_i = 3'd1; reg2_i = 3'd0; // R1 / R0
	#10	reg1_i = 3'd2; reg2_i = 3'd3; // R2 / R3
	#10	reg1_i = 3'd4; reg2_i = 3'd5; // R4 / R5
	#10	reg1_i = 3'd6; reg2_i = 3'd6; // R6 / R6
	#10	reg1_i = 3'd7; reg2_i = 3'd6; // R7 / R6
	end

	always
		#5 clk_i = !clk_i;

	initial
		#160 $finish;

endmodule
`endif
