OUT_BIN=zig-out/bin
BIN_TARGET=zwm
BIN_DIR=/usr/local/bin
CONFIG_LINK=./config.zig
CONFIG_SOURCE=./src/config.zig

build:
	@echo "building zwm."
	zig build
	@echo "linking config."
	@if [ -L $(CONFIG_LINK) ]; then \
		echo "symbolic link already exists.. skipping linking."; \
	elif [ -e $(CONFIG_LINK) ]; then \
		echo "warning: $(CONFIG_LINK) exists but is not a symbolic link!"; \
		echo "please remove it manually or backup before proceeding."; \
		exit 1; \
	else \
		ln -sf $(CONFIG_SOURCE) $(CONFIG_LINK); \
		echo "symbolic link created."; \
	fi

install:
	@echo "installing zwm to path... make sure 'make build' stage already passed."
	sudo cp $(OUT_BIN)/$(BIN_TARGET) $(BIN_DIR)

clean:
	@echo "cleaning build artifacts."
	rm -rf zig-out
	@if [ -L $(CONFIG_LINK) ]; then \
		rm $(CONFIG_LINK); \
		echo "removed symbolic link."; \
	fi

.PHONY: build install clean
