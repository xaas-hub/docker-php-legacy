# shellcheck shell=bash
#
# LOCALES: extra locales, see docker-php-locales for the syntax.

if [ -n "${LOCALES:-}" ]; then
	if is_root; then
		docker-php-locales "${LOCALES}"
	else
		log "LOCALES ignored: generating locales needs root, build them into the image with --build-arg LOCALES"
	fi
fi
