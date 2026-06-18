# 00 - System Overview

> **Audience:** the senior engineer taking full ownership of the ESM legacy platform.
> **Purpose:** a top-level orientation. This is the first of nine documents. Read this one first, then use the **Document Map** at the end to drill into specific areas.
>
> Every statement below is grounded in the source. File:line citations are inline. Where the evidence could not confirm something, it is flagged **(unverified / to confirm)** rather than asserted.

## What ESM Is

ESM is a **metadata-driven EMR/EHR platform** built on Rails 4.2. Instead of being a fixed application, ESM is a *runtime metamodel*: the definition of every end-user "application" is stored as **data in MySQL**, and at request time the platform reads that metadata and uses **ERB templating + `eval`** to synthesize real Ruby classes in memory. Nothing is generated to disk — applications are literally code-generated and `eval`'d per request.

Two facts capture the essence of the system and should anchor your mental model:

1. **Dual-ORM split.** ActiveRecord on **MySQL** holds the *metadata catalog* (the definition of apps), while MongoMapper + raw **GridFS** on **MongoDB** hold the *runtime application data* and uploaded files, in a separate Mongo database per solution (`app/models/esm.rb:147-149`).
2. **Runtime code generation is the core mechanism.** `Service#load` builds a Ruby class as a string from database-stored `Operation.command` scripts, `eval`s it, and dispatches `obj.send(params[:opt], params)` (`app/models/service.rb:259-262`, `app/controllers/esm_proxy_controller.rb:75`). The same pattern generates MongoMapper model classes (`app/models/schema.rb:143`).

The application module is `Esmx` (`config/application.rb:12`), running on **Ruby 2.3 / Rails 4.2.0**. The platform context is healthcare: the global constant `DOMAIN='emr-life.com'` and `MONGO_PREFIX='esm_emr'` are defined in `config/initializers/esm.rb:1-2`, the Docker image installs `dcmtk` (DICOM tooling), and per-request timezone is forced to Bangkok (`app/controllers/esm_controller.rb:12`).

> **A note on security posture.** This is end-of-life software with a large, designed-in remote-code-execution surface (runtime `eval` of operator-editable metadata), disabled CSRF on the main app surface, hardcoded secrets, and weak SHA-1 auth. These are not incidental bugs — they are structural. They are summarized in **Gotchas / risks** below and detailed in the per-area documents. Treat the whole platform as security-sensitive.

## Tech Stack & Versions

| Layer | Technology | Version / detail | Evidence |
|---|---|---|---|
| Language | Ruby | 2.3 (Docker base `ruby:2.3`, Debian Stretch) | `Dockerfile:1` |
| Framework | Rails | 4.2.0 (`module Esmx`, `require 'rails/all'`) | `config/application.rb:3,12` |
| App server | Thin | HTTPS on `:3000`, self-signed cert (`puma`/`unicorn` declared but commented out) | `docker-compose.yml:29` |
| Metadata store | MySQL (`mysql2`) | driver `0.3.21`; DB `soup_esm_emr`; server image `mysql:8.2` | `config/database.yml:6-31`, `Gemfile.lock:107` |
| Runtime data store | MongoDB + MongoMapper | `mongo` 1.12.5 + `mongo_mapper` 0.14.0 + `bson_ext`; Mongo server `3.2` | `Gemfile.lock:96-208`, `docker-compose.yml:19-26` |
| Binary store | GridFS (raw `Mongo::Grid` / `Mongo::GridFileSystem`) | default `fs.*` bucket | `app/controllers/esm_attachments_controller.rb:15` |
| Job queue | Redis + Resque | `resque` 1.25.2, `resque-scheduler` 4.0.0; namespace `resque:task` | `config/initializers/resque.rb:5-6` |
| Assets | Sprockets 2.12 + therubyracer/execjs | JS runtime for uglifier only | `app/assets/javascripts/application.js:8` |
| PDF | PDFKit → wkhtmltopdf | out-of-band Resque worker (not in request cycle) | `app/models/workers/pdf_generator.rb:23` |
| Images / barcodes | ImageMagick `convert`, Barby | thumbnails + Code128/Code39/Ean13/QR | `app/controllers/esm_image_controller.rb:254` |
| Auth | Hand-rolled SHA-1 + salt | no Devise/bcrypt; `protected_attributes` (legacy mass-assignment) | `app/models/user.rb:131-133` |
| Native deps | dcmtk, imagemagick, ffmpeg, wkhtmltopdf, libxmlsec1, mysql client | installed in image | `Dockerfile:6-9` |

