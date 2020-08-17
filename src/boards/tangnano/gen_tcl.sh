# MIT License
#
# Copyright (c) 2020 Davidson Francis <davidsondfgl@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#!/usr/bin/env bash

#
# Folders
#
CURDIR="$( cd "$(dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
RTLDIR="$(readlink -f "$CURDIR"/../../rtl)"
CFGDIR="$(readlink -f "$CURDIR"/configs)"

# Initial file
{
	echo "set_option -out_dir $CURDIR/output"
	echo "set_option -prj_name Tangle"
	echo "set_option -synthesis_tool gowinsynthesis"
	echo "set_option -device GW1N-1-QFN48-6"
	echo "set_option -pn GW1N-LV1QN48C6/I5"
} > "$CURDIR"/gowin_synthesis_pnr.tcl

# Iterate over each file
files_list=("$RTLDIR"/*.v)
for file in "${files_list[@]}"
do
	echo "add_file -verilog $file" >> "$CURDIR"/gowin_synthesis_pnr.tcl
done

# Add remaining options
{
	echo "add_file -cst $CFGDIR/physical_constraints.cst"
	echo "add_file -sdc $CFGDIR/timing_constraints.sdc"
	echo "add_file -cfg $CFGDIR/device.cfg"
	echo "run_synthesis"
	echo "run_pnr -tt -timing"
} >> "$CURDIR"/gowin_synthesis_pnr.tcl
