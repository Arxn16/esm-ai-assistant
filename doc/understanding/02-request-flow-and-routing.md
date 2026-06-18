# 02 - Request Flow & Routing

> Audience: the senior engineer now owning the ESM legacy Rails 4.2 EMR platform.
> Scope: how an HTTP request becomes a response — the route table in `config/routes.rb`, the `EsmProxyController` dispatcher, the generic `ManageController` CRUD path, attachment/content serving, and a full URL→response trace.
>
> Cross-references: see **"01 - Architecture & Bootstrapping"** for the dual-ORM/code-generation big picture, **"03 - Metadata-Driven Architecture & Operation Execution"** for what `Service#load` actually compiles, **"04 - Authentication & Authorization"** for the ACL model, and **"05 - View Rendering & Content/Attachment Flow"** for `render_template`/GridFS rendering details.

## 1. The one-paragraph mental model

ESM is a metadata-driven platform: almost every dynamic URL is funneled by `config/routes.rb` into a single front controller, `EsmProxyController#index`. That controller does **not** use normal Rails action rendering. Instead it resolves a `Service` from the URL "package", dynamically builds and `eval`s a Ruby class from database-stored `Operation` command scripts (`Service#load`), instantiates it, and invokes the operation named by `params[:opt]` via `obj.send(params[:opt], params)`. The operation method renders the HTTP response itself as a side effect by calling back into the controller (`controller.render(:inline => ...)`); the proxy's own captured return value (`out`) is discarded. A second route family (`manage/:model/*`) drives generic ActiveRecord CRUD through `ManageController`. Routing is **order-sensitive and fragile** because greedy wildcard catch-alls are interleaved with the dynamic dispatch routes.

```
Client ─HTTP─▶ config/routes.rb (top-down, first match wins)
                     │
                     ▼
       EsmProxyController#index  ◀── before_filter EsmController#context_filter
                     │             (resolves @current_solution/@current_project/@current_user)
                     ▼
   Service.get(package) ─▶ Service#load (ERB + eval => Ruby class) ─▶ obj.send(opt, params)
                     │
                     ▼
   operation body calls render_template -> controller.render(:inline=>..., content_type)
                     │
                     ▼
              HTTP RESPONSE (rendered as a side effect)
```

---

## 2. Key files

| Concern | File | Why it matters |
|---|---|---|
| All routing | `config/routes.rb` | Priority-ordered route table; ordering here determines which controller a 3+ segment URL hits |
| Central dispatcher | `app/controllers/esm_proxy_controller.rb` | `#index` (main), `#ws` (auth-less variant), `#home` (redirect), `#access` (implemented but unrouted), `#index2` (debug) |
| Per-request context | `app/controllers/esm_controller.rb` | `context_filter` before_filter resolves solution/project/user/role/theme for every ESM request |
| Service resolution + exec | `app/models/service.rb` | `Service.get` (resolve), `prepare` (context), `load` (eval class), `get_acl` (authorization tokens) |
| Generic CRUD | `app/controllers/manage_controller.rb` | `eval(params[:model])`-based CRUD over any ActiveRecord model, with html/json/xml negotiation |
| Auth gate (admin) | `app/controllers/esm_admin_controller.rb` | `login_admin_required` parent of `ManageController` |
| Legacy auth helpers | `lib/basic_auth.rb` | `login_required` filter + session-based `current_user` |
| Framework base | `app/controllers/application_controller.rb` | Only `protect_from_forgery`; confirms no global auth/exception handling at the base |
| Attachment/content serving | `app/controllers/esm_attachments_controller.rb` | GridFS file/thumbnail serving for `content/esm` and `content/data` routes |
| Global constants | `config/initializers/esm.rb` | `MONGO_PREFIX='esm_emr'`, `DOMAIN='emr-life.com'` used in subdomain detection, error reporting, DB naming |

---

## 3. `config/routes.rb` — the route table

Rails matches routes **top-down, first match wins**. The table below reflects the actual file (verified against `config/routes.rb`). The single most important fact: the **generic `:controller` catch-alls (lines 69–75) are declared BEFORE the deep `:solution_name/:project_name/:service/:opt` route (line 77)**, so a 2–3 segment URL whose first segment matches an existing controller is dispatched to that controller, not to the proxy.

