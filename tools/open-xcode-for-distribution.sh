#!/bin/sh
# Start Xcode with Apple's rsync selected for its local packaging subprocesses.
set -eu
xcode_app=${1:-/Applications/Xcode.app}
if [ ! -x "$xcode_app/Contents/MacOS/Xcode" ]; then
    printf 'Pass the installed Xcode application path as the first argument.\n' >&2
    exit 1
fi
if /usr/bin/pgrep -x Xcode >/dev/null 2>&1; then
    printf 'Save your work and quit Xcode first, then rerun this launcher.\n' >&2
    exit 2
fi
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Explicit --env is needed because LaunchServices may not inherit shell PATH.
/usr/bin/open --env "PATH=/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}" \
    -a "$xcode_app" "$project_root/ios/Vacuula.xcodeproj"
