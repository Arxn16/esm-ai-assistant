# 09 - Development Guide

> **Audience:** any engineer (human or AI) making changes to the ESM legacy EMR/EHR platform.
> **Status:** documentation only — this file prescribes *how* to work on the codebase. It changes no application code.
> **Golden rule:** this is a **production healthcare system**. Safety and stability outweigh speed. When in doubt, stop and ask.
>
> Read this alongside the rest of the set: **00 - System Overview** (orientation), **04 - Database Structure** (the two stores), **06 - Docker & Infrastructure** (the runtime), **07 - Metadata-Driven Architecture** and **08 - Operation Execution Flow** (the runtime `eval` engine that is the heart — and the chief risk — of the platform). Every constraint below is grounded in `Gemfile.lock`, the `config/` files, and the analysis in those documents.

---

## 0. The operating contract (read first)

For **every** change request, in order:

1. **Consult `doc/understanding/` first** — find the relevant doc(s) before touching code.
2. **Verify assumptions against source** — never trust the docs (or memory) over the actual files; the docs flag unconfirmed items as *(unverified / to confirm)*.
3. **Explain impact** — architecture impact, affected modules, affected database models (distinguish **MySQL metadata** vs **MongoDB runtime data**), and risks.
4. **Produce a plan** — an implementation plan plus an explicit list of files to modify.
5. **Wait for approval** — do not change application code until the plan is approved.

When approved: **minimize changes**, **do not refactor unrelated code**, **follow existing style**, and stay **Ruby 2.3 / Rails 4.2 compatible**.

> **Metadata vs. code — decide this early for every task.** Much ESM behavior is defined as *data* (rows in `esm_services`/`esm_operations`/`esm_tables`/`esm_documents`), not as Ruby in this repo. A change may be (a) a **metadata edit** (no deploy; takes effect on the next request; edited via the workspace UI or DB) or (b) a **Ruby/code change** (needs image rebuild + redeploy). Classify the task before planning. Editing metadata is also an **RCE surface** (see §5, and **07**/**08**) — treat it with the same care as code.

---

## 1. Project coding standards

These are derived from the existing code; the overriding standard is **consistency with the surrounding file**.

- **Match the file you're in.** Naming, indentation (the codebase mixes tabs/spaces — match the local block), quoting, and structure should look like the code already there. Do not reformat existing lines you aren't changing.
- **No new dependencies without approval.** The `Gemfile` is frozen against ancient transitive pins (see §2/§3). Adding a gem risks an unresolvable `bundle install` on Ruby 2.3 / bundler 1.17.3. Prefer stdlib or existing helpers.
- **Mass assignment uses `protected_attributes`, not strong params.** The app bundles `protected_attributes (1.0.8)` — the Rails-3-style model. Use `attr_accessible` in models as the existing models do; **do not** introduce `params.require(...).permit(...)`. (See §2.)
- **Controllers use the `*_filter` family.** Existing controllers use `before_filter` / `skip_before_filter` (e.g. `EsmProxyController` does `skip_before_filter :verify_authenticity_token`, `app/controllers/esm_proxy_controller.rb:4`). Keep a file internally consistent — don't mix `before_action` into a `before_filter` file.
- **Comments only where they earn their place.** Match the (low) comment density of the surrounding code. Explain *why*, not *what*.
- **Keep dynamic code (metadata) minimal and reviewed.** When authoring `Operation.command` / `Table.data` / `ScriptTemplate` generators, remember the text is `eval`'d verbatim. Keep it small, deterministic, and free of user-controlled interpolation.
- **Encoding & time.** Templates are UTF-8 (`config.encoding = "utf-8"`, `config/application.rb`). The app forces `Time.zone` to Asia/Bangkok per request (`EsmController#context_filter`) and the image is built with `TZ=Asia/Bangkok` (`Dockerfile`). Date fields apply a Buddhist-calendar correction (`Document#filter_record_params`, see **05**/**07**) — be careful with date math.
- **Logging over swallowing.** The proxy already `rescue Exception` → emails (XMPP) → renders `public/500.html` (`app/controllers/esm_proxy_controller.rb:82-101`). Don't add more broad rescues that hide failures; prefer letting errors surface to logs.

