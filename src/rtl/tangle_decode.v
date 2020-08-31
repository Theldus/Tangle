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
 * I know, I know, this is horrible and it should be burned in hell...
 * but it was the least eye-hurting solution I found; if you have a
 * better idea, please tell me, I'm all ears.
 *
 * In before, the macro expansion seems 'right', since the output
 * of Icarus Verilog '-E' seems correct to me.
 */
`define COND_JUMP(expr) \
	if ((expr)) begin                                \
		if (regdst_o == 3'b0) begin                  \
			nextpc_o = `INSN_PC_IMM;                 \
			imm_o = { {8{insn_i[7]}}, insn_i[7:0] }; \
		end else begin                               \
			nextpc_o = `INSN_PC_REG;                 \
		end                                          \
	end else begin                                   \
		nextpc_o = `INSN_PC_INC;                     \
	end

/*
 * Tangle Decode Unit
 *
 * Tangle CPU has 3 types of instructions: AMI, Branch/Jump and Memory.
 *
 * AMI:
 * =========================
 * AMI stands for ALU + Movimentation + I/O, instructions of this type
 * have the following format: (RD = Register Destination / RS = Register
 * Source)
 * - INSN RD, RS
 *   or
 * - INSN RD, Imm (5 bits, unsigned)
 *
 * and it is similar to x86 in its behavior, as an example, an:
 *   ADD r1, r5
 * would be interpreted as: r1 = r1 + r5. Immediate values in AMI
 * instructions are 5 bits long and are always treated as unsigned.
 *
 * Instruction format:
 * -------------------
 * REG/REG:
 * (5 bits)  (3 bits)   (3 bits)    (5 bits, unused, all zeros)
 *  OPCODE       RD         RS                 Imm
 *   00000      000        000                00000
 *
 * Note: In Reg/Reg insns, RS *must not* be 0.
 *
 * REG/Imm:
 * (5 bits)  (3 bits)   (3 bits)    (5 bits, unsigned)
 *  OPCODE       RD         RS             Imm
 *   00000      000        000            00000
 *
 * Note: Imm Reg/Imm insns, RS *must* be 0.
 *
 * Clock notes:
 * ------------
 * AMI instructions takes 3 clock cycles to finish.
 *
 *
 * Branch/Jump
 * =========================
 * (Branches and jumps are treated in the same way in Tangle, so the term
 * will be used interchangeably.)
 *
 * Branches can be PC-based, while used with immediate value, or absolute,
 * if register-based.
 *
 * Its usage is very straightforward:
 * - INSN rX     (rX = register, r1 -- r7)
 *   or
 * - INSN label  (or an integer, 8-bit signed value).
 *
 * Instruction format:
 * -------------------
 * REG:
 * (5 bits)  (3 bits)   (8 bits, unused, all zeros)
 *  OPCODE       RD             Imm
 *   00000      000          00000000
 *
 * Note: In Reg branches, RD *must not* be 0.
 *
 * Imm:
 * (5 bits)  (3 bits)   (8 bits, signed)
 *  OPCODE       RD           Imm
 *   00000      000        00000000
 *
 * Note: In Imm/Label branches, RD *must* be 0.
 *
 * Clock notes:
 * ------------
 * Taken jumps: 4 cycles
 * Not taken jumps: 3 cycles
 *
 *
 * Memory (Load/Store)
 * =========================
 * Load/Store instructions in Tangle is as follows:
 * - LW RD, IMM (RS)
 *   or
 * - SW RD, IMM (RS)
 *
 * where RD is the source (for store) and destination (for loads).
 *
 * The address is calculated as the sum of the immediate value
 * (5 bits, signed) and the register RS contents. The resulting value
 * is a memory 'position' where the content will be stored/loaded.
 *
 * Note that by position, it means that:
 * - LW r1, 2 (R0)
 *
 * r1 will contains the third word (word = 16-bit element) from the memory,
 * and *not* that r1 will contains a word starting from the byte 2!.
 *
 * Instruction format:
 * -------------------
 * Load/Store:
 * (5 bits)  (3 bits)   (3 bits)    (5 bits, signed)
 *  OPCODE       RD         RS             Imm
 *   00000      000        000            00000
 *
 * Clock notes:
 * ------------
 * Load: 4 cycles
 * Store: 3 cycles
 *
 *
 * General Notes
 * =========================
 * There is, to date, no standard in the organization of the opcode bits to
 * identify which type of instruction. Opcodes can be found in
 * "tangle_config.v".
 */
