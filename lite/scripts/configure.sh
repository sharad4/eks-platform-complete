#!/usr/bin/env bash
# Fills the __TOKENS__ in lite/ with your GitHub org/repo.
# Run once, then commit and push.
# Example:
#   GITHUB_ORG=your-org GITHUB_REPO=your-repo bash lite/scripts/configure.sh
#
# GHCR requires lowercase image names, so lowercase variants are derived.
set -euo pipefail
cd "$(dirname "$0")/../.."

: "${GITHUB_ORG:?Missing GITHUB_ORG}"
: "${GITHUB_REPO:?Missing GITHUB_REPO}"
org_lc="$(printf '%s' "$GITHUB_ORG" | tr '[:upper:]' '[:lower:]')"
repo_lc="$(printf '%s' "$GITHUB_REPO" | tr '[:upper:]' '[:lower:]')"

grep -rl --include='*.yaml' -E '__GITHUB_(ORG|REPO)(_LC)?__' lite \
  | xargs -r sed -i \
      -e "s|__GITHUB_ORG_LC__|$org_lc|g" \
      -e "s|__GITHUB_REPO_LC__|$repo_lc|g" \
      -e "s|__GITHUB_ORG__|$GITHUB_ORG|g" \
      -e "s|__GITHUB_REPO__|$GITHUB_REPO|g"

if grep -rn --include='*.yaml' -E '__[A-Z_]+__' lite; then
  echo "WARNING: tokens above are still unset." >&2
else
  echo "Done. Review with 'git diff', commit and push (the cluster pulls from GitHub)."
fi
