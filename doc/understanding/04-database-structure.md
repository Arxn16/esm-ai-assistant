# 04 - Database Structure

This document describes how the ESM legacy EMR platform stores its data. It is the canonical reference for the **three-store split** that defines the platform, the MySQL metadata schema, the MongoDB/GridFS runtime model, Redis usage, the MySQL migration timeline, and which model lives in which store.

Read this alongside **"05 - Core Domain Models & Relationships"** (model semantics), **"07 - Metadata-Driven Architecture"** (how metadata becomes running code), and **"06 - Docker & Infrastructure / Deployment"** (how the three datastores are wired in `docker-compose.yml`).

> **The one rule to internalize first:** in ESM, the *definition of an application* is **data in MySQL**, and the *application's actual records* are **documents in MongoDB**. Binary files live in **GridFS**. Redis only backs the Resque job queue. There are no database-level foreign keys anywhere.

---

## 1. The three-store architecture at a glance

| Store | Driver / gem | What it holds | Naming | Wired in |
|-------|--------------|---------------|--------|----------|
| **MySQL** | `mysql2` 0.3.21 + ActiveRecord (Rails 4.2) | **Metadata catalog** — the definition of solutions, projects, services, operations, schemas, tables, form-field definitions, users/roles, menus, settings, logs, code-gen templates | DB `soup_esm_emr`, 14 `esm_*` / auth tables | `config/database.yml:6-31` |
| **MongoDB** | `mongo` 1.12.5 + `mongo_mapper` 0.14.0 + `bson_ext` | **Runtime end-user records** — one collection per `esm_tables` row, generated at runtime | Per-solution DB `esm_emr-<solution>`; collections `<project>.<table>` | `app/models/schema.rb`, `config/mongo.yml`, `config/initializers/mongodb.rb` |
| **GridFS** | `Mongo::Grid` / `Mongo::GridFileSystem` (default `fs.*` bucket) | **Binary attachments** — images, PDFs, uploads — referenced by `ObjectId` | Lives inside the same per-solution Mongo DB | `app/models/document.rb`, `app/controllers/esm_attachments_controller.rb` |
| **Redis** | `redis` 3.2.1 + `resque` 1.25.2 | **Job queue only** (Resque) | Namespace `resque:task`, queues `:task`/`:job`/`default` | `config/resque.yml`, `config/initializers/resque.rb` |

The Docker topology that backs these is `db` (mysql:8.2), `mongo` (mongo:3.2), `redis` (redis:latest), and the `web` (Thin) container (`docker-compose.yml:3-41`). MySQL data persists under `./databases/mysql`, Mongo under `./databases/mongo` (with `./databases/dump` for mongorestore/mongodump), and **Redis has no volume — its data is ephemeral**. See "06 - Docker & Infrastructure / Deployment" for details.

```
+-----------------------------------------------------------+
|  DATA LAYER                                               |
|  MySQL (mysql2)        MongoDB (mongo 1.x + MongoMapper)  |
|  soup_esm_emr          per-solution DB (db_name) + GridFS |
|  Redis (Resque jobs: Task/Job/PdfGenerator/CMDTask)       |
+-----------------------------------------------------------+
```

> **Naming trap (read this twice):** the ActiveRecord model named `Document` (`app/models/document.rb`, `self.table_name = :esm_documents` at `app/models/document.rb:4,11`) is a **MySQL row storing a form/field DEFINITION** (a YAML blob of `Field` structs). It is **NOT** a MongoDB document. The real Mongo documents are anonymous classes generated at runtime by `Schema#load_model`. Do not confuse the two.

---

## 2. MySQL metadata schema (ER diagram)

### 2.1 The 14 tables

The authoritative schema is `db/schema.rb` (version `20150317170313`, exactly 14 `create_table` calls — `db/schema.rb:14`). The metadata hierarchy is `Esm > Project > Service > Operation`, with `Project` also owning a `Schema > Table` chain and a set of `Document`s.

