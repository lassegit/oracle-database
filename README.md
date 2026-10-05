# Oracle Database Free on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/oracle-database-free?utm_medium=integration&utm_source=button&utm_campaign=oracle-database-free)

Source repository for the **Oracle Database Free** template on Railway. It deploys the
official Oracle AI Database 26ai Free container image with persistent storage, private
networking and an optional TCP proxy, and it is set up for one schema per sandbox.

> Run a real Oracle Database on Railway — a single instance with up to **12 GB of user
> data**, **2 GB of database RAM** and **2 CPU threads**, free under Oracle's Free Use
> Terms and Conditions (FUTC).

## What is Oracle Database Free?

Oracle AI Database 26ai Free is a full-featured Oracle Database, free to use under
Oracle's Free Use Terms and Conditions. It supports the same SQL, PL/SQL, JSON, spatial
and vector/AI features as the commercial editions, capped at 12 GB of user data, 2 GB
of database RAM and 2 CPU threads, and one instance per logical environment.

## About hosting Oracle Database Free

Railway cannot use `container-registry.oracle.com` as a service source, so this
repository builds a small Dockerfile that wraps the official image. It uses the
**`-lite`** flavor (`23.26.3.0-lite`, ~0.9 GB compressed, multi-arch) instead of the
full image (~3.7 GB) or the `latest` tag (which points at the full image). The lite
image ships compressed, prebuilt data files that are expanded into the Railway volume on
first start, so there is no 15-minute DBCA database creation step. Because Railway mounts
volumes owned by root, the wrapper starts as root, makes `/opt/oracle/oradata` writable
by the `oracle` user (UID 54321), then drops privileges and hands PID 1 to Oracle's
entrypoint so redeploys shut the database down cleanly.

## Requirements

- **Railway Hobby plan or higher.** The Free/Trial plan caps a service at 1 vCPU /
  0.5 GB RAM, below Oracle's 2 GB minimum; the container exits with
  *"The container doesn't have enough memory allocated."* Give the service at least
  2 GB of RAM (4 GB is comfortable).
- **A volume of at least 5 GB.** Hobby volumes start at 5 GB; Pro at 50 GB. Oracle Free
  allows up to 12 GB of user data. The lite image expands its prebuilt data files into
  the volume on first boot.
- **First boot takes a few minutes.** Watch the deploy logs for
  `######################### DATABASE IS READY TO USE! #########################`.

## Common use cases

- Development, staging and CI databases for SQL, PL/SQL and Oracle-specific features.
- Sandboxed SQL/AI playgrounds where each sandbox is a schema in `FREEPDB1`.
- Testing migrations, query plans and schema changes against a real Oracle instance.
- Building Oracle-backed apps on the same private network as the rest of your stack.

## Template contents

| Resource | Value |
| --- | --- |
| Service image | `container-registry.oracle.com/database/free:23.26.3.0-lite`, built by the `Dockerfile` in this repo |
| Volume | `/opt/oracle/oradata` — database files and anything you write there (for example Data Pump dumps) |
| TCP proxy | Optional, port `1521`, for clients outside Railway |
| Private network | `<service>.railway.internal:1521`, service name `FREEPDB1` |

## Variables

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `ORACLE_PWD` | yes | generated | Password for `SYS`, `SYSTEM` and `PDBADMIN`. Applied on every start, so changing it and restarting rotates the password. |
| `RAILWAY_RUN_UID` | yes | `0` | Runs the container as root so the wrapper can prepare the volume before dropping to the `oracle` user. |
| `ORACLE_IMAGE_TAG` | no | `23.26.3.0-lite` | Build-time `ARG` selecting the image tag. Only use `-lite` tags; avoid `latest`. |
| `RAILWAY_SHM_SIZE_BYTES` | recommended | `2147483648` | Size of `/dev/shm` (2 GiB). Covers Oracle memory configurations that place part of the memory areas in shared memory instead of the default 64 MB. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | recommended | `30` | Seconds between SIGTERM and SIGKILL so Oracle can shut down gracefully on redeploy. |
| `APP_USER` | no | — | Creates (or updates) a schema/user in `FREEPDB1` on startup. |
| `APP_USER_PASSWORD` | no | — | Password for `APP_USER`. Change it and restart to rotate. |

Generate secrets with Railway's template variable functions, for example:

```
ORACLE_PWD=${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}
APP_USER_PASSWORD=${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}
```

## Connecting

The database listens on port `1521` on both the private network and the TCP proxy.

```
SID:           FREE
PDB / service: FREEPDB1   (always use FREEPDB1 as the service name)
Character set: AL32UTF8
Admin users:   SYS, SYSTEM, PDBADMIN (password: ORACLE_PWD)
```

From another Railway service (recommended — traffic stays on the private network and is
not billed as egress). Replace `oracle.railway.internal` with the database service's
private domain, which is `<service-name>.railway.internal` (`oracle` here assumes the
service is named `Oracle`; the dashboard shows the exact value):

```bash
# sqlplus
sqlplus system/"$ORACLE_PWD"@//oracle.railway.internal:1521/FREEPDB1

# JDBC
jdbc:oracle:thin:@//oracle.railway.internal:1521/FREEPDB1

# Python (python-oracledb)
oracledb.connect(user="system", password=os.environ["ORACLE_PWD"],
                 dsn="oracle.railway.internal:1521/FREEPDB1")

# Node.js (node-oracledb)
oracledb.getConnection({ user: "system", password: process.env.ORACLE_PWD,
                         connectString: "oracle.railway.internal:1521/FREEPDB1" })
```