```
config/routes.rb (first match wins)

 L5    /resque                                       -> Resque::Server (Sinatra dashboard, unauthenticated)
 L10   home/:action                                  -> home#:action
 L12-22 resources :esms,:menu_actions,:settings,:users,
        :roles,:permissions,:logs,:projects,:services,
        :operations,:script_templates                (RESTful metadata CRUD)
 L25   barcode                                       -> esm_image#barcode
 L26-27 content/esm/*package/:id ,
        content/data/*package/:id/:filename           -> esm_attachments#show  (GridFS)
 L32   esm/*package/:opt                             -> esm_proxy#index        (PRIMARY dynamic route)
 L35-36 user , user/:action                          -> user#*
 L37   elfinder                                      -> esm_content#elfinder   (see gotcha: action missing)
 L39-48 manage/:model[/...]                          -> manage#(index|create|new|show|update|destroy)
 L50-52 esm_home[/:action[/:id]]                     -> esm_home#*
 L54-55 esm_content/:id[/:action]                    -> esm_content#*
 L58-59 s/:service/:opt , s/:service                 -> esm_proxy#index        (short-form, opt defaults 'index')
 L61-62 ws/:service/:opt , ws/:service               -> esm_proxy#ws           (NO auth — see gotcha)
 L64-65 admin/:id[/:action]                          -> admin#*
 L69-75 :controller , :controller/new , :controller/:id ,
        :controller/:id/:action , :controller/destroy/:id   <== GREEDY CATCH-ALLS (precede L77)
 L77   :solution_name/:project_name/:service/:opt    -> esm_proxy#index
 L79   :solution_name/:project_name/:service/*id/:opt -> esm_proxy#index
 L85   :solution_name/:project_name                  -> esm_proxy#home
 L87-89 :project_name/:service/:opt  (x3: plain, :format=>json, :format=>shtml)  -> esm_proxy#index
 L95   :content                                      -> home#content
 L98   root                                          -> home#index
 L99   :controller(/:action(/:id(.:format)))         -> legacy catch-all
```

### Route facts to keep in mind

- **Three URL shapes all reach `esm_proxy#index`:** the glob form `esm/*package/:opt` (L32), the short form `s/:service/:opt` (L58–59, `opt` defaults to `index`), and the deep form `:solution_name/:project_name/:service/:opt` (L77) plus the project-scoped `:project_name/:service/:opt` (L87). Evidence: `config/routes.rb:32,58-62,77,87`.
- **The Resque dashboard is mounted at `/resque` (L5) with no authentication wrapper** in the route table. Evidence: `config/routes.rb:5`.
- **`manage/:model` is mapped per HTTP verb** (L39–48): GET/POST→`index`, POST→`create`, PUT/POST→`update`, DELETE→`destroy`, with explicit `/new`, `/create`, `/destroy/:id` paths. Evidence: `config/routes.rb:39-48`.
- **The `:project_name/:service/:opt` pattern is declared three times** (L87 plain, L88 `:format == :json`, L89 `:format == :shtml`). In Rails 4.2 the first (unconstrained) match wins, so the constrained variants look **unreachable** — unverified, since `rake routes` was not run. Treat as "to confirm".
- **`elfinder` (L37) maps to `esm_content#elfinder`**, but the evidence notes that action does not exist in `EsmContentController` (only `index`/`data`/`show`). Treat any `/elfinder` link as likely broken — to confirm.

---

## 4. The before_filter: `EsmController#context_filter`

`ApplicationController` only declares `protect_from_forgery` (`app/controllers/application_controller.rb:2`) — no before_actions, no exception handling, no auth at the framework base. All of that lives in `EsmController`, the parent of nearly every controller.

`EsmController` registers `context_filter` as a `before_filter` (`app/controllers/esm_controller.rb:8`). It runs for every request through an `EsmController` subclass and establishes the per-request world **before the action runs**:

