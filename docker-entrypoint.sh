#!/bin/sh
set -e

DB_PATH="/var/www/data/ipmagnet.db3"
INDEX_PHP="/var/www/html/index.php"

# Allow the public tracker URL and interval feature to be configured at
# container start instead of requiring a rebuild.
if [ -n "$TRACKER_URL" ]; then
	# it's substituted into a double-quoted PHP string by a #-delimited sed
	case "$TRACKER_URL" in
		*[\"\$\\#]*)
			echo "TRACKER_URL must not contain \", \$, \\ or #" >&2
			exit 1
			;;
	esac
	escaped_url=$(printf '%s' "$TRACKER_URL" | sed 's/[&/\]/\\&/g')
	sed -i "s#\$TRACKER=urlencode(\"[^\"]*\")#\$TRACKER=urlencode(\"${escaped_url}\")#" "$INDEX_PHP"
fi

if [ "$ENABLE_INTERVAL" = "true" ]; then
	sed -i 's/\$enableInterval=false;/$enableInterval=true;/' "$INDEX_PHP"
fi

if [ -n "$TRACKER_INTERVAL" ]; then
	case "$TRACKER_INTERVAL" in
		*[!0-9]*)
			echo "TRACKER_INTERVAL must be a whole number of seconds" >&2
			exit 1
			;;
	esac
	sed -i "s/\$trackerInterval=[0-9]*;/\$trackerInterval=${TRACKER_INTERVAL};/" "$INDEX_PHP"
fi

if [ "$TRUST_PROXY" = "true" ]; then
	sed -i 's/\$trustProxy=false;/$trustProxy=true;/' "$INDEX_PHP"
fi

if [ ! -f "$DB_PATH" ]; then
	sqlite3 "$DB_PATH" <<-'SQL'
		CREATE TABLE hits (
			id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL UNIQUE,
			hash TEXT NOT NULL,
			timestamp INTEGER NOT NULL,
			addr TEXT NOT NULL,
			agent TEXT NOT NULL
		);
	SQL
fi

# SQLite writes its journal next to the database, so the directory must be
# writable too (a bind-mounted host directory is typically root-owned)
chown www-data:www-data "$(dirname "$DB_PATH")" "$DB_PATH"

exec "$@"
