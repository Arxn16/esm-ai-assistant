# 05 - Core Domain Models

This document maps the complete domain model of the ESM legacy EMR platform: every model, where it persists, how the models relate, what each is responsible for, and the class-relationship diagram. It goes deep on the three models you will touch most as the owner of this codebase — `app/models/document.rb`, `app/models/project.rb`, and `app/models/service.rb` — because all three are not ordinary ActiveRecord models: they are *runtime compilers* that turn database rows into live Ruby classes via ERB + `eval`.

> Cross-references: the request path that drives these models is covered in **"02 - Request Flow & Routing"**; how operations actually run (sync + Resque) is in **"07 - Operation Execution Flow"**; the metadata-driven philosophy as a whole is **"06 - Metadata-Driven Architecture"**; the three datastores are **"04 - Database Structure"**; and how output is produced is **"08 - View Rendering & Content/Attachment Flow"**.

## The two persistence layers

ESM runs a deliberate **dual-ORM** design. Understanding which layer a model lives in is the single most important fact about the domain model.

| Layer | Store | ORM | What it holds | Models |
|---|---|---|---|---|
| **Metadata / definition** | MySQL (`soup_esm_emr`) | ActiveRecord | The *definition* of every application — solutions, projects, services, operations, schemas, tables, form definitions, users, roles, menus, settings, code-gen templates, logs | `Esm`, `Project`, `Service`, `Operation`, `Schema`, `Table`, `Document`, `User`, `Role`, `Account`, `Permission`, `MenuAction`, `Setting`, `Log`, `ScriptTemplate` |
| **Runtime / instance** | MongoDB (`esm_emr-<solution>`) + GridFS | MongoMapper (mongo 1.x) | The actual end-user records ("documents") and binary attachments | *No source files* — classes are generated at runtime by `Schema#load_model` and `eval`'d |

