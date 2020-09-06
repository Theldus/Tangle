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

/* Memory constants. */
`define RAM_SIZE_LOG  6
`define RAM_WIDTH    16

/* Default HW reset behaviour.
 * This *must* be double checked if used in others boards
 * besides Sipeed Tang Nano.
 */
`define HW_RESET_EDGE negedge
`define HW_ISRESET(rst_pin) (!(rst_pin))

/*
 * Is RESET button enabled at pos or negedge?
 * in simulations I'll assume posedge but on
 * Sipeed Tang Nano it is on negedge.
 */
`ifndef ENABLE_TESTSOC
	`ifndef ENABLE_TESTBENCHS
		`define RESET_EDGE `HW_RESET_EDGE
		`define IS_RESET `HW_ISRESET
	`else
		`define RESET_EDGE posedge
		`define IS_RESET(rst_pin) rst_pin
	`endif
`else
	`define RESET_EDGE posedge
	`define IS_RESET(rst_pin) rst_pin
`endif

/*
 * Alu operations.
 *
 * Note: Please note that for the moment Tangle
 * will not support sll/srl (opcode 3 and 4) and
 * mult/div (opcode 8 and 9) instructions due to
 * the fact that they are too much resource hungry.
 *
 * Maybe there is a way to reduce the resource
 * usage and thus, opcodes 3, 4, 8 and 9 are
 * reserved.
 */
`define OR    4'b0000
`define AND   4'b0001
`define XOR   4'b0010
`define SLL   4'b0011 /* Reserved. */
`define SLR   4'b0100 /* Reserved. */
`define NOT   4'b0101
`define NEG   4'b0110
`define ADD   4'b0111
`define SUB   4'b1000
`define MOV   4'b1001
`define MOVHI 4'b1010
`define MOVLO 4'b1011
`define CMP   4'b1100

/* ======== Tangle opcodes ======== */

// Logic instructions
`define TANGLE_OPCODE_OR    {1'b0,  `OR}
`define TANGLE_OPCODE_AND   {1'b0, `AND}
`define TANGLE_OPCODE_XOR   {1'b0, `XOR}
`define TANGLE_OPCODE_SLL   {1'b0, `SLL}
`define TANGLE_OPCODE_SLR   {1'b0, `SLR}
`define TANGLE_OPCODE_NOT   {1'b0, `NOT}
`define TANGLE_OPCODE_NEG   {1'b0, `NEG}

// Arithmetic
`define TANGLE_OPCODE_ADD   {1'b0, `ADD}
`define TANGLE_OPCODE_SUB   {1'b0, `SUB}
`define TANGLE_OPCODE_CMP   {1'b0, `CMP}

// Move
`define TANGLE_OPCODE_MOV   {1'b0, `MOV}
`define TANGLE_OPCODE_MOVHI {1'b0, `MOVHI}
`define TANGLE_OPCODE_MOVLO {1'b0, `MOVLO}

// Branch
`define TANGLE_OPCODE_JE    5'b01101
`define TANGLE_OPCODE_JNE   5'b01110

`define TANGLE_OPCODE_JGS   5'b01111
`define TANGLE_OPCODE_JGU   5'b10000
`define TANGLE_OPCODE_JLS   5'b10001
`define TANGLE_OPCODE_JLU   5'b10010

`define TANGLE_OPCODE_JGES  5'b10011
`define TANGLE_OPCODE_JGEU  5'b10100
`define TANGLE_OPCODE_JLES  5'b10101
`define TANGLE_OPCODE_JLEU  5'b10110

`define TANGLE_OPCODE_J     5'b10111
`define TANGLE_OPCODE_JAL   5'b11000

// Memory (Load/Store)
`define TANGLE_OPCODE_LW    5'b11001
`define TANGLE_OPCODE_SW    5'b11010

/* Instruction Types.
 * AMI = Alu/Mov/IO
 * BRA = Branches
 * MEM = Memory
 */
`define INSN_AMI_REGREG 3'b000
`define INSN_AMI_REGIMM 3'b001
`define INSN_BRA_JAL    3'b010
`define INSN_MEM_LW     3'b011
`define INSN_MEM_SW     3'b100

/* Next PC. */
`define INSN_PC_IMM 2'b00 //Next PC is immediate
`define INSN_PC_REG 2'b01 //Next PC is inside register based
`define INSN_PC_INC 2'b10 //Next PC just increments, not branch

/* Tangle CPU states. */
`define STATE_IDLE       3'd0
`define STATE_WAIT       3'd1
`define STATE_INSN_FETCH 3'd2
`define STATE_EXECUTE    3'd3
`define STATE_WAIT_MEM   3'd4
`define STATE_WAIT_ALU   3'd5
`define STATE_WRITEBACK  3'd6
