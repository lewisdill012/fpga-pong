PROJ = blink
DEVICE = up5k
PACKAGE = sg48

all: $(PROJ).bin

$(PROJ).json: $(PROJ).v
	yosys -p "synth_ice40 -top top -json $(PROJ).json" $(PROJ).v

$(PROJ).asc: $(PROJ).json $(PROJ).pcf
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --json $(PROJ).json --pcf $(PROJ).pcf --asc $(PROJ).asc

$(PROJ).bin: $(PROJ).asc
	icepack $(PROJ).asc $(PROJ).bin

flash: $(PROJ).bin
	iceprog $(PROJ).bin

clean:
	rm -f $(PROJ).json $(PROJ).asc $(PROJ).bin