BINARY = aircaps
MENUBAR_TARGET = AirCapsApp
APP_NAME = AirCaps
MENUBAR_APP = $(APP_NAME).app
BUILD_DIR = .build

.PHONY: all build clean install uninstall release bundle bundle-install bundle-uninstall

all: build

build:
	swift build -c debug

release:
	swift build -c release

clean:
	swift package clean
	rm -rf $(BUILD_DIR)
	rm -rf $(MENUBAR_APP)

install: release
	cp $(BUILD_DIR)/release/$(BINARY) /usr/local/bin/$(BINARY)

uninstall:
	rm -f /usr/local/bin/$(BINARY)

# Wraps the menu-bar app in a minimal .app bundle (needed for LSUIElement to
# reliably hide the Dock icon, and for a stable bundle identity that TCC and
# SMAppService login-item registration can key off). Ad-hoc signed — no
# Developer ID required for personal/local use.
bundle: release
	rm -rf $(MENUBAR_APP)
	mkdir -p $(MENUBAR_APP)/Contents/MacOS
	cp $(BUILD_DIR)/release/$(MENUBAR_TARGET) $(MENUBAR_APP)/Contents/MacOS/$(APP_NAME)
	cp Packaging/Info.plist $(MENUBAR_APP)/Contents/Info.plist
	codesign --force --sign - $(MENUBAR_APP)

bundle-install: bundle
	rm -rf /Applications/$(MENUBAR_APP)
	cp -R $(MENUBAR_APP) /Applications/

bundle-uninstall:
	rm -rf /Applications/$(MENUBAR_APP)
