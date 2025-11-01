OUT_BIN=zig-out/bin
BIN_TARGET=zwm
BIN_DIR=/usr/local/bin
CONFIG_LINK=./config.zig
CONFIG_SOURCE=./src/config.zig

build:
	@echo "building zwm."
	zig build

install:
	@echo "installing zwm to path... make sure 'make build' stage already passed."
	sudo cp $(OUT_BIN)/$(BIN_TARGET) $(BIN_DIR)
	@echo "config will automatically generated at $HOME/.config/zwm/zwm.kdl at first launch."

clean:
	@echo "cleaning build artifacts."
	rm -rf zig-out
	@if [ -L $(CONFIG_LINK) ]; then \
		rm $(CONFIG_LINK); \
		echo "removed symbolic link."; \
	fi

.PHONY: build install clean