- Resolves `@current_solution` by `Esm.find_by_url(request.host)`, then `cookies[:esm]`, then the URL subdomain (skipping `localhost`/`192.*`/the `DOMAIN` first label). Evidence: `app/controllers/esm_controller.rb:15-28`.
- Resolves `@current_user`/`@current_role` from `session[:user]` (short id ⇒ plain `User`) or `session[:esm]` (⇒ per-solution mock user via `get_user_role_by_id`). Note `@current_role` is set as a **String** here (`'user'` / `'developer'`). Evidence: `app/controllers/esm_controller.rb:53-74`.
- Forces `Time.zone = 'Bangkok'` globally (`app/controllers/esm_controller.rb:12`) — a per-request mutation of global state. Sets `@context`, `@current_theme`, `@theme_path`.

> Caution: `Time.zone` and (later) `MongoMapper.database` are mutated as **global per-request state**. This is only "safe" because the app runs on single-threaded/evented Thin. Under a threaded server (the commented-out puma config) this would be a cross-request / cross-tenant data-leak race. See **"01 - Architecture & Bootstrapping"** and **"04 - Authentication & Authorization"**.

---

## 5. `EsmProxyController` — the central dispatcher

`EsmProxyController < EsmController` (`app/controllers/esm_proxy_controller.rb:2`) is the front controller for all dynamic app routes. It **`skip_before_filter :verify_authenticity_token`** (`...:4`), disabling CSRF protection for the entire dynamic-app surface, and includes `EsmHelper` + `ServiceHelper`.

| Action | Routed? | Purpose |
|---|---|---|
| `index` | yes (L32, L58–59, L77, L87) | Main dispatch + GridFS static-content fallback. Lines 15–108 |
| `home` | yes (L85) | Redirects `:solution/:project` → `/<sol>/<proj>/Home/index`. Lines 110–117 |
| `ws` | yes (L61–62) | Web-service variant — **no ACL/auth check at all**. Lines 195–218 |
| `access` | **no route found** | Fully implemented alternate dispatch; appears dead/legacy. Lines 119–192 |
| `index2` | no | Debug stub returning `Time.now`. Lines 11–13 |

### 5.1 `#index` step by step

Reading `app/controllers/esm_proxy_controller.rb:15-108`:

1. **Select the Mongo database.** If `@current_solution` is set, `MongoMapper.database = @current_solution.db_name`; otherwise it derives the DB name from the URL: `MongoMapper.database = "esm-" + params[:package].split('/')[0]` (`...:19-23`). The URL can therefore choose the Mongo database when no solution is resolved.
2. **GridFS static fallback first.** It opens `request.path_info` as a GridFS file via `Mongo::GridFileSystem.new(MongoMapper.database)`; if found it renders the blob with `f.content_type` and returns (`...:25-37`). A static file therefore *shadows* a same-path service — the service is never reached if a GridFS file matches.
3. **Resolve the Service.** If `params[:service]` is present → `Service.get("#{@current_project.package}.#{params[:service]}")`; otherwise → `Service.get(params[:package].split('/').join('.'))` (`...:41-45`).
4. **Re-bind context from the service.** After resolving, it overrides what `context_filter` set: `@current_service = s; @current_project = s.project; @current_solution = @current_project.esm; @context = @current_solution` (`...:51-54`). It then finds the operation: `opt = s.operations.find_by_name params[:opt]` (`...:55`).
5. **Optional API-key auth.** If there is no `@current_user` but `params[:user_id]` is present, it authenticates via `User.where(:id => params[:user_id], :hashed_password => params[:api_key]).first` — i.e. the stored password hash *is* the API key, passed in the URL/query (`...:57-62`). See **"04 - Authentication & Authorization"**.
6. **Compute and check the ACL.** `acl = s.get_acl(params[:opt], @current_user)`; if empty it defaults to `['user']` (`...:64-66`). Access is granted if (`...:69`):
   - `acl` contains `'*'` (public), **OR**
   - there is a logged-in user **AND** (`@context.user == @current_user` (owner bypass) **OR** `acl` contains `'user'` **OR** (`@current_role != nil` and `acl` contains `@current_role`)).
   - Otherwise it stores `session[:return_to]` and renders an inline "not authorized / Click to Login" HTML snippet (`...:77-79`).
