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

#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <libgen.h>
#include <getopt.h>
#include "tas.h"

/* Label table hashtable. */
static struct hashtable *ht_lbls;

/* Output. */
static struct array *insn_out;

/* ASM file. */
static FILE *asmf;

/* Line. */
static int current_line;

/* Current PC. */
static off_t current_pc;

/* Filename. */
static char *src_file;

/* Input/Output files. */
static char *input_file;
static char *output_file;

/* Match flags. */
#define M_NI  0 /* Unconditionally not increment.     */
#define M_I   1 /* Unconditionally increment.         */
#define M_IC  2 /* Increment conditionally (if true.) */
#define M_NS  1 /* Not suppress error msgs.           */
#define M_S   0 /* Suppress error messages.           */

/* Setters routines. */
#define S_MATCH    1
#define S_NOMATCH  0
#define S_ERROR   -1

/* Register direction: source or destiny. */
#define S_DIR_RS   0
#define S_DIR_RD   1

/* Immediate type: branch or AMI. */
#define S_TYPE_IMM 0
#define S_TYPE_BRA 1

/**
 * Emits an error message and the location from which it occurred.
 *
 * @param fmt Formatted string to be printed.
 */
static void error(const char* fmt, ...)
{
    va_list args;

    /* Indentify the context. */
    fprintf(stderr, "%s:%d: Error: ", src_file, current_line);

    /* Emmits error. */
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
}

/**
 * @brief Check if the parameter @p c is a valid token*.
 *
 * @param c Character to be checked.
 *
 * @return Returns 1 if valid or 0 otherwise.
 *
 * @note A 'token' can be: label, register or number. This
 * function have a side effect of allowing labels starting
 * with '+' or '-', for example, but I do not think this
 * an issue, a label is just, a label.
 */
static inline int is_valid_label(char c)
{
	return (isalpha(c) || isdigit(c) ||
		c == '_' || c == '-' || c == '+');
}

/**
 * @brief Skips valid characters until there are no more.
 *
 * @param s Line pointer.
 */
static inline void skip_validlabel(char **s)
{
	char *p = *s; /* Current line pointer. */
	while (is_valid_label(*p))
		p++;
	*s = p;
}

/**
 * @brief Skips whitespace (spaces and tabs) characters until
 * there are no more.
 *
 * @param s Line pointer.
 */
static inline void skip_whitespace(char **s)
{
	char *p = *s; /* Current line pointer. */
	while (isblank(*p))
		p++;
	*s = p;
}

/**
 * @brief Allocates a new instruction.
 *
 * @return Returns a new instruction structure.
 */
static inline struct insn *create_insn(void)
{
	struct insn *insn; /* New instruction structure. */
	insn = calloc(1, sizeof(struct insn));
	return (insn);
}

/**
 * @brief Adds the label @p lbl_name to the list of labels, as
 * well as its offset @p off, relative to the program counter.
 *
 * @param lbl_name Label name.
 * @param off Label offset.
 *
 * @return Returns 0 if success and 1 otherwise.
 */
static inline int add_label(char *lbl_name, off_t off)
{
	struct label *lbl; /* New label structure. */

	/* Check if label already exists. */
	if (hashtable_get(&ht_lbls, lbl_name) != NULL)
	{
		error("label (%s) is already defined\n", lbl_name);
		goto err0;
	}

	/* Allocate. */
	if ((lbl = calloc(1, sizeof(struct label))) == NULL)
	{
		error("failed to allocate new label (%s), "
			"insufficient  memory", lbl_name);
		goto err0;
	}

	/* Name. */
	if ((lbl->name = strdup(lbl_name)) == NULL)
	{
		error("failed to allocate new label (%s), "
			"insufficient  memory", lbl_name);
		goto err1;
	}

	lbl->off = off;

	/* Add into the hashtable. */
	if (hashtable_add(&ht_lbls, lbl->name, lbl) < 0)
	{
		error("failed to insert label (%s) into the hashtable\n",
			lbl_name);
		goto err2;
	}
	return (1);

err2:
	free(lbl->name);
err1:
	free(lbl);
err0:
	return (0);
}

/**
 * @brief Checks if the (lowercase) character of the string pointed
 * by @p s is equal to the character @p c.
 *
 * @param s String to be checked.
 * @param c Character to be checked.
 *
 * @param inc Increment condition, if M_I, @p s will be increment
 * regardless the match result; if M_NI no increment will occur and
 * if M_IC, @p s will be increment if and only if the match occurs.
 *
 * @return Returns 1 if the match has occurred and 0 otherwise.
 */
