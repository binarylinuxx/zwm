OUT_BIN=zig-out/bin/
BIN_TARGET=zwm
BIN_DIR=/usr/local/bin

build:
	zig build

install: build
	cp $(OUT_BIN)/$(BIN_TARGET) $(BIN_DIR)