| Table | AR model | Role | Key columns (from `db/schema.rb`) |
|-------|----------|------|-----------------------------------|
| `esms` | `Esm` | Top-level "solution" / tenant | `name`, `title`, `url`, `user_id`, `default_project`, `published` (`:117-127`) |
| `esm_projects` | `Project` | Application namespace | `name`, `package`, `user_id`, `database_id`, `params`, `domain`, `extended`, `extended_acl_id`, `acl`, `esm_id` (`:56-72`) |
| `esm_services` | `Service` | Controller-like class definition | `name`, `package`, `params`, `extended`, `cache`, `project_id`, `acl` (`:84-97`) |
| `esm_operations` | `Operation` | Action/method definition | `name`, `service_id`, `template_id`, `command` (raw Ruby/ERB source), `snippet`, `acl` (`:42-54`) |
| `esm_schemas` | `Schema` | Data-shape container | `name`, `esm_id`, `project_id`, `schema_type`, `source` (`:74-82`) |
| `esm_tables` | `Table` | Per-Mongo-collection definition | `esm_id`, `schema_id`, `name`, `data` (MongoMapper `key` lines), `command` (extra class body) (`:99-107`) |
| `esm_documents` | `Document` | Form/field DEFINITION (NOT a Mongo doc) | `name`, `document_type`, `data` (YAML fields), `project_id`, `table_id`, `service_id`, `sort_order`, `published`, `tree_data` (`:26-40`) |
| `esm_templates` | `ScriptTemplate` | Code generator templates | `name`, `generator` (ERB), `template` (`:109-115`) |
| `users` | `User` | Auth — SHA1+salt passwords | `login`, `hashed_password`, `salt`, `email`, `role_id`, `esm_id`, `current_session` (`:187-201`) |
| `roles` | `Role` | Role per project/solution | `name`, `description`, `default_home`, `esm_id`, `project_id` (`:166-174`) |
| `accounts` | `Account` | Join: User ↔ Esm ↔ Role | `esm_id`, `role_id`, `user_id`, `expired_at`, `active` (`:16-24`) |
| `permissions` | `Permission` | RBAC join (**unused for auth**) | `name`, `menu_action_id`, `role_id` (`:158-164`) |
| `menu_actions` | `MenuAction` | Navigation tree (self-referential) | `name`, `label`, `parent_id`, `action_type`, `url`, `esm_id`, `project_id`, `acl` (`:141-156`) |
| `settings` | `Setting` | Config key/value | `name`, `value`, `group`, `esm_id`, `project_id` (`:176-185`) |
| `logs` | `Log` | Audit/access log | `user_id`, `role_id`, `remote_ip`, `action`, `path`, `remark`, `esm_id` (`:129-139`) |

All TEXT-typed metadata columns (`data`, `command`, `params`, `generator`, `tree_data`, etc.) are `limit: 65535` (MySQL `TEXT`). Large form/table definitions can be **silently truncated** at 64 KB — see Gotchas.

### 2.2 Relationship map (no DB-level foreign keys)

There are **no foreign-key constraints** in MySQL. Every relationship is a bare integer `*_id` column wired only through ActiveRecord associations. Orphan rows are likely; some read paths (`Service.get` / `Service.clean`) even self-destroy orphan services.

```
DEFINITION HIERARCHY (MySQL / ActiveRecord)

  User --belongs_to--> Role --belongs_to--> Project
   |  has_many esms                              ^
   |  has_many accounts                          | has_many
   v                                             |
  Account -(esm,user,role)-+                     |
                           v                     |
  Esm (solution) -has_many-> Project -has_many-> Service -has_many-> Operation
   |  db_name=esm_emr-<name>   |  package=esm.name.name   |              | belongs_to
   |- has_many roles           |- has_one  Schema         |              v
   |- has_many users           |- has_many MenuAction(tree)        ScriptTemplate
   |- has_many logs            |- has_many Setting         (generator ERB, fk template_id)
   |- has_many settings        |- has_many Role
   |- has_many menu_actions    |- has_many Document --belongs_to--> Table
                                              | (YAML fields)   ^ belongs_to
                                Schema -has_many-+---------------+
                                Schema belongs_to Project

  permissions(menu_action_id, role_id)  <-- DEAD: never checked in any auth decision
  settings(esm_id, project_id)   logs(user_id, role_id, esm_id)
```

