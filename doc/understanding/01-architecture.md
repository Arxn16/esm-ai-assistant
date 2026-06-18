# 01 - Architecture

> **Audience:** the senior engineer taking full ownership of the ESM legacy EMR platform.
> **Scope of this doc:** layering, boot sequence, the dual-ORM design, custom libs/initializers, the gem inventory and what each gem is actually for, and the server/SSL story. Request dispatch, the metadata-driven runtime, auth, the data stores, and deployment each have their own companion documents (see cross-references inline). Everything below is grounded in the source; anything the readers could not confirm is flagged **unverified / to confirm**.

## 1. What ESM is, in one paragraph

ESM is a **Rails 4.2.0 / Ruby 2.3** application (module `Esmx`, `config/application.rb:12`) that builds a runtime, **metadata-driven "platform"** on top of stock Rails MVC. Instead of shipping fixed models and controllers, ESM stores the *definition* of each hosted application as rows in MySQL and then **code-generates and `eval`s real Ruby classes per request**. This produces a hard architectural split worth internalizing on day one:

- **MySQL (ActiveRecord)** holds the **metadata catalog** — the rows that *describe* applications (`Esm > Project > Service > Operation`, `Schema > Table`, `Document/Field`, plus `User/Role`, etc.). All of these are `ActiveRecord::Base` subclasses bound to `esm_*` tables.
- **MongoDB (MongoMapper 0.14 + raw GridFS)** holds the **runtime application data and uploaded files**, in a *per-solution* Mongo database.

A request to `EsmProxyController` resolves a `Service` from the metadata, `Service#load` (`app/models/service.rb:126`) builds a Ruby class on the fly via ERB string templates + `eval`, instantiates it, and dispatches `obj.send(params[:opt], params)`. Applications are literally compiled and eval'd on each request. The deep mechanics of that live in **"06 - Metadata-Driven Architecture"** and **"07 - Operation Execution Flow"**; this doc covers the bones that hold it up.

---

## 2. Layered architecture

```
+-----------------------------------------------------------+
|  Thin (HTTPS :3000, self-signed cert)  [docker web svc]   |
+-----------------------------------------------------------+
|  Rack / Rails 4.2 middleware  (+ mounted Resque::Server)  |
+-----------------------------------------------------------+
|  Routes (config/routes.rb) -> EsmProxyController (front)  |
|  EsmController#context_filter: solution/project/user/zone |
+----------------------------+------------------------------+
|  AR METADATA LAYER (MySQL) |  RUNTIME GEN LAYER           |
|  Esm>Project>Service>      |  Service#load -> ERB+eval    |
|  Operation>Schema>Table>   |  => app class; obj.send(opt) |
|  Document>Field, User/Role |  Schema#load_model -> ERB+   |
|  (esm_* tables)            |  eval => MongoMapper classes |
+----------------------------+------------------------------+
|  DATA LAYER                                               |
|  MySQL (mysql2)        MongoDB (mongo 1.x + MongoMapper)  |
|  soup_esm_emr          per-solution DB (db_name) + GridFS |
|  Redis (Resque jobs: Task/Job/PdfGenerator/CMDTask)       |
+-----------------------------------------------------------+
```

The three layers to keep distinct in your head:

| Layer | Backing store | What lives here |
| --- | --- | --- |
| **Metadata / definition** | MySQL via ActiveRecord (`esm_*` tables) | The *definitions* of applications: solutions, projects, services, operations, schemas, tables, document/field layouts, users, roles, templates, menus, settings, logs. See **"05 - Core Domain Models"**. |
| **Runtime code-generation** | None (in-memory) | `Service#load` and `Schema#load_model` ERB-render Ruby source from metadata and `eval` it per request. The actual behavior objects and the actual ORM classes both materialize here. |
| **Runtime data** | MongoDB + GridFS (per solution), Redis (jobs) | End-user records in `<project>.<table>` collections, binary uploads in GridFS, queued jobs in Redis. See **"04 - Database Structure"**. |

The single front controller is `EsmProxyController`; `EsmController#context_filter` resolves the tenant/solution, project, user, role, and forces the timezone before any dynamic action runs (`app/controllers/esm_controller.rb:12`). Request-flow details are in **"02 - Request Flow & Routing"**.

