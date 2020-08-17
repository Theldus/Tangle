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

#
# Sipeed Tang Nano makefile
#

#
# Folders
#

#
# Gowin root folder
#
# Note: The Gowin EDA version that seems to work fine here
# (both IDE and Programmer) is v1.9.2 Beta, found in:
#    http://cdn.gowinsemi.com.cn/Gowin_V1.9.2Beta_linux.tar.gz
#
# later versions (until v1.9.6) do not work here.
#

#
# Please make sure that you're able to build/run simpler examples first,
# such as Blink for instance:
#    https://github.com/sipeed/Tang-Nano-examples
#

GOWINDIR ?= /usr/bin

#===================================================================
# Rules
#===================================================================

# Make TCL
$(BOARDDIR)/gowin_synthesis_pnr.tcl:
	@echo "Generating TCL script..."
	@bash $(BOARDDIR)/gen_tcl.sh

# Generate bitstream
$(BOARDDIR)/output/impl/pnr/Tangle.fs:
	build-board

#
# The Gowin Synthesizer seems to require the RAM full path, so
# we have to patch each time before using it.
#
patch_ram: $(RAMFILE)
	@echo "Patching RAM file... $(RAMFILE)"
	@sed -i 's|.*\$readmemh.*|\t\t$$readmemh("$(RAMFILE)", ram);|' \
		$(RTLDIR)/tangle_memory.v

# Synthesis, Place and Route
build-board: $(BOARDDIR)/gowin_synthesis_pnr.tcl patch_ram
	@echo "Synthesis and Place and Route started..."
	@$(GOWINDIR)/IDE/bin/gw_sh $(BOARDDIR)/gowin_synthesis_pnr.tcl

# Upload
upload-board: $(BOARDDIR)/output/impl/pnr/Tangle.fs
	@echo "Programming device on SRAM (this operation requires root)..."
	@sudo --preserve-env $(GOWINDIR)/Programmer/bin/programmer_cli \
		--device GW1N-1      \
		--operation_index 2  \
		--frequency 2.5MHz   \
		--fsFile $(BOARDDIR)/output/impl/pnr/Tangle.fs

# Clean
clean-board:
	@rm -rf $(BOARDDIR)/output
	@rm -rf $(BOARDDIR)/gowin_synthesis_pnr.tcl
