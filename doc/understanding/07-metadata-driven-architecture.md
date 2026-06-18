# 07 - Metadata-Driven Architecture

> **Audience:** the engineer taking full ownership of the ESM legacy Rails 4.2 EMR platform.
> **Scope of this doc:** the heart of the system — how rows in MySQL metadata tables become a *running application* at request time through ERB code generation and `eval`. For boot order, server stack, and infrastructure see **"01 - Architecture & Application Bootstrapping"**; for the URL-to-controller mapping see **"02 - Request Flow & Routing"**; for the ACL gate see **"03 - Authentication & Authorization"**; for the storage split see **"04 - Database Structure"**; for the model catalog see **"05 - Core Domain Models & Relationships"**; for sync/async execution see **"08 - Operation Execution Flow"**; for the view side see **"09 - View Rendering & Content/Attachment Flow"**.

## The one idea you must internalize

In ESM there is **no application source code on disk for the apps it hosts**. An "application" is *data*: rows in MySQL tables (`esms`, `esm_projects`, `esm_services`, `esm_operations`, `esm_schemas`, `esm_tables`, `esm_documents`). At request time the platform reads that metadata, builds Ruby source code as a **string** via ERB templates, runs `eval` on the string to define real classes in memory, instantiates one, and dispatches the requested method. The end-user records those apps operate on live in MongoDB collections that are *also* defined by metadata and *also* materialized through `eval`.

So there are two distinct planes, both ActiveRecord/MySQL on the *definition* side but diverging on the *instance* side:

| Plane | Stored as | Lives in | Materialized by |
|---|---|---|---|
| **Behavior** (controllers/actions) | `esm_services` + `esm_operations` rows (`command` = raw Ruby/ERB text) | MySQL | `Service#load` -> ERB + `eval` -> a Ruby class, instantiated per request (`app/models/service.rb:126`) |
| **Data structure** (collections/columns) | `esm_schemas` + `esm_tables` rows (`data` = literal `key :col, Type` lines) | MySQL | `Schema#load_model` -> ERB + `eval` -> `MongoMapper::Document` subclasses (`app/models/schema.rb:30`) |
| **Form definition** (fields/layout) | `esm_documents` rows (`data` = YAML of `Field` structs) | MySQL | deserialized into `Field` structs; drives the `esm_tables.data` columns (`app/models/document.rb`) |
| **End-user records** ("documents") | n/a (runtime) | per-solution MongoDB DB `esm_emr-<name>` | the eval'd MongoMapper classes; binaries in GridFS |

> **Naming trap — read this twice.** `Document` (`app/models/document.rb`) is an **ActiveRecord** model on the MySQL table `esm_documents` that stores a *form/field definition* as YAML. It is **not** a MongoDB document. The real Mongo documents are anonymous classes generated at runtime by `Schema#load_model`. Conflating the two will mislead every investigation you do. (`app/models/document.rb:4,11`)

## The metadata hierarchy

```
Esm (solution)         db_name = "esm_emr-<name>"  -> selects the MongoDB database
 |  has_many
 v
Project                package = "<esm>.<name>" ; may `extended` another Project
 |\__ has_one  Schema --< has_many >-- Table   (data: "key :col, Type" lines ; command: extra body)
 |                                       ^ schema.rb ERB+eval => class <Name> < MongoMapper::Document
 |                                                              bound to collection "<project>.<table>"
 | has_many
 v
Service                package = "<proj>.<Svc>" ; may `extended` another Service
 |  service.rb ERB+eval => class <ClassName> < EsmSuperClass
 | has_many
 v
Operation              command (raw Ruby/ERB) ; template_id -> ScriptTemplate ; acl

Document (data: YAML of Field structs) --belongs_to--> Table
 |  add_field => table.add_column (appends a "key" line)
 v
Field (Struct: field_type, column_name, lov, params)  -- data_types map --> Mongo key Type
```

Confirmed associations and identity rules:

- `Esm#db_name => "#{MONGO_PREFIX}-#{self.name}"`, i.e. `esm_emr-<solution>` — the per-solution Mongo database name. `MONGO_PREFIX = 'esm_emr'` is a global constant. (`app/models/esm.rb:147-149`, `config/initializers/esm.rb:1-2`)
- `Project#package = "#{esm.name}.#{name}"` set before save; `has_one :schema`, `has_many :services/documents/menu_actions/settings/roles`. (`app/models/project.rb:8-17,70`)
- `Service#package = "#{project.package}.#{name.camelize}"`; `has_many :operations`; optional `extended` pointing at another service's package. (`app/models/service.rb`)
- `Operation belongs_to :service` and `belongs_to :script_template` (foreign key `template_id`); holds `command` + `acl`. (`app/models/operation.rb:10`)

## The behavior plane: `Service#load` — metadata becomes a Ruby class

This is the single most important method in the codebase. `Service#load(context)` (`app/models/service.rb:126`) does the following, **verified against source**:

1. **Build the inheritance call stack.** `stack = [self] + self.extended_list` so a service that `extended` another service inherits its generated methods. (`service.rb:131-133`)
2. **Emit an inline `EsmSuperClass`** as a heredoc string (`service.rb:135-189`). This is the runtime base class. It defines `initialize`, `params`, `context`, `render_template`, `layout`, `context_menu`, and a `method_missing` that returns the literal string `"No service"`.
3. **For each service in the reversed stack, ERB-render a subclass** (`service.rb:217-240`). The class header chooses its superclass dynamically:
   ```ruby
   class <%=class_name%> < <%= s.extended && s.extended!="" ? s.extended.strip.split('.').reverse.join : 'EsmSuperClass' %>
   ```
   Each `Operation` becomes a method. **Two paths**, both confirmed at `service.rb:229-238`:
   - With a `template_id`: `def <name> *params; @params = params[0] if params[0]; ret = <ScriptTemplate#generate(command)> end`
   - Without one: the operation's `command` is spliced in **verbatim as raw method source** (`<%= m.command %>`).
4. **Concatenate** superclass + all subclass bodies into one string `tmp`. (`service.rb:193,250`)
5. **`eval(tmp)`** defines the classes. (`service.rb:259`)
6. **`return eval("#{class_name}.new context")`** instantiates and hands back the live object. (`service.rb:262`)

`class_name` is the package string reversed and joined, e.g. `acme.clinic.Patient` -> `PatientclinicAcme`. (`service.rb:199`)

> **No caching.** `cache = false` is hard-set at `service.rb:195`, and the file-cache read/write lines are commented out (`service.rb:202-208,243-245`). The entire class hierarchy is **regenerated and `eval`'d on every request**, including the recursive `home` service for the layout. This is both a performance cost and a constant-redefinition concern.

### `ScriptTemplate` — the operation-to-method generator

When an operation has a `template_id`, its `command` is wrapped by a `ScriptTemplate`. The generator is itself ERB run in the model's binding:

```ruby
def generate(command, this, params)
  ERB.new(self.generator).result(binding)
end
```
(`app/models/script_template.rb:8-10`)

There are **five seeded generators** (`ServiceTemplate`, `HTMLTemplate`, `PartialTemplate`, `LayoutTemplate`, `EvalTemplate`), confirmed from the seed data (`seed/seed.sql`, `esm_templates` INSERT; also `db/migrate/20111110041611_esm_seeds.rb`). For example `HTMLTemplate` expands an operation into `render_template(com, self, params, true)` (with layout); `PartialTemplate` does so without a layout. The actual generator bodies live in DB rows, **not in source** — to inspect them you must query `esm_templates`.

> **Open question / to confirm:** the running DB may contain `ScriptTemplate` rows created later through the workspace IDE beyond the five seeded ones. Only the five seeded generators are verified; enumerate `esm_templates` in the live DB to be sure.

### `Operation#command` escaping

`Operation#init`/`#escape` backslash-escape `#{` on save and unescape on load so stored `command` text is not prematurely interpolated until the generated method actually runs. (`app/models/operation.rb:20-30`) Editing operations outside the workspace (direct SQL, seed edits) can desync this escaping and break the generated method or open injection.

### Two `EsmSuperClass` definitions — which one runs