---

## 2. Rails 4.2 constraints

The app is pinned to **`rails (= 4.2.0)`** (`Gemfile.lock:149`, `Gemfile`). Do **not** use Rails 5+ APIs or idioms:

| Don't (Rails 5+) | Do (Rails 4.2) |
|---|---|
| `params.require(:x).permit(...)` (strong params) | `attr_accessible` via `protected_attributes` (already bundled) |
| `class Foo < ApplicationRecord` | `class Foo < ActiveRecord::Base` |
| `class AddX < ActiveRecord::Migration[5.2]` (versioned migration) | `class AddX < ActiveRecord::Migration` (no `[x.y]` suffix — see `db/migrate/*`) |
| `throw(:abort)` to halt a callback | `return false` halts the callback chain in 4.2 |
| `render plain:` everywhere / removing `render text:` | `render text:` / `render inline:` still valid (the proxy renders via `render inline:`) |
| `belongs_to` required by default | `belongs_to` is **optional** by default in 4.2 — no `optional: true` exists |
| `ActionController::Parameters` as non-hash | params still behave hash-like here (strong params are disabled by `protected_attributes`) |

Other 4.2-era facts to respect:
- **Routing** uses `match '...' , via: [:get, :post]` heavily (`config/routes.rb`) — keep that style; `match` without `via:` is already disallowed in 4.x.
- **Observers** come from the `rails-observers` gem (extracted from core in Rails 4) — `app/models/*observer` patterns rely on it.
- **Caching gems** `actionpack-action_caching` / `actionpack-page_caching` are external gems here (also extracted from core).
- **Mailers / ActiveJob** are 4.2 (`actionmailer 4.2.0`, `activejob 4.2.0`) — but async work in this app goes through **Resque directly**, not ActiveJob (see **08**).
- Erubis (`erubis 2.7.0`) is the ERB engine behind `render inline:` and the metadata templates.

---

## 3. Ruby 2.3 constraints

The Docker base image is **`ruby:2.3`** (`Dockerfile:1`), Debian Stretch (archived apt repos). Bundler is pinned to **`1.17.3`** (`Dockerfile`, `Gemfile.lock` `BUNDLED WITH 1.17.3`). Write **Ruby 2.3-compatible** syntax only.

**Available in 2.3 (OK to use):** safe-navigation `&.`, `Hash#dig` / `Array#dig`, `frozen_string_literal` magic comment, squiggly heredocs `<<~`, `Comparable` basics, keyword args. (Prefer the style already in the file over introducing new idioms.)

**NOT available — do not use:**
- 2.4+: `String#match?`, `Integer#digits`, `Comparable#clamp`, `Hash#transform_values`, `Array#sum` (use `inject(:+)`), unified `Integer`.
- 2.5+: `Hash#slice`, `yield_self`, `Array#append`/`prepend`, `rescue`/`else` inside blocks, `Dir.children`, `String#delete_prefix`/`delete_suffix`.
- 2.6+: `then`, endless ranges `(1..)`, `Enumerable#filter_map`, `Array#union`/`difference`.
- 2.7+: pattern matching (`case/in`), numbered block params `_1`, beginless ranges.
- 3.0+: rightward assignment, `Hash#except`, endless method defs, keyword-argument separation semantics, Ractor.

**Bundler discipline:** run `bundle _1.17.3_ install` (the pinned version) as the Dockerfile does. A bare `bundle install` with a newer bundler can rewrite `Gemfile.lock` and break the build. Native gems (`mysql2`, `bson_ext`, `nokogiri 1.6.8.1`, `therubyracer`/`libv8 3.16`, `nokogiri-xmlsec-instructure`) compile against the system libs installed in the image — changing them is high-risk.

---

## 4. Docker workflow

Topology (see **06** for detail): `db` (mysql:8.2, built from `./seed`), `mongo` (mongo:3.2), `redis` (redis:latest), `web` (this app, Thin + SSL). Use `docker compose` (or `docker-compose` on older hosts).