From outside Railway, add a TCP proxy on port `1521` in the service's Networking
settings, then connect to `$RAILWAY_TCP_PROXY_DOMAIN:$RAILWAY_TCP_PROXY_PORT` with the
same service name. Oracle Net does not encrypt the listener link by default, so prefer
the private network for applications and use the proxy for admin access.

## One schema per sandbox

Oracle Database Free caps the whole instance at 12 GB of user data, and every listener
connection and schema lives in the same instance. Creating a *schema/user* per sandbox
is much cheaper than a PDB per sandbox (no extra PDB overhead, instant create/drop) and
keeps the 12 GB pool shared. Connect as `SYSTEM` to `FREEPDB1` and run:

```sql
-- Create a sandbox. Use a quota so one sandbox cannot exhaust the 12 GB limit.
CREATE USER sandbox_42 IDENTIFIED BY "<password>"
  DEFAULT TABLESPACE USERS
  QUOTA 256M ON USERS;

GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER, CREATE TYPE, CREATE SYNONYM,
      CREATE MATERIALIZED VIEW, CREATE JOB
   TO sandbox_42;

-- Tear down a sandbox, including all of its objects.
DROP USER sandbox_42 CASCADE;
```

The optional `APP_USER`/`APP_USER_PASSWORD` variables provision one such schema
automatically at startup (see `init/90-app-user.sh`). Use that script as the reference
for creating the rest from your application.

## Query plans: EXPLAIN PLAN + DBMS_XPLAN

Every sandbox user can produce plans with plain SQL. `EXPLAIN PLAN` writes to the
user's `PLAN_TABLE` (created on first use, an object the sandbox already owns), and
`DBMS_XPLAN` formats it:

```sql
EXPLAIN PLAN FOR
SELECT /* sandbox query */
       d.department_name, SUM(e.salary)
  FROM hr.employees e
  JOIN hr.departments d ON d.department_id = e.department_id
 GROUP BY d.department_name;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

`DBMS_XPLAN` is granted to `PUBLIC` by default; the provisioning script grants it to
`APP_USER` explicitly so plans keep working if your database is hardened later. For
plans that need stats, run `DBMS_STATS.GATHER_SCHEMA_STATS` or
`DBMS_STATS.GATHER_TABLE_STATS` inside the sandbox first.

## Persistence and backups

Data lives on the Railway volume at `/opt/oracle/oradata` and survives redeploys.
Redeploying pauses the old deployment while the volume is attached (there is a short
downtime) and replicas cannot be used with volumes.

A volume is not a backup. Take backups with `expdp` to the volume (or a Railway
bucket) and/or enable Railway's volume backups:

```bash
# inside the container / via `railway ssh`
expdp system/"$ORACLE_PWD"@localhost:1521/FREEPDB1 \
      full=y directory=DATA_PUMP_DIR dumpfile=backup_$(date +%F).dmp
```

## Version upgrades

`ORACLE_IMAGE_TAG` is a build argument, so changing it rebuilds and redeploys the
service. Oracle data files are versioned: move forward within the 23.26.x line, never
downgrade, and test on a copy of the volume first. For anything larger, export/import
with Data Pump. Do not switch to `latest`: it points at the **full** image, not the
lite one, and redeploying it can complicate the volume layout.

## Local testing

```bash
docker build -t oracle-free-railway .
docker run --rm -p 1521:1521 \
  -e ORACLE_PWD=change_me_123 \
  -e RAILWAY_RUN_UID=0 \
  -v oracle-data:/opt/oracle/oradata \
  oracle-free-railway
# wait for "DATABASE IS READY TO USE!" in the logs, then:
sqlplus system/change_me_123@//localhost:1521/FREEPDB1
```

## Creating the Railway template (maintainers)

1. In Railway, create a project and deploy this repository as the service.
2. Attach a volume at `/opt/oracle/oradata` (5 GB+).
3. Add the variables from the table above; mark `ORACLE_PWD` as required and use a
   generated secret. Set `RAILWAY_RUN_UID=0`,
   `RAILWAY_SHM_SIZE_BYTES=2147483648` and
   `RAILWAY_DEPLOYMENT_DRAINING_SECONDS=30`.
4. Set the restart policy to `ON_FAILURE` (10 retries is reasonable) and add a TCP
   proxy on port `1521`.
5. Use **Generate Template from Project**, add the description/use cases/FAQ from this
   README, and publish. Update the deploy button URL above with the published slug if
   it differs from `oracle-database-free`.

## License

- The database and the container image are Oracle programs governed by the
  [Oracle Free Use Terms and Conditions](licenses/oracle-free-license.txt) (FUTC) and
  the license files inside the image. In short: free to use within the 12 GB / 2 GB RAM
  / 2 CPU thread limits for development, testing, prototyping, demonstration and your
  own internal business operations; unmodified redistribution is allowed under the
  FUTC as long as the license is included and no extra fee is charged for the
  programs. Oracle's terms, not this summary, control.
- The Dockerfile, entrypoint and init scripts in this repository are released under the
  [MIT license](LICENSE). The upstream image also contains scripts under Oracle's
  [UPL 1.0](https://oss.oracle.com/licenses/upl/).
- Oracle, Oracle Database and Java are trademarks of Oracle Corporation. This template
  is not affiliated with or endorsed by Oracle.
