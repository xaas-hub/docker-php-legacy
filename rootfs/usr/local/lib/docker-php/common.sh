# shellcheck shell=bash
#
# Helpers shared by docker-php-init and its steps in init.d/.

# shellcheck disable=SC2034 # used by the steps in init.d/
readonly DOCKER_PHP_RUNTIME_DIR=/run/docker-php
readonly DOCKER_PHP_APP_USER=www-data

log() {
	printf 'docker-php: %s\n' "$*" >&2
}

die() {
	log "ERROR: $*"
	exit 1
}

is_true() {
	case "${1,,}" in
	1 | true | yes | on) return 0 ;;
	*) return 1 ;;
	esac
}

is_root() {
	[ "$(id -u)" -eq 0 ]
}

# Writes stdin to $1 atomically. As root the file ends up owned by root and the
# group in $3 (root by default) with mode $2; in a rootless container the
# running user owns it and the group is left alone.
write_file() {
	local path="$1" mode="$2" group="${3:-root}" tmp
	tmp="$(mktemp "${path}.XXXXXX")"
	cat >"$tmp"
	chmod "$mode" "$tmp"
	if is_root; then
		chown "root:${group}" "$tmp"
	fi
	mv -f "$tmp" "$path"
}

# Runs a command as the application user when the container runs as root, as
# is otherwise. HOME has to follow, or tools such as Composer and WP-CLI would
# look for their configuration in /root.
run_as_app_user() {
	if is_root; then
		HOME="$(getent passwd "$DOCKER_PHP_APP_USER" | cut -d: -f6)" \
			setpriv --reuid="$DOCKER_PHP_APP_USER" --regid="$DOCKER_PHP_APP_USER" --init-groups -- "$@"
	else
		"$@"
	fi
}

# Prints "key = "value"" lines for every variable named <prefix><NAME>, sorted
# by name. NAME is lowercased and double underscores become dots:
# PHP_INI_OPCACHE__JIT_BUFFER_SIZE=64M -> opcache.jit_buffer_size = "64M".
# The variables listed after the prefix are skipped.
env_to_ini() {
	local prefix="$1" var key value skip
	shift
	while IFS= read -r var; do
		for skip in "$@"; do
			[ "$var" = "$skip" ] && continue 2
		done
		key="${var#"$prefix"}"
		key="${key//__/.}"
		key="${key,,}"
		value="${!var}"
		# A double quote would end the ini string early and a newline would
		# start a new directive: both could inject arbitrary settings.
		case "$value" in
		*'"'* | *$'\n'*) die "${var}: double quotes and newlines are not supported" ;;
		esac
		printf '%s = "%s"\n' "$key" "$value"
	done < <(compgen -e | grep "^${prefix}" | sort)
}
