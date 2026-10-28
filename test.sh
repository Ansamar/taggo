#!/bin/zsh
# Esegue i test. Con i soli Command Line Tools (senza Xcode) swift-testing
# va indicato a mano.
set -euo pipefail
cd "$(dirname "$0")"
DEV=/Library/Developer/CommandLineTools/Library/Developer
if [[ -d "$DEV/Frameworks/Testing.framework" ]]; then
    swift test -Xswiftc -F$DEV/Frameworks -Xlinker -F$DEV/Frameworks \
        -Xlinker -rpath -Xlinker $DEV/Frameworks -Xlinker -rpath -Xlinker $DEV/usr/lib "$@"
else
    swift test "$@"
fi
