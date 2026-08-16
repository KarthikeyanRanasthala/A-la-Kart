# A la Kart

A native, AppKit-only macOS menu-bar utility for inspecting local ports and routing web URLs to the right browser.

## Ports

- Inspect listening TCP ports using `/usr/sbin/lsof`.
- View details about the process holding a port.
- Send SIGTERM or SIGKILL to a process, with confirmation before the action.

## URL Routing

- Route HTTP and HTTPS URLs by hostname or subdomain to installed browsers.
- Set a fallback browser for URLs that do not match a rule.
- Enable, disable, and reorder routing rules.
- Import and export the complete configuration as JSON.
- View default-handler status and open the relevant macOS settings.

URL routing works after A la Kart is selected manually as the default web browser. Configure the fallback browser and rules from **URL Routing Settings…** in the menu-bar menu.

## Requirements

- macOS 13 or later
- Apple Silicon Mac (the current Release build is arm64-only)
- Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Product/bundle ID: `sh.karthikeyan.a-la-kart`

## Quick start from source

From the repository root, generate the Xcode project and run the local installer:

```sh
xcodegen generate
./scripts/install-local.sh
```

The installer builds Release, installs `A la Kart.app` to `~/Applications/A la Kart.app`, registers it with LaunchServices, and launches it. It does not change your default browser.

To enable URL interception, open **System Settings → Desktop & Dock → Default web browser** and select **A la Kart**. You may need to close and reopen System Settings before it appears. Then choose a fallback browser and configure rules in **URL Routing Settings…**. Keep the installed app running from `~/Applications/A la Kart.app` so LaunchServices continues to use that registration.

## Unsigned local build

The local installer produces an unsigned, unnotarized app. Because you compiled it locally, macOS may still ask for confirmation the first time it opens. If Gatekeeper blocks it, use Finder’s **Open** command on the app (or the option provided in **System Settings → Privacy & Security**) to approve this specific app. Do not disable Gatekeeper globally.

## Configuration

The live configuration is stored locally at:

```text
~/Library/Application Support/A la Kart/config.json
```

Use the import and export controls in URL Routing Settings to move or back up the full JSON configuration.

## Development

The primary build is Release:

```sh
xcodebuild -project A-la-Kart.xcodeproj -scheme A-la-Kart \
  -configuration Release -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
open "build/Build/Products/Release/A la Kart.app"
```

Tests use Debug:

```sh
xcodebuild -project A-la-Kart.xcodeproj -scheme A-la-Kart \
  -configuration Debug -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO test
```

Regenerate `A-la-Kart.xcodeproj` with `xcodegen generate` after changing `project.yml`.

## Privacy and security

A la Kart keeps its configuration on the local Mac and has no telemetry or network backend. When routing a URL, it naturally asks the selected browser to open that URL; the browser’s own handling and network activity still apply.

## Project status and support

A la Kart is currently a macOS-only, native AppKit project. It does not support Intel Macs in its current Release build. The app is distributed here as source for local compilation and installation; packaged, signed releases are not currently provided.