### Per-solution Mongo database selection at runtime

```
 request -> EsmController#context_filter (resolve @current_solution)
        -> EsmProxyController#index
             MongoMapper.database = @current_solution.db_name   # 'esm_emr-<name>'
             Service.get(package) -> Service#load (eval class)
             obj.send(opt, params)
             models read/write '<project>.<table>' collections + GridFS
```

`MongoMapper.database` is mutated as **global per-request state** (`app/controllers/esm_proxy_controller.rb:20`). This is only "safe" because Thin is single-threaded/evented — see Gotchas.

---

## 3. Boot sequence

Boot is standard Rails plumbing with two custom hooks. The chain:

```
config.ru
  -> require config/environment.rb
       -> require config/application.rb
            -> require config/boot.rb            (bundler/setup)
            -> require 'rails/all'
            -> Bundler.require(:assets in dev/test)
            -> module Esmx; class Application < Rails::Application
            -> Bundler.require(:default, Rails.env)
       -> Esmx::Application.initialize!
            -> run config/initializers/* in ALPHABETICAL order:
                 backtrace_silencers, esm.rb (constants), esm_lib.rb
                   (def msg_report; require esm_essential -> require basic_auth
                    + autoload_paths mutate; require esm_scaffold),
                 inflections, mime_types,
                 mongodb.rb (MongoMapper.connect, db=palette-<env>),
                 mongomapper.rb (logger off; prints Initialized),
                 resque.rb (Redis ns resque:task),
                 secret_token, session_store(_esmx_session), wrap_parameters
  -> run Rails.application  (served by Thin --ssl :3000)
```

Things to be precise about:

- **`config/boot.rb`** sets `BUNDLE_GEMFILE` and runs `bundler/setup`.
- **`config/application.rb`** requires the full Rails stack (`require 'rails/all'`, line 3) and **invokes `Bundler.require` twice**: once for the assets group in dev/test (line 7), and again for `:default, Rails.env` *inside* the `Application` class body (line 62). It also sets `config.encoding = "utf-8"`, filters `:password` from logs, enables HTML escaping in JSON, and sets `config.assets.version = '1.0'`. Note `config.force_ssl` is **commented out** (`application.rb:45`).
- **`config/environment.rb`** requires `application.rb` and then calls `Esmx::Application.initialize!`.
- **`config.ru`** requires `config/environment` and runs `Rails.application`.
- Initializers run in **alphabetical order**, which matters: `esm.rb` (constants) and `esm_lib.rb` run early; `mongodb.rb` runs *before* `mongomapper.rb` (this ordering is the whole reason the second Mongo initializer is effectively a no-op — see §6).

### Environment differences

| Env | Config notes (`config/environments/*.rb`) |
| --- | --- |
| development | `cache_classes false`, `eager_load false`, `assets.debug` on |
| production | `cache_classes true`, `perform_caching true`, `assets.compile + digest + uglifier`, `eager_load true`, **`consider_all_requests_local = true`** (`production.rb:8` — full error pages shown to end users) |
| test | sqlite3, forgery off |

> **Note on the deployed reality:** the Docker `web` command launches Thin *without* `-e production`, so the container actually boots in **development** mode. That is a deployment fact, covered in **"08 - Docker & Infrastructure"**, but worth flagging here because it changes which of the above tables is live.

---

## 4. The dual-ORM design

This is the single most important thing to understand before touching anything.

### 4a. ActiveRecord metadata layer (MySQL)

The metadata catalog is a hierarchy of plain ActiveRecord models, each pinned to an explicit `esm_*` table name:

```
Esm (esms) ─< Project (esm_projects) ─< Service (esm_services) ─< Operation (esm_operations)
                  │                          │
                  ├─ has_one Schema (esm_schemas) ─< Table (esm_tables)
                  └─ has_many Document (esm_documents)
```

Evidence of the explicit table bindings (`dual-ORM: AR side`):