7. **Execute.** `@project_instance = @current_project.get_instance`; `context = s.prepare(params, self, request)`; `obj = s.load(context)`; `out = obj.send(params[:opt], params)` (`...:70-75`). The return value `out` is **captured but never explicitly rendered** — rendering happens as a side effect inside the operation method.
8. **Error handling.** The whole dispatch (steps 4–7) is wrapped in `rescue Exception => e`: it builds a message (`DOMAIN`, `request.fullpath`, timestamp, `e.message`, `e.backtrace[0..10]`), fires `msg_report` (XMPP alert), logs to stdout, and renders `public/500.html` (`...:82-99`). Note: in development the backtrace local is also exposed — info-disclosure risk.
9. **No service found.** Renders plain text `'Not found service on server'` (`...:104`).

### 5.2 `#ws` — the auth-less variant

`#ws` (`app/controllers/esm_proxy_controller.rb:195-218`) resolves the project via `Project.find_by_domain(request.domain)` when `params[:service]` is present, loads the service **without a context** (`obj = s.load`), calls `s.prepare(...)`, and invokes `obj.send(params[:opt], params)` — **with no ACL/authorization check whatsoever**. Any operation reachable via `/ws/...` is effectively public. Treat this as a serious exposure.

### 5.3 `#home` and `#access`

- `#home` (`...:110-117`) just redirects `:solution/:project` to `/<sol>/<proj>/Home/index`.
- `#access` (`...:119-192`) is a complete alternate dispatcher (it sets `@current_role` as a `Role` **object**, not a String, and compares `acl.index(@current_role.name)`), but **no route maps to `esm_proxy#access`** in `config/routes.rb`. It appears to be dead/legacy code; whether some external/edge config routes to it is **unverified — to confirm**.

---

## 6. Full URL→response trace (sequence diagram)

The following sequence (from the `request_flow` findings, corroborated against the source) traces `GET /acme/clinic/Patient/list`:

```
SYNC OPERATION EXECUTION

Client        Routes            EsmProxyController          Service(model)                 GeneratedClass
  | GET /acme/clinic/Patient/list |                                |                              |
  |------------------>|                  |                          |                              |
  |                   | esm_proxy#index  |                          |                              |
  |                   |----------------->| context_filter (auth)    |                              |
  |                   |                  |  @current_solution/project/user                          |
  |                   |                  | MongoMapper.database = solution.db_name                  |
  |                   |                  | try GridFS static file (request.path_info) --found?-->render & STOP
  |                   |                  | Service.get('acme.clinic.Patient') ----->| (resolve row / instance)
  |                   |                  | rebind @current_service/project/solution/context        |
  |                   |                  | opt = s.operations.find_by_name 'list'   |               |
  |                   |                  | (api-key auth if no user)                |               |
  |                   |                  | acl = s.get_acl('list', user); acl<<'user' if empty       |
  |                   |                  | AUTHORIZE? --deny--> render 'not authorized' HTML & STOP  |
  |                   |                  | [allow]                                  |               |
  |                   |                  | @project_instance = project.get_instance |               |
  |                   |                  | context = s.prepare(params,self,request) |               |
  |                   |                  | obj = s.load(context) ------------------>| build EsmSuperClass + subclass
  |                   |                  |                          | ScriptTemplate-render each Operation (ERB)
  |                   |                  |                          | eval(source) => define class |
  |                   |                  |                          | ClassName.new(context) ------>| instance
  |                   |                  |<-----------------------------------------| obj
  |                   |                  | obj.send('list', params) ------------------------------->| run 'list' method
  |                   |                  |                          |                              | render_template ->
  |                   |                  |                          |                              | controller.render(:inline=>cmd, content_type)
  |<------------------|<-----------------| HTTP RESPONSE (html/json/pdf) rendered as side effect    |
  |                   |                  |                          |                              |
  | (on Exception)    |                  | msg_report (XMPP) + log + render public/500.html         |
```

Narrative of the same trace:

