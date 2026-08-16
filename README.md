# A la Kart

Native AppKit-only macOS menu-bar utility. Current features include:

- A port monitor backed by `/usr/sbin/lsof`, with SIGTERM and SIGKILL process actions.
- Configurable HTTP/HTTPS routing that opens matching domains in specific installed browsers.
- Versioned JSON configuration with full-config import and export.

URL interception works after A la Kart is selected as the default web browser. Configure routing, the fallback browser, domain rules, and default-handler status from **URL Routing Settings…** in the menu-bar menu. The live configuration is stored at `~/Library/Application Support/A la Kart/config.json`.

## Build and run

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Regenerate the checked-in project after changing `project.yml`:

```sh
/opt/homebrew/bin/xcodegen generate
xcodebuild -project A-la-Kart.xcodeproj -scheme A-la-Kart -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open "build/Build/Products/Debug/A la Kart.app"
```

Tests:

```sh
xcodebuild -project A-la-Kart.xcodeproj -scheme A-la-Kart -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

## Install locally as a browser candidate

LaunchServices is more reliable when A la Kart runs from a stable Applications location. The local installer builds the checked-in project, copies the unsigned app to `$HOME/Applications`, registers it, and launches it. It never changes the default browser:

```sh
./scripts/install-local.sh
```

After the script completes, close and reopen **System Settings**, open **Desktop & Dock → Default web browser**, and manually select **A la Kart** again (the bundle ID changed, so it is not selected automatically). Then configure the fallback browser and URL rules from **URL Routing Settings…**. The installed app must continue running from `$HOME/Applications/A la Kart.app` for LaunchServices to use that registration.