The trap that catches every new engineer: the model named **`Document` (`app/models/document.rb`) is an ActiveRecord model on the MySQL `esm_documents` table that stores form/field *definitions*. It is NOT a MongoDB document.** The real Mongo "documents" are anonymous MongoMapper classes synthesized at request time. See [Document — the dynamic record engine](#documentrb--the-dynamic-record-engine) below.

Two other things that *look* like ActiveRecord models but are not:
- **`Field`** (`app/models/field.rb`) is a plain Ruby `Struct` subclass (`FIELD = Struct.new(...)`), serialized as YAML inside `Document#data`. It has no table (`app/models/field.rb:1,5,11`).
- **`Fields::Relation` / `RelationOne` / `RelationMany`** (`app/models/fields/*.rb`) are view/plain helper classes (`Relation` subclasses `ActionView::Base`), not persisted models.

## The structural hierarchy

The definition tree is `Esm → Project → Service → Operation`, with `Project` also owning a `Schema → Table` chain and a set of `Document`s.

```
DEFINITION HIERARCHY (MySQL / ActiveRecord)

  User ──belongs_to──> Role ──belongs_to──> Project
   │  has_many esms                                ▲
   │  has_many accounts                            │ has_many
   ▼                                               │
  Account ─(esm,user,role)─┐                       │
                           ▼                       │
  Esm (solution) ─has_many─> Project ─has_many──> Service ─has_many─> Operation
   │  db_name=esm_emr-<name>   │  package=esm.name.name   │ package=...   │ belongs_to
   ├─ has_many roles           ├─ has_one  Schema          │              ▼
   ├─ has_many users           ├─ has_many MenuAction(tree)│        ScriptTemplate
   ├─ has_many logs            ├─ has_many Setting          │ (generator ERB)
   ├─ has_many settings        ├─ has_many Role
   └─ has_many menu_actions    └─ has_many Document ──belongs_to──> Table
                                                  │ (YAML fields)   ▲ belongs_to
                                  Schema ─has_many─┴────────────────┘
                                  Schema belongs_to Project
```

A critical and easily-missed property: **MySQL has no database-level foreign keys.** All referential integrity is application-level, via bare integer `*_id` columns and ActiveRecord associations only (confirmed in `db/schema.rb` and the base SQL dump). Orphan rows are likely — in fact `Service.get`/`Service.clean` will *destroy* orphan services as a side effect of reads (`app/models/service.rb:83-88`).

## Model-by-model reference

### Metadata models (MySQL / ActiveRecord)

| Model | Table | Key associations | Responsibility | File |
|---|---|---|---|---|
| `Esm` | `esms` | `belongs_to :user`; `has_many :projects, :users, :roles, :logs, :settings, :menu_actions` (projects `delete_all` on destroy) | Top-level tenant ("solution"). `db_name` supplies the Mongo DB name for the whole solution. `get_www`/`get_project` resolve child projects; `default_home` routes to the `www` project. | `app/models/esm.rb` |
| `Project` | `esm_projects` | `belongs_to :esm`; `has_one :schema`; `has_many :services, :menu_actions, :documents, :settings, :roles` (all `delete_all`) | Application namespace. The central **runtime resolver**: `get_instance`/`init_instance` merge metadata across the `extended` inheritance chain; `load_model`/`get_model` build MongoMapper classes via `Schema`. `package = "<esm>.<name>"` set before save. | `app/models/project.rb` |
| `Service` | `esm_services` | `belongs_to :project`; `has_many :operations` (`delete_all`) | A controller-like class *definition*. `#load` compiles the operations into a live Ruby class via `eval`. Also owns ACL logic. `package = "<project.package>.<name.camelize>"`. | `app/models/service.rb` |
| `Operation` | `esm_operations` | `belongs_to :service`; `belongs_to :script_template` (fk `template_id`) | An action/method definition. Holds the `command` (Ruby/ERB body) and an `acl`. Each operation becomes a method on the generated `Service` class. `init`/`escape` callbacks backslash-escape `#{` so interpolation survives storage. | `app/models/operation.rb` |
| `Schema` | `esm_schemas` | `belongs_to :project`; `has_many :tables` | The MongoDB layer compiler. `load_model` ERB-generates `MongoConnect` + `Attachment` + one MongoMapper class per `Table`, bound to collection `<project>.<table>`. Returns a `SchemaProxy` (lazy) or a single class. | `app/models/schema.rb` |
| `Table` | `esm_tables` | `belongs_to :schema` | Persisted definition of one Mongo collection's schema. `data` holds literal MongoMapper `key :col, Type` lines; `command` holds extra class body. `add_column`/`data_columns` parse/append. | `app/models/table.rb` |
| `Document` | `esm_documents` | `belongs_to :project, :table, :service` | **AR, not Mongo.** 990-LOC dynamic record engine — see deep dive below. | `app/models/document.rb` |
| `ScriptTemplate` | `esm_templates` | — | The code generator. `generate(command, this, params)` runs `ERB.new(self.generator).result(binding)` to turn an `Operation.command` into Ruby method source. Used by `Service#load`. | `app/models/script_template.rb` |
| `User` | `users` | `belongs_to :role, :esm`; `has_many :esms, :accounts` | Hand-rolled (non-Devise) auth: SHA-1+salt password (`encrypt`/`authenticate`), role helpers. `mock_user` builds throwaway cross-solution identities. (Auth detail in **"03 - Authentication & Authorization"**.) | `app/models/user.rb` |
| `Role` | `roles` | `belongs_to :project`; `has_many :accounts` | Role name + `default_home`. `developer?` keys off `name == 'developer'`. | `app/models/role.rb` |
| `Account` | `accounts` | `belongs_to :esm, :user, :role` | Join model linking a `User` to an `Esm` solution with a `Role` (scoped developer access). Queried by `Esm#developer?` and `User#my_solutions`. | `app/models/account.rb` |
| `Permission` | `permissions` | none declared | Near-empty (`name`, `menu_action_id`, `role_id`). **Never consulted in any authorization decision** — only CRUD-managed via scaffold. See gotchas. | `app/models/permission.rb` |
| `MenuAction` | `menu_actions` | `belongs_to :project`; `has_many :menu_actions` (self-referential via `parent_id`) | Navigation/menu tree entries with `action_type`/`url`/`acl`; scopes `:published` and `:root`. | `app/models/menu_action.rb` |
| `Setting` | `settings` | `belongs_to :project` | Simple `name`/`value`/`group` config rows, merged across the project inheritance chain in `Project#init_instance`. | `app/models/setting.rb` |
| `Log` | `logs` | (attributes only) | Audit/access log rows (`user_id`, `role_id`, `remote_ip`, `action`, `path`, `remark`, `esm_id`). No behavior. | `app/models/log.rb` |

### Runtime/data-layer classes (not ActiveRecord)

| Class | Kind | Responsibility | File |
|---|---|---|---|
| `Field` (`FIELD = Struct`) | Ruby Struct, serialized in `Document#data` | One form/data field: `field_type`, `column_name`, `params`, `lov`. Defines `field_types`/`data_types`/`visual_types` mapping (delegated to `Document`). | `app/models/field.rb` |
| `Fields::Relation` | subclass of `ActionView::Base` | Resolves a relation field's target (local or cross-project) into related `Document` + MongoMapper table + field list by `eval`'ing `field.params`. | `app/models/fields/relation.rb` |
| `Fields::RelationOne` | subclass of `Fields::Relation` | Persists a single related Mongo record: **deletes the old record and creates a new one**, returning its `ObjectId`. | `app/models/fields/relation_one.rb` |
| `Fields::RelationMany` | plain class (does NOT inherit `Relation`) | Persists a collection of related Mongo records (update matched / create new), returning an array of ids. Asymmetric design — lacks `Relation`'s resolution helpers. | `app/models/fields/relation_many.rb` |
| Generated `MongoConnect` / `Attachment` / `<Table>` | `eval`'d at runtime (`include MongoMapper::Document`) | The live ORM bound to `<project>.<table>` and `<project>.attachment` collections. | generated by `app/models/schema.rb` |
| `Task` / `Job::JobTest` / `PdfGenerator` / `CMDTask` | Resque workers (not AR/MM) | Background jobs. Covered in **"07 - Operation Execution Flow"**. | `app/models/task.rb`, `app/models/job.rb`, `app/models/workers/*.rb` |
| `EsmSuperClass` (file) | standalone class | **Legacy / superseded.** The runtime `EsmSuperClass` is an inline heredoc emitted by `Service#load` (`app/models/service.rb:135-189`); this file uses a different `ActionView::Base` path and appears dead. See gotchas. | `app/models/esm_super_class.rb` |

## Key files

| File | Why it matters |
|---|---|
| `app/models/document.rb` | 990-LOC dynamic record engine: YAML field defs, Mongo record create/update with relation/date/image coercion, field↔Table column sync, tree-node builders for the designer |
| `app/models/project.rb` | Inheritance-aware runtime instance assembler (`get_instance`/`init_instance`); entry point to `load_model` |
| `app/models/service.rb` | Compiles services into anonymous Ruby classes; defines the active inline `EsmSuperClass`; turns operations into methods via `ScriptTemplate` |
| `app/models/schema.rb` | The ONLY place the MongoDB persistence layer is defined — runtime ERB+`eval` of MongoMapper classes |
| `app/models/field.rb` | Struct-based field definition; field compression and LOV parsing |
| `app/models/esm.rb` | Top-level solution; `db_name` computes the per-solution Mongo DB name |
| `config/initializers/esm.rb` | Global constants `MONGO_PREFIX='esm_emr'`, `DOMAIN='emr-life.com'` used by `Esm#db_name` and host logic |

---

## Deep dive: `service.rb` — the runtime class compiler

`Service` is the most consequential model to understand because it does not behave like a model at all — it is a metaprogramming engine. The chain `Esm → Project → Service → Operation` is *data*; `Service#load` turns that data into executing Ruby on every request.

### Associations and naming

```ruby
# app/models/service.rb:5-16
self.table_name = :esm_services
attr_accessible :name,:package,:description,:params,:extended,:cache,:user_id,:project_id,:title,:acl
has_many :operations, :dependent => :delete_all
belongs_to :project
validates_uniqueness_of :name, :scope => :project_id

before_save :packaging
def packaging
  self.package = "#{self.project.package}.#{self.name.camelize}".strip
end
```

`package` is the dotted address (`<esm>.<project>.<ServiceCamelized>`) used everywhere for resolution. `extended` is a *package string* pointing at a parent service — the basis for service inheritance.

### `Service#load` — build a class string, `eval` it, instantiate it

This is the heart of the platform (`app/models/service.rb:126-264`). The flow:

1. **Build the call stack** (`:132-133`): `stack = [self] + self.extended_list`. `extended_list` (`:35-43`) walks up the `extended` package chain.
2. **Emit an inline `EsmSuperClass`** (`:135-189`) as a heredoc string — the base class for every generated service. It defines `initialize`, `context`, `params`, `render_template`, `layout`, `context_menu`, and a `method_missing` that returns the literal string `"No service"`.
3. **For each service in the reversed stack** (`:198-253`), ERB-render a subclass body where each `Operation` becomes a method:

```ruby
# app/models/service.rb:217-240 (template emitted into the eval'd source)
class <%=class_name%> < <%= s.extended && s.extended!="" ? s.extended...reverse.join : 'EsmSuperClass' %>
  ...
  <% for m in s.operations(:includes=>[:script_template])
       if m.template_id %>
        def <%=m.name%> *params
            @params = params[0] if params[0]
            ret = <%=templates[m.template_id].generate m.command, self, @params %>
        end
    <% else %>
        <%=m.command %>     # raw command spliced as method source
    <% end %>
  <% end %>
end
```

4. **`eval(tmp)`** (`:259`) defines all the classes; **`eval("#{class_name}.new context")`** (`:262`) returns a live instance.

The class name is the package reversed and joined (`:199`), e.g. `acme.clinic.Patient` → `PatientClinicAcme`. Operations *with* a `template_id` are wrapped through `ScriptTemplate#generate`; operations *without* one have their `command` spliced in verbatim as raw method source.

### Rendering and recursive layout

The injected `EsmSuperClass#render_template` (`app/models/service.rb:157-166`) renders an operation's output by calling back into the controller:

```ruby
(@context[:controller]).render(:inline => command, :content_type => ctype,
  :locals => {:command=>command, :this=>this, :context=>@context, :params=>params})[0]
```

`#layout` (`:170-179`) is recursive: it loads the project's `home` service, calls *its* `layout`, and stores the home instance as `@context[:delegate]`. So page chrome is itself a dynamic operation. (Full render mechanics in **"08 - View Rendering & Content/Attachment Flow"**.)

### Resolution, context, and ACL

- `Service.get(package)` (`:64-91`) resolves a package to a `Service`, falling back to the project's merged instance services if no direct DB row matches.
- `Service#prepare(params, controller, request)` (`:105-120`) builds the context hash `{project, service, params, controller, request}`.
- `Service#get_acl(opt_name, user)` (`:333-366`) walks the service + `extended` chain merging operation-level and service-level `acl` tokens. `#authorize` (`:368-387`) does the membership check.

```
SERVICE COMPILATION (runtime code-gen)

  Service#load(context)
    stack = [self] + extended_list           # inheritance chain
    src   = inline 'class EsmSuperClass ...'  # base
    for s in stack.reverse:
       src += ERB: 'class <Sn> < <super|EsmSuperClass>
                      def <op.name>; ScriptTemplate.generate(op.command); end ...'
    eval(src)  ->  returns <ClassName>.new(context)
    op method body rendered via render_template -> controller.render(:inline=>ERB)
```

### Sharp edges in `service.rb`

- **No caching.** The cache branch is `cache = false` (`:195`) and the file-write lines are commented out (`:243-245`). The *entire* class hierarchy is regenerated and `eval`'d on **every request** — a performance cost and a source of constant-redefinition warnings. `remove_const` is commented out (`:256`).
- **`Service#get_extended` is infinitely self-recursive** (`:45-48`): `if self.get_extended; return self.get_extended` calls itself unconditionally and would stack-overflow if ever invoked. Appears buggy/unreachable-by-design.
- **`Service.get` mutates on read** (`:83-88`): if `service.project` is nil it `destroy`s the row and returns nil.
- **`#authorize` has an operator-precedence quirk** (`:380`): `elsif role and acl.index(role.name) or` parses unexpectedly. (See **"03 - Authentication & Authorization"** for the full ACL analysis.)

---

## Deep dive: `project.rb` — the runtime instance assembler

`Project` is where the inheritance-aware "virtual application" is assembled. It is the bridge between the metadata tree and both runtime layers (services via `Service#load`, data via `Schema#load_model`).

### Associations and naming

```ruby
# app/models/project.rb:5-24
self.table_name = :esm_projects
attr_accessible :name,:title,:extended,:acl,:package,:description,:user_id,
                :database_id,:dependencies,:params,:esm_id,:domain
belongs_to :esm
has_one  :schema
has_many :services,      :dependent => :delete_all, :autosave => true
has_many :menu_actions,  :dependent => :delete_all
has_many :documents,     :dependent => :delete_all
has_many :settings,      :dependent => :delete_all
has_many :roles,         :dependent => :delete_all
validates_uniqueness_of :name, :scope => :esm_id
validates_uniqueness_of :package
```

`package = "#{self.esm.name}.#{self.name}"` is set in `filter_before_save` (`:66-71`).

### Auto-provisioning a new project

`after_create :filter_after_create` (`:28-38`) seeds a working `home` service unless the project `extended`s another: it creates `home` with an `index` operation (HTMLTemplate, `<h1>Hello world</h1>...`) and a `layout` operation (LayoutTemplate, `<%=default_layout%>`). This is how a brand-new project immediately renders something.

### `get_instance` / `init_instance` — inheritance merge by name

`get_instance` (`:262-265`) memoizes `@instance`; `get_refresh_instance` (`:268-271`) forces a rebuild. `init_instance` (`:277-386`) is the merge engine:

1. Start with an empty `list = {:menus=>[], :services=>[], :documents=>[], :tables=>[], :settings=>[]}` (`:279`).
2. If `extended` is set, recursively load the super-project's instance as the base (`:281-286`).
3. For each of `menus`, `services`, `documents`, `tables`, `settings`: merge the parent list with the local rows **by name**, with the local row overriding the parent (`:297-381`). Insertion order is preserved (parents first, then new local names appended).

The result is a single flat hash representing the effective application after inheritance.

### Model loading delegation

```ruby
# app/models/project.rb:83-89, 113-119
def get_schema
  self.schema = Schema.find_or_create_by(:name=>self.package) { |s|
    s.esm_id = self.esm_id; s.project_id = self.id }
  return self.schema
end

def load_model model_name=nil
  get_schema.load_model(self.get_instance, model_name)
end
def get_model model_name=nil; load_model model_name; end
```

So `project.load_model[:patient]` ultimately materializes the MongoMapper class for the `patient` table in this solution's Mongo DB. `get_document`/`get_service` (`:388-414`) fetch a definition by name from the merged instance and inject `self` as `.project`.

### Sharp edges in `project.rb`

- **`Project#get_params` `eval`s `self.params`** — another DB-sourced `eval` surface feeding the runtime (per the Operation Execution findings; `app/models/project.rb` params eval).
- **`@instance` is memoized for the object's lifetime** (`:262-265`): stale definitions persist on a loaded record unless `get_refresh_instance` is called.
- **Circular `extended` references would infinite-loop** `init_instance`'s recursive base-load (`:281-286`).
- `database_id` exists on the table but **no model association or usage was found** — purpose is *unverified / to confirm*.

---

## Deep dive: `document.rb` — the dynamic record engine (990 LOC)

`Document` is the most code-dense model and the one most likely to mislead. It is an **ActiveRecord model on MySQL** that:
- stores a **form/field definition** as YAML in its `data` column,
- keeps the backing `Table`'s Mongo schema in sync,
- and acts as the **CRUD engine for the actual Mongo records** through the runtime-generated MongoMapper class.

### Associations, table, and field storage

```ruby
# app/models/document.rb:4-33
class Document < ActiveRecord::Base
  self.table_name = :esm_documents
  belongs_to :project
  belongs_to :table
  belongs_to :service, :dependent => :delete
  attr_accessor :model, :fields

  before_save      :before_save_func
  after_initialize :after_find_func

  def get_model
    return self.project.load_model[self.table.name.to_sym]   # the runtime MongoMapper class
  end

  def before_save_func
    @model['fields'] = @fields.collect{|i| i.get_field_compression}
    self.data = YAML::dump(@model)    # fields persisted as YAML
  end
end
```

On load, `after_find_func → refresh_structure` (`:36-63`) deserializes the YAML back into `Field` structs, filtering to known `field_types`. Note: **the rescue around the YAML load is commented out** (`:54-56`), so malformed `data` could raise or silently leave `@fields` empty.

### Field ↔ Table column synchronization

Adding a field mutates the linked `Table`'s Mongo schema, not just the YAML:

```ruby
# app/models/document.rb:65-73
def add_field field
  field = Field.new field
  @fields << field
  if field.column_name != "" and t = Field.data_types[field.field_type] and t != nil
    self.table.add_column field.column_name, t   # appends a `key :col, Type` line to Table.data
  end
  self.save
end
```

### The field-type → Mongo-type map

`Document` defines the canonical mapping (`app/models/document.rb:380-453`). 28 `field_types`; `data_types` translates each to a MongoMapper key type, and "visual" types (`chapter`, `section`, `tab`, `html`, `clear`) map to `nil` (no column):

| field_type (examples) | Mongo key type |
|---|---|
| `text_string`, `text_area`, `select_string`, `radio_string` | `String` |
| `text_integer`, `check_integer`, `radio_integer` | `Integer` |
| `text_float` | `Float` |
| `select_date` | `Date` |
| `select_time` | `Time` |
| `select_datetime` | `Datetime` |
| `relation_one`, `extra_attachment` | `ObjectId` |
| `relation_many`, `image_camera`, `image_selection` | `Array` |
| `chapter`, `section`, `tab`, `html`, `clear` | `nil` (visual only) |

### Writing end-user records: `record_create` / `record_update` / `filter_record_params`

`record_create`/`record_update` (`:356-372`) call `filter_record_params` (`:193-372`) to coerce posted params per field type before writing to the runtime Mongo model:

- `relation_one` → convert id to `BSON::ObjectId`; if nested params present, `Fields::RelationOne.filter_params` recreates the related Mongo doc and returns its id.
- `relation_many` → JSON-decode the id array; `Fields::RelationMany.filter_params` updates/creates related docs, returns an id array.
- `select_date` → **Buddhist-calendar hack**: if the posted year is more than ~200 years in the future, subtract 543 (`~:262-270`).
- `image_camera` / `image_selection` → JSON-decode; image fields handled via GridFS attachment flow.

The cleaned params are then `create`'d / `update_attributes`'d on the runtime MongoMapper class — persisting to the per-solution Mongo collection.

### Tree-node builders for the designer

`get_root_data_node`, `get_fields_node`, `get_root_format_node`, and `mapping` (`:663-988`) convert `@fields` into Kendo-style tree nodes for the form/data designer, expanding `relation_many` fields into nested sub-nodes by loading related Mongo records and cloning the related document's node map.

```
DATA-MODEL / RUNTIME LAYER

  Document.data (YAML)
     └─> [ Field(Struct), Field, ... ]   field_type -> data_type
              │ relation_one/relation_many
              ▼
        field.params => {:relation=>{:document=>'...', :fields=>[...]}}
              │ resolved by
              ▼
        Fields::Relation / RelationOne / RelationMany

  Project#load_model ─> Schema#load_model (ERB + eval)
     produces MongoMapper classes:
        MongoConnect (include MongoMapper::Document)
          ├─ Attachment            -> coll <project>.attachment (GridFS file_id)
          └─ <Table>.camelize      -> coll <project>.<table>   (keys from Table.data)

  End-user records live in MongoDB collections, NOT MySQL.
```

### Sharp edges in `document.rb`

- **`Field.params` is `eval`'d** as `eval("{#{field.params}}")` in multiple places (`document.rb:149`, plus `schema.rb:51`, `fields/relation.rb:14`) — operator-supplied metadata executes as Ruby.
- **YAML deserialization has no rescue** (`:54-56`) — malformed `data` can raise or silently empty the field set.
- **`Field` ids are random and non-deterministic** (`'F%010d'`, `rand`, `field.rb:11`) — collisions are possible.
- **Image attachments shell out to ImageMagick `convert`** via backticks with interpolated temp filenames (`~:588`) — command-injection-adjacent and environment-dependent.
- **`RelationOne` updates are destructive** — `filter_params` deletes the existing related Mongo record and creates a fresh one, changing its `ObjectId` (`fields/relation_one.rb:25-31`); references can break.
- `Document#service` `belongs_to` is declared (`:14`) but how/where it is written is **unverified / to confirm** — no writer was observed in the read files.
- `tree_data` is read/`eval`'d but the UI/controller that persists it was **not in scope** — *unverified / to confirm*.

---

## End-to-end: how the models cooperate on one request

```
RUNTIME REQUEST RESOLUTION

 HTTP /esm/<sol>/<proj>/<Svc>/<opt>
        |
        v
 EsmController#context_filter  -> @current_solution/@current_project/@current_user
        |
        v
 EsmProxyController#index
   1. MongoMapper.database = solution.db_name            # Esm#db_name => esm_emr-<name>
   2. (GridFS static?) else
   3. s = Service.get('<sol>.<proj>.<Svc>')              # Service.get
   4. ACL: s.get_acl(opt, user) -> authorize            # Service#get_acl
   5. context = s.prepare(params, self, request)        # Service#prepare
   6. obj = s.load(context)                             # Service#load -> eval'd class
   7. obj.send(params[:opt], params)                    # operation method runs
        |  (render_template -> controller.render(:inline=>command + layout))
        v
   HTTP response (HTML/JSON)
```

Inside step 6/7, when an operation touches data it calls `project.load_model[table_name]` → `Schema#load_model` (ERB+`eval` of the MongoMapper class) and `Document#record_create`/`record_update` to persist into the per-solution Mongo collection. (The full controller path is in **"02 - Request Flow & Routing"**; the operation execution and async variants are in **"07 - Operation Execution Flow"**.)

## Gotchas / risks

- **Pervasive `eval` of DB-stored strings.** `Service#load` (`service.rb:259`), `Schema#load_model` (`schema.rb:143`), `Project#get_params`, and `Field`/relation `params` (`eval("{#{field.params}}")`) all execute Ruby sourced from operator-editable metadata. Anyone who can write `Operation.command`, `Table.data`/`command`, or `Field.params` achieves remote code execution in the web process — a serious concern for a healthcare application. (Security analysis lives in **"03 - Authentication & Authorization"** and **"07 - Operation Execution Flow"**.)
- **`Document` is NOT a Mongo document.** It is AR on `esm_documents` and stores *definitions*. The real Mongo records are anonymous runtime classes. This is the most common source of confusion.
- **No class caching.** `Service#load` regenerates and `eval`s the entire class hierarchy on every request (`service.rb:195` `cache=false`); `Schema#load_model` rebuilds the model hash per call. A single CRUD action can recompile the ORM many times.
- **No MySQL foreign keys.** Referential integrity is application-level only; reads can even destroy orphans (`Service.get`/`Service.clean`).
- **Two `EsmSuperClass` definitions.** The runtime one is the inline heredoc in `Service#load` (`service.rb:135-189`); the standalone `app/models/esm_super_class.rb` uses a `vendor/plugins/esm_essential/app/views` path and appears legacy/dead. Editing the file has no effect on request rendering. Whether the standalone file is reachable in any path is **unverified / to confirm**.
- **`Service#get_extended` is infinitely self-recursive** (`service.rb:45-48`) — buggy/unreachable as written.
- **`Permission` is dead for auth.** The model has no associations and is never queried for an authorization decision; ACL is implemented purely via the string `acl` columns on `Service`/`Operation`/`Project` plus role-name matching.
- **`Field` ids are random** (`field.rb:11`) and non-deterministic across reloads.
- **Buddhist-calendar date mutation** in `Document#filter_record_params` silently subtracts 543 years for far-future dates — locale-specific and lossy.
- **Mongo collection/DB names are string-built from project/solution names with no sanitization** (`schema.rb`, `esm.rb:148`); renaming a project or solution orphans its Mongo collections.
- **Rails 4.2 + `protected_attributes`** (`attr_accessible`) is used throughout; mass-assignment protection depends on those allow-lists, and the many `eval` paths bypass them entirely.

### Open questions (unverified / to confirm)

- The role and exact write-path of `Document#service` (`belongs_to :service`, `document.rb:14`).
- Where `esm_documents.tree_data` is authored and its full node schema.
- The purpose of `esm_projects.database_id` (no model usage found).
- Whether `Permission` rows are ever written/consumed by any controller.
- The concrete `ScriptTemplate.generator` bodies (HTMLTemplate, LayoutTemplate, per-operation generators) — these live in DB rows / seed data, not in the model files. (Five seeded generators are documented in **"06 - Metadata-Driven Architecture"**.)
- Whether the standalone `app/models/esm_super_class.rb` is invoked anywhere in the live request path.

