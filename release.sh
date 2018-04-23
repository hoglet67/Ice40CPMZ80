#!/bin/bash

mkdir -p releases

release=releases/ice40cpmz80_$(date +"%Y%m%d_%H%M").zip

echo building ${release}

rm -rf build
mkdir -p build

for board in blackice blackice2
do

    echo building ${board}
    
    pushd ${board}
    ./clean.sh
    ./build.sh
    mv cpmz80.bin ../build/cpmz80_${board}.bin
    popd

    pushd target/blackice/iceboot
    make clean
    make raw
    cp output/iceboot.raw icebootcpmz80_${board}.raw
    truncate -s 126976 icebootcpmz80_${board}.raw
    cat ../../../build/cpmz80_${board}.bin >> icebootcpmz80_${board}.raw
    mv icebootcpmz80_${board}.raw ../../../build    
    popd

done

pushd build
zip -qr ../${release} .
popd

unzip -l ${release}