**Inheritance columns** are central to the platform:
- `esm_projects.extended` + `esm_projects.extended_acl_id` implement project inheritance (added in migration `20120518152807`). `Project#init_instance` recursively merges a super-project's menus/services/documents/tables/settings by name.
- `esm_services.extended` (renamed from `service_id` in migration `20111028122523`) implements service inheritance. `Service#load` reverses the extension chain so the most-derived class extends its ancestor's generated class.
- Circular `extended` references would infinite-loop the merge — to confirm whether any guard exists (**unverified / to confirm**).

### 2.3 Connection config

`config/database.yml:6-31`: both **development and production** point at DB `soup_esm_emr`, host `db`, user `root` / password `minadadmin`, pool 5. The **`test` environment uses sqlite3** (`db/test.sqlite3`), creating a schema-divergence risk for tests vs dev/prod.

> The `esm_projects.database_id` column has existed since the first project migration, but no model association or usage for it was found in the code read (**unverified / to confirm**). The `esm_documents.document_type` and `esm_schemas.schema_type`/`source` columns likewise have no traced consumer.

---

## 3. MongoDB document model

### 3.1 Models are generated at runtime, not defined as files

There are **no MongoMapper model `.rb` files**. The Mongo layer is materialized at request time by `Schema#load_model` (`app/models/schema.rb:30-150`), which builds a Ruby source string via ERB and `eval`s it. The template (`app/models/schema.rb:76-138`) emits:

1. A `MongoConnect` base class (`include MongoMapper::Document`).
2. `MongoMapper.database = '<%=self.project.esm.db_name%>'` — switching to the per-solution DB inside the generated code (`app/models/schema.rb:82`).
3. A fixed `Attachment` class on collection `<project>.attachment` (GridFS metadata — see §4).
4. **One class per `esm_tables` row**, named `<table>.camelize`, bound to collection `<project>.<table>` (`app/models/schema.rb:116-118`), splicing the table's `data` (the literal `key :col, Type` MongoMapper DSL lines) and a second pass for `command` (extra class body).

`Schema#load_model` returns a `{:attachment => Attachment, :<table> => Class}` hash, or a lazy `SchemaProxy` (`app/models/schema.rb:1-15`) that resolves a single model on hash access.

### 3.2 Field-type → Mongo key-type mapping

The shape of a Mongo collection is driven by the `Document` model's field definitions. `Document` stores its fields as a YAML dump of `Field` structs in `esm_documents.data` (`app/models/document.rb:26-34`). `Field` is **not an ActiveRecord model** — it is a Ruby `Struct` (`app/models/field.rb:1`). `Document` defines 28 `field_types` and a `data_types` map (`app/models/document.rb:380-453`) that translates each UI field type into a MongoMapper key type:

| Field type (sample) | Mongo key type |
|---------------------|----------------|
| `text_string` | `String` |
| `text_integer` | `Integer` |
| `text_float` | `Float` |
| `select_date` | `Date` |
| `relation_one` | `ObjectId` (reference to another `<project>.<table>` doc) |
| `relation_many` | `Array` (of `ObjectId`s) |
| `image_camera` / `extra_attachment` | `ObjectId`(s) → `<project>.attachment` |
| visual types (`chapter`/`section`/`tab`/`html`/`clear`) | `nil` (no column added) |

