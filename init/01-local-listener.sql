-- Pin listener registration to the loopback address.
--
-- The -lite image's prebuilt spfile ships local_listener='', so LREG derives
-- the registration address from the container hostname. On Railway's
-- IPv6-capable internal network the hostname can resolve to an address the
-- listener is not on; "lsnrctl status" then shows no services and clients get
-- ORA-12514 for FREE and FREEPDB1. Pin registration to the loopback address
-- the listener always serves, regardless of which interfaces it binds.
--
-- This file lands in /opt/oracle/scripts/startup and runs as SYSDBA in
-- CDB$ROOT after every database start (see runUserScripts.sh in the image).
-- SCOPE=BOTH also persists the setting in the spfile on the volume, so it is
-- in effect from database startup on subsequent boots.
ALTER SYSTEM SET local_listener='(ADDRESS=(PROTOCOL=TCP)(HOST=127.0.0.1)(PORT=1521))' SCOPE=BOTH;
ALTER SYSTEM REGISTER;

-- LOCAL_LISTENER is PDB-modifiable in 26ai. Oracle's workaround for this issue
-- sets it in the PDB as well, so make FREEPDB1's registration independent of
-- the hostname too.
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SYSTEM SET local_listener='(ADDRESS=(PROTOCOL=TCP)(HOST=127.0.0.1)(PORT=1521))' SCOPE=BOTH;
ALTER SYSTEM REGISTER;