module decode
	(
		input [15:0] insn_i,
		input zf_i,
		input sf_i,
		input cf_i,
		input of_i,

		output [2:0] regdst_o, //All insns
		output [2:0] regsrc_o, //ALU Reg/Reg and Memory

		output reg  [1:0] nextpc_o,
		output reg  [2:0] insntype_o,
		output reg  [3:0] aluop_o,
		output reg [15:0] imm_o, //Immediate: ALU Reg/Imm + Memory + Branch
		output reg regwe_o,
		output reg memwe_o,
		output reg aluen_o
	);

	assign regsrc_o = insn_i[7:5];
	assign regdst_o = insn_i[10:8];

	always @(*)
	begin
		nextpc_o = `INSN_PC_INC;
		insntype_o = 3'h0;
		aluop_o = 4'bxxxx;
		imm_o = 16'h0;
		regwe_o = 1'b0;
		memwe_o = 1'b0;
		aluen_o = 1'b0;

		/* Opcode. */
		case (insn_i[15:11])
			/* ALU + Mov + IO = AMI. */
			`TANGLE_OPCODE_OR,
			`TANGLE_OPCODE_AND,
			`TANGLE_OPCODE_XOR,
			`TANGLE_OPCODE_SLL,
			`TANGLE_OPCODE_SLR,
			`TANGLE_OPCODE_NOT,
			`TANGLE_OPCODE_NEG,
			`TANGLE_OPCODE_ADD,
			`TANGLE_OPCODE_SUB,
			`TANGLE_OPCODE_MOV,
			`TANGLE_OPCODE_CMP:
			begin
				aluen_o = 1'b1;
				aluop_o = insn_i[14:11];        //Alu opcode
				regwe_o = 1'b1;                 //Register write back
				imm_o   = {11'h0, insn_i[4:0]}; //Unsigned immediate

				/*
				 * CMP needs to be treated separately from the others, since
				 * it is exactly the same as SUB, but cannot write to the
				 * register bank, i.e.: without regwe.
				 */
				if (insn_i[15:11] != `TANGLE_OPCODE_CMP)
					regwe_o = 1'b1;
				else
					regwe_o = 1'b0;

				/* Immediate or reg/reg. */
				if (regsrc_o != 3'b0)
					insntype_o = `INSN_AMI_REGREG;
				else
					insntype_o = `INSN_AMI_REGIMM;
			end
			/*
			 * MOVHI and MOVLI, an unfortunatell exception on AMI insns:
			 *
			 * Instead of having 5-bit immediate values, MOVHI/LO
			 * have 8-bit immediate values, which 'breaks' the
			 * encoding. Anyway, for all intents and purposes, they
			 * will still be considered as 'AMI' instructions.
			 */
			`TANGLE_OPCODE_MOVHI,
			`TANGLE_OPCODE_MOVLO:
			begin
				aluen_o    = 1'b1;
				aluop_o    = insn_i[14:11];
				regwe_o    = 1'b1;
				imm_o      = {8'h0, insn_i[7:0]}; //Unsigned immediate
				insntype_o = `INSN_AMI_REGIMM;
			end

			/* Conditional jumps. */
			`TANGLE_OPCODE_JE: begin
				`COND_JUMP(zf_i == 1'b1)
			end
			`TANGLE_OPCODE_JNE: begin
				`COND_JUMP(zf_i == 1'b0)
			end
			`TANGLE_OPCODE_JGS: begin
				`COND_JUMP(zf_i == 1'b0 && sf_i == of_i)
			end
			`TANGLE_OPCODE_JGU: begin
				`COND_JUMP(cf_i == 1'b0 && zf_i == 1'b0)
			end
			`TANGLE_OPCODE_JGES: begin
				`COND_JUMP(sf_i == of_i)
			end
			`TANGLE_OPCODE_JGEU: begin
				`COND_JUMP(cf_i == 1'b0)
			end
			`TANGLE_OPCODE_JLS: begin
				`COND_JUMP(sf_i != of_i)
			end
			`TANGLE_OPCODE_JLU: begin
				`COND_JUMP(cf_i == 1'b1)
			end
			`TANGLE_OPCODE_JLES: begin
				`COND_JUMP(zf_i == 1'b1 || sf_i != of_i)
			end
			`TANGLE_OPCODE_JLEU: begin
				`COND_JUMP(cf_i == 1'b1 || zf_i == 1'b1)
			end

			/* Unconditional jumps. */
			`TANGLE_OPCODE_J: begin
				if (regdst_o == 3'b0) begin
					nextpc_o = `INSN_PC_IMM;
					imm_o = { {8{insn_i[7]}}, insn_i[7:0]};
				end else begin
					nextpc_o = `INSN_PC_REG;
				end
			end
			`TANGLE_OPCODE_JAL: begin
				regwe_o = 1'b1;
				insntype_o = `INSN_BRA_JAL;
				if (regdst_o == 3'b0) begin
					nextpc_o = `INSN_PC_IMM;
					imm_o = { {8{insn_i[7]}}, insn_i[7:0]};
				end else begin
					nextpc_o = `INSN_PC_REG;
				end
			end

			/* Load. */
			`TANGLE_OPCODE_LW:
			begin
				aluen_o = 1'b1;
				aluop_o = `ADD;
				insntype_o = `INSN_MEM_LW;
				imm_o = { {11{insn_i[4]}}, insn_i[4:0]}; //Signed immediate
				regwe_o = 1'b1;
			end

			/* Store. */
			`TANGLE_OPCODE_SW:
			begin
				aluen_o = 1'b1;
				aluop_o = `ADD;
				insntype_o = `INSN_MEM_SW;
				imm_o  = { {11{insn_i[4]}}, insn_i[4:0]}; //Signed immediate
				memwe_o = 1'b1;
			end
		endcase
	end
endmodule


/* Decode Unit testbench, define 'ENABLE_TESTBENCHS' in order to test this unit. */
`ifdef ENABLE_TESTBENCHS
module testbench_decode;
	reg  [15:0] insn_i;
	reg  zf_i;
	reg  sf_i;
	reg  cf_i;
	reg  of_i;

	wire  [2:0] regdst_o;
	wire  [2:0] regsrc_o;
	wire  [1:0] nextpc_o;
	wire  [2:0] insntype_o;
	wire  [3:0] aluop_o;
	wire [15:0] imm_o;
	wire regwe_o;
	wire memwe_o;

	initial  begin
		$dumpfile("decode.vcd");
		$dumpvars;
	end

	decode decode_unit(
		.insn_i(insn_i),
		.zf_i(zf_i),
		.sf_i(sf_i),
		.cf_i(cf_i),
		.of_i(of_i),
		.regdst_o(regdst_o),
		.regsrc_o(regsrc_o),
		.nextpc_o(nextpc_o),
		.insntype_o(insntype_o),
		.aluop_o(aluop_o),
		.imm_o(imm_o),
		.regwe_o(regwe_o),
		.memwe_o(memwe_o)
	);

	initial begin
		{zf_i, sf_i, cf_i, of_i} = 4'b0;

		// Alu + Mov
		#5 insn_i = {`TANGLE_OPCODE_OR,  3'b000, 3'b000,  5'd0}; // OR  r0,  0
		#5 insn_i = {`TANGLE_OPCODE_OR,  3'b001, 3'b000,  5'd5}; // OR  r1,  5
		#5 insn_i = {`TANGLE_OPCODE_SUB, 3'b101, 3'b011,  5'd0}; // SUB r5, r3
		#5 insn_i = {`TANGLE_OPCODE_ADD, 3'b001, 3'b000, 5'd10}; // ADD r1, 10

		// Branch
		#5 insn_i = {`TANGLE_OPCODE_JE, 3'b000, -8'd5};                 // JZ  -5, not taken
		#5 insn_i = {`TANGLE_OPCODE_JE, 3'b000, -8'd5};    zf_i = 1'b1; // JZ  -5, taken

		#5 insn_i = {`TANGLE_OPCODE_JGS, 3'b000,  8'd128}; zf_i = 1'b0; // JGS 128, taken
		#5 insn_i = {`TANGLE_OPCODE_JGS, 3'b011,  8'd0};   sf_i = 1'b1; // JGS  r3, not taken

		#5 insn_i = {`TANGLE_OPCODE_JLS, 3'b000,  8'd10};               // JLS  10, taken
		#5 insn_i = {`TANGLE_OPCODE_JLS, 3'b000,  8'd10};  sf_i = 1'b0; // JLS  10, not taken

		#5 insn_i = {`TANGLE_OPCODE_J,   3'b000, 8'd60};               //  J  10, taken
		#5 insn_i = {`TANGLE_OPCODE_JAL, 3'b001, 8'd0};                // JAL r1, taken

		// Load/Store
		#5 insn_i = {`TANGLE_OPCODE_LW, 3'b011, 3'b001, -5'd4};  // LW r3, -4(r1)
		#5 insn_i = {`TANGLE_OPCODE_SW, 3'b101, 3'b010,  5'd8};  // SW r5,  8(r2)

		// Invalid opcode
		#5 insn_i = {5'b11111, 3'b101, 3'b010,  5'd8}; // Invalid
	end

endmodule
`endif