Adding a field via `Document#add_field` (`app/models/document.rb:65-73`) mutates the linked `Table#data` (appending a `key` line), so the next generated Mongo class includes the new column. The field designer and tree layout (`tree_data`) are covered in "08 - View Rendering & Content/Attachment Flow".

### 3.3 Per-solution database selection

Each solution gets its own Mongo database. `Esm#db_name` returns `"#{MONGO_PREFIX}-#{self.name}"` → **`esm_emr-<solution>`** (`app/models/esm.rb:147-149`); `MONGO_PREFIX = 'esm_emr'` is a global constant (`config/initializers/esm.rb`). At request time `EsmProxyController#index` mutates `MongoMapper.database` to the active solution's `db_name` (`app/controllers/esm_proxy_controller.rb:19-23`).

```
Per-solution Mongo DB selection at runtime:
 request -> EsmController#context_filter (resolve @current_solution)
        -> EsmProxyController#index
             MongoMapper.database = @current_solution.db_name   # 'esm_emr-<name>'
             Service.get(package) -> Service#load (eval class)
             obj.send(opt, params)
             models read/write '<project>.<table>' collections + GridFS
```

> **Threading hazard:** `MongoMapper.database` is **global per-request state**. Under a threaded server this would be a cross-tenant data-leak race. It is "safe" only because the deployed server is single-threaded/evented Thin (the commented-out puma `-w4` would break this). See "06 - Docker & Infrastructure / Deployment".

### 3.4 Confusing / vestigial Mongo configuration

There are three competing Mongo config sources, and the configured DB names are largely **vestigial** because the real per-request DB is set by `MongoMapper.database = solution.db_name`:

| Source | What it says | Effect |
|--------|--------------|--------|
| `config/mongo.yml:1-22` | host `mongo`:27017, w:1, pool_size 1, dev DB `esmx_development`, prod DB `esmx` | **Never read by any initializer.** |
| `config/initializers/mongodb.rb:3-13` | `MongoMapper.config` from `ENV['MONGOHQ_URL']` or hardcoded `mongodb://mongo/xxxxxxxx`; sets DB name `palette-<env>` | This is the **real boot connection** (runs first, alphabetically). |
| `config/initializers/mongomapper.rb:5,16-21` | reads `['logger']`; would `YAML.load` a non-existent `config/mongodb.yml` | Guarded behind `unless ...class_variables.include?(:@@database_name)`, which is already true after `mongodb.rb` ran, so the missing-file branch is **skipped**; it only turns logging off and prints `Initialized: <dbname>`. |

Net effect: the boot-time default DB resolves to `palette-development` (or whatever `ENV['MONGOHQ_URL']` provides), but **actual instance data is served from `esm_emr-<solution>`** because the proxy overrides it per request. The exact production value of `ENV['MONGOHQ_URL']`/`MONGO_USERNAME`/`MONGO_PASSWORD` is not set in the repo (the compose `mongo` service has no auth), so the hardcoded fallback is *likely* what runs — but the live env cannot be confirmed (**unverified / to confirm**).

```
MongoDB / GridFS model (per solution DB `esm_emr-<solution>`):

  Mongo DB: esm_emr-<solution_name>
    ├── collection <project>.<table>      (one per esm_tables row; schema from esm_tables.data/.command)
    │     { _id:ObjectId, <fields...>, created_at, updated_at }
    │        relation_one  -> ObjectId  -> another <project>.<table> doc
    │        relation_many -> [ObjectId,...]
    │        image_camera/extra_attachment -> ObjectId(s) -> <project>.attachment
    ├── collection <project>.attachment
    │     { _id, title, filename, path, ssid, ref, project_id,
    │       file_id:ObjectId, thumb_id:ObjectId, original_id:ObjectId }
    └── GridFS (default fs.files / fs.chunks)
          binary blobs referenced by file_id / thumb_id / original_id
```

---

## 4. GridFS (binary attachments)

Uploaded files (images, PDFs, etc.) are stored in MongoDB **GridFS**, not on disk, and not in a document collection. The flow:

