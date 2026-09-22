APP_NAME  := which-account
BUNDLE_ID := dev.wine-fall.which-account
PREFIX    ?= $(HOME)/Applications
APP       := $(PREFIX)/$(APP_NAME).app
BIN       := .build/release/$(APP_NAME)
EXEC      := $(APP)/Contents/MacOS/$(APP_NAME)
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
CONFIG_DIR := $(if $(XDG_CONFIG_HOME),$(XDG_CONFIG_HOME),$(HOME)/.config)/$(APP_NAME)

.PHONY: help build release test lint install uninstall purge clean

help:
	@echo "which-account"
	@echo
	@echo "  make build      debug build"
	@echo "  make test       run the unit tests"
	@echo "  make release    optimised build at $(BIN)"
	@echo "  make install    build, assemble $(APP), and ask macOS to make it your"
	@echo "                  default browser (macOS shows its own confirmation)"
	@echo "  make uninstall  hand the default browser back and remove the app;"
	@echo "                  your config is kept"
	@echo "  make purge      uninstall, and delete $(CONFIG_DIR) too"
	@echo
	@echo "Try it without installing anything:"
	@echo "  $(BIN) --dry-run https://linear.app/x"
	@echo "  $(BIN) --show-picker https://linear.app/x"

build:
	swift build

release:
	swift build -c release

test:
	swift test

lint:
	plutil -lint Resources/Info.plist

# Assemble the .app by hand. A locally compiled binary carries no quarantine
# flag, so it needs no signing and no developer account.
$(APP): release Resources/Info.plist
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$(BIN)" "$(EXEC)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	@echo "assembled $(APP)"

install: $(APP)
	@echo "==> telling LaunchServices about the app"
	"$(LSREGISTER)" -f "$(APP)"
	@echo "==> recording your current browser, then asking to take over http/https"
	@echo "    macOS will show its own confirmation dialog; nothing changes until you accept."
	"$(EXEC)" --setup

uninstall:
	@if [ -x "$(EXEC)" ]; then \
		echo "==> handing the default browser back to the one in your config"; \
		"$(EXEC)" --restore || true; \
	else \
		echo "==> $(APP) is not installed; nothing to hand back"; \
	fi
	-"$(LSREGISTER)" -u "$(APP)" 2>/dev/null || true
	rm -rf "$(APP)"
	@echo "==> removed $(APP). Your config is still at $(CONFIG_DIR)"
	@echo "    run 'make purge' to delete that too."

purge: uninstall
	rm -rf "$(CONFIG_DIR)"
	@echo "==> removed $(CONFIG_DIR)"

clean:
	rm -rf .build