- `Service` → `self.table_name = :esm_services` (`app/models/service.rb:5`)
- `Project` → `:esm_projects` (`app/models/project.rb:5`)
- `Operation` → `:esm_operations` (`app/models/operation.rb:8`)
- `Table` → `:esm_tables` (`app/models/table.rb:2`)
- `Document` → `:esm_documents` (`app/models/document.rb:11`)
- `Schema` → `:esm_schemas` (`app/models/schema.rb:18`)

> **Naming trap:** `app/models/document.rb` is an **ActiveRecord model on MySQL `esm_documents`** that stores *form/field definitions* (a YAML blob of `Field` structs). It is **not** a Mongo document. The real Mongo documents are anonymous runtime-generated MongoMapper classes. Do not confuse the two.

These models additionally use **`protected_attributes`** (legacy `attr_accessible` / `attr_protected`) rather than Rails 4 strong parameters — e.g. `User` `attr_accessible` (`app/models/user.rb:5`) and `attr_protected :id, :salt` (`user.rb:32`), `Esm` (`esm.rb:4`), `Service` (`service.rb:6`), `Project` (`project.rb:6`). This is enabled by the `protected_attributes` gem (see §7).

### 4b. MongoMapper + GridFS runtime layer (MongoDB)

The actual end-user data lives in MongoDB, accessed through **MongoMapper classes that are generated at runtime**, not defined as files:

- `Schema#load_model` (`app/models/schema.rb:30`) ERB-renders Ruby source declaring a `MongoConnect` base (`include MongoMapper::Document`), an `Attachment` model, and **one class per `esm_table`** bound to a collection named `<project>.<table>` (`schema.rb:76-143`), then `eval`s it (`schema.rb:143`).
- Binary/document storage uses **raw GridFS directly** via `Mongo::Grid` / `Mongo::GridFileSystem`, not an abstraction. Static content is served from GridFS in the proxy (`Mongo::GridFileSystem.new(MongoMapper.database)`, `esm_proxy_controller.rb:25`); attachments use `Mongo::Grid.new(...)` (`esm_attachments_controller.rb:15`); `Document` writes via `grid.put` (`document.rb:525`).

### 4c. The metadata-to-code generator (the bridge)

```
Service#load(context)
  stack = [self] + extended_list           # inheritance chain
  src   = inline 'class EsmSuperClass ...'  # base, defined as a heredoc
  for s in stack.reverse:
     src += ERB: 'class <Sn> < <super|EsmSuperClass>
                    def <op.name>; ScriptTemplate.generate(op.command); end ...'
  eval(src)  ->  returns <ClassName>.new(context)
```

Confirmed in source: `Service#load` builds `superclass` as a heredoc defining `EsmSuperClass` (`service.rb:135-189`), concatenates one ERB-rendered subclass per service in the extended chain where each `Operation` becomes a method (`service.rb:217-238`), `eval(tmp)` (`service.rb:259`), and returns `eval("#{class_name}.new context")` (`service.rb:262`). `Schema#load_model` does the analogous thing for Mongo model classes. There is a `cache = false` branch and the file-cache writes are commented out (`service.rb:195, 243-245`), so **the class hierarchy is regenerated and `eval`'d on every request**.

> The runtime `EsmSuperClass` defined inside `Service#load` is the one that actually executes. There is a **stale standalone file** `app/models/esm_super_class.rb` that renders via `ActionView::Base` against a `vendor/plugins/esm_essential/app/views` path; it appears to be legacy/dead. **Unverified / to confirm:** whether any live code path requires the standalone file.

---

## 5. Custom bootstrap libs and the `esm_lib` initializer

Two custom libs are pulled in from `config/initializers/esm_lib.rb` and they reach into Rails internals.

