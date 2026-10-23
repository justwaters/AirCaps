BINARY = aircaps
MENUBAR_TARGET = AirCapsApp
APP_NAME = AirCaps
MENUBAR_APP = $(APP_NAME).app
BUILD_DIR = .build
DMG_NAME = $(APP_NAME).dmg
DMG_STAGING = .dmg-staging

# Signing. The default is ad hoc ("-"), which works locally but is blocked by
# Gatekeeper on other Macs. `make dist` builds the release DMG: Developer ID
# signed (hardened runtime), notarized through Xcode's signed-in Apple ID and
# stapled, with no extra credentials to set up.
SIGN_IDENTITY ?= -
DEVELOPER_ID ?= Developer ID Application: Justin Waters (ZM89DBVX2V)
ifeq ($(SIGN_IDENTITY),-)
CODESIGN_FLAGS = --force --sign -
else
CODESIGN_FLAGS = --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)"
endif

.PHONY: all build clean install uninstall release bundle bundle-install bundle-uninstall dmg package dist

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
	mkdir -p $(MENUBAR_APP)/Contents/Resources
	cp Packaging/AppIcon.icns $(MENUBAR_APP)/Contents/Resources/AppIcon.icns
	cp Packaging/MenuIcons/*.pdf $(MENUBAR_APP)/Contents/Resources/
	codesign $(CODESIGN_FLAGS) $(MENUBAR_APP)

bundle-install: bundle
	rm -rf /Applications/$(MENUBAR_APP)
	cp -R $(MENUBAR_APP) /Applications/

bundle-uninstall:
	rm -rf /Applications/$(MENUBAR_APP)

# Packages the .app bundle into a distributable .dmg with a symlink to
# /Applications, for attaching to GitHub releases.
dmg: bundle package

# Packages the existing $(MENUBAR_APP) without rebuilding it.
package:
	rm -rf $(DMG_STAGING) $(DMG_NAME)
	mkdir -p $(DMG_STAGING)
	cp -R $(MENUBAR_APP) $(DMG_STAGING)/
	ln -s /Applications $(DMG_STAGING)/Applications
	hdiutil create -volname $(APP_NAME) -srcfolder $(DMG_STAGING) -ov -format UDZO $(DMG_NAME)
	rm -rf $(DMG_STAGING)
ifneq ($(SIGN_IDENTITY),-)
	codesign --force --timestamp --sign "$(SIGN_IDENTITY)" $(DMG_NAME)
endif

# Release build: signed + notarized + stapled app, packaged into a signed DMG.
dist:
	$(MAKE) bundle SIGN_IDENTITY="$(DEVELOPER_ID)"
	SIGN_IDENTITY="$(DEVELOPER_ID)" Packaging/notarize.sh $(MENUBAR_APP)
	$(MAKE) package SIGN_IDENTITY="$(DEVELOPER_ID)"
