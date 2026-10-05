#!/bin/bash
# Railway wrapper for container-registry.oracle.com/database/free.
#
# The upstream image runs as the unprivileged "oracle" user (UID 54321) and
# requires /opt/oracle/oradata to be writable by that user. Railway mounts
# volumes owned by root, which is why the template sets RAILWAY_RUN_UID=0:
# this script starts as root, fixes ownership, then drops back to oracle.
#
# setpriv is used instead of su/runuser because it keeps oracle's full
# supplementary group list (dba, oper, backupdba, ...), which
# `sqlplus / as sysdba` needs, and because it replaces this shell with the
# Oracle entrypoint: PID 1 stays the Oracle script, so Railway's SIGTERM
# reaches its graceful shutdown trap.
set -euo pipefail

ORACLE_UID=54321
ORACLE_GID=54321

if [ "$(id -u)" != "0" ]; then
  echo "railway-entrypoint: running as uid=$(id -u), not root." >&2
  echo "railway-entrypoint: set RAILWAY_RUN_UID=0 so the volume can be prepared." >&2
  exec "$@"
fi

mkdir -p /opt/oracle/oradata /opt/oracle/scripts/startup
chown -R "${ORACLE_UID}:${ORACLE_GID}" /opt/oracle/oradata /opt/oracle/scripts

exec setpriv --reuid="${ORACLE_UID}" --regid="${ORACLE_GID}" --init-groups -- "$@"
