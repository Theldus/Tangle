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
 * Tangle CPU.
 */
module cpu
	(
		input  clk_i,
		input  rst_i,
		input  [15:0] mem_data_o,
		output [15:0] mem_data_i,
		output [15:0] mem_addr_i,
		output mem_we,
		output dbg_zf,
		output dbg_sf,
		output dbg_cf
	);

	reg  [`RAM_SIZE_LOG-1:0] pc;
	reg  [2:0]  state;
	reg  [15:0] mem_addr;
	reg  [15:0] insn_i;
	reg  [15:0] next_insn;

	// Decode wires
	wire zf_o;
	wire sf_o;
	wire cf_o;
	wire of_o;
	wire  [2:0] regdst_o;
	wire  [2:0] regsrc_o;
	wire  [1:0] nextpc_o;
	wire  [2:0] insntype_o;
	wire  [3:0] aluop_o;
	wire [15:0] imm_o;
	wire  regwe_o;
	wire  memwe_o;
	wire  aluen_o;

	// Reg file wires
	wire [15:0] reg_data1;
	wire [15:0] reg_data2;
	wire [15:0] reg_input;

	// Alu
	wire [15:0] alu_out;
	wire [15:0] alu_data1;
	wire [15:0] alu_data2;
	wire alu_busy;

	// Alu enable
	wire alu_en = (aluen_o && (state == `STATE_INSN_FETCH
		|| state == `STATE_EXECUTE
		|| state == `STATE_WAIT_ALU));

	// Reg write-enable
	wire reg_we =
		(state == `STATE_EXECUTE ? regwe_o :
		 state == `STATE_WAIT_ALU ? regwe_o :
		 state == `STATE_WRITEBACK && insntype_o == `INSN_MEM_LW ? regwe_o :
		 1'b0);

	/* Next PC and PC w/ imm jump. */
	wire [`RAM_SIZE_LOG-1:0] PCplus2    = pc + 1'd1;
	wire [`RAM_SIZE_LOG-1:0] PCplus_imm = pc + imm_o[`RAM_SIZE_LOG-1:0];

	/* Memory wires. */
	assign mem_we = (state == `STATE_WRITEBACK ? memwe_o : 1'b0);
	assign mem_data_i = reg_data1;
	assign mem_addr_i = mem_addr;

	/* Debug pin. */
	assign dbg_zf = zf_o;
	assign dbg_sf = sf_o;
	assign dbg_cf = cf_o;

	/* Decode. */
	decode decode_unit(
		.insn_i(insn_i),
		.zf_i(zf_o),
		.sf_i(sf_o),
		.cf_i(cf_o),
		.of_i(of_o),
		.regdst_o(regdst_o),
		.regsrc_o(regsrc_o),
		.nextpc_o(nextpc_o),
		.insntype_o(insntype_o),
		.aluop_o(aluop_o),
		.imm_o(imm_o),
		.regwe_o(regwe_o),
		.memwe_o(memwe_o),
		.aluen_o(aluen_o)
	);

	/* Register file. */
	register_file register_file_unit(
		.clk_i(clk_i),
		.rst_i(rst_i),
		.we_i(reg_we),
		.reg1_i(insntype_o != `INSN_BRA_JAL ? regdst_o : 3'b111),
		.reg2_i(regsrc_o),
		.data_i(reg_input),
		.data1_o(reg_data1),
		.data2_o(reg_data2)
	);

	/* Alu. */
	alu alu_unit(
		.clk_i(clk_i),
		.rst_i(rst_i),
		.op_i(aluop_o),
		.data1_i(alu_data1),
		.data2_i(alu_data2),
		.alu_en(alu_en),
		.wr_shift(state == `STATE_INSN_FETCH),
		.data_o(alu_out),
		.zf_o(zf_o),
		.sf_o(sf_o),
		.cf_o(cf_o),
		.of_o(of_o),
		.busy_o(alu_busy)
	);

	/* Some inputs. */
	assign alu_data1 = (
		insntype_o == `INSN_AMI_REGREG ? reg_data1 :
		insntype_o == `INSN_AMI_REGIMM ? reg_data1 :
		insntype_o == `INSN_MEM_LW ? reg_data2 :
		insntype_o == `INSN_MEM_SW ? reg_data2 :
		reg_data1
	);
	assign alu_data2 = (
		insntype_o == `INSN_AMI_REGREG ? reg_data2 : imm_o
	);
	assign reg_input = (
		(insntype_o == `INSN_AMI_REGREG || insntype_o == `INSN_AMI_REGIMM) ? alu_out :
		(insntype_o == `INSN_BRA_JAL) ? PCplus2 :
		mem_data_o
	);

	/* CPU state machine. */
	always @(posedge clk_i, `RESET_EDGE rst_i)
	begin

		if (`IS_RESET(rst_i)) begin
			pc        <= 0;
			insn_i    <= 0;
			next_insn <= 0;
			mem_addr  <= 0;
			state     <= `STATE_IDLE;
		end

		else begin
			case (state)
				/* Initial states. */
				`STATE_IDLE: begin
					state <= `STATE_WAIT;
				end
				`STATE_WAIT: begin
					mem_addr  <= PCplus2;
					insn_i    <= mem_data_o;
					next_insn <= mem_data_o;
					state     <= `STATE_INSN_FETCH;
				end

				/*
				 * Instruction fetch.
				 * Intentional delay to save our insn_i
				 * properly.
				 */
				`STATE_INSN_FETCH: begin

					/*
					 * Before go to execute, check in beforehand
					 * if we have a taken branch and if so, already
					 * adjusts the memory input.
					 */
					case (nextpc_o)
						`INSN_PC_IMM: begin
							mem_addr <= PCplus_imm;
						end
						`INSN_PC_REG: begin
							mem_addr <= reg_data1;
						end
					endcase

					/* Go to execute. */
					state  <= `STATE_EXECUTE;
				end

				/* Decode/execute. */
				`STATE_EXECUTE: begin

					/* Adjusts PC and next state. */
					case (nextpc_o)

						/* If taken branch. */
						`INSN_PC_IMM: begin
							pc    <= PCplus_imm;
							state <= `STATE_WAIT_MEM;
						end
						`INSN_PC_REG: begin
							pc    <= reg_data1[`RAM_SIZE_LOG-1:0];
							state <= `STATE_WAIT_MEM;
						end

						/* If normal execution, go to writeback. */
						default: begin
							if (alu_busy != 1'b1) begin
								pc    <= PCplus2;
								state <= `STATE_WRITEBACK;
							end else begin
								state <= `STATE_WAIT_ALU;
							end
						end
					endcase

					/*
					 * Load or store.
					 *
					 * If store _and_ if the next instruction have the same
					 * address as the store instruction, set the next
					 * instruction value to be the store content. Otherwise,
					 * next instruction will just be the data available from
					 * memory in the next clock.
					 */
					if (insntype_o == `INSN_MEM_LW || insntype_o == `INSN_MEM_SW)
					begin
						mem_addr <= alu_out;

						if (insntype_o == `INSN_MEM_LW)
							state <= `STATE_WAIT_MEM;

						if (insntype_o == `INSN_MEM_SW && alu_out == PCplus2)
							next_insn <= reg_data1;
						else
							next_insn <= mem_data_o;

					end else begin
						next_insn <= mem_data_o;
					end

				end

				/* Memory. */
				`STATE_WAIT_MEM: begin
					next_insn <= mem_data_o;
					state     <= `STATE_WRITEBACK;
				end

				/* ALU, wait for shifts. */
				`STATE_WAIT_ALU: begin
					if (alu_busy != 1'b1) begin
						pc    <= PCplus2;
						state <= `STATE_WRITEBACK;
					end
				end

				/* Write-back. */
				`STATE_WRITEBACK: begin

					/* Lookahead our next instruction. */
					insn_i   <= next_insn;
					mem_addr <= PCplus2;
					state    <= `STATE_INSN_FETCH;
				end

			endcase
		end
	end
endmodule