- **Write:** `Document#attach_field_file` (`app/models/document.rb:560-614`) does `grid = Mongo::Grid.new(MongoMapper.database); id = grid.put(content, :filename => filename)` and stores the returned `ObjectId` on the `Attachment` record's `file_id`. JPEGs are resized via a shell-out to ImageMagick `convert` before being stored.
- **Read:** `EsmAttachmentsController#show` (`app/controllers/esm_attachments_controller.rb:15,26-48`) resolves `Esm → Project → attachment_model → record`, then streams bytes via `Mongo::Grid#get(file_id)` (or `thumb_id`, generating a thumbnail on demand and caching it back into GridFS).
- **Static content:** `EsmProxyController#index` (`app/controllers/esm_proxy_controller.rb:25`) serves arbitrary path content via `Mongo::GridFileSystem.new(MongoMapper.database).open(path)` before any service dispatch.

The `Attachment` MongoMapper class (collection `<project>.attachment`, generated at `app/models/schema.rb:100-112`) carries `file_id`, `thumb_id`, and `original_id` ObjectIds, supporting on-the-fly thumbnails and image versioning.

> **GridFS bucket prefix:** `Mongo::Grid.new`/`Mongo::GridFileSystem.new` are called with only the DB (no custom prefix), so GridFS uses the **default `fs.files` / `fs.chunks`** bucket in the mongo 1.x driver. This is inferred from the gem default, not from an explicit config in the repo (**unverified / to confirm**). The commented `Mongo::Grid.new(MongoMapper.database, 'attachments')` in `config/initializers/mongomapper.rb:23` is **not** used.
>
> **Note:** there is a *separate* on-disk content store — the el_finder file manager (`EsmContentController`) operates against `public/esm/<solution>/<project>` on the filesystem, **not** GridFS. Document attachments and the file manager are two different, non-unified stores. See "08 - View Rendering & Content/Attachment Flow".
>
> **`rack-gridfs` middleware:** the gem (0.4.1) is in the Gemfile but no `Rack::GridFS` mount was found in `config/`; all GridFS access is via `Mongo::Grid`/`GridFileSystem` directly (**unverified / to confirm** whether it is wired in an unread view/initializer).

---

## 5. Redis usage

Redis is used **only** for the Resque background-job queue. There is no confirmed use as a Rails cache or session store (sessions use `:cookie_store`; `production.rb` has the `:redis_store` cache line commented out).

- **Connection:** `config/resque.yml:1,5` → `redis://redis:6379/` for both development and production.
- **Namespace:** `resque:task` (`config/initializers/resque.rb:5-6`).
- **Queues:** `:task`, `:job`, `default`.
- **Producers:** `Task.enqueue` → `Resque::Job.create(queue, self, params)` (`app/models/task.rb:16,29-33`); `Resque.enqueue(Job::JobTest, params)` (`app/models/job.rb:7-29`); `ServiceHelper#enqueue_job`.
- **Consumers (workers):** `Task`, `Job::JobTest`, `PdfGenerator` (PDFKit/wkhtmltopdf), `CMDTask` (which `eval`s arbitrary code — see "08/Operation Execution Flow" and Gotchas).
- **Web UI:** `Resque::Server` is mounted at `/resque` (`config/routes.rb:5`), unauthenticated.

```
Redis usage:
  Redis (host redis:6379, db 0)
    └── namespace 'resque:task'  (Resque.redis.namespace)
         queues: :task, :job, default
         producers: Task.enqueue (Resque::Job.create), Resque.enqueue(Job::JobTest), enqueue_job
         consumers: Resque workers -> Task/JobTest/PdfGenerator/CMDTask#perform
  Resque::Server mounted at /resque (routes.rb)
  resque-scheduler gem present (4.0.0) but no schedule config file found.
```

