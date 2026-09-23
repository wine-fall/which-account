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

# Assemble the .app by hand. A locally compiled binary carries no quarantine flag,
# so no Apple developer account or notarization is involved — but the bundle still
# has to be ad-hoc signed. The linker's own signature covers only the executable and
# names it after the binary, which leaves the bundle failing validation
# ("code has no resources but signature indicates they must be present"), and
# LaunchServices will not make an invalidly signed app the default browser.
$(APP): release Resources/Info.plist
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$(BIN)" "$(EXEC)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign - --identifier $(BUNDLE_ID) "$(APP)"
	codesign --verify --strict "$(APP)"
	@echo "assembled and signed $(APP)"

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
