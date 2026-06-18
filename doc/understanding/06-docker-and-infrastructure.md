# 06 - Docker & Infrastructure

This document is for the engineer taking full ownership of the ESM legacy Rails 4.2 EMR platform. It covers how the system is containerized, built, networked, persisted, and served, plus the operational landmines you will hit on day one. For how requests actually flow through the app once it boots, see **02 - Request Flow & Routing**; for the data stores themselves, see **04 - Database Structure**; for the eval-based execution model that makes this app what it is, see **01 - Architecture & Application Bootstrapping** and **07 - Metadata-Driven Architecture**.

> Scope note: this is a single-host `docker compose` deployment. There is no Kubernetes, no Terraform, no reverse proxy, and no CI/CD config in the repo. What you see in `docker-compose.yml`, `Dockerfile`, and `seed/Dockerfile` is the entire infrastructure story as committed.

## Container Topology

The stack is defined with Compose file format `version: '3'` (`docker-compose.yml:1`) and runs four services on the default project bridge network. Service-to-service traffic uses Docker DNS names (`db`, `mongo`, `redis`), which is why the app configs point at those hostnames rather than `localhost`.

| Service | Image / Build | Host:Container ports | Restart | Role |
|---|---|---|---|---|
| `web` | `build: .` (ruby:2.3 + Thin) | `3000:3000` | always | Rails 4.2 app (`module Esmx`), TLS terminated at Thin |
| `db` | `mysql:8.2`, `build: ./seed` | `3316:3306` | always | MySQL metadata store (`soup_esm_emr`) |
| `mongo` | `mongo:3.2` | `27117:27017` | always | Document/GridFS runtime store |
| `redis` | `redis:latest` | `6379:6379` | always | Resque queue backend (namespace `resque:task`) |

Evidence: `docker-compose.yml:3-6` (db), `:8-9` (db ports), `:14-18` (redis), `:19-23` (mongo), `:27-41` (web). `web` declares `depends_on: db, mongo, redis` (`docker-compose.yml:38-41`).

```
Container topology (docker-compose default bridge network)

  Host (macOS)                          Docker network: <project>_default
  ===========                          ====================================

  browser ──HTTPS──> :3000 ───────────> [ web ]  build: .  (ruby:2.3 + Thin)
  (self-signed,                          cmd: thin start --port 3000 --ssl
   CN=localhost)                              --ssl-key-file config/ssl/private.key
                                              --ssl-cert-file config/ssl/server.crt
                                         volume: . -> /docker_app  (source over image)
                                         depends_on: db, mongo, redis
                                              │        │         │
                          mysql2 0.3.21 ──────┘        │         └──── Resque/redis
                          host=db                      │               host=redis
                                                  MongoMapper
                                                  host=mongo
          host:3316 ─────> :3306 [ db ]   mysql:8.2  (build ./seed)
                                  cmd: --default-authentication-plugin=mysql_native_password
                                  vol: ./databases/mysql -> /var/lib/mysql
                                  initdb: seed.sql (DB=soup_esm_emr)

          host:27117 ────> :27017 [ mongo ]  mongo:3.2
                                  vol: ./databases/mongo -> /data/db
                                  vol: ./databases/dump  -> /dump

          host:6379 ─────> :6379  [ redis ]  redis:latest  (no volume = ephemeral)

  (((  NO resque worker / resque-scheduler container exists  )))
     Task.enqueue / Resque::Job.create push to redis namespace 'resque:task'
     but nothing ever pops them -> jobs accumulate, never run.

  All services: restart: always
```

### `depends_on` is start-order only

`depends_on` (`docker-compose.yml:38-41`) guarantees only that `db`/`mongo`/`redis` *start* before `web`, not that they are *ready*. There are no healthchecks. Combined with `restart: always` and the slow first-run MySQL import (a ~20MB dump), `web` may crash-loop while MySQL initializes. `entrypoint.sh` has no wait-for-db logic — it only clears the Rails PID file. This is noisy but self-healing once MySQL is up.

## Ports & Volumes

### Port mappings