static inline int match(char **s, char c, int inc, int supr)
{
	char *p = *s; /* Current line pointer. */
	int ret = 0;  /* Return code.          */

	if (tolower(*p) == c)
		ret = 1;
	else
	{
		if (supr)
			error("expected '%c', found '%c'\n", c, *p);
	}
	/* Increment. */
	if (inc == M_I)
		*s = p + 1;
	else if (inc == M_IC && ret)
		*s = p + 1;
	return (ret);
}

/**
 * @brief Checks if the (lowercase) character of the string pointed
 * by @p s is less than the character @p c.
 *
 * @param s String to be checked.
 * @param c Character to be checked.
 *
 * @param inc Increment condition, if M_I, @p s will be increment
 * regardless the match result; if M_NI no increment will occur and
 * if M_IC, @p s will be increment if and only if the match occurs.
 *
 * @return Returns 1 if the match has occurred and 0 otherwise.
 */
static inline int match_lt(char **s, char c, int inc, int supr)
{
	char *p = *s; /* Current line pointer. */
	int ret = 0;  /* Return code.          */

	if (*p < c)
		ret = 1;
	else
	{
		if (supr)
			error("expected '%c' < '%c'\n", c, *p);
	}
	if (inc == M_I)
		*s = p + 1;
	else if (inc == M_IC && ret)
		*s = p + 1;
	return (ret);
}

/**
 * @brief Checks if the (lowercase) character of the string pointed
 * by @p s is greater than the character @p c.
 *
 * @param s String to be checked.
 * @param c Character to be checked.
 *
 * @param inc Increment condition, if M_I, @p s will be increment
 * regardless the match result; if M_NI no increment will occur and
 * if M_IC, @p s will be increment if and only if the match occurs.
 *
 * @return Returns 1 if the match has occurred and 0 otherwise.
 */
static inline int match_gt(char **s, char c, int inc, int supr)
{
	char *p = *s; /* Current line pointer. */
	int ret = 0;  /* Return code.          */

	if (*p > c)
		ret = 1;
	else
	{
		if (supr)
			error("expected '%c' > '%c'\n", c, *p);
	}
	if (inc == M_I)
		*s = p + 1;
	else if (inc == M_IC && ret)
		*s = p + 1;
	return (ret);
}

/**
 * @brief Creates a string token based on @p token_start and @p
 * token_end.
 *
 * @param token Output token.
 * @param token_size Max token size.
 * @param token_start Pointer that marks the beginning of the
 * token.
 *
 * @param token_end Pointer that marks the end of the
 * token.
 *
 * @return If success, returns the token pointer, otherwise, NULL.
 */
static inline char* create_token(char *token, size_t token_size,
	char *token_start, char *token_end)
{
	uintptr_t diff; /* Bytes to copy. */
	uintptr_t st;   /* Token start.   */
	uintptr_t ed;   /* Token end.     */

	st = (uintptr_t)token_start;
	ed = (uintptr_t)token_end;

	if ( (diff = ed - st) > token_size)
	{
		error("token too much big\n");
		return (NULL);
	}
	strncpy(token, token_start, (size_t)diff);
	token[diff] = '\0';
	return (token);
}

/**
 * @brief Reads the next token, i.e: a label or instruction.
 *
 * @param line Line pointer.
 * @param token Output token.
 * @param token_size Max token size.
 *
 * @return Returns 1 if success and 0 otherwise.
 *
 * @note The parameter @p line will be updated to point
 * to the next valid character after the token.
 */
static inline int read_token(char **line, char *token,
	size_t token_size)
{
	char *p = *line; /* Current line pointer. */
	char *tokst;     /* Start token pointer.  */
	char *toked;     /* End token pointer.    */

	tokst = p;
	skip_validlabel(&p);
	toked = p;
	skip_whitespace(&p);
	*line = p;

	return (create_token(token, token_size, tokst, toked) != NULL &&
		strlen(token) != 0);
}

/**
 * @brief Reads a number (in octal, hexa or decimal) from the
 * specified line @p s.
 *
 * @param s Line pointer.
 * @param supr Suppress (M_S) or not (M_NS) error messages.
 *
 * @return Returns the read number or LONG_MAX if error.
 *
 * @note Returning LONG_MAX is not an issue here, because Tangle
 * do not supports numbers greater than 16-bit, so if a valid
 * is bigger than this, it will trigger an error anyway.
 *
 * The parameter @p s will be updated to point to the next valid
 * character after the number.
 */
static inline long read_number(char **s, int supr)
{
	char *nptr = NULL; /* Next char pointer.    */
	char *p = *s;      /* Current line pointer. */
	long number;       /* Number read.          */

	number = strtol(p, &nptr, 0);
	*s = nptr;

	if (p != nptr && errno == 0)
		return (number);
	if (supr)
		error("invalid number\n");

	return (LONG_MAX);
}

