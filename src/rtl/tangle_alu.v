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
		input wr_shift,
		output reg [15:0] data_o,
		output reg zf_o,           /* Zero flag.     */
		output reg sf_o,           /* Signal flag.   */
		output reg cf_o,           /* Carry flag.    */
		output reg of_o,           /* Overflow flag. */
		output busy_o              /* ALU is computing a shift. */
	);

	reg [15:0] shift_out;
	reg  [3:0] shifts = 4'b0;
	reg zf_next;
	reg sf_next;
	reg cf_next;
	reg of_next;

	assign busy_o = (shifts != 0);

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
				`SLL: begin
					data_o = shift_out;
				end
				`SLR: begin
					data_o = shift_out;
				end
			endcase
		end
	end

	/*
	 * Delayed shifts.
	 *
	 * This implementation is quite based on the femtorv32 approach:
	 * shifting 4-bits per time and 1, when there is no enough space.
	 *
	 * It should be noted that this implementation uses only 27 LUTs
	 * (114 vs 141) less than the 'default' (data1_i << data2_i[3:0]).
	 * However, this approach does not 'hurt' the maximum clock, on
	 * the contrary, the maximum clock slightly increases (from
	 * 31.298 to 32.921 MHz), so I will stay with this approach.
	 *
	 * The amount of cycles spent here would be:
	 *   AMI INSN Cyc (3 Cyc ATM) + shift_amt/4 + shift_amt%4
	 *
	 * so, it would spend from 3 cycles (0 bit shift) to at most
	 * (for 15 bits) 9 cycles to complete.
	 */
	always @(posedge clk_i)
	begin
		if (wr_shift) begin
			case (op_i)
				`SLL, `SLR: begin
					shift_out <= data1_i;
					shifts    <= data2_i[3:0];
				end
			endcase
		end else begin
			if (shifts >= 4'd4) begin
				shifts <= shifts - 4'd4;
				case (op_i)
					`SLL: shift_out <= shift_out << 4;
					`SLR: shift_out <= shift_out >> 4;
				endcase
			end else begin
				if (shifts != 4'd0) begin
					shifts <= shifts - 4'd1;
					case (op_i)
						`SLL: shift_out <= shift_out << 1;
						`SLR: shift_out <= shift_out >> 1;
					endcase
				end
			end
		end
	end

endmodule


/* ALU testbench, define 'ENABLE_TESTBENCHS' in order to test this unit. */
`ifdef ENABLE_TESTBENCHS
module testbench_alu;
	reg clk_i;
	reg rst_i;
	reg alu_en;
	reg wr_shift;
	reg   [3:0] op_i;
	reg  [15:0] data1_i;
	reg  [15:0] data2_i;
	wire [15:0] data_o;
	wire zf_o;
	wire sf_o;
	wire cf_o;
	wire of_o;
	wire alu_busy_o;

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
		.wr_shift(wr_shift),
		.data_o(data_o),
		.zf_o(zf_o),
		.sf_o(sf_o),
		.cf_o(cf_o),
		.of_o(of_o),
		.busy_o(alu_busy_o)
	);

	initial begin
		$monitor(
			{"(time: %d) clk: %d / rst: %d / data1_i: %d / data2_i: %d",
			" / data_o: %d / op_i: %d / zf_o: %d / sf_o: %d / cf_o: %d / of_o: %d"},
			$time, clk_i, rst_i, data1_i, data2_i, data_o, op_i, zf_o, sf_o, cf_o, of_o
		);

		op_i = 4'h0;
		data1_i  = 16'h0; data2_i = 16'h0; rst_i = 1'b1; clk_i = 1'b0; alu_en = 1'b1;
		wr_shift = 1'b1;

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