**Vestigial / declared-but-unused dependencies.** The Gemfile declares `saml2`, `omniauth`, `omniauth-google-oauth2`, `rest-graph`, `rest-client`, `roo`/`roo-xls`, `creek`, `time_diff`, and `parallel`, but a repo-wide grep finds **zero references** in `app/`, `lib/`, or `config/`. Notably, **SAML2 and Google OAuth login are not implemented** despite the gems being bundled — treat any claim of SSO as non-functional. Similarly, `therubyracer`/`execjs`/`libv8` exist only as Rails JS asset runtimes; ESM's "dynamic execution" is Ruby `eval`/ERB, never JavaScript.

## The Domain Hierarchy

ESM's metadata is organized as a strict hierarchy, all stored in MySQL as `ActiveRecord::Base` subclasses bound to `esm_*` tables. The canonical chain is:

```
Esm  >  Project  >  Service  >  Operation  >  Table  >  Field  >  Document
```

This chain is best understood as **two interlocking sub-trees** hanging off `Project`: a *behavior* sub-tree (Service → Operation, which define controller-like actions) and a *structure/form* sub-tree (Schema → Table, Document → Field, which define data shape and forms).

| Level | Model / file | MySQL table | Role | Evidence |
|---|---|---|---|---|
| **Esm** | `Esm` (`app/models/esm.rb`) | `esms` | Top-level tenant / "solution". Owns projects, users, roles, settings. `db_name` = `esm_emr-<name>` selects the Mongo DB for all of its data. | `app/models/esm.rb:147-149` |
| **Project** | `Project` (`app/models/project.rb`) | `esm_projects` | Application namespace. `package = <esm>.<name>`. Owns Schema, Services, Documents, MenuActions, Settings, Roles. Supports inheritance via `extended`. | `app/models/project.rb:8-17,70` |
| **Service** | `Service` (`app/models/service.rb`) | `esm_services` | Controller-like class definition. `package = <proj>.<Service>`. `#load` compiles it into a live Ruby class. May `extended` another Service. | `app/models/service.rb:5,219` |
| **Operation** | `Operation` (`app/models/operation.rb`) | `esm_operations` | Action/method definition. `command` holds raw Ruby/ERB source; `template_id` selects a ScriptTemplate generator. Becomes a method on the generated Service class. | `app/models/operation.rb:8,10` |
| **Schema** | `Schema` (`app/models/schema.rb`) | `esm_schemas` | The Mongo-model compiler. `#load_model` ERB-generates MongoMapper classes per Table. | `app/models/schema.rb:30` |
| **Table** | `Table` (`app/models/table.rb`) | `esm_tables` | Physical structure of one Mongo collection. `data` holds literal `key :col, Type` MongoMapper lines; `command` holds extra body. | `app/models/table.rb:2,6-28` |
| **Field** | `Field` (`app/models/field.rb`) | *none* | **Not ActiveRecord** — a Ruby `Struct` serialized inside `Document`. Defines field type → Mongo data type mapping. | `app/models/field.rb:1,5` |
| **Document** | `Document` (`app/models/document.rb`) | `esm_documents` | **ActiveRecord on MySQL, NOT a Mongo document.** Stores form *definitions* (YAML array of Field structs in `data`). The 990-LOC dynamic record engine. | `app/models/document.rb:4,11` |