There is a standalone file `app/models/esm_super_class.rb` that renders via `ActionView::Base` against a hardcoded `vendor/plugins/esm_essential/app/views` path. **It is not the one that runs.** The live `EsmSuperClass` is the heredoc string emitted inside `Service#load` (`service.rb:135-189`), which uses `controller.render(:inline=>...)`. Editing the standalone file has no effect on request rendering. (Treat the file as legacy/dead until proven otherwise — its vendored view path was not verified to exist.)

## The data plane: `Schema#load_model` — metadata becomes MongoMapper classes

`Schema#load_model(project_instance, model_name)` (`app/models/schema.rb:30`) generates the ORM the same way `Service#load` generates behavior — ERB string + `eval` (verified by reading the method):

- It builds a template (`schema.rb:76-138`) that:
  - declares a base `class MongoConnect; include MongoMapper::Document; end` (`schema.rb:78-80`);
  - sets `MongoMapper.database = '<%=self.project.esm.db_name%>'` *inside the generated code* (`schema.rb:82`);
  - declares a fixed `Attachment < MongoConnect` on collection `"<project>.attachment"` with keys `title, selected, params, ref, filename, path, project_id, ssid, file_id(ObjectId), thumb_id(ObjectId), original_id(ObjectId)` (`schema.rb:86-113`);
  - for each `Table`, declares `class <Name.camelize> < MongoConnect; set_collection_name "<project>.<table>"; <%= table.data %>; timestamps!; end` (`schema.rb:115-124`), then a **second pass** splicing `<%= table.command %>` for extra methods (`schema.rb:127-133`);
  - finally evaluates to a hash `{:attachment=>Attachment, :<table>=><Class>, ...}` (`schema.rb:137`).
- `command = ERB.new(template).result(binding)` then `models = eval(command)` (`schema.rb:140,143`).
- Returns the whole hash, or a single model when `model_name` is given (`schema.rb:144-148`).

`Table.data` literally stores MongoMapper DSL lines — e.g. the seeded `user` table's `data` is `"\n\tkey :first_name, String..."`. `Table#add_column`/`#data_columns` parse and append these `key` lines. (`app/models/table.rb:6-28`, `:20-27`)

### `SchemaProxy` — lazy per-model loading

`SchemaProxy < Hash` (`schema.rb:1-15`) defers compilation: `proxy[:patient]` calls `@schema.load_model(@project, "patient")`, so only the requested model (plus its relation targets) is generated. `Project#load_model`/`#get_model` are the public entry points and delegate to `Schema#load_model` with the merged instance. (`app/models/project.rb:113-119`)

## Documents: the form designer that drives the Mongo schema

A `Document` (MySQL `esm_documents`) holds its field set as YAML of `Field` structs in its `data` column, round-tripped on every save/load:

- `before_save_func` dumps `@fields` (as `FIELDCOMPRESSION` structs) to YAML into `data`. (`document.rb:26-34`)
- `after_initialize`/`after_find` -> `refresh_structure` re-loads `@fields` from YAML and filters by valid `field_type`. **Note:** the `rescue` around the YAML load is commented out (`document.rb:54-56`), so malformed data can raise or silently leave `@fields` empty.
- `get_model` returns the runtime MongoMapper class: `self.project.load_model[self.table.name.to_sym]`. (`document.rb:22-24`)

`Field` is **not** an ActiveRecord model — it is a Ruby `Struct` (`FIELD = Struct.new(...)`) serialized inside `Document`, with random ids `'F%010d'` generated via `rand` (collisions possible). (`app/models/field.rb:1,5,11`)

### Field type -> Mongo column type

`Document.data_types` maps each UI field type to a Mongo key type (`document.rb:380-453`). Adding a field auto-mutates the backing `Table`:

```ruby
def add_field field
  field = Field.new field
  @fields << field
  if field.column_name != "" and t = Field.data_types[field.field_type] and t != nil
    self.table.add_column field.column_name, t   # appends a "key :col, Type" line to Table.data
  end
  self.save
end
```
(`document.rb:65-73`)

Representative mappings (from `document.rb:412-453`):

