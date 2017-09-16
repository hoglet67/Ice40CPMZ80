#!/bin/bash

SRCS="../src/Microcomputer/Microcomputer.v ../src/ROMS/ROM.v ../src/Components/SDCARD/sd_controller.v ../src/Components/UART/bufferedUART.v ../src/Components/Z80/tv80_core.v ../src/Components/Z80/tv80n.v ../src/Components/Z80/tv80_mcode.v ../src/Components/Z80/tv80_reg.v ../src/Components/Z80/tv80_alu.v"

iverilog ../src/cpmz80_tb.v $SRCS
./a.out  
gtkwave -g -a signals.gtkw dump.vcd
