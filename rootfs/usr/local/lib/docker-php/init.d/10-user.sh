# shellcheck shell=bash
#
# USER_ID / GROUP_ID: gives www-data the host user's ids, so that what PHP
# writes on bind mounts belongs to that user. Only the home directory is
# re-owned: the document root is left alone, it is normally a bind mount that
# already belongs to the host user. 0 or empty leaves the id unchanged.

if is_root; then
	user_remapped=0
	if [ -n "${GROUP_ID:-}" ] && [ "${GROUP_ID}" != 0 ]; then
		[[ "${GROUP_ID}" =~ ^[0-9]+$ ]] || die "GROUP_ID must be numeric, got '${GROUP_ID}'"
		if [ "$(id -g "$DOCKER_PHP_APP_USER")" != "${GROUP_ID}" ]; then
			groupmod -o -g "${GROUP_ID}" "$DOCKER_PHP_APP_USER"
			user_remapped=1
		fi
	fi
	if [ -n "${USER_ID:-}" ] && [ "${USER_ID}" != 0 ]; then
		[[ "${USER_ID}" =~ ^[0-9]+$ ]] || die "USER_ID must be numeric, got '${USER_ID}'"
		if [ "$(id -u "$DOCKER_PHP_APP_USER")" != "${USER_ID}" ]; then
			usermod -o -u "${USER_ID}" "$DOCKER_PHP_APP_USER"
			user_remapped=1
		fi
	fi
	# usermod -u re-owns the home directory but groupmod does not: one chown
	# covers both.
	if [ "$user_remapped" = 1 ]; then
		chown -R "${DOCKER_PHP_APP_USER}:${DOCKER_PHP_APP_USER}" \
			"$(getent passwd "$DOCKER_PHP_APP_USER" | cut -d: -f6)"
	fi
	unset user_remapped
elif [ -n "${USER_ID:-}${GROUP_ID:-}" ]; then
	log "USER_ID and GROUP_ID ignored: the container already runs as $(id -u):$(id -g)"
fi