> **Critical naming trap (read twice).** `Document` (`app/models/document.rb`) is an **ActiveRecord model on the MySQL `esm_documents` table** that stores *form/field definitions* as YAML. It is **not** a MongoDB document. The actual Mongo records are anonymous, runtime-generated MongoMapper classes produced by `Schema#load_model`. Conflating the two will cause real confusion.

Supporting models (also MySQL/ActiveRecord) hang off this tree: `User`, `Role`, `Account`, `Permission`, `MenuAction`, `Setting`, `Log`, and `ScriptTemplate` (`esm_templates`, the code generators). See **02 - Core Domain Models & Relationships** for the full ER map.

### Two persistence layers, side by side

```
MySQL metadata (the definition)            MongoDB (the data)
-------------------------------            ------------------------------------
Esm                                        DB per solution: esm_emr-<solution>
 └ Project ── has_one ── Schema ── Table ──►  collection <project>.<table>
 └ Project ── has_many ─ Service ─ Operation    { _id, <fields...>, timestamps }
 └ Project ── has_many ─ Document ─ Field ──► drives Table.data (key lines)
                                           collection <project>.attachment
                                           GridFS fs.files / fs.chunks (binaries)
```

## Master Architecture Diagram

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

### Runtime request resolution (the single most important flow)

Nearly every dynamic URL funnels through `EsmProxyController#index`. The view is not a Rails template — it is the operation's `command` field, rendered as inline ERB.

```
HTTP /esm/<sol>/<proj>/<Service>/<opt>   (or /s/<Service>/<opt>, /ws/<Service>/<opt>)
        |
        v
EsmController#context_filter  -> @current_solution/@current_project/@current_user/@current_role
        |
        v
EsmProxyController#index
   1. MongoMapper.database = solution.db_name          (esm_proxy_controller.rb:20)
   2. try GridFS static file on request.path_info; if found, render bytes & STOP
   3. s = Service.get('<sol>.<proj>.<Service>')         (service.rb:64)
   4. ACL: s.get_acl(opt, user) -> authorize            (esm_proxy_controller.rb:64-80)
   5. context = s.prepare(params, self, request)        (service.rb:105)
   6. obj = s.load(context)                             (service.rb:126)
        |   build stack = [svc] + extended chain
        |   ERB: EsmSuperClass + per-svc class; each Operation -> method via ScriptTemplate
        |   eval(source);  ClassName.new(context)
        v
   7. obj.send(params[:opt], params)                    (esm_proxy_controller.rb:75)
        |   operation body calls render_template -> controller.render(:inline => command + layout)
        v
   HTTP response (HTML/JSON)   |   on exception: msg_report (XMPP) + render public/500.html
```

### Boot sequence

```
config.ru
  -> require config/environment.rb
       -> require config/application.rb
            -> require config/boot.rb (bundler/setup)
            -> require 'rails/all'
            -> Bundler.require(:assets in dev/test)            (application.rb:7)
            -> module Esmx; class Application < Rails::Application
            -> Bundler.require(:default, Rails.env)
       -> Esmx::Application.initialize!
            -> initializers run ALPHABETICALLY:
                 esm.rb (constants), esm_lib.rb (def msg_report; require esm_essential
                   -> require basic_auth + autoload_paths mutate; require esm_scaffold),
                 mongodb.rb (MongoMapper.connect, db=palette-<env>),
                 mongomapper.rb (logger off; guarded YAML skip),
                 resque.rb (Redis ns resque:task),
                 secret_token, session_store (_esmx_session), ...
  -> run Rails.application  (served by Thin --ssl :3000)
```

Two custom bootstrap libraries are wired in by `config/initializers/esm_lib.rb`: `lib/esm_essential.rb` (mutates `ActiveSupport::Dependencies.autoload_paths`) and `lib/esm_scaffold.rb` (defines the global `esm_scaffold(model)` CRUD macro). The initializer also defines the global `msg_report` XMPP error notifier. Details in **01 - Architecture & Bootstrapping**.

## Glossary of ESM-Specific Terms