```bash
# Build & start everything
docker compose build
docker compose up -d

# Tail the app logs
docker compose logs -f web

# Shell into the web container
docker compose exec web bash

# Rails console (mind the environment — see note below)
docker compose exec web bundle exec rails console

# DB shells
docker compose exec db    mysql -uroot -pminadadmin soup_esm_emr
docker compose exec mongo mongo                # legacy 3.2 shell

# Resque worker (NOT started by compose — must be launched manually)
docker compose exec web bundle exec rake resque:work QUEUE=task,job,default
```

**Ports (host → container):** `3000→3000` (web, HTTPS), `3316→3306` (MySQL), `27117→27017` (MongoDB), `6379→6379` (Redis). Web serves **HTTPS** via Thin with `config/ssl/private.key` + `config/ssl/server.crt` — use `https://localhost:3000`.

**Critical Docker gotchas (verify before relying on the environment):**
- **Source is bind-mounted** (`volumes: - .:/docker_app` in `docker-compose.yml`) over the image's baked-in copy, so local edits are live **without rebuild** — but a fresh `bundle install` still requires a rebuild.
- **Resque workers and the scheduler are NOT in `docker-compose.yml`.** Enqueued jobs pile up in Redis and never run unless a worker is launched (the `.gitignore` entry `nohup.out` hints the real deployment uses `nohup ... rake resque:work`). `resque-scheduler` is bundled but unwired (see **08**).
- **Redis has no volume** — its data (queued jobs) is ephemeral and lost on container recreation.
- **Environment is likely `development`.** The active `web` command runs `thin start --port 3000 --ssl ...` **without `-e production`**, and nothing sets `RAILS_ENV`. Confirm the intended environment before treating prod-only config as active. *(unverified — confirm against the real deployment)*

---

## 5. Database safety rules

There are **two** databases with very different change models. Know which you're touching.