/**
 * @brief Converts an valid ASCII string to lowercase.
 *
 * @param s String to be converted.
 */
static inline void str_tolower(char *s)
{
	if (s == NULL)
		return;
	for (; *s; ++s)
		*s = tolower(*s);
}

/**
 * @brief Parses the @p line and sets the destination register
 * (or source) of the current @p insn instruction according to
 * the @p direction.
 *
 * @param direction If S_DIR_RD, sets the destination register,
 * and S_DIR_RS sets the source register.
 *
 * @param line Current line.
 * @param insn Current instruction.
 *
 * @return Returns S_MATCH if success, S_NOMATCH if the @p line
 * does not points to a register and S_ERROR if invalid register.
 *
 * @note The parameter @p line will be updated to point
 * to the next valid character after the register.
 */
static int set_reg(int direction, char **line, struct insn *insn)
{
	char *p = *line; /* Current line pointer. */

	if (match(&p, '%', M_IC, M_S))
	{
		if (match(&p, 'r', M_IC, M_NS))
		{
			if (match_lt(&p, '0', M_NI, M_S) || match_gt(&p, '7', M_I, M_S))
				return (S_ERROR);

			if (direction)
			{
				INSN_SET_RD(insn, *(p - 1) - '0');
			}

			/*
			 * MOVHI and MOVLO cannot have a register in the second
			 * operand, so we want to make sure that first.
			 */
			else if (INSN_GET_OPCODE(insn->insn) != OPC_MOVHI &&
				INSN_GET_OPCODE(insn->insn) != OPC_MOVLO)
			{
				INSN_SET_RS(insn, *(p - 1) - '0');
			}
			else
				return (S_ERROR);
		}
		else
			return (S_ERROR);
	}
	else
		return (S_NOMATCH);

	*line = p;
	return (S_MATCH);
}

/**
 * @brief Parses the @p line and sets the immediate value of the
 * current @p insn instruction accordingly to the type @p type
 * (if branch or AMI).
 *
 * @param type Indicates if the instruction is branch (S_TYPE_BRA)
 * or AMI (S_TYPE_AMI). This is needed because the immediate value
 * size is different for both kind of instructions: 5-bits for AMI
 * and 8-bits for branch.
 *
 * @param line Current line.
 * @param insn Current instruction.
 *
 * @return Returns S_MATCH if success, S_NOMATCH if the @p line
 * does not points to a number and S_ERROR if invalid number.
 *
 * @note The parameter @p line will be updated to point to the
 * next valid character after the immediate.
 */
static int set_imm(int type, char **line,
	struct insn_tbl *tbl, struct insn *insn)
{
	char *p = *line; /* Current line pointer. */
	long imm;        /* Immediate value.      */

	if (match(&p, '$', M_IC, M_S))
	{
		if (type == S_TYPE_BRA)
		{
			/*
			 * Single operand instructions only allows immediate values
			 * inside branches, so we need to ensure that first.
			 */
			if (tbl->type != INSN_BRA)
			{
				error("in single-operand instructions, immediate values are only\n"
					"allowed inside branches!\n");
				return (S_ERROR);
			}

			imm = read_number(&p, M_NS);

			/* Check if valid number and range. */
			if (imm == LONG_MAX || imm < MIN_IMM_BRA || imm > MAX_IMM_BRA)
			{
				error("invalid number or out-of-range (expects: %d -- %d)\n",
					MIN_IMM_BRA, MAX_IMM_BRA);
				return (S_ERROR);
			}

			/* Fill imm. */
			INSN_SET_IMM8(insn, imm);
		}

		else
		{
			imm = read_number(&p, M_NS);

			/* MOVHI and MOVLO exceptions. */
			if (INSN_GET_OPCODE(insn->insn) != OPC_MOVHI &&
				INSN_GET_OPCODE(insn->insn) != OPC_MOVLO)
			{
				/* Check if valid number and range. */
				if (imm == LONG_MAX || imm < MIN_IMM_AMI || imm > MAX_IMM_AMI)
				{
					error("invalid number or out-of-range (expects: %d -- %d)\n",
						MIN_IMM_AMI, MAX_IMM_AMI);
					return (S_ERROR);
				}

				/* Fill imm. */
				INSN_SET_IMM5(insn, imm);
			}

			else
			{
				/* Check if valid number and range. */
				if (imm == LONG_MAX || imm < MIN_LOHI_AMI || imm > MAX_LOHI_AMI)
				{
					error("invalid number or out-of-range (expects: %d -- %d)\n",
						MIN_LOHI_AMI, MAX_LOHI_AMI);
					return (S_ERROR);
				}

				/* Fill imm. */
				INSN_SET_IMM8(insn, imm);
			}
		}
	}
	else
		return (S_NOMATCH);