| `field_type` | Mongo key type |
|---|---|
| `text_string` | `String` |
| `text_float` | `Float` |
| `select_date` | `Date` |
| `relation_one` | `ObjectId` |
| `relation_many` | `Array` |
| `image_camera` | `Array` |
| visual types (`chapter`/`section`/`tab`/`html`/`clear`) | `nil` (no column added) |

### Writing an instance record

`Document#record_create`/`#record_update` route posted params through `filter_record_params` (`document.rb:193-372`) before calling `model.create` / `record.update_attributes` on the eval'd MongoMapper class. Coercions confirmed:

- `relation_one` -> `BSON::ObjectId`, and if nested params exist, `Fields::RelationOne.filter_params` recreates the related Mongo record (destroying the old one — its ObjectId changes) and returns the new id. (`document.rb`, `app/models/fields/relation_one.rb:10-66`)
- `relation_many` -> JSON-decode to an array, `Fields::RelationMany.filter_params` updates/creates each and returns an array of ids. (`app/models/fields/relation_many.rb:10-75`)
- `select_date` -> Thai Buddhist-calendar fix: if the posted year is > current+200, subtract 543. (`document.rb:262-270`)
- `image_camera`/`image_selection` -> JSON-decode and GridFS attachment handling.

Relation targets are resolved at runtime by parsing `field.params` via `eval("{#{field.params}}")`, supporting local (`patient`) and cross-project (`ehr#patient`) references. (`app/models/fields/relation.rb:12-31`)

## The runtime entry point: `EsmProxyController#index`

Almost every dynamic app URL (`/esm/*package/:opt`, `/s/:service/:opt`, `/:solution/:project/:service/:opt`) funnels into `EsmProxyController#index` — see **"02 - Request Flow & Routing"** for the full route table and ordering caveats. The dispatch sequence, verified at `app/controllers/esm_proxy_controller.rb:15-108`:

1. **Select the Mongo database** for the tenant: `MongoMapper.database = @current_solution.db_name`, or, if no solution resolved, `"esm-" + params[:package].split('/')[0]` (note: untrusted input chooses the DB in that fallback). (`:19-23`)
2. **Try a GridFS static file first:** `Mongo::GridFileSystem.new(MongoMapper.database).open(request.path_info)`; if found, stream it and stop. (`:25-37`)
3. **Resolve the Service:** `Service.get("#{@current_project.package}.#{params[:service]}")` when `params[:service]` is present, else `Service.get(params[:package].split('/').join('.'))`. (`:41-45`)
4. **Re-bind context from the service:** `@current_project = s.project; @current_solution = @current_project.esm; @context = @current_solution` (overrides what `context_filter` set). (`:51-54`)
5. **Optional API auth:** if no logged-in user but `params[:user_id]`/`params[:api_key]` given, `User.where(id:, hashed_password:).first` — the password hash *is* the API key (see **"03 - Authentication & Authorization"**). (`:57-62`)
6. **ACL check:** `acl = s.get_acl(params[:opt], @current_user)`; if empty, default to `['user']`. Authorize if `acl` has `'*'`, OR the user is the owner, OR `acl` has `'user'`, OR `acl` matches the current role. (`:64-69`)
7. **Build and dispatch:**
   ```ruby
   @project_instance = @current_project.get_instance
   context = s.prepare(params, self, request)   # {project, service, params, controller, request}
   obj = s.load context                          # ERB + eval -> instance
   out = obj.send params[:opt], params           # invoke the operation method
   ```
   (`:70-75`) — note `out` is captured but never explicitly rendered; the operation renders itself (see **"09 - View Rendering"**).
8. **Error handling:** a broad `rescue Exception => e` formats `e.backtrace[0..10]`, emails via `msg_report` (XMPP), prints to stdout, and renders `public/500.html`. (`:82-101`) If no service resolves: plain text `"Not found service on server"`. (`:104`)

