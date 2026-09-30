#!/bin/sh
set -eu
umask 077

usage() {
    cat <<'EOF'
Usage: pg-backup-manager backup|dump|restore FILE [PostgreSQL options...]

Connection: DATABASE_URL or standard PGHOST/PGPORT/PGDATABASE/PGUSER/PGPASSWORD.
Formats: .dump (compressed custom archive), .sql, .sql.gz.
Restore requires an existing database. No objects are dropped by default.
For .dump replacement, explicitly pass --clean --if-exists.
Native tools: pg-backup-manager pg_dump|pg_restore|psql [arguments...]
EOF
}

action=${1:-help}
case "$action" in
    help|-h|--help) usage; exit 0 ;;
    pg_dump|pg_restore|psql) exec "$@" ;;
    backup|dump|restore) shift ;;
    *) usage >&2; exit 2 ;;
esac
[ "$#" -gt 0 ] || { usage >&2; exit 2; }
file=$1
shift
# Prefix relative paths so filenames cannot become command options.
case "$file" in /*) ;; *) file=./$file ;; esac
case "$file" in
    *.dump) format=custom ;;
    *.sql) format=plain ;;
    *.sql.gz) format=gzip ;;
    *) echo 'Expected a .dump, .sql or .sql.gz filename.' >&2; exit 2 ;;
esac

# Pass conninfo explicitly: PGDATABASE alone does not expand a connection URI.
if [ -n "${DATABASE_URL:-}" ]; then
    export PGDATABASE="$DATABASE_URL"
    unset DATABASE_URL
fi
if [ -n "${PGDATABASE:-}" ]; then
    set -- "$@" --dbname="$PGDATABASE"
fi

tmp=
cleanup() { [ -z "$tmp" ] || rm -f "$tmp" "$tmp.gz"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

case "$action" in
    backup|dump)
        [ ! -e "$file" ] && [ ! -L "$file" ] || {
            echo 'Backup destination already exists; choose a new filename.' >&2
            exit 1
        }
        tmp=$(mktemp "${file}.tmp.XXXXXX")
        case "$format" in
            custom) pg_dump "$@" --no-password --format=custom --file="$tmp" ;;
            plain|gzip)
                pg_dump "$@" --no-password --no-owner --no-acl --format=plain --file="$tmp"
                if [ "$format" = gzip ]; then
                    gzip -c "$tmp" > "$tmp.gz"
                    mv "$tmp.gz" "$tmp"
                fi
                ;;
        esac
        # Hard-link atomically: never publish an incomplete file or overwrite one.
        ln "$tmp" "$file"
        echo "Backup saved: $file" >&2
        ;;
    restore)
        [ -r "$file" ] || { echo 'Backup file is not readable.' >&2; exit 1; }
        case "$format" in
            custom)
                pg_restore "$@" --no-password --exit-on-error --single-transaction \
                    --no-owner --no-acl --dbname="${PGDATABASE:-${PGUSER:-postgres}}" "$file"
                ;;
            plain|gzip)
                if [ "$format" = gzip ]; then
                    tmp=$(mktemp)
                    gzip -dc "$file" > "$tmp"
                    file=$tmp
                fi
                psql "$@" --no-password --no-psqlrc --set=ON_ERROR_STOP=1 \
                    --single-transaction --file="$file"
                ;;
        esac
        ;;
esac