	*line = p;
	return (S_MATCH);
}

/**
 * @brief Parses the @p line and sets (or not*) the label of the
 * current @p insn instruction accordingly to the type @p type
 * (if branch or AMI).
 *
 * @param type Indicates if the instruction is branch (S_TYPE_BRA)
 * or AMI (S_TYPE_AMI). This is needed because the label for a
 * branch instruction is relative to the current PC, while for an
 * AMI instruction, the label is the absolute value. Besides that,
 * the sizes are different: 8-bits for branches and 5-bits for AMI
 * instructions.
 *
 * @param line Current line.
 * @param insn Current instruction.
 *
 * @return Returns 1 if success and 0 otherwise.
 *
 * @note The parameter @p line will be updated to point the next
 * valid character after the label.
 */
static int set_label(int type, char **line,
	struct insn_tbl *tbl, struct insn *insn)
{
	char tok[TOK_SZ + 1]; /* Label name.           */
	struct label *lbl;    /* Current label.        */
	char *p = *line;      /* Current line pointer. */
	long imm;             /* Immediate value.      */

	if (type == S_TYPE_BRA)
	{
		/*
		 * Single operand instructions only allows labels inside
		 * branches, so we need to ensure that first.
		 */
		if (tbl->type != INSN_BRA)
		{
			error("in single-operand instructions, labels are only\n"
				"allowed inside branches!\n");
			return (0);
		}

		/* Read label. */
		if (!read_token(&p, tok, TOK_SZ))
			return (0);

		/* Check if label exists. */
		if ((lbl = hashtable_get(&ht_lbls, tok)) != NULL)
		{
			imm = (long)(lbl->off - insn->pc);

			/* Check if out of bounds or not. */
			if (imm < MIN_IMM_BRA || imm > MAX_IMM_BRA)
			{
				error("label (%s) is too far from current pc (%d to %d insn)\n"
					"please consider using register-based branches\n",
					lbl->name, MIN_IMM_BRA, MAX_IMM_BRA);
				return (0);
			}

			/* Fill imm. */
			INSN_SET_IMM8(insn, imm);
		}

		/* If not exists, let us ''relocate''. */
		else
		{
			INSN_SET_IMM8(insn, 0);
			insn->lbl_name = strdup(tok);
			if (!insn->lbl_name)
				return (0);
		}
	}

	else
	{
		/* MOVHI and MOVLO do not handle labels at the moment. */
		if (INSN_GET_OPCODE(insn->insn) == OPC_MOVHI ||
			INSN_GET_OPCODE(insn->insn) == OPC_MOVLO)
		{
			return (0);
		}

		/* Read label. */
		if (!read_token(&p, tok, TOK_SZ))
			return (0);

		/* Check if label exists. */
		if ((lbl = hashtable_get(&ht_lbls, tok)) != NULL)
		{
			imm = (long)(lbl->off);

			/* Check if out of bounds or not. */
			if (imm < MIN_IMM_AMI || imm > MAX_IMM_AMI)
			{
				error("label (%s) is too big (%d) to fit in the register, \n"
					"valid range: %d to %d\n",
					tok, imm, MIN_IMM_AMI, MAX_IMM_AMI);
				return (0);
			}

			/* Fill imm. */
			INSN_SET_IMM5(insn, imm);
		}

		/* If not exists, let us ''relocate''. */
		else
		{
			INSN_SET_IMM5(insn, 0);
			insn->lbl_name = strdup(tok);
			if (!insn->lbl_name)
				return (0);
		}
	}

	*line = p;
	return (1);
}

/**
 * @brief Reads the first operand of the current instruction
 * and sets the destination register properly.
 *
 * @param line Current line.
 * @param tbl Instruction table entry.
 * @param insn Current instruction.
 *
 * @return Returns 1 if success and 0 otherwise.
 *
 * @note The parameter @p line will be updated to point
 * to the next valid character after the first operand.
 */
static int read_first_operand(char **line, struct insn_tbl *tbl,
	struct insn *insn)
{
	/* Reg Dest. */
	if (set_reg(S_DIR_RD, line, insn) != S_MATCH)
	{
		error("first operand of instruction '%s' is invalid!\n",
			tbl->name);
		return (0);
	}
	return (1);
}

/**
 * @brief Reads the second operand of the current instruction
 * and sets the destination register or the immediate value
 * properly.
 *
 * @param line Current line.
 * @param tbl Instructon table entry.
 * @param insn Current instruction.
 *
 * @return Returns 1 if success and 0 otherwise.
 *
 * @note The parameter @p line will be updated to point
 * to the next valid character after the register.
 *
 * Also note that the second operand can be: register,
 * immediate value and/or a label.
 */
