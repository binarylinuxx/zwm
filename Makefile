OUT_BIN=zig-out/bin
ZWM_BIN=zwm
ZWMCTL_BIN=zwmctl
BIN_DIR=/usr/local/bin
CONFIG_LINK=./config.zig
CONFIG_SOURCE=./src/config.zig

build:
	@echo "Building zwm and zwmctl (debug mode)..."
	zig build
	@echo "Build complete: $(OUT_BIN)/$(ZWM_BIN) and $(OUT_BIN)/$(ZWMCTL_BIN)"

release:
	@echo "Building zwm and zwmctl (release mode - optimized, no stack traces)..."
	zig build -Doptimize=ReleaseFast
	@echo "Build complete: $(OUT_BIN)/$(ZWM_BIN) and $(OUT_BIN)/$(ZWMCTL_BIN)"

install:
	@echo "Installing zwm and zwmctl to $(BIN_DIR)..."
	@echo "Make sure 'make build' stage already passed."
	sudo cp $(OUT_BIN)/$(ZWM_BIN) $(BIN_DIR)/$(ZWM_BIN)
	sudo cp $(OUT_BIN)/$(ZWMCTL_BIN) $(BIN_DIR)/$(ZWMCTL_BIN)
	@echo "Installed $(BIN_DIR)/$(ZWM_BIN)"
	@echo "Installed $(BIN_DIR)/$(ZWMCTL_BIN)"
	@echo "Config will be automatically generated at \$$HOME/.config/zwm/zwm.kdl at first launch."

uninstall:
	@echo "Removing zwm and zwmctl from $(BIN_DIR)..."
	sudo rm -f $(BIN_DIR)/$(ZWM_BIN)
	sudo rm -f $(BIN_DIR)/$(ZWMCTL_BIN)
	@echo "Uninstalled zwm and zwmctl."

clean:
	@echo "Cleaning build artifacts..."
	rm -rf zig-out .zig-cache
	@if [ -L $(CONFIG_LINK) ]; then \
		rm $(CONFIG_LINK); \
		echo "Removed symbolic link."; \
	fi
	@echo "Clean complete."

test-zwmctl:
	@echo "Testing zwmctl commands..."
	@echo "---"
	@echo "Workspaces:"
	$(OUT_BIN)/$(ZWMCTL_BIN) --get-workspaces || echo "Note: zwm must be running"
	@echo "---"
	@echo "Clients:"
	$(OUT_BIN)/$(ZWMCTL_BIN) --clients || echo "Note: zwm must be running"
	@echo "---"
	@echo "Active window:"
	$(OUT_BIN)/$(ZWMCTL_BIN) --active-window || echo "Note: zwm must be running"

help:
	@echo "ZWM Makefile targets:"
	@echo "  build        - Build zwm compositor and zwmctl control tool (debug)"
	@echo "  release      - Build in release mode (optimized, no stack traces)"
	@echo "  install      - Install both binaries to $(BIN_DIR)"
	@echo "  uninstall    - Remove both binaries from $(BIN_DIR)"
	@echo "  clean        - Remove build artifacts"
	@echo "  test-zwmctl  - Test zwmctl commands (requires zwm to be running)"
	@echo "  help         - Show this help message"

.PHONY: build release install uninstall clean test-zwmctl help
