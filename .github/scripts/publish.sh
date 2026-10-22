#!/usr/bin/env bash
#
# Merge job of ci.yml: turns the per-platform digests pushed by the build jobs
# into multi-platform tags, on Docker Hub and GHCR.
#
#   digests/<target>/<sha256 hex>   one empty file per platform
#   digests/php-version             full PHP version, e.g. 7.4.33
#
# Tags, for target fpm (fpm-dev, cli and cli-dev alike):
#   7.4-fpm, 7.4.33-fpm   rolling, only when ROLLING=true
#   7.4-fpm-v1.2.3        when VERSION is set

set -euo pipefail

: "${PHP_MINOR:?}" "${VARIANT:?}" "${DOCKERHUB_IMAGE:?}" "${GHCR_IMAGE:?}" "${ROLLING:?}"
version="${VERSION:-}"

full="$(<digests/php-version)"
[[ "$full" == "${PHP_MINOR}."* ]] || {
	echo "::error::built PHP ${full} does not belong to ${PHP_MINOR}"
	exit 1
}

for target in "$VARIANT" "${VARIANT}-dev"; do
	tags=()
	if [ "$ROLLING" = true ]; then
		tags+=("${PHP_MINOR}-${target}" "${full}-${target}")
	fi
	if [ -n "$version" ]; then
		tags+=("${PHP_MINOR}-${target}-v${version}")
	fi
	if [ "${#tags[@]}" -eq 0 ]; then
		echo "${target}: nothing to tag"
		continue
	fi

	digests=(digests/"${target}"/*)
	[ "${#digests[@]}" -eq 2 ] || {
		echo "::error::${target}: expected 2 platform digests, found ${#digests[@]}"
		exit 1
	}

	for image in "$DOCKERHUB_IMAGE" "$GHCR_IMAGE"; do
		args=()
		for tag in "${tags[@]}"; do
			args+=(-t "${image}:${tag}")
		done
		for digest in "${digests[@]}"; do
			args+=("${image}@sha256:${digest##*/}")
		done
		docker buildx imagetools create "${args[@]}"
		docker buildx imagetools inspect "${image}:${tags[0]}"
	done
done
