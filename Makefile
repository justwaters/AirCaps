BINARY = airpodsctl
BUILD_DIR = .build

.PHONY: all build clean install uninstall release

all: build

build:
	swift build -c debug

release:
	swift build -c release

clean:
	swift package clean
	rm -rf $(BUILD_DIR)

install: release
	cp $(BUILD_DIR)/release/$(BINARY) /usr/local/bin/$(BINARY)

uninstall:
	rm -f /usr/local/bin/$(BINARY)