> **Operational caveats:**
> - **No worker process is started in `docker-compose.yml`** — only the Thin web container runs. Jobs enqueue into Redis but **nothing dequeues them** unless `rake resque:work` is started out-of-band. Whether a worker runs in the real production deployment is **unverified / to confirm** (the `.dockerignore` listing `nohup.out` hints at a manual launch). See "06 - Docker & Infrastructure / Deployment".
> - **`resque-scheduler`** (4.0.0) is bundled but never wired — no `schedule.yml`, no `resque/scheduler` require, no `enqueue_at`/`enqueue_in` calls. Cron/delayed scheduling is effectively dead.
> - Redis has **no persistent volume**, so any queued jobs are lost on container recreation.

---

## 6. MySQL migration timeline

The MySQL schema evolved over `db/migrate/` from 2011 to 2015. The store has only ever been MySQL for metadata; there are no migrations that touch Mongo (Mongo collections are created implicitly at runtime). Final `schema.rb` version: `20150317170313`.

| Date (migration) | What it added |
|------------------|---------------|
| `20110917102546_esm_core_system` | Core system tables (esms / users / roles bootstrap) |
| `20111002094148_project_service_operation` | The `Project > Service > Operation` chain |
| `20111028122523_rename_esm_services` | Renamed `esm_services.service_id` → `extended` (service inheritance) |
| `20111110041611_esm_seeds` | Seeds the 5 `ScriptTemplate` generators (ServiceTemplate / HTMLTemplate / PartialTemplate / LayoutTemplate / EvalTemplate) — drives code-gen |
| `20111129182950_add_domain_to_esm_projects` | `esm_projects.domain` (subdomain/host tenant resolution) |
| `20111211164400_create_esm_tables` | `esm_tables` (Mongo collection definitions) |
| `20111211165417_create_esm_schemas` | `esm_schemas` (data-shape container) |
| `20111229073001_add_project_to_menu_actions` | `menu_actions.project_id` |
| `20120108074402_create_esm_documents` | `esm_documents` (form/field definitions) |
| `20120205041812_add_project_to_roles` | `roles.project_id` |
| `20120210082254_add_title_to_esm_projects` | `esm_projects.title` |
| `20120212151615_add_serivce_id_to_esm_documents` | `esm_documents.service_id` (note the typo `serivce` in the filename) |
| `20120216163642_create_accounts` | `accounts` join table (User ↔ Esm ↔ Role) |
| `20120518152807_add_project_inheritance_to_esm_projects` | `esm_projects.extended` + `extended_acl_id` (project inheritance / ACL backbone) |
| `20120612075609_add_acl_to_esm_projects` | `acl` string column on `esm_projects`/`esm_services`/`esm_operations`/`menu_actions` (the ACL system) |
| `20130412054728_add_group_to_settings` | `settings.group` |
| `20140306173722_add_command_to_esm_tables` | `esm_tables.command` (extra MongoMapper class body) |
| `20140924092404_add_tree_data_to_esm_documents` | `esm_documents.tree_data` (designer layout) |
| `20150317170313_add_columns_to_users` | Final user columns (`name`, `last_actived`, `current_session`) |

### Seeding / restore baseline

- `db/seeds.rb` is **empty** (only Rails example comments). Real seed data lives in migration `20111110041611_esm_seeds.rb` (the ScriptTemplate generators) plus the SQL dumps.
- `db/base-20150204.sql` is a ~3.2 MB full MySQL dump originating from prod DB `soup_siamsky`, MySQL 5.0.51a, InnoDB, utf8/utf8_unicode_ci — the same 14 tables plus `schema_migrations` (`db/base-20150204.sql:1-5`).
- `seed/seed.sql` (~20 MB, header `Distrib 5.5.31`) is COPYed into `/docker-entrypoint-initdb.d/` by `seed/Dockerfile` (`MYSQL_DATABASE=soup_esm_emr`) and auto-loads **only on a fresh datadir**. Because `./databases/mysql` is bind-mounted and already populated, re-seeding requires wiping that directory. See "06 - Docker & Infrastructure / Deployment".

