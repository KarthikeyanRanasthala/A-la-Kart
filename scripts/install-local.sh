#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$repo_dir/.build-local"
built_app="$derived_data/Build/Products/Debug/kart-os.app"
applications_dir="$HOME/Applications"
install_path="$applications_dir/kart-os.app"
staging_path="$applications_dir/.kart-os.app.staging.$$"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

mkdir -p "$applications_dir"
xcodebuild -project "$repo_dir/kart-os.xcodeproj" -scheme kart-os -configuration Debug \
  -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO build

if [[ ! -d "$built_app" ]]; then
  echo "Build did not produce $built_app" >&2
  exit 1
fi

killall kart-os 2>/dev/null || true
rm -rf "$staging_path"
ditto "$built_app" "$staging_path"
rm -rf "$install_path"
mv "$staging_path" "$install_path"

"$lsregister" -f -R -trusted "$install_path"
open "$install_path"
echo "Installed and launched $install_path"
