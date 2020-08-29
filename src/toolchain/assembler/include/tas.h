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
 * This is basically a transcription of 'tangle_config.v' and *must*
 * mirror and the changes made in the mentioned file.
 */

#ifndef TANGLE_H
#define TANGLE_H
	#include <sys/types.h>
	#include "array.h"
	#include "hashtable.h"

	/*
	 * Parser configs
	 */

	/*
	 * Instruction.
	 */
	struct insn
	{
		char *lbl_name;
		uint16_t insn;
		uint8_t type;
		off_t pc;
	};

	/*
	 * Label
	 */
	struct label
	{
		off_t off;
		char *name;
	};

	/* Instruction macros. */
	#define INSN_SET_OPCODE(i, o) ((i)->insn |= (((o) & 0x1F) << 11))
	#define INSN_SET_RD(i, o)     ((i)->insn |= (((o) & 7) << 8))
	#define INSN_SET_RS(i, o)     ((i)->insn |= (((o) & 7) << 5))
	#define INSN_SET_IMM5(i, o)   ((i)->insn |= ((o)  & 0x1F))
	#define INSN_SET_IMM8(i, o)   ((i)->insn |= ((o)  & 0xFF))

	/*
	 * Ranges.
	 * Note: MAX_IMM_AMI considers the min negative (signed)
	 * and max positive (unsigned), because the signal does
	 * not matter in AMI instructions.
	 */
	#define MIN_IMM_BRA (-(1 << (IMM_BRA_WIDTH-1)))
	#define MAX_IMM_BRA ( (1 << (IMM_BRA_WIDTH-1))-1)
	#define MIN_IMM_AMI (-(1 << (IMM_AMI_WIDTH-1)))
	#define MAX_IMM_AMI ( (1 << IMM_AMI_WIDTH)-1)

	/* Instruction table. */
	struct insn_tbl
	{
		char *name;
		uint8_t opcode;
		uint8_t type;
		int (*parser)(char **, struct insn_tbl *, struct insn *);
	};

	/*
	 * General configs
	 */
	#define BYTE_SIZE    16
	#define INSN_SIZE    16
	#define IMM_AMI_WIDTH 5
	#define IMM_BRA_WIDTH 8
	#define TOK_SZ       32

	/*
	 * Tangle opcodes
	 */

	/* Logical instructions. */
	#define OPC_OR    0
	#define OPC_AND   1
	#define OPC_XOR   2
	#define OPC_SLL   3
	#define OPC_SLR   4
	#define OPC_NOT   5
	#define OPC_NEG   6

	/* Arithmetic. */
	#define OPC_ADD   7
	#define OPC_SUB   8
	#define OPC_CMP   10

	/* Move. */
	#define OPC_MOV   9

	/* Branch. */
	#define OPC_JE    11
	#define OPC_JNE   12

	#define OPC_JGS   13
	#define OPC_JGU   14
	#define OPC_JLS   15
	#define OPC_JLU   16

	#define OPC_JGES  17
	#define OPC_JGEU  18
	#define OPC_JLES  19
	#define OPC_JLEU  20

	#define OPC_J     21
	#define OPC_JAL   22

	/* Memory (Load/Store). */
	#define OPC_LW    23
	#define OPC_SW    24

	/* Instruction types. */
	#define INSN_AMI 0 /* ALU/Memory/IO.  */
	#define INSN_BRA 1 /* Branch/Jump.    */
	#define INSN_MEM 2 /* Memory (LW/SW). */

#endif /* TANGLE_H */