| Term | Meaning |
|---|---|
| **Esm / Solution** | Top-level tenant. One Esm = one Mongo database named `esm_emr-<name>`. The terms "Esm" and "solution" are used interchangeably in the code (`@current_solution`). `app/models/esm.rb:147-149` |
| **Project** | An application namespace within a solution; `package = <esm>.<name>`. Owns the schema, services, documents, menus, settings. Can inherit from another Project via `extended`. |
| **Package** | A dotted string identifier used to resolve metadata, e.g. `<esm>.<project>.<Service>`. `Service.get(package)` walks these. `app/models/service.rb:64` |
| **Service** | A controller-like class definition. Compiled into a live Ruby class at request time by `Service#load`. |
| **Operation** | A single action/method on a Service. Its `command` column holds raw Ruby/ERB source that becomes a method body (or is rendered as inline ERB). Selected by `params[:opt]`. |
| **opt** | The URL/param segment naming which Operation to run; dispatched via `obj.send(params[:opt], params)`. |
| **ScriptTemplate** | A code generator (`esm_templates` table). `#generate` runs `ERB.new(self.generator).result(binding)` to wrap an operation's command into Ruby. Five seeded variants: `ServiceTemplate`, `HTMLTemplate`, `PartialTemplate`, `LayoutTemplate`, `EvalTemplate`. `app/models/script_template.rb:8-10` |
| **EsmSuperClass** | The base class all generated Service classes descend from. **Two divergent definitions exist:** the *runtime* one is a heredoc inside `Service#load` (uses `controller.render`); the standalone file `app/models/esm_super_class.rb` is **legacy/dead** (uses `ActionView::Base` on a nonexistent vendor path). The runtime one is what actually executes. |
| **Schema / Table** | Schema (`esm_schemas`) compiles MongoMapper model classes; Table (`esm_tables`) defines one Mongo collection's columns via literal `key :col, Type` lines in its `data` field. |
| **Document** | A form/schema *definition* (MySQL `esm_documents`). Holds a YAML array of Field structs; drives Table columns. **Not** a Mongo record. |
| **Field** | A Ruby `Struct` (not AR) describing one form field. Maps a UI `field_type` to a Mongo `data_type` (e.g. `relation_one` → ObjectId). `app/models/document.rb:412-453` |
| **Attachment** | A runtime-generated MongoMapper class on collection `<project>.attachment`; references binary blobs in GridFS via `file_id`/`thumb_id`/`original_id`. `app/models/schema.rb:100-112` |
| **Instance** | The in-memory merged metadata for a Project after walking the `extended` inheritance chain (`Project#get_instance`/`init_instance`). `app/models/project.rb:277-386` |
| **extended** | The inheritance pointer. Projects extend Projects and Services extend Services (e.g. document services extend `system.util.Document`). Merge is by name, child overrides parent. |
| **render_to_panel** | The admin/IDE AJAX rendering primitive: renders an ERB partial wrapped in a `<script>` that DOM-injects via jQuery `$('#...').html(...)`. `app/controllers/esm_controller.rb:147` |
| **render_template** | The runtime view primitive inside the generated EsmSuperClass: `controller.render(:inline => command)`. The "view" is the operation's stored command. `app/models/service.rb:165` |
| **msg_report** | Global XMPP error notifier (`config/initializers/esm_lib.rb`); emails backtraces on proxy exceptions. |
| **Task / Job / CMDTask / PdfGenerator** | Resque worker classes. `CMDTask` `eval`s an arbitrary `cmd` param; `PdfGenerator` runs wkhtmltopdf; `Job::JobTest` replays an internal HTTP GET. |

## Key files

