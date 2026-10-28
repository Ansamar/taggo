#!/bin/zsh
# Ricrea la release, la carica su GitHub (Ansamar/taggo) e pubblica la Release vVERSION.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
NOTES="docs/release-notes-$VERSION.md"
[[ -f "$NOTES" ]] || { echo "Mancano le note: $NOTES" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Ci sono modifiche non committate" >&2; exit 1; }

scripts/release.sh

if ! gh repo view Ansamar/taggo >/dev/null 2>&1; then
    gh repo create Ansamar/taggo --public --source . --remote origin \
        --description "Editor di tag audio per macOS (SwiftUI + TagLib)"
fi
git push -u origin main
git tag -a "v$VERSION" -m "Taggo $VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" --repo Ansamar/taggo --title "Taggo $VERSION" --notes-file "$NOTES" \
    "dist/Taggo-$VERSION.dmg" "dist/Taggo-$VERSION.zip" dist/SHA256SUMS.txt