static int read_second_operand(char **line, struct insn_tbl *tbl,
	struct insn *insn)
{
	int set; /* Return code. */

	if (!match(line, ',', M_I, M_NS))
		goto err;

	skip_whitespace(line);

	/* If Reg/Reg. */
	if ((set = set_reg(S_DIR_RS, line, insn)) != S_NOMATCH)
	{
		if (set == S_ERROR)
			goto err;
	}

	/* Reg/Imm. */
	else if ((set = set_imm(S_TYPE_IMM, line, tbl, insn)) != S_NOMATCH)
	{
		if (set == S_ERROR)
			goto err;
	}

	/* Reg/Label. */
	else if (!set_label(S_TYPE_IMM, line, tbl, insn))
		goto err;

	/* Check if ok. */
	skip_whitespace(line);

	if (!match(line, '#',  M_NI, M_S) && !match(line, ';',  M_IC,  M_S) &&
		!match(line, '\n', M_NI, M_S) && !match(line, '\0', M_NI, M_S))
	{
		goto err;
	}

	return (1);
err:
	error("second operand of instruction '%s' is invalid!\n",
		tbl->name);
	return (0);
}

/**
 * @brief Parses instructions that have three operands; at the
 * moment, only lw and sw fits in this category.
 *
 * @param line Current line.
 * @param tbl Instructon table entry.
 * @param insn Current instruction.
 *
 * @return Returns 1 if success and 0 otherwise.
 *
 * @note The parameter @p line will be updated to point
 * to the next valid character after the register.
 *
 * Note that sw/lw has a specific (and strict) format that
 * differs from instructions with one or two operands, and thus
 * the parser is slightly different from the first two.
 */
static int parse_three_params(char **line, struct insn_tbl *tbl,
	struct insn *insn)
{
	char *p = *line; /* Current line pointer. */

	/* Fill opcode. */
	INSN_SET_OPCODE(insn, tbl->opcode);
	insn->type = tbl->type;
	insn->pc = current_pc;

	/* Read operands. */
	if (!read_first_operand(&p, tbl, insn))
	{
		error("first operand needs to be a valid register!\n");
		goto err;
	}

	skip_whitespace(&p);

	if (!match(&p, ',', M_I, M_NS))
		goto err;

	skip_whitespace(&p);

	if (set_imm(S_TYPE_IMM, &p, tbl, insn) != S_MATCH)
	{
		error("second operand needs to be a valid number!\n");
		goto err;
	}

	skip_whitespace(&p);

	if (!match(&p, '(', M_I, M_NS))
		goto err;

	skip_whitespace(&p);

	if (set_reg(S_DIR_RS, &p, insn) != S_MATCH)
	{
		error("third operand needs to be a valid register!\n");
		goto err;
	}

	skip_whitespace(&p);

	if (!match(&p, ')', M_I, M_NS))
		goto err;

	/* Check if ok. */
	skip_whitespace(&p);

	if (!match(&p, '#',  M_NI, M_S) && !match(&p, ';',  M_IC,  M_S) &&
		!match(&p, '\n', M_NI, M_S) && !match(&p, '\0', M_NI, M_S))
	{
		goto err;
	}

	/* Update the pointer. */
	*line = p;
	return (1);
err:
	return (0);
}

/**
 * @brief Parses instructions that have two operands; at the
 * moment, only AMI instructions fall into this category.
 *
 * @param line Current line.
 * @param tbl Instructon table entry.
 * @param insn Current instruction.
 *
 * @return Returns 1 if success and 0 otherwise.
 *
 * @note The parameter @p line will be updated to point
 * to the next valid character after the register.
 */
static int parse_two_params(char **line, struct insn_tbl *tbl,
	struct insn *insn)
{
	char *p = *line; /* Current line pointer. */

	/* Fill opcode. */
	INSN_SET_OPCODE(insn, tbl->opcode);
	insn->type = tbl->type;
	insn->pc = current_pc;

	/* Read operands. */
	if (!read_first_operand(&p, tbl, insn))
		return (0);

	skip_whitespace(&p);

	if (!read_second_operand(&p, tbl, insn))
		return (0);

	/* Update the pointer. */
	*line = p;
	return (1);
}

/**
 * @brief Parses instructions that have one operand; at the
 * moment, AMI and branches instructions.
 *
 * @param line Current line.
 * @param tbl Instructon table entry.
 * @param insn Current instruction.
 *
 * @return Returns 1 if success and 0 otherwise.
 *
 * @note The parameter @p line will be updated to point
 * to the next valid character after the register.
 */
