# Config
DESIGN_NAME = ICE40_Computer
PINOUT = config/pinout.pcf
NEXTPNR_ARGS = --up5k --package sg48 --freq 25.175
PICO_SDK_PATH ?= /home/ryzerth/pico-sdk

# Tools
YOSYS = yosys
NEXTPNR = nextpnr-ice40
ICEPACK = icepack

all: build/$(DESIGN_NAME).uf2

.PHONY: build/$(DESIGN_NAME).uf2
build/$(DESIGN_NAME).uf2: build/bitstream.h  build/bitstream_loader/Makefile
	cd build/bitstream_loader && make && cp bitstream_loader.uf2 ../$(DESIGN_NAME).uf2

build/bitstream_loader/Makefile: bitstream_loader/CMakeLists.txt
	echo $(PICO_SDK_PATH) && mkdir -p build/bitstream_loader/ && cd build/bitstream_loader/ && cmake ../../bitstream_loader -DPICO_SDK_PATH=$(PICO_SDK_PATH)

build/bitstream.h: build/$(DESIGN_NAME).bin
	xxd -i $< > $@

build/$(DESIGN_NAME).bin: build/$(DESIGN_NAME).asc
	$(ICEPACK) $< $@

build/$(DESIGN_NAME).asc: build/$(DESIGN_NAME).json $(PINOUT)
	$(NEXTPNR) $(NEXTPNR_ARGS) --json $< --pcf $(PINOUT) --asc $@

build/$(DESIGN_NAME).json: src/$(DESIGN_NAME).vhd src/ICE40_VGA.vhd src/ICE40_VRAM.vhd src/ICE40_CPU.vhd src/ICE40_CRAM.vhd
	$(YOSYS) -m ghdl -p "ghdl -fsynopsys -fexplicit $^ -e $(DESIGN_NAME); read_verilog src/ice40_blocks/pll.v src/ice40_blocks/bram.v; synth_ice40 -json $@"

clean:
	rm -rf build/*