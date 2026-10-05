#!/bin/bash
# Railway wrapper for container-registry.oracle.com/database/free.
#
# The upstream image runs as the unprivileged "oracle" user (UID 54321) and
# requires /opt/oracle/oradata to be writable by that user. Railway mounts
# volumes owned by root, which is why the template sets RAILWAY_RUN_UID=0:
# this script starts as root, fixes ownership, then drops back to oracle.
#
# It also makes the listener dual-stack. The prebuilt database ships an
# IPv4-only listener.ora (0.0.0.0:1521), but Railway's private network is
# IPv6-capable and environments created before October 2025 resolve service
# names to IPv6 only. Rewriting the file here, before runOracle_lite.sh starts
# the listener, avoids both a boot-time reachability gap and an lsnrctl reload:
# on first boot the prebuilt copy in /opt/oracle/tmp_oradata is patched,
# afterwards the copy on the volume.
#
# setpriv is used instead of su/runuser because it keeps oracle's full
# supplementary group list (dba, oper, backupdba, ...), which
# `sqlplus / as sysdba` needs, and because it replaces this shell with the
# Oracle entrypoint: PID 1 stays the Oracle script, so Railway's SIGTERM
# reaches its graceful shutdown trap.
set -euo pipefail

ORACLE_UID=54321
ORACLE_GID=54321
ORACLE_BASE="${ORACLE_BASE:-/opt/oracle}"

# Add or remove the IPv6 listening endpoint in a listener.ora, matching the
# capabilities of the host. The listener binds each ADDRESS separately, so the
# existing IPv4 endpoint (0.0.0.0) and an IPv6 endpoint (::) together give a
# dual-stack listener. The file is rewritten in place so ownership is kept.
patch_listener_ora() {
  local file="$1" tmp

  [ -f "$file" ] || return 0

  if [ ! -s /proc/net/if_inet6 ]; then
    # No IPv6 stack: make sure the listener can still start IPv4-only.
    if grep -qE 'HOST[[:space:]]*=[[:space:]]*::' "$file"; then
      echo "railway-entrypoint: removing IPv6 listener endpoint from $file (no IPv6 stack)"
      tmp="$(mktemp)"
      grep -vE 'HOST[[:space:]]*=[[:space:]]*::' "$file" > "$tmp"
      cat "$tmp" > "$file"
      rm -f "$tmp"
    fi
    return 0
  fi

  if grep -qE 'HOST[[:space:]]*=[[:space:]]*::' "$file"; then
    return 0
  fi

  echo "railway-entrypoint: adding IPv6 listener endpoint to $file"
  tmp="$(mktemp)"
  awk '
    !inserted && /\(ADDRESS = \(PROTOCOL = TCP\)/ {
      print
      print "      (ADDRESS = (PROTOCOL = TCP)(HOST = ::)(PORT = 1521))"
      inserted = 1
      next
    }
    { print }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

if [ "$(id -u)" != "0" ]; then
  echo "railway-entrypoint: running as uid=$(id -u), not root." >&2
  echo "railway-entrypoint: set RAILWAY_RUN_UID=0 so the volume can be prepared." >&2
  exec "$@"
fi

mkdir -p "${ORACLE_BASE}/oradata" "${ORACLE_BASE}/scripts/startup"
chown -R "${ORACLE_UID}:${ORACLE_GID}" "${ORACLE_BASE}/oradata" "${ORACLE_BASE}/scripts"

shopt -s nullglob
for listener_gz in "${ORACLE_BASE}"/tmp_oradata/dbconfig/*/listener.ora.gz; do
  if gunzip -f "$listener_gz"; then
    listener_ora="${listener_gz%.gz}"
    patch_listener_ora "$listener_ora"
    chown "${ORACLE_UID}:${ORACLE_GID}" "$listener_ora"
  fi
done
for listener_ora in "${ORACLE_BASE}"/oradata/dbconfig/*/listener.ora; do
  patch_listener_ora "$listener_ora"
  chown "${ORACLE_UID}:${ORACLE_GID}" "$listener_ora"
done
shopt -u nullglob

exec setpriv --reuid="${ORACLE_UID}" --regid="${ORACLE_GID}" --init-groups -- "$@"