static int parse_one_param(char **line, struct insn_tbl *tbl,
	struct insn *insn)
{
	char *p = *line; /* Current line pointer. */
	int set;         /* Return code.          */

	/* Fill opcode. */
	INSN_SET_OPCODE(insn, tbl->opcode);
	insn->type = tbl->type;
	insn->pc = current_pc;

	/* If Reg/Reg. */
	if ((set = set_reg(S_DIR_RD, &p, insn)) != S_NOMATCH)
	{
		if (set == S_ERROR)
			goto err;
	}

	/* Reg/Imm. */
	else if ((set = set_imm(S_TYPE_BRA, &p, tbl, insn)) != S_NOMATCH)
	{
		if (set == S_ERROR)
			goto err;
	}

	/* Reg/Label. */
	else if (!set_label(S_TYPE_BRA, &p, tbl, insn))
		goto err;

	/* Check if ok. */
	skip_whitespace(&p);

	if (!match(&p, '#',  M_NI, M_S) && !match(&p, ';',  M_IC,  M_S) &&
		!match(&p, '\n', M_NI, M_S) && !match(&p, '\0', M_NI, M_S))
	{
		goto err;
	}

	/* Update the pointer. */
	*line = p;
	return (1);

err:
	error("error while parsing single operand\n");
	return (0);
}

/**
 * @brief Parses instructions that do not have any operands;
 * such as nop and halt (to be implemented).
 *
 * @param line Current line.
 * @param tbl Instructon table entry.
 * @param insn Current instruction.
 *
 * @return Returns 1 if success and 0 otherwise.
 *
 * @note The parameter @p line will be updated to point
 * to the next valid character after the register.
 */
static int parse_no_param(char **line, struct insn_tbl *tbl,
	struct insn *insn)
{
	((void)line);

	/* Fill opcode. */
	INSN_SET_OPCODE(insn, tbl->opcode);
	insn->type = tbl->type;
	insn->pc = current_pc;

	return (1);
}

/* Instruction table. */
static struct insn_tbl insn_tbl[] ={
	/* Logical. */
	{.name = "or",  .opcode = OPC_OR , .type = INSN_AMI, .parser = parse_two_params},
	{.name = "and", .opcode = OPC_AND, .type = INSN_AMI, .parser = parse_two_params},
	{.name = "xor", .opcode = OPC_XOR, .type = INSN_AMI, .parser = parse_two_params},
	{.name = "sll", .opcode = OPC_SLL, .type = INSN_AMI, .parser = parse_two_params},
	{.name = "slr", .opcode = OPC_SLR, .type = INSN_AMI, .parser = parse_two_params},
	{.name = "not", .opcode = OPC_NOT, .type = INSN_AMI, .parser = parse_one_param},
	{.name = "neg", .opcode = OPC_NEG, .type = INSN_AMI, .parser = parse_one_param},

	/* Arithmetic. */
	{.name = "add", .opcode = OPC_ADD, .type = INSN_AMI, .parser = parse_two_params},
	{.name = "sub", .opcode = OPC_SUB, .type = INSN_AMI, .parser = parse_two_params},
	{.name = "cmp", .opcode = OPC_CMP, .type = INSN_AMI, .parser = parse_two_params},

	/* Move. */
	{.name = "mov",   .opcode = OPC_MOV,   .type = INSN_AMI, .parser = parse_two_params},
	{.name = "movhi", .opcode = OPC_MOVHI, .type = INSN_AMI, .parser = parse_two_params},
	{.name = "movlo", .opcode = OPC_MOVLO, .type = INSN_AMI, .parser = parse_two_params},

	/* Branch. */
	{.name = "j",   .opcode = OPC_J,   .type = INSN_BRA, .parser = parse_one_param},
	{.name = "jne", .opcode = OPC_JNE, .type = INSN_BRA, .parser = parse_one_param},

	{.name = "jgs", .opcode = OPC_JGS, .type = INSN_BRA, .parser = parse_one_param},
	{.name = "jgu", .opcode = OPC_JGU, .type = INSN_BRA, .parser = parse_one_param},
	{.name = "jls", .opcode = OPC_JLS, .type = INSN_BRA, .parser = parse_one_param},
	{.name = "jlu", .opcode = OPC_JLU, .type = INSN_BRA, .parser = parse_one_param},

	{.name = "jges", .opcode = OPC_JGES, .type = INSN_BRA, .parser = parse_one_param},
	{.name = "jgeu", .opcode = OPC_JGEU, .type = INSN_BRA, .parser = parse_one_param},
	{.name = "jles", .opcode = OPC_JLES, .type = INSN_BRA, .parser = parse_one_param},
	{.name = "jleu", .opcode = OPC_JLEU, .type = INSN_BRA, .parser = parse_one_param},

