# shellcheck shell=bash
#
# SUPERCRONIC_ENABLED: runs Supercronic in the background, as www-data, next to
# the main command. Nothing restarts it if it dies, so give the container
# `init: true` to reap it, or rather run the cli image as a separate cron
# container: `command: supercronic /etc/crontab`.

if is_true "${SUPERCRONIC_ENABLED:-}"; then
	supercronic_crontab="${SUPERCRONIC_CRONTAB:-/etc/crontab}"
	[ -f "$supercronic_crontab" ] || die "SUPERCRONIC_CRONTAB: ${supercronic_crontab} not found"
	read -r -a supercronic_flags <<<"${SUPERCRONIC_FLAGS:-}"
	log "starting supercronic ${supercronic_crontab}"
	run_as_app_user supercronic "${supercronic_flags[@]}" "$supercronic_crontab" &
	unset supercronic_crontab supercronic_flags
fi
