# Oracle AI Database 26ai Free ("Oracle Database Free") for Railway.
#
# Flavor guide for container-registry.oracle.com/database/free:
#
#   * 23.26.3.0-lite  ~0.9 GB compressed. Ships compressed, prebuilt data
#                     files that are unpacked into /opt/oracle/oradata on
#                     first start. Best fit for Railway: fast pull, fast
#                     first boot. Multi-arch (amd64 + arm64).
#   * 23.26.3.0       ~3.7 GB compressed. Full image with pre-expanded data
#                     and the optional Oracle components (APEX, ORDS, ...).
#   * latest          points at the FULL image, not the lite one. Do not use.
#
# Railway cannot use container-registry.oracle.com as a service source
# directly, so this Dockerfile wraps the official image.
ARG ORACLE_IMAGE_TAG=23.26.3.0-lite
FROM container-registry.oracle.com/database/free:${ORACLE_IMAGE_TAG}

# The upstream image runs as the unprivileged "oracle" user (UID 54321), but
# Railway mounts volumes owned by root. Start as root and let the wrapper fix
# ownership before dropping privileges back to oracle.
USER root

COPY railway-entrypoint.sh healthcheck.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/railway-entrypoint.sh /usr/local/bin/healthcheck.sh

# Optional, idempotent provisioners. The image runs every *.sh / *.sql in this
# directory as the oracle user after the database is ready, on every container
# start. SQL files are executed as SYSDBA.
COPY init/ /opt/oracle/scripts/startup/
RUN chmod 0755 /opt/oracle/scripts/startup/*.sh \
    && chown -R oracle:oinstall /opt/oracle/scripts/startup

# Keep the image's readiness probe working under the root entrypoint. The probe
# also requires FREEPDB1 to be registered with the listener; the image's own
# checkDBStatus.sh stays green when the listener has no services. Railway ignores
# Docker healthchecks (it uses its own deploy-time checks), so this is mainly for
# `docker run` and other platforms.
HEALTHCHECK --interval=30s --start-period=600s --timeout=30s --retries=10 \
  CMD setpriv --reuid=54321 --regid=54321 --init-groups -- /usr/local/bin/healthcheck.sh

# The wrapper starts as root, prepares the volume, then execs this command as
# the oracle user with its full supplementary group list (dba, oper, ...).
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["/bin/bash", "-c", "$ORACLE_BASE/$RUN_FILE"]
