#!/bin/bash

SRCS="../src/ROMS/ROM.v ../src/Components/TERMINAL/DisplayRam.v ../src/Components/TERMINAL/SBCTextDisplayRGB.v "

iverilog ../src/Test/terminal_tb.v $SRCS
./a.out  
gtkwave -g -a signals_terminal.gtkw dump.vcd