| Path | Why it matters |
|---|---|
| `config/application.rb` | Defines `module Esmx` + `Application`; double-invokes `Bundler.require`. |
| `config/initializers/esm.rb` | Hardcoded globals: `MONGO_PREFIX='esm_emr'`, `DOMAIN='emr-life.com'`, XMPP creds. |
| `config/routes.rb` | All routing; order-sensitive greedy wildcards funnel to `EsmProxyController`. |
| `app/controllers/esm_proxy_controller.rb` | The central runtime dispatcher for all dynamic app/API requests. |
| `app/controllers/esm_controller.rb` | `context_filter` before_filter — resolves solution/project/user/role/zone every request. |
| `app/models/service.rb` | `Service#load` — the ERB+`eval` engine that compiles Operations into a live class. |
| `app/models/schema.rb` | `Schema#load_model` — ERB+`eval` generates MongoMapper model classes. |
| `app/models/document.rb` | 990-LOC form/record engine: field definitions (YAML), Mongo CRUD, GridFS uploads. |
| `app/models/script_template.rb` | The code-generator that turns `Operation.command` into Ruby method source. |
| `lib/basic_auth.rb` | `login_required`/`current_user`; solution resolution by host/cookie/subdomain. |
| `app/models/user.rb` | Hand-rolled SHA-1 + salt auth; `protected_attributes` whitelists. |
| `docker-compose.yml` | Topology: `db` (mysql:8.2), `redis`, `mongo` (3.2), `web` (Thin --ssl :3000). |
| `Dockerfile` | `ruby:2.3` on EOL Debian Stretch; native deps; `TZ=Asia/Bangkok`. |
| `db/schema.rb` | Authoritative MySQL structure (14 tables, version `20150317170313`). |

## Gotchas / Risks (orientation level)

These are the cross-cutting traps every new owner must internalize before touching anything. Each is expanded in the linked per-area document.

- **Pervasive runtime `eval` of operator-editable metadata = designed-in RCE.** `Service#load` (`app/models/service.rb:259`), `Schema#load_model` (`app/models/schema.rb:143`), `Project#get_params`, and field-param parsing all `eval` strings sourced from DB-stored metadata. Anyone who can edit an Operation/Service/Table/Field executes arbitrary Ruby in the web process. → **04 - Operation Execution Flow**, **05 - Metadata-Driven Architecture**.
- **`CMDTask` worker `eval`s an arbitrary `cmd` param** (`app/models/workers/exec.rb:11`) — arbitrary code execution for anyone who can enqueue a job. → **04 - Operation Execution Flow**.
- **CSRF disabled on the main app surface.** `EsmProxyController` does `skip_before_filter :verify_authenticity_token` (`app/controllers/esm_proxy_controller.rb:4`); the `/ws/:service/:opt` route performs **no ACL/auth check at all** (`app/controllers/esm_proxy_controller.rb:209-213`). → **03 - Authentication & Authorization**.
- **Weak auth.** Passwords are unsalted-iteration SHA-1 (`SHA1(pass+salt)`, `app/models/user.rb:131-133`), salt from `Kernel#rand` not a CSPRNG. API auth compares the stored password *hash* as a plaintext `api_key` URL param (`app/controllers/esm_proxy_controller.rb:60`). The `Permission` table exists but is **never consulted** in any auth decision. → **03 - Authentication & Authorization**.
- **Hardcoded secrets committed to source.** `secret_token == secret_key_base` (`config/initializers/secret_token.rb`), MySQL root password `minadadmin`, XMPP creds in `esm.rb`. With a leaked `secret_key_base`, cookie sessions are forgeable. → **01 - Architecture & Bootstrapping**.
- **Single-threaded safety only.** `MongoMapper.database` and `Time.zone` are mutated as *global per-request state* (`app/controllers/esm_proxy_controller.rb:20`). Safe only because Thin is single-threaded/evented; switching to puma would cause cross-tenant data-leak races. → **01**, **05**.
- **Production runs as development.** The Thin command omits `-e production` (`docker-compose.yml:29`), and `production.rb` sets `consider_all_requests_local = true` (full error pages / info leak). → **06 - Docker & Infrastructure**.
- **Resque workers are never started by compose.** Jobs enqueue to Redis but nothing dequeues them — no `rake resque:work` service exists, and Redis has no persistence volume. **(unverified / to confirm:** whether a worker is started out-of-band in the real deployment — `.dockerignore` listing `nohup.out` hints at a manual `nohup rake resque:work`). → **06 - Docker & Infrastructure**, **04 - Operation Execution Flow**.
- **Confusing/dead Mongo config.** `config/mongo.yml` is never read; `mongodb.rb` connects via `ENV['MONGOHQ_URL']` or hardcoded `mongodb://mongo/xxxxxxxx` and sets DB `palette-<env>`; the real per-request DB is set to `esm_emr-<solution>` at dispatch. **(unverified / to confirm:** the live `ENV['MONGOHQ_URL']` and Mongo auth at deploy time). → **06**, **03 (DB structure)**.
- **`Service#get_extended` is infinitely self-recursive** as written (`app/models/service.rb:46`) and would stack-overflow if ever invoked. **(unverified / to confirm:** whether any path reaches it). → **02 - Core Domain Models**.
- **Two `EsmSuperClass` definitions** — only the runtime heredoc in `Service#load` is live; editing the standalone file has no effect. → **05 - Metadata-Driven Architecture**, **07 - View Rendering**.
- **End-of-life stack throughout.** Ruby 2.3, Rails 4.2.0, mongo 1.x driver, MySQL 3.2 Mongo server, Debian Stretch from `archive.debian.org` with cert validation disabled. → **06 - Docker & Infrastructure**.