| Lib / initializer | What it does |
| --- | --- |
| `config/initializers/esm_lib.rb` | Defines the global `msg_report(subject, body)` method (an **XMPP notifier** via `xmpp4r` to `soup@server.esm-solution.com`, `esm_lib.rb:4-29`), then `require 'esm_essential'` and `require 'esm_scaffold'`, and sets `@theme = 'default'`. |
| `lib/esm_essential.rb` | `require 'basic_auth'`, then pushes `app/{models,controllers,helpers,views}` onto both `$LOAD_PATH` and **`ActiveSupport::Dependencies.autoload_paths`** (`esm_essential.rb:4-9`). Also adds `<root>/themes/default/views` (`esm_essential.rb:12-15`). |
| `lib/esm_scaffold.rb` | Defines a global `esm_scaffold(model, &block)` macro that `define_method`s generic CRUD actions at class scope: `index`/`show`/`new`/`edit`/`create`/`update`/`destroy` over an AR class (`esm_scaffold.rb:3, 22, 28, 82, 93, 103, 111, 127, 143`). |
| `lib/basic_auth.rb` | `BasicAuth` mixin: `login_required` resolves the solution by host/cookie/subdomain and sets `Time.zone = 'Bangkok'` (`basic_auth.rb:23`); `current_user = session[:user]`. Mixed into `EsmController`. |

Two cautions confirmed against source:

- **`esm_essential.rb:12` adds `<root>/themes/default/views`, which does not exist.** The real theme views live at `app/views/esm/themes/default`. The added path is effectively a no-op.
- `msg_report` is the platform's error-alerting channel (the proxy's `rescue` block calls it), so an XMPP outage silently swallows error notifications.

`esm_scaffold` is used for built-in ActiveRecord models (e.g. the admin/scaffold CRUD), **not** for the metadata-driven Mongo documents — those go through `EsmProxyController` and a `system.util.Document` service. **Unverified / to confirm:** the exact set of controllers invoking `esm_scaffold` (none were located in the files read).

---

## 6. Initializers and config files (and the Mongo config confusion)

```
config/initializers/
  esm.rb            -> global constants: MONGO_PREFIX='esm_emr', DOMAIN='emr-life.com', ESM_MSG_USER/PASS
  esm_lib.rb        -> msg_report; require esm_essential + esm_scaffold
  mongodb.rb        -> FIRST Mongo init (alpha order)
  mongomapper.rb    -> SECOND Mongo init (effectively a no-op at boot)
  resque.rb         -> Resque.redis + namespace 'resque:task'
  secret_token.rb   -> secret_token AND secret_key_base (identical, committed)
  session_store.rb  -> cookie_store, key '_esmx_session'
```

### The two MongoMapper initializers

This is a known landmine. There are **two** Mongo initializers and they run in alphabetical order (`mongodb.rb` before `mongomapper.rb`):

1. **`config/initializers/mongodb.rb`** sets the *real* connection. Confirmed in source:
   ```ruby
   MongoMapper.config = { Rails.env => { 'uri' => ENV['MONGOHQ_URL'] || 'mongodb://mongo/xxxxxxxx' } }
   MongoMapper.connect(Rails.env)
   name = "palette-#{Rails.env}"
   ...
   MongoMapper.database = "#{name}"
   ```
   So at boot the default DB name is **`palette-<env>`**, connecting to `ENV['MONGOHQ_URL']` or the hardcoded placeholder `mongodb://mongo/xxxxxxxx`.

2. **`config/initializers/mongomapper.rb`** reads `MongoMapper.config[Rails.env]['logger']` (nil → logging off), and only *inside* an `unless MongoMapper::Connection.class_variables.include?(:@@database_name)` guard tries to `YAML.load` a `../mongodb.yml` file **that does not exist** in the repo. Because `mongodb.rb` already ran and set the database, the guard is false, the missing-file branch is skipped, and it just prints `Initialized: <dbname>`.

3. **`config/mongo.yml`** *looks* authoritative (host `mongo:27017`, per-env DB names `esmx_development`/`esmx`), **but no initializer reads it.** It is vestigial.

**Net effect:** the configured names (`esmx_development`, `xxxxxxxx`) are largely irrelevant. The per-request DB that actually serves data is whatever `EsmProxyController` sets via `MongoMapper.database = @current_solution.db_name`, which evaluates to `#{MONGO_PREFIX}-#{esm.name}` = `esm_emr-<solution>` (`esm.rb:147-149`, `config/initializers/esm.rb:1`).

> **Unverified / to confirm:** the live value of `ENV['MONGOHQ_URL']` / `MONGO_USERNAME` / `MONGO_PASSWORD` at deploy time. The compose `mongo` service has no auth env set, so the `mongodb://mongo/xxxxxxxx` fallback is *likely* what runs, but this cannot be confirmed from the repo.

