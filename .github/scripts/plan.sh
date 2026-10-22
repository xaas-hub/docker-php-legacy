#!/usr/bin/env bash
#
# Plan job of ci.yml: decides which images to build, from which git ref, and
# whether to publish them. Writes the job outputs to $GITHUB_OUTPUT.
#
# - INPUT_VERSION set (release.yml, or a manual run): publish that release.
# - schedule / manual run without a version: republish the latest release,
#   never unreleased commits of main. The daily schedule, and a manual run
#   without force, skip the images whose Debian base image did not move.
# - push / pull_request: build and test only.
#
# Rolling tags (7.4-fpm, 7.4.33-fpm) only follow the latest release: a manual
# republish of an older one refreshes its -vX.Y.Z tags and nothing else.

set -euo pipefail

: "${EVENT:?}" "${DEBIAN_CODENAME:?}" "${DOCKERHUB_IMAGE:?}" "${DAILY_CRON:?}"

latest="$(git tag --list 'v*' --sort=-v:refname | head -n1)"

publish=false
rolling=false
check_base=false
ref="${GITHUB_SHA}"
version=""

if [ -n "${INPUT_VERSION:-}" ]; then
	version="${INPUT_VERSION#v}"
	ref="v${version}"
	git rev-parse -q --verify "refs/tags/${ref}" >/dev/null || {
		echo "::error::tag ${ref} not found"
		exit 1
	}
	publish=true
	if [ "$ref" = "$latest" ]; then
		rolling=true
	fi
elif [ "$EVENT" = schedule ] || [ "$EVENT" = workflow_dispatch ]; then
	if [ -z "$latest" ]; then
		echo "::notice::no release yet: nothing to republish, building ${ref} without publishing"
	else
		ref="$latest"
		publish=true
		rolling=true
		if { [ "$EVENT" = schedule ] && [ "${SCHEDULE:-}" = "$DAILY_CRON" ]; } ||
			{ [ "$EVENT" = workflow_dispatch ] && [ "${INPUT_FORCE:-}" != true ]; }; then
			check_base=true
		fi
	fi
fi

# Every branch builds on the same Debian image.
base_tag="debian:${DEBIAN_CODENAME}-slim"
digest="$(docker buildx imagetools inspect "$base_tag" --format '{{json .Manifest}}' | jq -r .digest)"
[[ "$digest" == sha256:* ]] || {
	echo "::error::cannot resolve ${base_tag}"
	exit 1
}
base="${base_tag}@${digest}"

# The branches of the ref being built, which for a republish is a release, not
# the checked out main.
php_versions="$(git show "${ref}:versions.json" | jq -r 'keys_unsorted[]')"

build='[]'
merge='[]'
for php in ${php_versions}; do
	for variant in fpm cli; do

		if [ "$check_base" = true ]; then
			# The label written by the Dockerfile on the image currently
			# published; empty if there is none yet.
			current="$(docker buildx imagetools inspect "${DOCKERHUB_IMAGE}:${php}-${variant}" \
				--format '{{json .Image}}' 2>/dev/null |
				jq -r '."linux/amd64".config.Labels["org.opencontainers.image.base.name"] // empty')" || current=""
			if [ "$current" = "$base" ]; then
				echo "${php}-${variant}: ${base} already published, skipped"
				continue
			fi
		fi

		merge="$(jq -c --arg php "$php" --arg variant "$variant" \
			'. + [{php: $php, variant: $variant}]' <<<"$merge")"
		for platform in amd64 arm64; do
			runner=ubuntu-24.04
			[ "$platform" = arm64 ] && runner=ubuntu-24.04-arm
			build="$(jq -c --arg php "$php" --arg variant "$variant" --arg base "$base" \
				--arg platform "$platform" --arg runner "$runner" \
				'. + [{php: $php, variant: $variant, base: $base, platform: $platform, runner: $runner}]' <<<"$build")"
		done
	done
done

{
	echo "publish=${publish}"
	echo "rolling=${rolling}"
	echo "ref=${ref}"
	echo "version=${version}"
	echo "build=${build}"
	echo "merge=${merge}"
} >>"$GITHUB_OUTPUT"

echo "publish=${publish} rolling=${rolling} ref=${ref} version=${version:-none}"
jq -r '.[] | "\(.php)-\(.variant)"' <<<"$merge"