```
HTTP /:sol/:proj/:Svc/:opt
      |
      v
EsmController#context_filter  ->  @current_solution/@current_project/@current_user/@current_role
      |
      v
EsmProxyController#index
   1. MongoMapper.database = @current_solution.db_name
   2. GridFS static lookup (request.path_info) --found?--> render bytes (STOP)
   3. s = Service.get(package)
   4. re-bind @current_project/@current_solution/@context from s
   5. (optional) API-key auth via user_id + hashed_password
   6. acl = s.get_acl(opt, user)   (empty -> ['user'])  -> authorize
   7. context = s.prepare(...) ; obj = s.load(context)   <== ERB + eval per request
        |  build stack=[svc]+extended ; emit EsmSuperClass + per-svc class
        |  each Operation -> method via ScriptTemplate.generate ; eval(src) ; ClassName.new(context)
        v
      obj.send(params[:opt], params)
        |  (generated method body runs; render_template -> controller.render(:inline=>command))
        v
      HTTP response  (errors -> msg_report + public/500.html)
```

## Inheritance: how apps extend apps

Inheritance is pervasive and operates at two levels:

- **Project inheritance.** `Project#init_instance` walks the `extended` super-project chain (by package string) and merges menus, services, documents, tables, and settings **by name**, with the child overriding the parent. `get_instance` memoizes the merged `@instance`. (`app/models/project.rb:277-386`; refresh via `get_refresh_instance`.)
- **Service inheritance.** `Service#load` reverses the stack so the most-derived class `< ` its ancestor's generated class. Document-backed services typically `extended` `system.util.Document` to inherit generic CRUD. (`service.rb:198-219`; provisioning at `app/controllers/esm_documents_controller.rb:23-37`)

> **Cycle risk / to confirm:** circular `extended` references would infinite-loop the merge/stack walk. Separately, `Service#get_extended` (`service.rb:45-47`) calls itself unconditionally and would stack-overflow if ever invoked — it appears buggy/unreachable, not part of the live path. Verify before relying on either.

## How a new app is created (design time)

The workspace controllers (`EsmProjectsController`, `EsmServicesController`, `EsmOperationsController`, `EsmTablesController`, `EsmDocumentsController`) are the IDE for editing the metadata itself. The key auto-provisioning step: `EsmDocumentsController#new` creates a `Document` **and** auto-creates its backing `Table`, a `Service` that `extended`s `system.util.Document`, a `MenuAction`, and a `document_name` operation — turning a single metadata definition into a working CRUD app. (`app/controllers/esm_documents_controller.rb:23-37`) Adding a `Field` (`field_new`) calls `Document#add_field`, which appends a `key` line to the `Table.data` column so the next `Schema#load_model` includes the new Mongo column.

## Key files

| Path | Purpose |
|---|---|
| `app/models/service.rb:126` | `Service#load` — builds `EsmSuperClass` + per-service classes from operations, `eval`s, returns an instance. The core of dynamic behavior. |
| `app/models/script_template.rb:8` | `ScriptTemplate#generate` — ERB-runs the `generator` field to turn an operation `command` into method source. |
| `app/models/operation.rb` | Operation metadata; `command`/`acl`; `#{` escaping on save (`:20-30`). |
| `app/models/schema.rb:30` | `Schema#load_model` — ERB-generates `MongoConnect`/`Attachment`/per-table MongoMapper classes, `eval`s them. The core of dynamic data structures. `SchemaProxy` lazy-loads. |
| `app/models/table.rb` | Stores literal `key :col, Type` lines in `data`; `add_column`/`data_columns` (`:6-28`). |
| `app/models/document.rb` | Form designer: YAML `Field` structs in `data`; `field_types`/`data_types` (`:380-453`); `record_create`/`filter_record_params` (`:193-372`); field<->column sync (`:65-73`). |
| `app/models/field.rb` | `Field` `Struct` (not AR); compression round-trip; LOV parsing. |
| `app/models/project.rb:277` | `init_instance` merges metadata across inheritance; `load_model`/`get_model`/`get_schema`/`get_document`/`get_service`. |
| `app/models/esm.rb:147` | `db_name => "esm_emr-<name>"` — the per-solution Mongo DB. |
| `app/controllers/esm_proxy_controller.rb:15` | The single runtime dispatcher: package -> Service -> ACL -> `s.load` -> `obj.send(opt, params)`. |
| `config/initializers/esm.rb:1` | Global constants `MONGO_PREFIX='esm_emr'`, `DOMAIN='emr-life.com'`. |
| `db/migrate/20111110041611_esm_seeds.rb` / `seed/seed.sql` | Seeds the five `ScriptTemplate` generators and base metadata. |