> Whether `seed.sql` (generated by MySQL 5.5.31) imports cleanly under the compose MySQL 8.2 is **unverified / to confirm** — deprecated `TYPE`/charset/SQL_MODE constructs may break import.

---

## 7. Which model uses which store

Use this table to know where any given model's data lives.

| Model | File | Store | Backing table / collection |
|-------|------|-------|----------------------------|
| `Esm` | `app/models/esm.rb` | MySQL | `esms` |
| `Project` | `app/models/project.rb` | MySQL | `esm_projects` |
| `Service` | `app/models/service.rb` | MySQL | `esm_services` |
| `Operation` | `app/models/operation.rb` | MySQL | `esm_operations` |
| `Schema` | `app/models/schema.rb` | MySQL | `esm_schemas` |
| `Table` | `app/models/table.rb` | MySQL | `esm_tables` |
| `Document` | `app/models/document.rb` | **MySQL** (definition only) | `esm_documents` |
| `ScriptTemplate` | `app/models/script_template.rb` | MySQL | `esm_templates` |
| `User` | `app/models/user.rb` | MySQL | `users` |
| `Role` | `app/models/role.rb` | MySQL | `roles` |
| `Account` | `app/models/account.rb` | MySQL | `accounts` |
| `Permission` | `app/models/permission.rb` | MySQL | `permissions` (unused for auth) |
| `MenuAction` | `app/models/menu_action.rb` | MySQL | `menu_actions` |
| `Setting` | `app/models/setting.rb` | MySQL | `settings` |
| `Log` | `app/models/log.rb` | MySQL | `logs` |
| `Field` | `app/models/field.rb` | **None** — a Ruby `Struct`, serialized inside `Document#data` (no table) |
| Generated `<table>` classes | `app/models/schema.rb` (runtime ERB+eval) | **MongoDB** | `<project>.<table>` |
| Generated `Attachment` class | `app/models/schema.rb` (runtime ERB+eval) | **MongoDB + GridFS** | `<project>.attachment` collection + `fs.*` blobs |
| `Fields::Relation` / `RelationOne` / `RelationMany` | `app/models/fields/*.rb` | **None** — resolve/persist *into* Mongo via the generated classes; not persisted themselves |
| `Task` / `Job::JobTest` / `PdfGenerator` / `CMDTask` | `app/models/task.rb`, `app/models/job.rb`, `app/models/workers/*.rb` | **Redis** (Resque payloads) — plain Ruby, not AR/MM |

**Rule of thumb:**
- *Anything that defines the app* (the catalog) → **MySQL**, ActiveRecord, `esm_*` / auth tables.
- *Anything an end user actually saves* (patient records, form data) → **MongoDB**, runtime-generated MongoMapper classes, `<project>.<table>` collections.
- *Anything binary* (images, PDFs) → **GridFS**, referenced by ObjectId from `<project>.attachment`.
- *Anything async* → **Redis** via Resque.

---

## 8. Key files

| Path | Purpose |
|------|---------|
| `db/schema.rb` | Authoritative MySQL schema, version `20150317170313`, 14 tables |
| `db/migrate/` | 19 migrations (2011–2015) — see §6 timeline |
| `db/base-20150204.sql` | Full prod MySQL dump (restore baseline, `soup_siamsky`) |
| `seed/seed.sql` | 20 MB seed dump auto-loaded into a fresh MySQL datadir |
| `config/database.yml` | MySQL connection (`soup_esm_emr`, host `db`); test uses sqlite3 |
| `config/mongo.yml` | MongoMapper defaults — **not actually read** by initializers |
| `config/initializers/mongodb.rb` | The real boot Mongo connection (`palette-<env>`) |
| `config/initializers/mongomapper.rb` | Secondary Mongo init (logging only at boot) |
| `config/initializers/esm.rb` | `MONGO_PREFIX='esm_emr'`, `DOMAIN='emr-life.com'` |
| `config/resque.yml` / `config/initializers/resque.rb` | Redis endpoint + Resque namespace `resque:task` |
| `app/models/schema.rb` | **Mongo layer core**: `Schema#load_model` ERB-generates MongoMapper classes |
| `app/models/document.rb` | Form/field definitions (YAML); record CRUD; GridFS attachment upload |
| `app/models/field.rb` | `Field` Struct + 28 field types → Mongo key-type map |
| `app/models/esm.rb` | `Esm#db_name` → `esm_emr-<solution>` |
| `app/controllers/esm_proxy_controller.rb` | Sets `MongoMapper.database` per request; serves GridFS static content |
| `app/controllers/esm_attachments_controller.rb` | Reads/serves attachment binaries from GridFS |

