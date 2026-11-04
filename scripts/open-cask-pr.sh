#!/bin/bash
# Propose le cask dans une PR pour respecter la protection de stable.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 2 ]] || { echo 'Usage : scripts/open-cask-pr.sh <version> <dmg>' >&2; exit 1; }
version=$1
python3 scripts/release-version.py "$version"
[[ $(git branch --show-current) == stable && -z $(git status --porcelain) ]] || {
  echo 'Une copie propre de stable est nécessaire.' >&2
  exit 1
}
python3 scripts/update-cask.py "$version" "$2"
scripts/check-cask.sh
if git diff --quiet -- Casks/whoa-stash.rb; then
  echo 'Le cask est déjà à jour, aucune PR nécessaire.'
  exit 0
fi
branch="codex/cask-v$version"
expected=$(git ls-remote --heads origin "refs/heads/$branch" | awk '{print $1}')
git switch -c "$branch"
git add -- Casks/whoa-stash.rb
git commit -m "chore(cask): update whoa-stash to $version"
# Seule la branche dédiée au bot peut être remplacée ; stable passe par une PR.
git push --force-with-lease="refs/heads/$branch:$expected" origin "HEAD:refs/heads/$branch"
pr_url=$(gh pr list --state open --base stable --head "$branch" --json url --jq '.[0].url // empty')
if [[ -z $pr_url ]]; then
  body=$(mktemp)
  trap 'rm -f "$body"' EXIT
  printf 'Updates the Homebrew cask to the published v%s DMG and its SHA-256.\n\nValidation: brew audit --cask --strict and brew style passed.\n\nMerge after the required Build and test check and approving review.\n' "$version" > "$body"
  gh pr create --base stable --head "$branch" \
    --title "chore(cask): update whoa-stash to $version" --body-file "$body"
else
  echo "PR mise à jour : $pr_url"
fi