1. **Route match.** `/acme/clinic/Patient/list` matches `:solution_name/:project_name/:service/:opt` (`config/routes.rb:77`) → `esm_proxy#index` — *unless* `acme` matches an existing controller name, in which case the catch-alls at L69–75 intercept first.
2. **`context_filter`** resolves `@current_solution` (host/cookie/subdomain), `@current_project` (`params[:project_name]` or `'www'`), `@current_user`/`@current_role`, sets `Time.zone='Bangkok'`. (`app/controllers/esm_controller.rb:8-74`)
3. **`#index`** sets `MongoMapper.database`, tries the GridFS static read, then `Service.get('acme.clinic.Patient')`.
4. **Re-bind + ACL.** Re-derives context from the service, finds the `list` operation, computes the ACL, authorizes.
5. **Compile + dispatch.** `s.prepare` builds `{project, service, params, controller: self, request}`; `s.load` builds an `EsmSuperClass` heredoc + one ERB-rendered subclass per service in the extension stack (each `Operation` becomes a method, optionally wrapped by a `ScriptTemplate`), `eval`s the string, and returns an instance. `obj.send('list', params)` runs the operation.
6. **Render.** Inside the operation, `render_template` calls `@context[:controller].render(:inline => command, :content_type => params[:content_type] || 'text/html', ...)`. This is the actual response. Content type/format (html/json/pdf) is chosen by the operation via `params[:content_type]` — the proxy never calls `respond_to`. (`app/models/service.rb:157-166`)

> The runtime render path lives inside the `EsmSuperClass` heredoc emitted by `Service#load` (`app/models/service.rb:135-189`), **not** in the standalone `app/models/esm_super_class.rb` file (which uses `ActionView::Base` and is stale/legacy). Editing the file has no effect on request rendering. See **"05 - View Rendering & Content/Attachment Flow"** and **"03 - Metadata-Driven Architecture & Operation Execution"**.

---

## 7. `ManageController` — generic ActiveRecord CRUD

The `manage/:model/*` routes (`config/routes.rb:39-48`) drive a generic CRUD UI over arbitrary ActiveRecord models. `ManageController < EsmAdminController`, so it requires login.

- **Model resolution:** the `model_filter` before_filter does `@model = eval(params[:model].singularize.camelize)` and builds a default column config from `@model.column_names` (`app/controllers/manage_controller.rb:6-25`). The model name comes straight off the URL segment.
- **`index`:** supports `params[:q]` query, a "today" filter, and offset/limit pagination (default offset 0, limit 50), then negotiates `json`/`html` (both render `esm/scaffold/index`) and `xml` (`app/controllers/manage_controller.rb:27-74`). This is the **only** routing-layer path that uses real `respond_to` format negotiation.
- **`create`/`update`** read `params[@model_name]` (mass assignment) and rely on each model's `attr_accessible` whitelist (legacy `protected_attributes`, not strong params). Any model without a tight whitelist is mass-assignable via `/manage`.
- **Auth gate:** `EsmAdminController#login_admin_required` redirects to `/user/login` unless `@current_user` is present (`app/controllers/esm_admin_controller.rb:5-18`). Note the secondary role check on line 12 uses `=` (assignment) not `==`, so it is effectively inert — see **"04 - Authentication & Authorization"**.

---

## 8. Content / attachment serving

- **GridFS files:** `content/esm/*package/:id` and `content/data/*package/:id/:filename` (`config/routes.rb:26-27`) map to `EsmAttachmentsController#show`. It resolves `Esm → Project → attachment_model → record` from `params[:package]` segments and `params[:id]`, fetches the blob from `Mongo::Grid`, and (for thumbs) shells out to ImageMagick `convert`, streaming raw bytes with the stored `content_type` (`app/controllers/esm_attachments_controller.rb:6-65`).
- **Static content via the proxy:** `EsmProxyController#index` also serves arbitrary GridFS content inline via `Mongo::GridFileSystem#open(request.path_info)` *before* any service dispatch (`...:25-37`).
- **Barcodes/images:** `barcode` (`config/routes.rb:25`) → `esm_image#barcode`.
- **el_finder file manager:** `esm_content/:id[/:action]` (`config/routes.rb:54-55`) operates on the **on-disk** `public/esm/...` tree, *not* GridFS — two separate content stores. See **"05 - View Rendering & Content/Attachment Flow"** for details on the rendering and attachment pipelines.

> Open question (to confirm): `rack-gridfs` is in the Gemfile but no `Rack::GridFS` middleware mount was found in `config/`; all GridFS access in the request path is via `Mongo::Grid`/`Mongo::GridFileSystem` directly.

---

## 9. Root and home dispatch