	/* Memory. */
	{.name = "lw", .opcode = OPC_LW, .type = INSN_MEM, .parser = parse_three_params},
	{.name = "sw", .opcode = OPC_SW, .type = INSN_MEM, .parser = parse_three_params},

	/* Misc. */
	{.name = "nop", .opcode = OPC_NEG, .type = INSN_AMI, .parser = parse_no_param}
};

/* Instruction table hashtable. */
static struct hashtable *ht_insntbl;

/**
 * @brief Parses all the instructions from the current opened
 * file and creates a list of labels and instructions.
 *
 * @return Returns 1 if success and 0 otherwise.
 */
static int parse_insn(void)
{
	char tok[TOK_SZ + 1]; /* 'Token' read.            */
	struct insn_tbl *tbl; /* Instruction table entry. */
	struct insn *insn;    /* Allocated instruction.   */

	ssize_t read; /* Bytes read.        */
	size_t len;   /* Allocated size.    */
	char *line;   /* Current line.      */
	char *p;      /* Current character. */

	current_line = 1;
	line = NULL;
	len  = 0;

	/* Process each line. */
	while ((read = getline(&line, &len, asmf)) != -1)
	{
		p = line;

		while (*p && *p != '\n')
		{
			skip_whitespace(&p);

			/*
			 * If GNU AS directives or comment, ignore the remaining
			 * line.
			 */
			if (match(&p, '.', M_NI, M_S) || match(&p, '#', M_NI, M_S) ||
				match(&p, '\n', M_NI, M_S))
			{
				goto skip;
			}

			/* Read token. */
			if (!read_token(&p, tok, TOK_SZ))
				goto err0;

			/* Check if label or instruction. */
			if (match(&p, ':', M_NI, M_S))
			{
				if (!add_label(tok, current_pc))
					goto err0;
			}
			else
			{
				str_tolower(tok);
				if ((tbl = hashtable_get(&ht_insntbl, tok)) == NULL)
				{
					error("instruction (%s) not exist!\n", tok);
					goto err0;
				}

				/* Allocate and parse a isntruction. */
				insn = create_insn();
				if (!insn || !tbl->parser(&p, tbl, insn))
				{
					error("error while parsing (%s)\n", tok);
					goto err1;
				}

				/* Add instruction to the list. */
				if (array_add(&insn_out, insn) < 0)
				{
					error("error while adding processed instruction: %x\n",
						insn->insn);
					goto err1;
				}

				current_pc += (INSN_SIZE/BYTE_SIZE);
				continue;

			}
			p++;
		}
		skip: current_line++;
	}
	free(line);
	return (1);
err1:
	free(insn);
err0:
	free(line);
	return (0);
}

/**
 * @brief Resolves all the pending labels that are referenced
 * ahead of time.
 *
 * @return Returns 1 if all the labels are successfully
 * resolved and 0 otherwise.
 */
static int resolve_labels(void)
{
	struct insn *insn; /* Current instruction.   */
	struct label *lbl; /* Current label.         */
	size_t len;        /* Instruction list size. */
	long imm;          /* Immediate value.       */
	int ret;           /* Return code.           */

	ret = 1;
	len = array_size(&insn_out);

	for (size_t i = 0; i < len; i++)
	{
		insn = array_get(&insn_out, i, NULL);
		if (insn->lbl_name != NULL)
		{
			/* Check if we already have the label. */
			if ((lbl = hashtable_get(&ht_lbls, insn->lbl_name)) == NULL)
			{
				error("label (%s) not found!\n", insn->lbl_name);
				ret = 0;
				goto proceed;
			}

			/* Check if branch or AMI. */
			if (insn->type == INSN_BRA)
			{
				imm = (long)(lbl->off - insn->pc);

				/* Check if out of bounds or not. */
				if (imm < MIN_IMM_BRA || imm > MAX_IMM_BRA)
				{
					error("label (%s) is too far from current pc (%d to %d insn)\n"
						"please consider using register-based branches\n",
						lbl->name, MIN_IMM_BRA, MAX_IMM_BRA);
					ret = 0;
					goto proceed;
				}

				/* Fill imm. */
				INSN_SET_IMM8(insn, imm);
			}

			/* AMI. */
			else
			{
				imm = (long)(lbl->off);

				/* Check if out of bounds or not. */
				if (imm < MIN_IMM_AMI || imm > MAX_IMM_AMI)
				{
					error("label (%s) is too big (%d) to fit in the register, \n"
						"valid range: %d to %d\n",
						lbl->name, imm, MIN_IMM_AMI, MAX_IMM_AMI);
					ret = 0;
					goto proceed;
				}

				/* Fill imm. */
				INSN_SET_IMM5(insn, imm);
			}

			proceed:
				free(insn->lbl_name);
				insn->lbl_name = NULL;
		}
	}
	return (ret);
}

