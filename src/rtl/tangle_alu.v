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
 * ALU Unit
 *
 * @notes Please consider the notes below:
 * - ZF, SF, CF and OF are updated in the next clock.
 * - left/right shift instructions are not implemented
 *   at the moment!.
 */
module alu
	(
		input clk_i,
		input rst_i,
		input [3:0] op_i,
		input      [15:0] data1_i,
		input      [15:0] data2_i,
		input alu_en,
		output reg [15:0] data_o,
		output reg zf_o,           /* Zero flag.     */
		output reg sf_o,           /* Signal flag.   */
		output reg cf_o,           /* Carry flag.    */
		output reg of_o            /* Overflow flag. */
	);

	reg zf_next;
	reg sf_next;
	reg cf_next;
	reg of_next;

	always @(posedge clk_i, `RESET_EDGE rst_i)
	begin
		if (`IS_RESET(rst_i)) begin
			zf_o <= 1'b0;
			sf_o <= 1'b0;
			cf_o <= 1'b0;
			of_o <= 1'b0;
		end else begin
			zf_o <= zf_next;
			sf_o <= sf_next;
			cf_o <= cf_next;
			of_o <= of_next;
		end
	end

	/* ALU. */
	always @(*)
	begin
		data_o = 16'h0;
		zf_next = zf_o;
		sf_next = sf_o;
		cf_next = cf_o;
		of_next = of_o;

		if (alu_en) begin
			case (op_i)
				`OR:  begin
					data_o = data1_i | data2_i;
					zf_next = (data_o == 16'h0);
					sf_next = data_o[15];
					{cf_next, of_next} = 2'b0;
				end
				`AND: begin
					data_o = data1_i & data2_i;
					zf_next = (data_o == 16'h0);
					sf_next = data_o[15];
					{cf_next, of_next} = 2'b0;
				end
				`XOR: begin
					data_o = data1_i ^ data2_i;
					zf_next = (data_o == 16'h0);
					sf_next = data_o[15];
					{cf_next, of_next} = 2'b0;
				end
				`NOT: begin
					data_o = ~data1_i;
				end
				`NEG: begin
					data_o = -data1_i;
				end
				`ADD: begin
					{cf_next, data_o} = {1'b0, data1_i} + {1'b0, data2_i};
					zf_next = (data_o == 16'h0);
					sf_next = data_o[15];
					of_next = (data1_i[15] == data2_i[15] && data1_i[15] != data_o[15]);
				end
				`SUB,
				`CMP: begin
					{cf_next, data_o} = {1'b0, data1_i} - {1'b0, data2_i};
					zf_next = (data_o == 16'h0);
					sf_next = data_o[15];
					of_next = (data1_i[15] != data2_i[15] && data1_i[15] != data_o[15]);
				end
				`MOV: begin
					data_o = data2_i;
				end
				`MOVHI: begin
					data_o = {data2_i[7:0], 8'h0};
				end
				`MOVLO: begin
					data_o = data1_i | data2_i;
				end
			endcase
		end
	end
endmodule


/* ALU testbench, define 'ENABLE_TESTBENCHS' in order to test this unit. */
`ifdef ENABLE_TESTBENCHS
module testbench_alu;
	reg clk_i;
	reg rst_i;
	reg alu_en;
	reg   [3:0] op_i;
	reg  [15:0] data1_i;
	reg  [15:0] data2_i;
	wire [15:0] data_o;
	wire zf_o;
	wire sf_o;
	wire cf_o;
	wire of_o;

	initial  begin
		$dumpfile("alu.vcd");
		$dumpvars;
	end

	alu alu_unit(
		.clk_i(clk_i),
		.rst_i(rst_i),
		.op_i(op_i),
		.data1_i(data1_i),
		.data2_i(data2_i),
		.alu_en(alu_en),
		.data_o(data_o),
		.zf_o(zf_o),
		.sf_o(sf_o),
		.cf_o(cf_o),
		.of_o(of_o)
	);

	initial begin
		$monitor(
			{"(time: %d) clk: %d / rst: %d / data1_i: %d / data2_i: %d",
			" / data_o: %d / op_i: %d / zf_o: %d / sf_o: %d / cf_o: %d / of_o: %d"},
			$time, clk_i, rst_i, data1_i, data2_i, data_o, op_i, zf_o, sf_o, cf_o, of_o
		);

		op_i = 4'h0;
		data1_i = 16'h0; data2_i = 16'h0; rst_i = 1'b1; clk_i = 1'b0; alu_en = 1'b1;

		#5 op_i = `OR; data1_i = 16'd15; data2_i = 16'd25; rst_i = 1'b0; /* OR. */
		#5 op_i = `AND; /* AND. */
		#5 op_i = `XOR; /* XOR. */
		#5 op_i = `SLL; /* SLL, not available, but interesting to
						   see what happens with invalid op. */

		/* 4'h4, Skip SLR, since is also unavailable. */

		#5 op_i = `NOT; // NOT
		#5 op_i = `ADD; // ADD
		#5 op_i = `SUB; // SUB

		#5  op_i = `ADD; data1_i = 16'hFFFF; data2_i = 16'h1; //  Overflow  ADD
		#10 op_i = `SUB; data1_i = 16'h8000; data2_i = 16'h1; // 'Overflow' SUB
		#10 op_i = `SUB; data1_i = 16'h0;    data2_i = 16'h1; //  'Carry'   SUB
		#10 op_i = `NEG; data1_i = 16'h3;    data2_i = 16'h0; //  Neg
	end

	always
		#5 clk_i = !clk_i;

	initial
		#70 $finish;

endmodule
`endif
