#!/usr/bin/env bash
#
# Applies to the GitHub repository the settings that do not live in git: the
# labels the workflows and templates refer to, deletion of merged branches, and
# the rulesets in .github/rulesets/. Idempotent: run it again after changing
# any of them.
#
#   .github/scripts/setup-repo.sh [owner/repo]
#
# Needs gh, authenticated as an admin of the repository, and jq. Without an
# argument it targets the repository gh resolves from the current directory.
#
# Apply the rulesets only once main has every check they require: a required
# check no job reports blocks every pull request.

set -euo pipefail

repo="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
rulesets="$(dirname "$0")/../rulesets"

# Referenced by .github/labeler.yml, .github/dependabot.yml, the stale workflow
# and the issue templates. Labels missing from the list are left alone.
while IFS='|' read -r name color description; do
	gh label create "$name" --repo "$repo" --color "$color" --description "$description" --force
done <<'EOF'
area: image|1d76db|Dockerfile, build inputs, patches, rootfs
area: tests|0e8a16|Smoke tests
area: docs|0075ca|Documentation
area: ci/cd|5319e7|Workflows and release configuration
dependencies|0366d6|Dependency updates
github-actions|000000|GitHub Actions updates
bug|d73a4a|Something isn't working
enhancement|a2eeef|New feature or request
stale|cfd3d7|No recent activity
pinned|fbca04|Exempt from stale
security|b60205|Security related
EOF

gh repo edit "$repo" --delete-branch-on-merge

# Matched by name: an existing ruleset is replaced, a missing one is created.
# Rulesets inherited from the organization are not listed, so never touched.
for file in "$rulesets"/*.json; do
	name="$(jq -r .name "$file")"
	id="$(gh api --paginate "repos/${repo}/rulesets?includes_parents=false" |
		jq -r --arg name "$name" '.[] | select(.name == $name) | .id')"
	if [ -n "$id" ]; then
		gh api --method PUT "repos/${repo}/rulesets/${id}" --input "$file" >/dev/null
		echo "ruleset updated: ${name}"
	else
		gh api --method POST "repos/${repo}/rulesets" --input "$file" >/dev/null
		echo "ruleset created: ${name}"
	fi
done