Note the deliberately offset host ports for the data stores (so they don't collide with locally-installed MySQL/Mongo), while Redis and the web port are passed through 1:1:

- `web`: `3000:3000` — HTTPS (TLS at Thin) — `docker-compose.yml:35-36`
- `db`: `3316:3306` — MySQL — `docker-compose.yml:8-9`
- `mongo`: `27117:27017` — MongoDB — `docker-compose.yml:22-23`
- `redis`: `6379:6379` — Redis — `docker-compose.yml:17-18`

All four data/app ports are published to the host, so anything that can reach the host can reach MySQL (`minadadmin` root password), Mongo (no auth in dev), and Redis (no auth). Treat the host firewall as the only thing standing between the internet and these stores.

### Volumes (host bind-mounts under `./databases`)

| Mount | Purpose | Persistence | Citation |
|---|---|---|---|
| `./databases/mysql -> /var/lib/mysql` | MySQL datadir | Persistent on host | `docker-compose.yml:12-13` |
| `./databases/mongo -> /data/db` | MongoDB datadir | Persistent on host | `docker-compose.yml:24-25` |
| `./databases/dump -> /dump` | mongodump/mongorestore staging | Persistent on host | `docker-compose.yml:26` |
| `. -> /docker_app` (web) | Live source bind-mount | Host source overrides image | `docker-compose.yml:33-34` |
| (none for redis) | — | **Ephemeral** — lost on container recreation | `docker-compose.yml:14-18` |

**Redis has no volume.** Any queued Resque jobs, cache entries, or anything else in Redis evaporate when the container is recreated. The host `./databases/` already contains populated `mysql/` and `mongo/` datadirs (confirmed on disk), which has a direct consequence for seeding (below).

## Build Flow

### Web image (`Dockerfile`)

```
FROM ruby:2.3 (Debian Stretch)
 └─ rewrite /etc/apt/sources.list -> archive.debian.org stretch + stretch/updates
 └─ disable Check-Valid-Until, apt-get install --allow-unauthenticated:
       nodejs imagemagick ffmpeg wkhtmltopdf dcmtk openssl libssl-dev
       default-libmysqlclient-dev libxmlsec1-dev libxml2-dev libxslt1-dev pkg-config
 └─ mkdir /docker_app ; WORKDIR /docker_app
 └─ COPY Gemfile + Gemfile.lock
 └─ gem install bundler -v 1.17.3 ; bundle _1.17.3_ install
 └─ COPY . /docker_app
 └─ COPY entrypoint.sh -> /usr/bin ; chmod +x
 └─ ENTRYPOINT entrypoint.sh ; EXPOSE 3000
 └─ ENV TZ=Asia/Bangkok ; ln -snf .../$TZ /etc/localtime
 (CMD is commented out — runtime command comes entirely from compose)
```

Key facts and citations:

- Base is `ruby:2.3` on **EOL Debian Stretch**, pulling from `archive.debian.org` with `Acquire::Check-Valid-Until "false"` and `--allow-unauthenticated` (`Dockerfile:1-10`). Builds depend on the Debian archive staying reachable and accept unverified packages — a reproducibility and supply-chain risk.
- Native deps reflect the healthcare/EMR domain: `dcmtk` (DICOM), `imagemagick` (thumbnailing — see **08 - View Rendering & Content/Attachment Flow**), `ffmpeg`, `wkhtmltopdf` (PDF worker), `libxmlsec1-dev` (SAML, though SAML is unwired — see **03 - Authentication & Authorization**), and `default-libmysqlclient-dev` (`Dockerfile:6-9`).
- Bundler is pinned to `1.17.3` and the install runs under that exact version (`Dockerfile:15`).
- `TZ=Asia/Bangkok` is baked into the image (`Dockerfile:24-25`); the app also forces `Time.zone = 'Bangkok'` per request (see **01 - Architecture**).
- **The `CMD` is commented out** (`Dockerfile:29`). The runtime command comes *solely* from `docker-compose.yml`. If you ever run the image without Compose, it will start with no server command.

### Web startup command

```bash
# docker-compose.yml:29
bash -c "rm -f tmp/pids/server.pid && \
  bundle exec thin start --port 3000 --ssl \
    --ssl-key-file config/ssl/private.key \
    --ssl-cert-file config/ssl/server.crt"
```

`entrypoint.sh` runs `set -e`, removes `/docker_app/tmp/pids/server.pid`, then `exec "$@"` (`entrypoint.sh:1-8`) — so the PID is cleared twice (entrypoint + the compose command's `rm -f`). The Puma and `-e production` variants are present but commented out (`docker-compose.yml:30-32`).

**The app boots in `development`, not `production`.** The Thin command has no `-e production` flag. This means class reloading, verbose logging, live asset compilation, and `consider_all_requests_local = true` style full-error pages. (See **01 - Architecture** for the per-environment config differences.) This is likely intentional for this legacy box but is not production-hardened.

### Source bind-mount shadows the image

`web` mounts `.:/docker_app` (`docker-compose.yml:33-34`), so the host working tree is layered *over* the `COPY . /docker_app` from the image. Practical effects:

- Local source edits are **live** — no rebuild needed to pick up code changes (development mode also reloads classes).
- The image is **not self-contained for deployment**: the running code is whatever is on the host, not what was COPY'd at build time.
- Bundle artifacts installed under `/docker_app` during build can be masked by host content. If gems were installed to a path inside `/docker_app`, runtime can diverge from the image. Keep an eye on this if you change the gem install path or `BUNDLE_PATH`.

### DB seed image (`seed/Dockerfile`)

```
FROM mysql:8.2            # pinned to match the existing 8.2 datadir
ENV MYSQL_DATABASE soup_esm_emr
COPY seed.sql /docker-entrypoint-initdb.d/
```

On a **fresh, empty** `./databases/mysql` datadir, the official MySQL entrypoint creates `soup_esm_emr` then runs `seed.sql`. The dump itself was generated by **MySQL 5.5.31** (`seed/seed.sql` header: `Distrib 5.5.31 ... Server version 5.5.31`) and contains **no `CREATE DATABASE`** — it relies entirely on the `MYSQL_DATABASE` env var. The seed is ~20MB and defines the metadata tables (`esms`, `esm_projects`, `esm_services`, `esm_operations`, `esm_tables`, `esm_schemas`, `esm_documents`/`esm_templates`) plus `users`/`roles`/`permissions`/`logs`/`settings`. The `seed/Dockerfile:2-3` comment explicitly pins 8.2 because the existing host datadir was created by 8.2 and MySQL 9.x refuses to open it.

## SSL / TLS

TLS is **terminated at the application** — Thin reads the cert and key directly. There is no nginx/HAProxy/load-balancer in front of it in the repo.

| Property | Value | Citation |
|---|---|---|
| Cert file | `config/ssl/server.crt` | `docker-compose.yml:29` |
| Key file | `config/ssl/private.key` (RSA) | `docker-compose.yml:29` |
| Subject | `C=TH, ST=Bangkok, L=Bangkok, O=ESM, CN=localhost` | verified via `openssl x509` |
| Validity | `notBefore=2026-06-15`, `notAfter=2036-06-12` | verified via `openssl x509` |
| Self-signed | Yes (CN=localhost) | verified |

Operational implications:

- Browsers/clients get certificate warnings (self-signed, `CN=localhost`). There is no trusted chain, no HSTS, and no documented rotation process.
- `force_ssl` is commented out in both `config/application.rb` and `config/environments/production.rb`, so the app does **not** redirect HTTP→HTTPS. Thin only listens with `--ssl` on `3000`; plain HTTP to `3000` will not be served correctly.
- The PDF worker shells out with `curl --insecure` (`app/models/workers/pdf_generator.rb:35`), explicitly disabling TLS verification for the callback. See **09 - Operation Execution Flow** for the full async picture.

## The MySQL 8.2 vs Old-Client Tension

This is the single most fragile part of the infrastructure and the most likely thing to bite you.

- The **server** is `mysql:8.2` (`docker-compose.yml:4`).
- The **client driver** is `mysql2 0.3.21` (`Gemfile.lock:107`; Gemfile requests `~> 0.3.20`, `Gemfile.lock:301`). The 0.3.x series predates MySQL 8's default `caching_sha2_password` auth and the newer wire protocol.
- The Compose workaround is `command: --default-authentication-plugin=mysql_native_password` (`docker-compose.yml:6`).

Why this is fragile:

1. In **MySQL 8.2 the `--default-authentication-plugin` server option is deprecated** (replaced by `authentication_policy`). It still works for now but will eventually be removed.
2. That flag only sets the default plugin for **newly created** users. The `root` user that actually authenticates lives in the **already-seeded `./databases/mysql` datadir**, so its stored auth plugin — not the compose flag — determines whether login succeeds.
3. A MySQL 8.x point upgrade, or any user created with `caching_sha2_password`, can break auth for the ancient `mysql2 0.3.21` client with no warning.

**Unverified / to confirm:** the actual auth plugin recorded for the `root` user inside the existing `./databases/mysql` datadir (`mysql_native_password` vs `caching_sha2_password`). This is datadir state, not visible in source. If you ever wipe and re-seed, confirm the seeded `root` ends up on `mysql_native_password`.

Investigation commands for this tension are in the section below.

## Missing Resque Workers in Compose

Resque is fully *wired* but nothing *runs* the consumers in the Dockerized setup.

What exists:

- Gems bundled: `resque 1.25.2`, `resque-scheduler 4.0.0` (`Gemfile.lock:198,204`).
- Redis configured: `config/resque.yml` points dev+prod at `redis://redis:6379/`; `config/initializers/resque.rb:5-6` sets `Resque.redis` and namespace `resque:task`.
- Web UI mounted: `mount Resque::Server.new, :at => "/resque"` (`config/routes.rb:1,5`) — **with no authentication wrapper**.
- Producers in code: `Task.enqueue` -> `Resque::Job.create(queue, self, params)` (`app/models/task.rb:29-33`); `Job::JobTest` via `Resque.enqueue`; worker classes `PdfGenerator` (`app/models/workers/pdf_generator.rb`) and `CMDTask` (`app/models/workers/exec.rb`).
- Rake task enabling workers: `require "resque/tasks"` (`lib/tasks/resque.rake:1`), enabling `rake resque:work`.

What is missing:

- **No Compose service runs a worker.** Only `web` (Thin) is launched (`docker-compose.yml:27-41`). There is no `bundle exec rake resque:work QUEUE=...` service and no `resque-scheduler` daemon.

Net effect: enqueued jobs accumulate in Redis under namespace `resque:task` and are **never dequeued or executed**. Combined with Redis having no persistent volume, the queue is doubly unreliable — jobs that never run, and a queue that vanishes on container recreation.

`resque-scheduler` is also effectively dormant: it is in the Gemfile but there is no `schedule.yml`, no `resque/scheduler` require, and no `enqueue_at`/`enqueue_in` calls anywhere in app/lib/config. Treat any expectation of cron/delayed jobs as **unimplemented**.

**Unverified / to confirm:** whether a worker/scheduler is started **out of band** in the real deployment (e.g. a manual `nohup rake resque:work` on the host — hinted at by `.dockerignore` listing `nohup.out`, `.dockerignore:7`). This cannot be confirmed from the repo. If you adopt this system, the first thing to check on the live host is `ps aux | grep resque`.

To actually run background jobs, add a worker service sharing the same image/build and environment, e.g.:

```yaml
# Suggested addition to docker-compose.yml — NOT currently present
worker:
  build: .
  command: bash -c "bundle exec rake resque:work QUEUE='*'"
  volumes:
    - .:/docker_app
  depends_on:
    - db
    - mongo
    - redis
  restart: always
```

## Mongo Connection Wiring (confusing, by design)

There are three Mongo-related config sources and they do not agree. Knowing the precedence matters because the "configured" DB names are largely vestigial.

| Source | What it says | Actually used? |
|---|---|---|
| `config/mongo.yml` | host `mongo:27017`, db `esmx_development`/`esmx` | **No** — not read by any initializer |
| `config/initializers/mongodb.rb` | `ENV['MONGOHQ_URL']` or hardcoded `mongodb://mongo/xxxxxxxx`; sets `MongoMapper.database = "palette-<env>"` | **Yes** — this opens the boot-time connection |
| `config/initializers/mongomapper.rb` | would read non-existent `config/mongodb.yml`, but behind an `unless` guard that is already satisfied | Effectively a no-op at boot |

At boot, `mongodb.rb` (alphabetically first) connects and sets the database to `palette-development` (`config/initializers/mongodb.rb:3-13`). But **per request**, `EsmProxyController#index` overrides this with `MongoMapper.database = @current_solution.db_name` (`esm_emr-<solution>`). So the configured names (`esmx_development`, `palette-*`, `xxxxxxxx`) are not what serves real per-tenant data — the request-time override is. See **04 - Database Structure** and **05 - Core Domain Models** for `db_name` and the per-solution database model.

**Unverified / to confirm:** whether `MONGOHQ_URL` / `MONGO_USERNAME` / `MONGO_PASSWORD` are injected at runtime in production. They are referenced (`config/mongo.yml:23-24`, `config/initializers/mongodb.rb:4`) but **unset** in `docker-compose.yml` (the `mongo` service has no auth env), so the hardcoded `mongodb://mongo/xxxxxxxx` fallback is likely what runs. Mongo has no authentication in this Compose setup.

## Boot & Connection Sequence (infrastructure view)

```
docker compose up
  ├─ db (mysql:8.2)   first run: create soup_esm_emr -> run seed.sql (skipped if datadir exists)
  ├─ mongo (3.2)      mount ./databases/mongo
  ├─ redis (latest)   no volume (ephemeral)
  └─ web              entrypoint.sh: rm server.pid -> exec compose command
                        └─ bundle exec thin start --ssl :3000
                             └─ Rails boot (development env)
                                  ├─ ActiveRecord -> mysql2 -> host db (soup_esm_emr)
                                  ├─ mongodb.rb -> MongoMapper.connect (palette-<env>)
                                  │                (overridden per-request to esm_emr-<solution>)
                                  └─ resque.rb -> Resque.redis @ redis:6379 ns resque:task
```

## Key Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Service topology, ports, volumes, `depends_on`, and the Thin+SSL web command (`:29`) |
| `Dockerfile` | Web image build: ruby:2.3, archived Stretch apt, native deps, bundler 1.17.3, TZ, entrypoint |
| `seed/Dockerfile` | DB seed image: `FROM mysql:8.2`, `MYSQL_DATABASE=soup_esm_emr`, `COPY seed.sql` |
| `seed/seed.sql` | ~20MB MySQL 5.5.31-era dump; auto-loaded only on a fresh datadir |
| `entrypoint.sh` | Clears `tmp/pids/server.pid`, then `exec "$@"` |
| `.dockerignore` | Excludes `.git`, `databases`, `tmp`, `log`, `*.log`, `.DS_Store`, `nohup.out` from build context |
| `config/database.yml` | mysql2 -> host `db`, `soup_esm_emr`, `root`/`minadadmin` (dev+prod); test = sqlite3 |
| `config/mongo.yml` | MongoMapper defaults (host `mongo`) — not actually read by initializers |
| `config/initializers/mongodb.rb` | Real Mongo wiring: `MONGOHQ_URL` or `mongodb://mongo/xxxxxxxx`, db `palette-<env>` |
| `config/resque.yml` / `config/initializers/resque.rb` | Redis endpoints + namespace `resque:task` |
| `lib/tasks/resque.rake` | `require "resque/tasks"` — enables `rake resque:work` (never invoked by Compose) |
| `config/ssl/server.crt`, `config/ssl/private.key` | Self-signed TLS material read by Thin |

## Gotchas / Risks

- **Resque workers are never started.** Jobs queue in Redis (`resque:task`) and never run. Redis has no volume, so the queue is also lost on recreation. Add a worker service or run `rake resque:work` out of band. (`docker-compose.yml:27-41`)
- **MySQL 8.2 + mysql2 0.3.21 mismatch.** Held together by the deprecated `--default-authentication-plugin=mysql_native_password` flag, which only affects new users — the seeded `root` user's stored plugin governs real logins. Fragile across any MySQL 8.x upgrade. (`docker-compose.yml:6`, `Gemfile.lock:107`)
- **Seed only runs on a FRESH datadir.** `./databases/mysql` is already populated, so `docker-entrypoint-initdb.d/seed.sql` is **skipped** on every run after the first. Re-seeding requires wiping `./databases/mysql` (and re-confirming the auth plugin afterward). (`seed/Dockerfile:10`)
- **App boots in development, not production.** No `-e production` on the Thin command means class reloading, verbose logs, live asset compilation, and full error pages (info leak risk). (`docker-compose.yml:29`)
- **Source bind-mount shadows the image.** The container is not self-contained for deployment; running code is whatever is on the host. (`docker-compose.yml:33-34`)
- **Self-signed TLS at Thin, no proxy, no HTTP→HTTPS redirect.** `CN=localhost`, valid to 2036, `force_ssl` commented out. Clients will see cert warnings. (`config/ssl/server.crt`)
- **Unauthenticated Resque dashboard at `/resque`.** Mounted with no auth wrapper; leaks queue internals and (via job creation) can be abused to enqueue `CMDTask`, which `eval`s arbitrary Ruby. See **09 - Operation Execution Flow** and **03 - Authentication & Authorization**. (`config/routes.rb:5`, `app/models/workers/exec.rb:11`)
- **Hardcoded / reused weak credentials.** `MYSQL_ROOT_PASSWORD: minadadmin` in compose (`:11`), same `root`/`minadadmin` in `config/database.yml`, and `minadadmin` reused as the XMPP password in `config/initializers/esm.rb`. Mongo has no auth in this setup.
- **All data ports published to the host.** `3316` (MySQL), `27117` (Mongo), `6379` (Redis), `3000` (web) are all bound to the host; the host firewall is the only barrier.
- **No healthchecks; `depends_on` is start-order only.** `web` may crash-loop until MySQL finishes its slow first-run import; functional but noisy. (`docker-compose.yml:38-41`)
- **EOL build base.** Debian Stretch from `archive.debian.org` with cert/date checks disabled and unauthenticated apt — a reproducibility and supply-chain risk. (`Dockerfile:1-10`)
- **Mongo config is split and misleading.** Effective runtime DB is `esm_emr-<solution>` (set per request), not the `esmx_*` or `palette-*` names in the config files.

## Investigation Commands

Run these on the host where the stack is deployed. They are read-only unless noted.

### Stack state and logs

```bash
# What is actually running (note: NO worker container should appear)
docker compose ps

# Tail the web app (will show development-mode logging)
docker compose logs -f web

# Confirm the web process is Thin with --ssl (not Puma, not production)
docker compose exec web ps aux | grep -E 'thin|puma'

# Confirm timezone baked into the image
docker compose exec web date
docker compose exec web cat /etc/timezone
```

### MySQL 8.2 vs old-client tension

```bash
# Confirm server version
docker compose exec db mysql -uroot -pminadadmin -e "SELECT VERSION();"

# THE key check: what auth plugin is the root user actually using in the seeded datadir?
docker compose exec db mysql -uroot -pminadadmin \
  -e "SELECT user, host, plugin FROM mysql.user;"

# Confirm the deprecated default-authentication-plugin flag is in effect
docker compose exec db mysql -uroot -pminadadmin \
  -e "SHOW VARIABLES LIKE 'default_authentication_plugin'; SHOW VARIABLES LIKE 'authentication_policy';"

# Confirm the app can actually connect through mysql2 0.3.21
docker compose exec web bundle exec rails runner 'puts ActiveRecord::Base.connection.execute("SELECT VERSION()").first'

# Confirm the seeded schema is present
docker compose exec db mysql -uroot -pminadadmin soup_esm_emr -e "SHOW TABLES;"
```

### Seeding behaviour

```bash
# Is the datadir already populated? (If yes, seed.sql will NOT re-run)
ls -la ./databases/mysql | head

# Origin/version of the dump (expect MySQL 5.5.31, no CREATE DATABASE)
head -5 seed/seed.sql

# DANGER (destructive): to FORCE a re-seed you must wipe the datadir first.
# Take a backup, then:
#   docker compose down
#   rm -rf ./databases/mysql
#   docker compose up db
# After re-seed, re-run the mysql.user plugin check above.
```

### Resque / background jobs

```bash
# Confirm Redis is reachable and namespaced
docker compose exec redis redis-cli KEYS 'resque:task*'

# Inspect queued (but un-consumed) jobs
docker compose exec redis redis-cli LRANGE 'resque:task:queue:default' 0 -1
docker compose exec redis redis-cli LRANGE 'resque:task:queue:task' 0 -1

# Is ANY worker running? (In stock Compose this returns nothing — that's the bug)
docker compose exec web ps aux | grep -i resque
ps aux | grep -i resque   # also check the host, in case workers run out-of-band

# Resque web dashboard (unauthenticated) is at:
#   https://<host>:3000/resque
```

### Mongo connection reality check

```bash
# Confirm Mongo server version (pinned 3.2)
docker compose exec mongo mongo --eval 'db.version()'

# List databases — expect per-solution 'esm_emr-<name>' DBs, NOT 'esmx_*'/'palette-*'
docker compose exec mongo mongo --eval 'db.adminCommand("listDatabases")'

# What DB name does the app actually resolve at boot vs per request?
docker compose exec web bundle exec rails runner 'puts MongoMapper.database.name'
```

### SSL material

```bash
# Verify the cert subject and validity window
openssl x509 -in config/ssl/server.crt -noout -subject -dates

# Confirm key/cert pair match (modulus hashes must be equal)
openssl x509 -noout -modulus -in config/ssl/server.crt | openssl md5
openssl rsa  -noout -modulus -in config/ssl/private.key | openssl md5
```

### Build / image hygiene

```bash
# Rebuild the web image (e.g. after Gemfile changes)
docker compose build web

# Verify pinned versions inside the image
docker compose run --rm web bundler --version          # expect 1.17.3
docker compose run --rm web bundle show mysql2          # expect 0.3.21
docker compose run --rm web ruby -v                     # expect 2.3.x
```