### Other config files

| File | Purpose |
| --- | --- |
| `config/database.yml` | MySQL (`mysql2`) for dev+prod → DB `soup_esm_emr`, host `db`, `root`/`minadadmin`. **test uses sqlite3** (schema-divergence risk for tests). |
| `config/resque.yml` | Redis URLs per env → `redis://redis:6379/` for dev+prod. |
| `config/initializers/secret_token.rb` | Hardcoded `secret_token` **and** `secret_key_base` — *identical* values, committed to source (`secret_token.rb:7-8`). |
| `config/initializers/session_store.rb` | `cookie_store` with key `_esmx_session`. |
| `config/initializers/esm.rb` | Hardcoded global constants: `MONGO_PREFIX='esm_emr'`, `DOMAIN='emr-life.com'`, plus XMPP creds `ESM_MSG_USER`/`ESM_MSG_PASS`. |

Auth implications of the committed secrets (SHA-1 passwords, cookie-store session forgery, API-key-is-the-password-hash) are detailed in **"03 - Authentication & Authorization"**.

---

## 7. Gems and their purpose

Pinned to **Rails 4.2.0 / Ruby 2.3** with a `mongo 1.x` era stack. Grouped by what they actually do in *this* codebase:

| Gem(s) | Role in ESM |
| --- | --- |
| `rails` 4.2.0 | Core framework (no patch-level pin). |
| `mysql2` 0.3.21 (`~> 0.3.20`) | ActiveRecord adapter for the MySQL metadata store. (Pre-MySQL-8 driver — see Docker doc for the auth-plugin tension.) |
| `mongo` 1.12.5 + `mongo_mapper` 0.14.0 + `bson` / `bson_ext` 1.12.5 | The Mongo runtime-data ORM. Legacy moped-era driver. |
| `rack-gridfs` 0.4.1 | Declared for serving GridFS over Rack — **but no `Rack::GridFS` mount was found**; all GridFS access is via `Mongo::Grid`/`Mongo::GridFileSystem` directly. (See open question below.) |
| `redis` 3.2.1, `resque` 1.25.2, `resque-scheduler` 4.0.0 (`rufus-scheduler` 3.0.9) | Background jobs (queues in Redis, namespace `resque:task`). `resque-scheduler` is declared but **no schedule config / scheduler invocation was found** — likely dormant. |
| `protected_attributes` | Re-enables Rails-3-style `attr_accessible`/`attr_protected` (strong-params disabled across all models). |
| `rails-observers`, `actionpack-page_caching`, `actionpack-action_caching` | Backfill Rails 4 extractions used by legacy code. |
| `therubyracer` / `libv8` / `execjs` | JS runtime for `uglifier` asset minification. **Not** used for app logic — dynamic execution is Ruby `eval`/ERB, not JS. |
| `pdfkit` + `wkhtmltopdf-binary` (and `prawn`, bundled but unused in the workers) | PDF generation, used out-of-band by the `PdfGenerator` Resque worker. |
| barcode stack (`barby` etc.) | On-the-fly barcode/QR PNG generation in `EsmImageController`. |
| `xmpp4r` | The `msg_report` error-alert channel. |
| Asset pipeline (Sprockets 2.12) | `application.js`/`application.css` are `//= require` manifests (`application.js:8`, `application.css:13`). |
| `thin` (used), `puma` / `unicorn` (declared, **commented out** in compose) | App servers; only Thin is wired up. |

### Vestigial / declared-but-unreferenced gems

A repo-wide grep found **zero references in `app/lib/config`** for these. Treat any feature they imply as **not implemented**:

`saml2`, `omniauth`, `omniauth-google-oauth2`, `rest-graph`, `rest-client`, `roo` / `roo-xls`, `creek`, `time_diff`, `parallel`, plus the unused `puma` / `unicorn` / `prawn`.

In particular: **SAML2 and Google OAuth login are not wired** — no initializer, no `provider` block, no controller/route/view references. The only authentication that exists is the home-grown SHA-1 mechanism (see **"03 - Authentication & Authorization"**).

