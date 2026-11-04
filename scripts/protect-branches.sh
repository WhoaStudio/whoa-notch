#!/usr/bin/env bash
# Protège `main` et `stable` sur GitHub avec deux rulesets (API Rulesets, via `gh api`).
#
#   1. « Protect main and stable: history » — aucune exception :
#        pas de suppression, pas de force-push.
#   2. « Protect stable » — PR obligatoire, 1 approbation, check CI « Build and test » vert.
#        Exception : les admins du dépôt (`always`), pour que scripts/release.sh puisse
#        pousser le commit de version directement sur `stable`.
#
# GitHub Actions ne peut pas figurer dans les exceptions de ce dépôt (HTTP 422) : le push
# du cask par .github/workflows/release.yml reste bloqué par le ruleset 2.
#
# Les rulesets s'appliquent aussi à `main` tant qu'elle n'existe pas.
# Relancer le script met les rulesets à jour (repérés par leur nom).
#
# Usage : scripts/protect-branches.sh [owner/repo]   (défaut : WhoaStudio/whoa-stash)
# Requiert : gh authentifié avec un compte admin du dépôt.
set -euo pipefail

REPO="${1:-WhoaStudio/whoa-stash}"
CI_CHECK="Build and test"     # `name:` du job dans .github/workflows/ci.yml
ACTIONS_APP_ID=15368          # application GitHub Actions, qui publie le check CI
ADMIN_ROLE_ID=5               # rôle de dépôt « admin »

# Crée le ruleset nommé $1 avec le JSON de l'entrée standard, ou le remplace s'il existe.
upsert_ruleset() {
  local name="$1" body id
  body="$(cat)"
  id="$(gh api "repos/$REPO/rulesets" --paginate \
    --jq ".[] | select(.name == \"$name\") | .id" | head -n 1)"
  if [[ -n "$id" ]]; then
    echo "Mise à jour du ruleset « $name » (#$id)"
    gh api --method PUT "repos/$REPO/rulesets/$id" --input - <<<"$body" >/dev/null
  else
    echo "Création du ruleset « $name »"
    gh api --method POST "repos/$REPO/rulesets" --input - <<<"$body" >/dev/null
  fi
}

upsert_ruleset "Protect main and stable: history" <<JSON
{
  "name": "Protect main and stable: history",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main", "refs/heads/stable"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" }
  ]
}
JSON

upsert_ruleset "Protect stable" <<JSON
{
  "name": "Protect stable",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH", "refs/heads/main"], "exclude": [] } },
  "bypass_actors": [
    { "actor_id": $ADMIN_ROLE_ID, "actor_type": "RepositoryRole", "bypass_mode": "always" }
  ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "allowed_merge_methods": ["merge", "squash", "rebase"],
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "do_not_enforce_on_create": false,
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "$CI_CHECK", "integration_id": $ACTIONS_APP_ID }
        ]
      }
    }
  ]
}
JSON

echo "Rulesets actifs :"
gh api "repos/$REPO/rulesets" --jq '.[] | "  #\(.id) \(.name) (\(.enforcement))"'