- `root` → `home#index` (`config/routes.rb:98`). `HomeController#index` either renders the Home service, redirects to `/www/Home/index` **only if** the `www` Home `index` operation ACL strips to `'*'`, or redirects to `/user/login`; logged-in users go to their solution's `default_home` (`app/controllers/home_controller.rb:5-63`).
- `:content` → `home#content` (`config/routes.rb:95`) — but this single-segment route is unreachable for any path that matches a controller name (the L69–75 catch-alls and L99 win first). Exact precedence is **unverified — to confirm via `rake routes`**.

---

## 10. Gotchas / risks

These are routing- and dispatch-specific. Security-model details are expanded in **"04 - Authentication & Authorization"**; the eval/code-gen surface is detailed in **"03 - Metadata-Driven Architecture & Operation Execution"**.

- **CSRF disabled on the entire dynamic surface.** `EsmProxyController` does `skip_before_filter :verify_authenticity_token` (`app/controllers/esm_proxy_controller.rb:4`), so all state-changing operations dispatched through the proxy accept cross-site POST.
- **`/ws/:service/:opt` performs NO authorization.** `#ws` (`...:195-218`) loads the service and invokes the operation with zero ACL/auth checks. Every operation reachable via `/ws` is effectively public.
- **Route ordering is brittle.** The generic `:controller` catch-alls (`config/routes.rb:69-75`) precede the deep `:solution_name/:project_name/:service/:opt` route (L77). A solution named the same as an existing controller, or a 2–3 segment URL, can be silently swallowed by the wrong controller. The same `:project_name/:service/:opt` pattern is even defined three times (L87–89) with redundant format constraints that look unreachable.
- **Authorization default-opens.** In `#index`, if `get_acl` returns empty it is forced to `['user']` (`...:66`), so any operation with no ACL configured becomes accessible to any logged-in user.
- **URL chooses the Mongo database.** When `@current_solution` is nil, `MongoMapper.database = "esm-" + params[:package].split('/')[0]` (`...:22`) — untrusted input selects the DB.
- **Weak API-key auth in the URL.** `params[:user_id]` + `params[:api_key]` are matched against `User.hashed_password` in plaintext (`...:60`); the password hash is the API key, passed as a URL/body param (lands in logs/proxies).
- **RCE surface in the dispatch path.** `Service#load` (`app/models/service.rb:259`) `eval`s a class body built from DB-stored `Operation.command`; `ManageController#model_filter` does `eval(params[:model].camelize)` on a URL segment (`app/controllers/manage_controller.rb:11`). Anyone who can write metadata or craft a `:model` param can execute Ruby.
- **`#access` is dead/unrouted** (`...:119-192`) — implemented but no route maps to it. Do not rely on or extend it without confirming reachability.
- **Errors leak internals.** On exception the proxy emails the backtrace via `msg_report` and renders `public/500.html`; the full backtrace local is constructed and may be exposed (`...:82-99`). Combined with `production.rb` setting `consider_all_requests_local = true`, non-proxy controllers also show full Rails error pages.
- **No `respond_to` in the proxy path.** The proxy never negotiates format; content type depends entirely on operation scripts setting `params[:content_type]`. Only `ManageController` and `esm_attachments#upload` use real format negotiation.
- **Per-request class redefinition.** `Service#load` `eval`s a class definition on **every** request (caching is hard-disabled, `app/models/service.rb:195`; `remove_const` is commented out), causing constant-redefinition warnings and a performance cost.

## 11. Unverified / to confirm

- Whether the duplicated `:project_name/:service/:opt` routes constrained by `:format == :json` / `:shtml` (`config/routes.rb:88-89`) are ever reachable, vs the unconstrained L87 match. Run `rake routes` to confirm precedence.
- Whether anything routes to `EsmProxyController#access` in production (no route found in `config/routes.rb`).
- Whether `esm_content#elfinder` exists (route L37 references it; the controller reportedly defines only `index`/`data`/`show`).
- Exact resolution order when both a GridFS static file and a Service exist for the same path (the proxy serves the static file first and returns, but real GridFS `path_info` matching semantics were not verified).
- Whether `Project.find_by_domain` (used in `#ws`, `...:201`) maps to a real indexed column and how multi-tenant domain collisions resolve.
- Whether the `:content` single-segment route (L95) is reachable at all given the catch-alls above it.