> **Unverified / to confirm:** the intended role of `saml2`/`omniauth`/`rest-graph`/`roo`/`creek`. They may back features in unread view templates or external scripts, or be leftovers; there is no evidence either way in `app/lib/config`.

---

## 8. Server, SSL, and background processing

### Thin over SSL

The Docker `web` service runs Thin with TLS terminated **at the app** on port 3000:

```
thin start --port 3000 --ssl \
  --ssl-key-file config/ssl/private.key \
  --ssl-cert-file config/ssl/server.crt
```

(`docker-compose.yml:29`; the `puma` alternative is commented at line 30.) The cert is **self-signed** (`CN=localhost`, `O=ESM`, `C=TH`, valid 2026-06-15 → 2036-06-12). There is no reverse proxy in the repo, no HSTS, and `force_ssl` is commented out in both `application.rb` and `production.rb`, so the app does not redirect HTTP→HTTPS itself.

Timezone is forced in two places: `Time.zone = 'Bangkok'` per request (`EsmController#context_filter`, `esm_controller.rb:12`; also `basic_auth.rb:23`) and `ENV TZ=Asia/Bangkok` at the container layer (`Dockerfile:24-25`).

The image base is `ruby:2.3` on Debian **stretch** (archived repos, `Check-Valid-Until` disabled, `--allow-unauthenticated`), installing native deps for the healthcare/EMR domain: `nodejs`, `imagemagick`, `ffmpeg`, `wkhtmltopdf`, `dcmtk` (DICOM), `libxmlsec1`. Bundler is pinned to 1.17.3. Full deployment topology is in **"08 - Docker & Infrastructure"**.

### Resque (declared and wired, but no worker process)

Resque is configured (`config/initializers/resque.rb:5-6`, namespace `resque:task`), the dashboard is mounted at `/resque` (`config/routes.rb:5`), and jobs are enqueued (`Task`/`Job` base classes; `PdfGenerator` uses PDFKit/wkhtmltopdf; `CMDTask` `eval`s an arbitrary `cmd`). However **no compose service runs `rake resque:work` or the scheduler**, so enqueued jobs would queue in Redis and never execute in the Dockerized setup. **Unverified / to confirm:** whether a worker is started out-of-band in real production (the `.dockerignore` lists `nohup.out`, hinting at a manual `nohup rake resque:work`). See **"07 - Operation Execution Flow"** and **"08 - Docker & Infrastructure"**.

---

## 9. Key files

| Path | Why it matters |
| --- | --- |
| `config/application.rb` | Defines `Esmx::Application`; `require 'rails/all'`; double `Bundler.require` (lines 7, 62); encoding/param-filter/asset-version config; `force_ssl` commented (line 45). |
| `config/boot.rb` | Sets `BUNDLE_GEMFILE`, runs `bundler/setup`. |
| `config/environment.rb` / `config.ru` | Standard initialize! + Rack entrypoint. |
| `config/initializers/esm.rb` | Global constants `MONGO_PREFIX='esm_emr'`, `DOMAIN='emr-life.com'`, XMPP creds. |
| `config/initializers/esm_lib.rb` | Global `msg_report` (XMPP); requires the two custom libs; sets theme. |
| `config/initializers/mongodb.rb` | The *real* Mongo connect (`ENV['MONGOHQ_URL']` or `mongodb://mongo/xxxxxxxx`, DB `palette-<env>`). |
| `config/initializers/mongomapper.rb` | Second Mongo init; effectively a no-op (guard false, missing `mongodb.yml`); just prints "Initialized". |
| `config/mongo.yml` | Looks authoritative but **not read** by any initializer (vestigial). |
| `config/database.yml` | MySQL `soup_esm_emr` (dev/prod); sqlite3 (test). |
| `config/initializers/secret_token.rb` | Committed `secret_token == secret_key_base`. |
| `lib/esm_essential.rb` | Mutates `autoload_paths`; adds a non-existent `themes/default/views` path. |
| `lib/esm_scaffold.rb` | Global `esm_scaffold` CRUD macro. |
| `lib/basic_auth.rb` | `BasicAuth` mixin; solution resolution; `Time.zone='Bangkok'`. |
| `app/models/service.rb:126` | `Service#load` — the runtime metaprogramming engine (ERB + `eval` of a generated class). |
| `app/models/schema.rb:30` | `Schema#load_model` — ERB-generates MongoMapper model classes per `esm_table`. |
| `app/controllers/esm_proxy_controller.rb` | Front controller; swaps Mongo DB per request; serves GridFS; dispatches `obj.send(opt)`. |
| `app/controllers/esm_controller.rb:9` | `context_filter` — establishes solution/project/user/role/zone for every request. |
| `docker-compose.yml:27-41` | `web` (Thin --ssl), `db` (mysql:8.2), `mongo` (3.2), `redis`. |
| `Dockerfile` | `ruby:2.3` on archived Debian stretch; native EMR deps; `TZ=Asia/Bangkok`. |