## Gotchas / risks

- **Pervasive `eval` of DB-stored metadata = arbitrary RCE/SSTI by design.** `Service#load` evals a class body assembled from `Operation.command` (`service.rb:259`), `Schema#load_model` evals generated ORM source (`schema.rb:143`), and `field.params` is evaled as `eval("{#{field.params}}")` in multiple places (`schema.rb:50`, `relation.rb:14`, `document.rb`). `Project#get_params` evals `self.params` too. Anyone who can write operation/table/field metadata gets code execution in the web process on the next request. This is the dominant security property of the whole platform — treat metadata as untrusted code.
- **No class caching.** `cache = false` (`service.rb:195`) means the full hierarchy — including the recursively-loaded `home` service for the layout — is regenerated and eval'd on **every request**. Performance cost plus repeated constant redefinition. `Schema#load_model` likewise recompiles per call, and a single CRUD action calls `project.load_model` repeatedly (e.g. `document.rb` `filter_record_params`, `analysis_attributes`).
- **`method_missing` returns the string `"No service"`** instead of raising (`service.rb:185-187`), so a typo'd or missing operation silently renders the literal text `"No service"` rather than a 404. Combined with `obj.send(params[:opt], ...)`, the URL can invoke any public method on the generated object (including inherited helpers).
- **CSRF disabled on the dynamic surface.** `EsmProxyController` and `EsmDocumentsController` `skip_before_filter :verify_authenticity_token`. (`esm_proxy_controller.rb:4`)
- **ACL defaults partially open.** Empty ACL becomes `['user']` (`esm_proxy_controller.rb:66`), so an operation with no ACL configured is reachable by any logged-in user. The authorize boolean uses tricky `and`/`or` precedence — easy to misread. See **"03 - Authentication & Authorization"**.
- **`TEXT` column truncation.** `esm_documents.data` and `esm_tables.data` are `TEXT(65535)` in MySQL (`db/schema.rb`); a large Document YAML or Table key list can silently truncate and corrupt the generated schema.
- **Stale dates.** `select_date` silently subtracts 543 years for years > current+200 (`document.rb:262-270`) — Thai-locale-specific and lossy.
- **Relation persistence is destructive.** `RelationOne.filter_params` deletes and recreates the related Mongo record on every update, changing its ObjectId and risking dangling references (`relation_one.rb:25-31`). Note the asymmetry: `RelationMany` does **not** inherit `Fields::Relation` while `RelationOne` does.
- **Collection/DB names are unsanitized string concatenations** of project/esm names (`schema.rb:82,116-118`, `esm.rb:147-149`); renaming a project or solution orphans its Mongo collections.
- **Tenant DB selection is global mutable state.** `MongoMapper.database` is set per request in `EsmProxyController` (`:19-23`); safe only because Thin is single-threaded/evented. Under a threaded server this is a cross-tenant data-leak race. See **"01 - Architecture & Application Bootstrapping"** and **"06 - Docker & Infrastructure"**.

### Unverified / to confirm

- The full grammar of `field.params` for relations (beyond `:relation=>{:document, :fields, :partial}`) is inferred from eval sites, not documented in any single source file.
- How `esm_documents.tree_data` is authored and its complete node schema — `get_root_data_node`/`mapping` (`document.rb:826-988`) consume it but the producing UI/JS was not read.
- The actual `generator` bodies of the `ScriptTemplate` rows live in `esm_templates` (DB), not in source; only the five seeded generators are confirmed. Additional templates may have been created via the IDE.
- Which Mongo DB name actually serves instance data depends on initializer load order (`config/initializers/mongodb.rb` hardcodes `palette-<env>`) versus the per-request `MongoMapper.database = esm.db_name` override; the request-time override wins for app traffic, but confirm against the live env (see **"04 - Database Structure"** and **"06 - Docker & Infrastructure"**).
- Whether the standalone `app/models/esm_super_class.rb` is referenced anywhere in the live path, or is purely legacy (its `vendor/plugins/esm_essential` view path was not verified to exist).