---

## 9. Gotchas / risks

- **`Document` is MySQL, not Mongo.** `app/models/document.rb` (`self.table_name = :esm_documents`, `:4,11`) stores form DEFINITIONS as YAML. The actual records are runtime-generated MongoMapper classes. This is the single most common confusion in the codebase.
- **No database-level foreign keys.** Confirmed in `db/schema.rb` and the base SQL CREATE TABLEs (only `PRIMARY KEY` on `id`). All referential integrity is application-level via AR associations and bare integer `*_id` columns — orphan rows are likely.
- **Runtime `eval` of metadata is a massive RCE/injection surface.** `Schema#load_model` (`app/models/schema.rb:143`) and `Service#load` `eval` Ruby source built from user-editable columns (`esm_tables.data`/`command`, `esm_operations.command`). `field.params` is parsed with `eval("{#{i.params}}")` (`app/models/schema.rb:50`); `Project#get_params` evals `self.params`; `CMDTask` evals `params['cmd']`. Anyone who can write metadata can execute arbitrary Ruby in the web/worker process. See "03 - Authentication & Authorization" and "07 - Metadata-Driven Architecture".
- **`MongoMapper.database` is mutated globally per request** (`app/controllers/esm_proxy_controller.rb:19-23`). Under a threaded server this is a cross-tenant data-leak race; only safe because the deployed server is single-threaded Thin.
- **TEXT(65535) columns can truncate.** `esm_documents.data`, `esm_tables.data`/`command`, etc. are MySQL `TEXT`. A large form/table definition can be silently truncated, corrupting the generated Mongo schema.
- **Three competing Mongo configs; configured DB names are vestigial.** `config/mongo.yml` (`esmx`) is never read; `mongodb.rb` sets `palette-<env>`; the real per-request DB is `esm_emr-<solution>`. Easy to chase the wrong DB name when debugging.
- **GridFS default bucket assumed.** `fs.files`/`fs.chunks` is inferred from the mongo 1.x driver default, not from explicit config (**unverified / to confirm**).
- **Hardcoded credentials in repo.** MySQL `root` / `minadadmin` (`config/database.yml`, `docker-compose.yml`). MongoDB has no auth in dev/compose; prod auth depends on unset `ENV` vars.
- **End-of-life stack.** `mongo` 1.12.5 + `mongo_mapper` 0.14.0 + `bson_ext` (legacy driver), `mysql2` 0.3.21, Mongo server pinned to 3.2 (EOL), MySQL 8.2 paired with the pre-MySQL-8 mysql2 driver (requires `--default-authentication-plugin=mysql_native_password`).
- **Thai Buddhist-calendar date hack.** In `Document#filter_record_params` (`app/models/document.rb` ~262-270), `select_date` values with year > current+200 have 543 subtracted before write — silent locale-specific date mutation.
- **Circular `extended` references** in projects/services would infinite-loop `init_instance`/`extended_list` (**unverified / to confirm** whether any guard exists).
- **Redis is Resque-only and ephemeral**; no worker runs in compose, so jobs queue but never execute in the default Docker setup.
