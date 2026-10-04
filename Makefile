.PHONY: app run debug test clean

INSTALL_PATH = /Applications/Switchboard.app
LSREGISTER = /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

app:
	./scripts/build-app.sh release

# Rebuild, install to /Applications (Launch at Login expects a stable location), quit
# any running copy, and launch.
run: app
	-pkill -x Switchboard
	@while pgrep -x Switchboard >/dev/null; do sleep 0.2; done
	rm -rf "$(INSTALL_PATH)"
	cp -R build/Switchboard.app "$(INSTALL_PATH)"
	$(LSREGISTER) -f "$(INSTALL_PATH)"
	open "$(INSTALL_PATH)" || (sleep 1 && open "$(INSTALL_PATH)")

debug:
	./scripts/build-app.sh debug
	-pkill -x Switchboard
	open build/Switchboard.app

test:
	swift test

clean:
	rm -rf .build build
