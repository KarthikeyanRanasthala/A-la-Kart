# kart-os

Native AppKit-only macOS menu-bar port monitor. It runs `/usr/sbin/lsof` without DNS/service-name resolution, showing TCP LISTEN and bound UDP sockets. Each process submenu offers SIGTERM and SIGKILL (with confirmation enabled by default), while protected/current processes remain visible but cannot be signaled.

## Build and run

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Regenerate the checked-in project after changing `project.yml`:

```sh
/opt/homebrew/bin/xcodegen generate
xcodebuild -project kart-os.xcodeproj -scheme kart-os -configuration Debug CODE_SIGNING_ALLOWED=NO build
open build/Debug/kart-os.app
```

Tests:

```sh
xcodebuild -project kart-os.xcodeproj -scheme kart-os -configuration Debug CODE_SIGNING_ALLOWED=NO test
```