/**
 * @brief Parses the file @p file.
 *
 * @return Returns 1 if success and 0 otherwise.
 */
static int parse(char *file)
{
	if ((asmf = fopen(file, "r")) == NULL)
		return (0);

	/* Initialize instruction hashtable. */
	if (hashtable_init(&ht_insntbl, hashtable_sdbm_setup) < 0)
		return (0);
	for (size_t i = 0; i < sizeof(insn_tbl)/sizeof(struct insn_tbl); i++)
		if (hashtable_add(&ht_insntbl, insn_tbl[i].name, &insn_tbl[i]) < 0)
			return (0);

	/* Label hashtable. */
	if (hashtable_init(&ht_lbls, hashtable_sdbm_setup) < 0)
		return (0);

	/* Instruction list. */
	if (array_init(&insn_out) < 0)
		return (0);

	/* Parse. */
	src_file = basename(file);
	if (!parse_insn())
		return (0);
	if (!resolve_labels())
		return (0);

	return (1);
}

/**
 * Emits an output hex file with all the processed instructions
 * from the input file.
 *
 * @return Returns 1 if success and 0 otherwise.
 */
static int emit_hexfile(void)
{
	struct insn *insn; /* Current instruction.   */
	size_t il_size;    /* Instruction list size. */
	FILE *outf;        /* Output file.           */

	if ((outf = fopen(output_file, "w")) == NULL)
		return (0);

	fprintf(outf, "// %s file\n", input_file);

	il_size = array_size(&insn_out);
	for (size_t i = 0; i < il_size; i++)
	{
		insn = array_get(&insn_out, i, NULL);
		fprintf(outf, "%04x\n", insn->insn);
	}

	fclose(outf);
	return (1);
}

/**
 * @brief Frees all allocated resources used during the parsing.
 */
static void free_resources(void)
{
	struct label *l_v; /* Current label.         */
	struct insn *insn; /* Current isntruction.   */
	size_t size;       /* Instruction list size. */
	char *l_k;         /* Current key.           */

	((void)l_k);

	/* Close asm file. */
	if (asmf)
		fclose(asmf);

	/* Instruction hashtable. */
	hashtable_finish(&ht_insntbl, 0);

	/* Label hashtable. */
	if (ht_lbls)
	{
		HASHTABLE_FOREACH(ht_lbls, l_k, l_v,
		{
			free(l_v->name);
			free(l_v);
		});
		hashtable_finish(&ht_lbls, 0);
	}

	/* Instruction list. */
	size = array_size(&insn_out);
	for (size_t i = 0; i < size; i++)
	{
		insn = array_get(&insn_out, i, NULL);

		/* If has a label. */
		if (insn->lbl_name)
			free(insn->lbl_name);

		free(insn);
	}
	array_finish(&insn_out);
}

/**
 * Shows the usage.
 *
 * @param prgname Program name.
 */
static void usage(const char *prgname)
{
	fprintf(stderr, "Usage: %s [options] <input-file>\n", prgname);
	fprintf(stderr, "Options: \n");
	fprintf(stderr, "   -o <ouput-file>\n\n");
	fprintf(stderr, "If -o is omitted, 'ram.hex' will be used "
		"instead\n");
	exit(EXIT_FAILURE);
}

/**
 * Parse the command-line arguments.
 *
 * @param argc Argument count.
 * @param argv Argument list.
 *
 * @return Returns 1 if success or abort otherwise.
 */
static int parse_args(int argc, char **argv)
{
	int c; /* Current arg. */
	while ((c = getopt(argc, argv, "ho:")) != -1)
	{
		switch (c)
		{
			case 'h':
				usage(argv[0]);
				break;
			case 'o':
				output_file = optarg;
				break;
			default:
				usage(argv[0]);
				break;
		}
	}

	/* If not input file available. */
	if (optind >= argc)
	{
		fprintf(stderr, "Expected <input-file> after options!\n");
		usage(argv[0]);
	}

	if (!output_file)
		output_file = "ram.hex";

	/*
	 * For the moment, 'Tangle Assembler' will only read
	 * one input-file.
	 */
	input_file = argv[optind];
	return (1);
}

/**
 * Main
 */
int main(int argc, char **argv)
{
	/* Parse arguments. */
	parse_args(argc, argv);

	/* Parse file. */
	if (!parse(input_file))
		fprintf(stderr, "error while parsing %s\n", input_file);

	/* Emit .hex. */
	emit_hexfile();

	/* Free \o/. */
	free_resources();
}