---

## 10. Gotchas / risks (architecture-level)

These are the architecture-shaped traps; security specifics (RCE surface, CSRF, weak auth, committed secrets) are detailed in **"02 - Request Flow"**, **"03 - Auth"**, and **"07 - Operation Execution"**, but the highest-impact ones are repeated here because they shape how you reason about the whole system.

- **Runtime `eval` of metadata is the core mechanism *and* a large RCE/injection surface.** `Service#load`, `Schema#load_model`, `Project#get_params` (`eval self.params`), `Field`/relation params (`eval("{#{field.params}}")`), and `SchemaProxy` all `eval` strings sourced from DB-stored metadata. Anyone who can edit an `Operation.command`, `Table.data/command`, or project/field params executes arbitrary Ruby in the web process. Plan all changes with this in mind.
- **No class caching.** The `cache = false` branch in `Service#load` means the entire class hierarchy is regenerated and re-`eval`'d on *every* request (constant redefinition + performance cost). `remove_const` is commented out (`service.rb:256`).
- **`MongoMapper.database` is global per-request state.** Mutated in `EsmProxyController`/`EsmAttachmentsController`. Under a threaded server (e.g. the commented-out Puma) this is a **cross-tenant data-leak race**. It is only "safe" because Thin is single-threaded/evented. Do not switch app servers without solving this.
- **Two Mongo initializers + an unread `config/mongo.yml`.** The effective DB name is set per-request (`esm_emr-<solution>`), not by any config file. Editing `config/mongo.yml` does nothing.
- **The standalone `app/models/esm_super_class.rb` is not the runtime class.** The live `EsmSuperClass` is the heredoc inside `Service#load`. Editing the file has no effect on request rendering.
- **`esm_essential.rb` adds a non-existent `themes/default/views` path** — a silent no-op; real theme views are at `app/views/esm/themes/default`.
- **End-of-life stack.** Ruby 2.3, Rails 4.2.0 (no patch pin), `mongo` 1.12.5 + MongoMapper 0.14, Mongo server pinned to 3.2; Debian stretch from `archive.debian.org` with unauthenticated apt. Upgrades are high-risk and must account for the `eval`-everything runtime.
- **App boots in development in Docker** (`thin` command lacks `-e production`), and `production.rb` sets `consider_all_requests_local = true` — full stack traces would be exposed if production were ever used directly. See **"08 - Docker & Infrastructure"**.
- **Many declared gems are dead weight** (`saml2`, `omniauth*`, `rest-graph`, `roo`/`roo-xls`, `creek`, `time_diff`, `parallel`, `puma`, `unicorn`, `prawn`). Do not assume SAML/OAuth/spreadsheet-import features exist; they are unwired.

### Open questions to confirm with the team

1. Is `rack-gridfs` middleware mounted anywhere? None found in `config`; all GridFS access is manual via `Mongo::Grid`/`GridFileSystem`.
2. Live production value of `ENV['MONGOHQ_URL']` and Mongo auth env vars (determines the actual runtime DB name and whether auth is on).
3. Is `resque-scheduler` actually started/used? Gem present and `resque.rake` requires `resque/tasks`, but no schedule config or scheduler invocation found.
4. Is the standalone `EsmSuperClass` file (`app/models/esm_super_class.rb`) dead, or required somewhere not yet traced?
5. How are Resque workers launched relative to the web container? Compose defines only the `web` command + DB services; the worker process launch is not in `docker-compose.yml`.

