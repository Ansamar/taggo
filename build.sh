#!/bin/zsh
# Build di sviluppo: compila per questo Mac (TagLib di Homebrew) e crea Taggo.app qui.
# Per la versione da distribuire usa scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
scripts/make-app.sh "$(swift build -c release --show-bin-path)/Taggo" Taggo.app "$(cat VERSION)-dev"
codesign --force --sign - Taggo.app
echo "Creato $(pwd)/Taggo.app"
