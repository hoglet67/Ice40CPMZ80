#!/bin/bash

TOP=Microcomputer
NAME=cpmz80
PACKAGE=tq144:4k
SRCS="../src/bootstrap.v ../src/Microcomputer/Microcomputer.v ../src/ROMS/ROM.v ../src/Components/SDCARD/sd_controller.v ../src/Components/UART/bufferedUART.v ../src/Components/Z80/tv80_core.v ../src/Components/Z80/tv80n.v ../src/Components/Z80/tv80_mcode.v ../src/Components/Z80/tv80_reg.v ../src/Components/Z80/tv80_alu.v ../src/Components/TERMINAL/DisplayRam.v ../src/Components/TERMINAL/SBCTextDisplayRGB.v "

./clean.sh

yosys -q -f "verilog -Duse_sb_io" -l ${NAME}.log -p "synth_ice40 -top ${TOP} -abc2 -blif ${NAME}.blif" ${SRCS}
arachne-pnr -d 8k -P ${PACKAGE} -p blackice.pcf ${NAME}.blif -o ${NAME}.txt
icepack ${NAME}.txt ${NAME}.bin
icetime -d hx8k -P ${PACKAGE} -t ${NAME}.txt
truncate -s 135104 ${NAME}.bin