### MySQL (`soup_esm_emr`) — the metadata catalog
- **Schema changes go through migrations.** Add a new file under `db/migrate/` (`class X < ActiveRecord::Migration`, no version suffix), then `docker compose exec web bundle exec rake db:migrate`. Always provide a working **`down`/rollback** (use `change` only when truly reversible).
- **Never drop or truncate `esm_*` tables.** They hold the *definitions of the running applications* (`esm_projects`, `esm_services`, `esm_operations`, `esm_tables`, `esm_documents`, `esm_schemas`, …). Dropping them deletes customer applications, not just data. See **04**/**05**.
- **`data`/`command` columns are `TEXT`** (e.g. `esm_documents.data`, `esm_tables.data`). Large form/field definitions can be silently truncated — corrupting the dynamic schema. Watch payload size.

### MongoDB (`esm_emr-<solution>`) — runtime data + GridFS
- **No migrations.** Collections and their "schema" are generated at runtime from `esm_tables.data` (`Schema#load_model`, see **07**). To change a collection's shape you change the `Table` metadata in MySQL — the MongoDB side follows automatically on next load.
- **GridFS holds binaries** (attachments, generated PDFs, images). Don't manipulate `fs.*` chunks directly.

### Before any database-affecting change
1. **Back up both stores** (volumes `./databases/mysql`, `./databases/mongo`):
   ```bash
   docker compose exec db mysqldump -uroot -pminadadmin soup_esm_emr > backup_$(date +%F).sql
   docker compose exec mongo mongodump --out /dump        # writes to ./databases/dump
   ```
2. State **tables/models/queries affected** and the **rollback** in the plan.
3. **Never** delete production data or change schema without an explicit, approved explanation.
4. Treat any edit to `Operation.command`, `Table.data`/`command`, or `Field.params` as **both** a behavior change **and** a code-execution surface (it is `eval`'d). Review it like code; never interpolate untrusted input into it.

---

## 6. Deployment checklist

Because several required files are **gitignored** (`config/initializers/esm.rb`, `config/database.yml`) or **untracked** (`config/ssl/`), a clean checkout is **not** deployable as-is. Confirm each item:

- [ ] **Secrets/config present on host** (not from git): `config/initializers/esm.rb` (defines `MONGO_PREFIX`, `DOMAIN`, etc.), `config/database.yml`, `config/mongo.yml`, `config/resque.yml`.
- [ ] **SSL certs present**: `config/ssl/private.key` and `config/ssl/server.crt` (the Thin `--ssl` flags reference them).
- [ ] **Backups taken** of `./databases/mysql` and `./databases/mongo` (see §5).
- [ ] **Image builds** with bundler `1.17.3` on `ruby:2.3` (`docker compose build` succeeds; native gems compile).
- [ ] **Dependencies up before web**: `db`, `mongo`, `redis` healthy (compose `depends_on` only orders start, not readiness — verify MySQL accepts connections, esp. the `mysql_native_password` plugin flag).
- [ ] **Migrations applied**: `rake db:migrate` (and confirm `db/schema.rb` version).
- [ ] **Resque worker(s) started** (manually — not in compose) for `task,job,default`; decide on `nohup`/supervisor and on the scheduler if delayed jobs are needed.
- [ ] **Environment confirmed** (`development` vs `production`) and matches intent (see §4 gotcha).
- [ ] **Smoke test over HTTPS**: a known `/:solution/:project/:service/:opt` route renders; `/resque` dashboard reachable (and, ideally, access-restricted — it is currently unauthenticated, see **08**).
- [ ] **Timezone** is Asia/Bangkok in the container.

> Roll-forward only after the smoke test passes. Keep the previous image tag and the DB backups for rollback.

---

## 7. Common debugging workflow

1. **Reproduce and read logs first.** `docker compose logs -f web`; app logs under `log/` (gitignored). Remember the proxy **swallows exceptions** into an XMPP email + `public/500.html` (`app/controllers/esm_proxy_controller.rb:82-101`), so the user-visible 500 may hide the real trace — check stdout/logs and the rescued message.
2. **Locate the entry point.** Almost all app requests go through `EsmProxyController#index`. Identify the resolved `Service` package and `params[:opt]` from the URL (see **02**).
3. **Decide code vs metadata.** If the failing logic is an operation, it lives in `esm_operations.command` (data), compiled by `Service#load` — *not* in a controller. Inspect the actual `Operation`/`Service` row.
4. **Reproduce in console.**
   ```ruby
   s = Service.get("solution.project.ServiceName")
   # inspect s.operations, s.extended, etc.
   ```
   For runtime data, set the tenant DB first: `MongoMapper.database = Esm.find_by_name("...").db_name`, then query the generated model via `project.load_model[:table_name]` (see **07**).
5. **Eval'd-code errors are awkward.** Backtraces point into `(eval)` strings. Narrow by reading the offending `Operation.command` / `Table.data`; reproduce the generated source with `Service#load` logic if needed.
6. **Async jobs.** Inspect queues/failures at the **`/resque`** dashboard, or in Redis. If jobs "don't run," confirm a worker process is actually running (see §4).
7. **Datastore checks.** MySQL via `mysql` shell; MongoDB via the 3.2 `mongo` shell (legacy syntax); GridFS files referenced by `ObjectId`.
8. **No cache to fight.** `Service#load` has caching disabled (`cache = false`), so edits to metadata take effect on the next request — handy for debugging, costly for performance (see **07**).

---

## 8. Git workflow

- **Default branch is `master`.** Create a topic branch for changes; never commit directly to `master` for non-trivial work. Keep commits scoped and descriptive.
- **Commit/push only when the user asks.** Per the operating contract, code changes wait for approval; commits are a separate, explicit step.
- **Never commit secrets or data.** `.gitignore` already excludes `config/initializers/esm.rb`, `config/database.yml`, `/databases/*`, `/log/*`, `/tmp/*`, `nohup.out`, `/public/esm/*`, `/public/assets/*`. Do **not** add credentials, SSL keys (`config/ssl/`), or DB dumps.
- **Beware already-tracked sensitive files.** `.gitignore` does not untrack files already in history. `config/database.yml` and `config/initializers/mongodb.rb` show as tracked/modified — review diffs carefully so you don't commit environment-specific credentials. If a secret must change, coordinate rather than committing it.
- **Review the diff before every commit** (`git diff`), confirm only intended files changed, and confirm no unrelated reformatting crept in.
- **Commit message trailer** (project convention for AI-authored commits):
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  ```

---

## 9. Feature implementation workflow

The end-to-end loop for any feature or fix:

1. **Understand** — read the relevant `doc/understanding/` doc(s); restate the requirement.
2. **Verify** — confirm current behavior in source (controllers, models, and — crucially — the relevant `esm_services`/`esm_operations`/`esm_tables` metadata).
3. **Classify** — is this a **metadata change** (runtime, no deploy) or a **Ruby/code change** (rebuild + deploy)? Prefer the smallest mechanism that fits, but never put untrusted input into eval'd metadata.
4. **Impact analysis** — present:
   - **Architecture impact** (which layer: proxy/dispatch, metadata engine, ORM, async, view).
   - **Affected modules** (files + the generated-class chain, if relevant).
   - **Affected database models** (MySQL metadata tables and/or MongoDB collections — name them).
   - **Risks** (security/RCE surface, multi-tenant `MongoMapper.database` global state, performance from per-request `eval`, data integrity, backward compatibility).
5. **Plan + file list** — a concrete, minimal implementation plan and the exact files to modify.
6. **Approval gate** — **wait** for the user to approve before editing application code.
7. **Implement** — minimal, style-preserving, Ruby 2.3 / Rails 4.2-compatible changes; no unrelated refactors; search for references before changing shared code.
8. **Validate** — provide commands to test (console reproduction, targeted request over HTTPS, `rake` tasks, log inspection). Run them where possible and report real results.
9. **Document the change** — files modified, what changed, validation steps, risks, and a **rollback plan**.
10. **Update the docs** — if the change alters architecture, request flow, the data model, or the runtime engine, update the relevant `doc/understanding/` file in the same change so the documentation stays the source of truth.

---

## Key references

| Concern | Where |
|---|---|
| Versions / pins | `Gemfile`, `Gemfile.lock` (`rails 4.2.0`, `mysql2 0.3.21`, `mongo 1.12.5`, `mongo_mapper 0.14.0`, `resque 1.25.2`, bundler `1.17.3`) |
| Runtime / containers | `Dockerfile`, `docker-compose.yml`, `entrypoint.sh`, `seed/` → **06** |
| Env config | `config/environments/production.rb` (`consider_all_requests_local`, `serve_static_assets=false`, `eager_load`), `config/application.rb` |
| Datastores | `config/database.yml`, `config/mongo.yml`, `config/resque.yml`, `db/schema.rb`, `db/migrate/` → **04** |
| Dispatch / engine | `app/controllers/esm_proxy_controller.rb`, `app/models/service.rb`, `app/models/schema.rb` → **02**/**07**/**08** |
| Secrets (gitignored) | `config/initializers/esm.rb`, `config/database.yml`, `config/ssl/` |

---

## Gotchas this guide assumes you've internalized

- **Runtime `eval` of operator-editable metadata = designed-in RCE.** Authoring metadata is equivalent to writing code that runs in the web/worker process. (See **07**/**08**.)
- **CSRF disabled** on the proxy; **`/ws/*`** has no ACL; **`/resque`** is unauthenticated; PDF worker shells out with `curl --insecure`. Don't widen these; consider narrowing them in security work.
- **`MongoMapper.database` is global per-request state** — safe only under single-threaded Thin. Do not introduce threaded servers or background threads that touch Mongo without re-binding the database.
- **No class cache** — every request regenerates and `eval`s the service class hierarchy (including the layout/home service). Performance work starts here.
- **Several gems are bundled but unused** (`saml2`, `omniauth*`, `rest-graph`, `roo`, `parallel`) — don't assume SSO/import features exist; verify before building on them.
