#!/bin/bash
# Optional application schema provisioning.
#
# Set APP_USER and APP_USER_PASSWORD on the Railway service to create (or
# update) a schema/user in the FREEPDB1 pluggable database. The script runs on
# every container start, so changing APP_USER_PASSWORD rotates the password on
# the next restart.
#
# The image sources this file only after the database reports
# "DATABASE IS READY TO USE!". It is safe to delete if no default schema is
# wanted: sandboxes can also be created from a privileged connection.

set -u

if [ -z "${APP_USER:-}" ]; then
  echo "APP_USER not set; skipping application schema provisioning."
  return 0 2>/dev/null || exit 0
fi

# Oracle user names: up to 30 characters, start with a letter.
app_user="$(printf '%s' "$APP_USER" | tr '[:lower:]' '[:upper:]')"
if ! [[ "$app_user" =~ ^[A-Z][A-Z0-9_$#]{0,29}$ ]]; then
  echo "APP_USER='${APP_USER}' is not a valid Oracle user name; skipping." >&2
  return 1 2>/dev/null || exit 1
fi

case "$app_user" in
  SYS|SYSTEM|PDBADMIN|XDB|DBSNMP|OUTLN|AUDSYS|GSMADMIN_INTERNAL|OJVMSYS|ORDDATA|ORDSYS|MDSYS|WMSYS|CTXSYS|LBACSYS|DVSYS|DBSFWUSER|GGSYS|ANONYMOUS|APPQOSSYS|REMOTE_SCHEDULER_AGENT)
    echo "APP_USER='${APP_USER}' is a reserved Oracle account; skipping." >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

if [ -z "${APP_USER_PASSWORD:-}" ]; then
  echo "APP_USER is set but APP_USER_PASSWORD is empty; skipping." >&2
  return 1 2>/dev/null || exit 1
fi

# The password is placed inside a double-quoted identifier in DDL below.
if [[ "$APP_USER_PASSWORD" == *'"'* || "$APP_USER_PASSWORD" == *"'"* || "$APP_USER_PASSWORD" == *$'\n'* ]]; then
  echo "APP_USER_PASSWORD must not contain single quotes, double quotes or newlines; skipping." >&2
  return 1 2>/dev/null || exit 1
fi

# Generate the DDL with printf (no shell re-expansion of the password) so that
# $, &, % and friends in the password reach SQL*Plus untouched.
sql_file="$(mktemp)"
trap 'rm -f "$sql_file"' EXIT

{
  echo "SET DEFINE OFF"
  echo "WHENEVER SQLERROR EXIT SQL.SQLCODE"
  echo "ALTER SESSION SET CONTAINER = FREEPDB1;"
  echo "DECLARE"
  echo "  v_count NUMBER;"
  echo "BEGIN"
  printf "  SELECT COUNT(*) INTO v_count FROM dba_users WHERE username = '%s';\n" "$app_user"
  echo "  IF v_count = 0 THEN"
  printf '    EXECUTE IMMEDIATE '\''CREATE USER %s IDENTIFIED BY "%s" DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS'\'';\n' "$app_user" "$APP_USER_PASSWORD"
  echo "  ELSE"
  printf '    EXECUTE IMMEDIATE '\''ALTER USER %s IDENTIFIED BY "%s"'\'';\n' "$app_user" "$APP_USER_PASSWORD"
  echo "  END IF;"
  echo "END;"
  echo "/"
  printf "GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,\n"
  printf "      CREATE PROCEDURE, CREATE TRIGGER, CREATE TYPE, CREATE SYNONYM,\n"
  printf "      CREATE MATERIALIZED VIEW, CREATE JOB TO %s;\n" "$app_user"
  echo "GRANT EXECUTE ON DBMS_XPLAN TO $app_user;"
} > "$sql_file"

echo "Provisioning application schema ${app_user} in FREEPDB1..."
sqlplus -s "/ as sysdba" @"$sql_file"
