OUT_BIN=zig-out/bin/
BIN_TARGET=zwm
BIN_DIR=/usr/local/bin

build:
	@echo "building zwm."
	zig build
	@echo "linking config."
	ln -sf ./src/config.zig ./config.zig

install:
	@echo "installing zwm to path... make sure 'make build' stage already passed."
	sudo cp $(OUT_BIN)/$(BIN_TARGET) $(BIN_DIR)
