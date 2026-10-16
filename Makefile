PAK_DIR := Restart ADB.pak
DEVICE_TOOLS ?= /mnt/SDCARD/Tools/h700
# Override with SHELLCHECK=shellcheck to use a local install.
SHELLCHECK ?= podman run --rm -v "$(CURDIR):/mnt:Z" docker.io/koalaman/shellcheck:stable

MINUI_PRESENTER_VERSION := 0.13.4
MINUI_PRESENTER_URL := https://github.com/josegonzalez/minui-presenter

.PHONY: lint test bin zip push clean

lint:
	$(SHELLCHECK) -s sh "$(PAK_DIR)/launch.sh"

# Run launch.sh under the shells H700 base OSes use: dash and BusyBox ash.
test:
	podman run --rm -v "$(CURDIR):/repo:ro,Z" docker.io/library/debian:stable-slim sh /repo/tests/harness.sh dash
	podman run --rm -v "$(CURDIR):/repo:ro,Z" docker.io/library/busybox:stable sh /repo/tests/harness.sh ash

# PAK_DIR has a space in it, so this checks for the file itself rather than
# using it as a make target. `make clean bin` re-fetches.
bin:
	mkdir -p "$(PAK_DIR)/bin"
	[ -f "$(PAK_DIR)/bin/minui-presenter" ] || curl -fsSL -o "$(PAK_DIR)/bin/minui-presenter" \
		"$(MINUI_PRESENTER_URL)/releases/download/$(MINUI_PRESENTER_VERSION)/minui-presenter-h700-nextui"
	[ -f "$(PAK_DIR)/bin/minui-presenter.LICENSE" ] || curl -fsSL -o "$(PAK_DIR)/bin/minui-presenter.LICENSE" \
		"https://raw.githubusercontent.com/josegonzalez/minui-presenter/$(MINUI_PRESENTER_VERSION)/LICENSE"
	chmod +x "$(PAK_DIR)/bin/minui-presenter"

# Same layout as other NextUI pak releases: pak contents at the zip root, plus pak.json.
zip: bin
	mkdir -p dist
	rm -f "dist/$(PAK_DIR).zip"
	chmod +x "$(PAK_DIR)/launch.sh"
	cd "$(PAK_DIR)" && zip -r "$(CURDIR)/dist/$(PAK_DIR).zip" .
	zip "dist/$(PAK_DIR).zip" pak.json

# Only works while adbd is alive, which is rather the point of this pak.
push: bin
	adb push "$(PAK_DIR)" "$(DEVICE_TOOLS)/"

clean:
	rm -rf dist "$(PAK_DIR)/bin"
