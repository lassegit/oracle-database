#!/bin/bash
# Container healthcheck: database open AND services registered with the listener.
#
# The image's checkDBStatus.sh uses local OS authentication
# (sqlplus / as sysdba), so it reports healthy even when the listener has no
# services and clients get ORA-12514. Checking lsnrctl status as well catches
# that failure mode.
#
# Railway ignores Docker HEALTHCHECK and uses its own deploy-time checks; this
# probe is for `docker run` and other container platforms (see README's Local
# testing section).

set -u

/opt/oracle/checkDBStatus.sh >/dev/null || exit 1

if [ -n "${ORACLE_HOME:-}" ] && [ -x "${ORACLE_HOME}/bin/lsnrctl" ]; then
  LSNRCTL="${ORACLE_HOME}/bin/lsnrctl"
elif command -v lsnrctl >/dev/null 2>&1; then
  LSNRCTL="$(command -v lsnrctl)"
else
  echo "lsnrctl not found" >&2
  exit 1
fi

status="$("${LSNRCTL}" status 2>/dev/null)" || exit 1

printf '%s\n' "${status}" | grep -qi 'service "FREE"' || exit 1
printf '%s\n' "${status}" | grep -qi 'service "FREEPDB1' || exit 1
