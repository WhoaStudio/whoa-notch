#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "Erreur : $*" >&2; exit 1; }
[[ $# == 1 ]] || fail 'Usage : scripts/release.sh <version>'
version=$1
python3 scripts/release-version.py "$version"
tag="v$version"
[[ $(git branch --show-current) == stable ]] || fail 'La branche courante doit être stable.'
[[ -z $(git status --porcelain) ]] || fail 'Le répertoire de travail doit être propre (working tree is dirty).'
if git show-ref --verify --quiet "refs/tags/$tag"; then
  fail "Le tag $tag existe déjà."
fi
git fetch origin stable --tags
if git show-ref --verify --quiet "refs/tags/$tag"; then
  fail "Le tag $tag existe déjà."
fi
[[ $(git rev-parse HEAD) == "$(git rev-parse refs/remotes/origin/stable)" ]] || fail 'stable doit être à jour avec origin/stable (ni en avance ni en retard).'
[[ -z $(git ls-remote --tags origin "refs/tags/$tag") ]] || fail "Le tag distant $tag existe déjà."
python3 scripts/release-version.py "$version" whoa-notch.xcodeproj/project.pbxproj
git add -- whoa-notch.xcodeproj/project.pbxproj
# Autorise la première version même si les métadonnées portent déjà cette version.
git commit --allow-empty -m "chore(release): $tag"
tag_message=$tag
if [[ ${RELEASE_CI:-0} == 1 && -n ${GITHUB_RUN_ID:-} ]]; then
  tag_message+=$'\n\n'"GitHub Actions run: $GITHUB_RUN_ID"
fi
git tag -a "$tag" -m "$tag_message"
git push --atomic origin HEAD:refs/heads/stable "refs/tags/$tag"
url="$(git remote get-url origin)"
url=${url%.git}
url=${url/git@github.com:/https:\/\/github.com/}
echo "Actions : $url/actions/workflows/release.yml"
if command -v gh >/dev/null && [[ ${RELEASE_CI:-0} != 1 ]]; then
  sha=$(git rev-parse HEAD)
  for ((attempt=0; attempt<12; attempt++)); do
    run_url=$(gh run list --workflow release.yml --event push --commit "$sha" --json url --jq '.[0].url // empty' 2>/dev/null || true)
    if [[ -n $run_url ]]; then
      echo "Actions : $run_url"
      gh run watch "${run_url##*/}" --exit-status
      exit $?
    fi
    sleep 5
  done
  echo "Le run n'est pas encore visible ; utilisez le lien Actions ci-dessus."
fi