## Document Map (the other 8 documents)

This System Overview synthesizes across all nine reader-agent analyses. Use the table below to navigate to the area you need.

| # | Document | Covers | When to read it |
|---|---|---|---|
| **01** | **Architecture & Application Bootstrapping** | Boot chain, dual-ORM design, initializers, custom libs (`esm_essential`/`esm_scaffold`), Thin SSL, hardcoded secrets, vestigial gems | Understanding how the app starts and what `Esmx::Application` wires up. |
| **02** | **Core Domain Models & Relationships** | The full Esm→Document model tree, associations, `extended` inheritance, `Field` struct, `ScriptTemplate`, relation fields | Working with the metadata models or their relationships. |
| **03** | **Authentication & Authorization** | SHA-1 password auth, sessions/CookieStore, string-based ACLs, `get_acl`, API-key auth, the dead `Permission` table | Anything touching login, sessions, or who-can-do-what. |
| **04** | **Operation Execution Flow (sync + async)** | `Service#load` compiler, `obj.send(opt)` dispatch, ScriptTemplates, Resque (`Task`/`CMDTask`/`PdfGenerator`/`JobTest`), scheduling | How an operation actually runs, and the background-job story. |
| **05** | **Metadata-Driven Architecture** | The runtime metamodel, ERB+`eval` codegen for services and Mongo models, design-time vs runtime, inheritance merging | The deepest dive into the "apps are data" mechanism. |
| **06** | **Docker & Infrastructure / Deployment** | Compose topology, the four services, MySQL 8.2 ⇄ mysql2 0.3.21 tension, seeding, SSL, the missing worker process | Deploying, running locally, or debugging the container setup. |
| **07** | **View Rendering & Content/Attachment Flow** | `render_template` inline ERB, `render_to_panel` AJAX, GridFS attachment serving, ImageMagick thumbnails, barcodes, el_finder, async PDF | Anything about output, attachments, images, or the IDE UI. |
| **08** | **Request Flow & Routing** | `config/routes.rb` ordering, greedy wildcard catch-alls, `EsmProxyController` variants, `ManageController` generic CRUD, content routes | Tracing how a URL reaches a controller and which one wins. |
| *(Database Structure findings)* | *Cross-referenced within 01/02/06* | MySQL 14-table schema, per-solution Mongo DBs, GridFS, Redis/Resque, no DB-level foreign keys | DB-level questions on stores, tables, and collections. |

> **Reading order suggestion:** 00 (this doc) → 08 (Routing) → 04/05 (Execution & Metadata, the core mechanism) → 02 (Models) → 03 (Auth) → 07 (Views) → 01/06 (Bootstrapping & Infra).

