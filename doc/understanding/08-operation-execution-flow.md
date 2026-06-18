# 08 - Operation Execution Flow

This document explains how an ESM "operation" actually runs — from an HTTP request, through the metadata-driven dynamic-code compiler, to the rendered response (synchronous path), and through Resque/Redis to a background worker (asynchronous path). It also covers PDF generation, scheduling status, and the large dynamic-code execution security surface that is unique to this platform.

Read this alongside **"02 - Request Flow & Routing"** (how URLs reach the proxy), **"07 - Metadata-Driven Architecture"** (how Services/Operations/ScriptTemplates are stored and compiled), **"09 - View Rendering & Content/Attachment Flow"** (how operation output becomes HTML/PDF/attachments), and **"03 - Authentication & Authorization"** (the ACL gate described below).

## Mental model in one paragraph

In ESM, an "operation" is **not** a method written on disk. It is a row in the MySQL `esm_operations` table whose `command` column holds raw Ruby/ERB source text. At request time the proxy controller resolves a `Service`, calls `Service#load`, which **textually concatenates a Ruby class body** (one method per operation, each expanded through a `ScriptTemplate` ERB generator), `eval`s that string to define a class, instantiates it, and then calls the requested operation via `obj.send(params[:opt], params)`. This is entirely synchronous Ruby metaprogramming and `eval`. Despite `therubyracer`/`execjs`/`libv8` being bundled, **there is no JavaScript engine in the execution path** — those gems are only Rails asset JS runtimes and are never referenced in `app/` or `lib/` (`Gemfile:80-81`). Background work is offloaded to Resque (Redis namespace `resque:task`); the workers themselves also rely on `eval` (`CMDTask`) and shell-out (`PdfGenerator`).

## Key files

| File | Role |
| --- | --- |
| `app/controllers/esm_proxy_controller.rb` | HTTP entry point for all dynamic ops. `#index` (line 15) resolves Service, runs ACL, dispatches `obj.send(opt, params)` at line 75. `#ws` (line 195) is an auth-less variant. |
| `app/models/service.rb` | `Service#load` (lines 126-264): assembles class source, `eval(tmp)` at line 259, returns `eval("#{class_name}.new context")` at line 262. The sync compiler/executor. |
| `app/models/script_template.rb` | `generate` (line 8-10): `ERB.new(self.generator).result(binding)` — turns an operation's `command` into Ruby method-body source. |
| `app/models/operation.rb` | Operation metadata; `command` text + `template_id`; escapes `#{` on save (init/escape, lines 20-30); ACL (lines 61-84). |
| `app/models/task.rb` | Resque base worker. `@queue=:task` (line 16); `self.enqueue` → `Resque::Job.create(queue, self, params)` (lines 29-33); commented-out `RetriedJob` retry mixin. |
| `app/models/workers/exec.rb` | `CMDTask.perform` runs `eval cmd` (line 11) — async arbitrary Ruby. |
| `app/models/workers/pdf_generator.rb` | `PdfGenerator.perform`: PDFKit/wkhtmltopdf → `tmp/cache/<path>.<id>.pdf` (line 24), then `curl --insecure '<return_url>'` callback (line 35). |
| `app/models/job.rb` | `Job::JobTest.perform` replays an `/esm/` URL in-process via `ActionDispatch::Integration::Session` (lines 11-23). |
| `app/helpers/service_helper.rb` | `enqueue_job` (lines 292-299) → `Resque.enqueue(Job::JobTest, params)`; callable from operation source. |
| `config/initializers/resque.rb` | Points `Resque.redis` at `config/resque.yml` entry; namespace `resque:task` (line 6). |
| `config/resque.yml` | Redis URLs per env → `redis://redis:6379/` for dev & prod. |
| `lib/tasks/resque.rake` | `require 'resque/tasks'` — enables `rake resque:work QUEUE=...`. |
| `config/routes.rb` | Proxy routes (`esm/*package/:opt` line 32; `s/:service/:opt` line 58; `ws/...` line 61; `:solution/:project/:service/:opt` line 77); `Resque::Server` mounted at `/resque` (line 5). |

---

## Part 1 — Synchronous execution path

### 1.1 Request entry and dispatch

All dynamic-app URLs funnel into `EsmProxyController#index`. The route shapes are defined in `config/routes.rb` (lines 32, 58, 77) and described in detail in **"02 - Request Flow & Routing"**. The dispatch sequence (`app/controllers/esm_proxy_controller.rb:15-108`) is:

1. `context_filter` (inherited from `EsmController`) has already resolved `@current_solution`, `@current_project`, `@current_user`, `@current_role` from host/cookie/session and forced `Time.zone='Bangkok'`.
2. `#index` selects the per-solution Mongo database (`MongoMapper.database = @current_solution.db_name`, line 20) and first attempts a GridFS static-file read of `request.path_info` (lines 25-37); if a file is found it is streamed and dispatch stops.
3. Otherwise the `Service` is resolved via `Service.get(...)` (lines 41-45).
4. The operation row is loaded (`s.operations.find_by_name params[:opt]`, line 55); optional API-key auth runs (`params[:user_id]` + `params[:api_key]` matched against `User.hashed_password`, line 60).
5. **ACL gate** (lines 64-69): `acl = s.get_acl(params[:opt], @current_user)`; if empty, `'user'` is appended (default-open to any logged-in user, line 66). Access granted if `acl` contains `'*'`, or the user is the solution owner, or `acl` contains `'user'`, or `@current_role` matches an acl token.
6. If authorized: `context = s.prepare(...)` builds `{project, service, params, controller, request}`; `obj = s.load(context)` compiles and instantiates the dynamic class; `out = obj.send(params[:opt], params)` invokes the operation (line 75).
7. All exceptions are rescued, formatted with `backtrace[0..10]`, emailed via `msg_report` (XMPP), printed to stdout, and rendered as `public/500.html` (lines 82-99). When no service resolves, it renders plain text `'Not found service on server'` (line 104).

### 1.2 Runtime class compilation (`Service#load`)

`Service#load` (`app/models/service.rb:126-264`) is the core of dynamic behavior. It:

- Builds a **call stack** `[self] + extended_list` representing the service inheritance chain (line 132-133).
- Emits an inline `EsmSuperClass` heredoc (lines 135-189) defining `initialize`, `render_template`, `layout`, `context_menu`, and a `method_missing` that returns the literal string `"No service"` (line 186).
- For each service in the reversed stack, ERB-renders a `class <ClassName> < <super|EsmSuperClass>` body (template at lines 217-240). Each operation is turned into a method:
  - **With a `template_id`**: `def <name> *params; @params = params[0] if params[0]; ret = <ScriptTemplate.generate(command,self,@params)>; end` (lines 231-234).
  - **Without a template**: the `command` text is spliced in as **raw method source** (line 236).
- The full concatenated source string is executed with `eval(tmp)` (line 259), then the class is instantiated via `eval("#{class_name}.new context")` (line 262).

> **Note (verified):** On-disk caching of the generated `.rb` is fully disabled — `cache = false` at line 195 and the `File.open(...).puts program` writes are commented out (lines 243-245). The entire class hierarchy is **regenerated and re-`eval`'d on every request**. This is both a performance concern and a repeated constant-redefinition concern.

### 1.3 Template generation (`ScriptTemplate#generate`)

`ScriptTemplate#generate` (`app/models/script_template.rb:8-10`) runs the stored `generator` ERB against the operation command in the model's binding: `ERB.new(self.generator).result(binding)`. The five seeded generators (per the metadata findings) are **ServiceTemplate, HTMLTemplate, PartialTemplate, LayoutTemplate, EvalTemplate**. For example, an `HTMLTemplate` operation produces `render_template(com, self, params, true)` (layout = true).

> **Unverified / to confirm:** The actual `generator` bodies live in the `esm_templates` DB rows / seed data, not in the model source. Whether any generator performs sanitization beyond plain ERB could not be confirmed from source. Operations could also reference ScriptTemplates created later via the IDE that are not in the seed.

### 1.4 Output rendering

The operation method renders itself; the controller's local `out` is captured but **not** explicitly rendered (`esm_proxy_controller.rb:75`). Rendering happens as a side effect inside `EsmSuperClass#render_template` (`service.rb:157-166`):

- `ctype` defaults to `'text/html'` but is overridden by `params[:content_type]` (lines 162-163) — **this is how HTML vs JSON vs PDF content types are chosen** (manual content negotiation; the proxy never calls `respond_to`).
- The actual render is `controller.render(:inline => command, :content_type => ctype, :locals => {command, this, context, params})` (line 165) — i.e. the operation's stored `command` is rendered as **inline ERB**.
- When `layout = true`, the command is wrapped with `content_for :content` and `self.layout`. `layout` recursively loads the project's `home` service and returns its layout string (lines 170-179), so the page chrome is itself a dynamic operation. See **"09 - View Rendering & Content/Attachment Flow"** for the full render pipeline.

### 1.5 Sync sequence diagram

```
SYNC OPERATION EXECUTION

Client        Routes            EsmProxyController        Service(model)                 GeneratedClass
  |  GET /esm/pkg/opt |                  |                          |                              |
  |------------------>|                  |                          |                              |
  |                   | esm_proxy#index  |                          |                              |
  |                   |----------------->| context_filter (auth)    |                              |
  |                   |                  | Service.get(package)     |                              |
  |                   |                  |------------------------->| (load row)                   |
  |                   |                  | get_acl + ACL check       |                              |
  |                   |                  | prepare(params,self,req)  |                              |
  |                   |                  | s.load(context)           |                              |
  |                   |                  |------------------------->| build class src              |
  |                   |                  |                          | ScriptTemplate#generate(ERB) |
  |                   |                  |                          | eval(tmp)  ==> define class   |
  |                   |                  |                          | eval('Class.new context')    |
  |                   |                  |<-------------------------| return instance              |
  |                   |                  | obj.send(opt,params) -------------------------------->| run op method (Ruby/ERB)
  |                   |                  |                          |                              | render(:inline=>command)
  |<------------------|<-----------------| rendered HTML/JSON         |                              |
```

### 1.6 The `#ws` variant

`EsmProxyController#ws` (`app/controllers/esm_proxy_controller.rb:195-218`) is a second sync entry point routed at `ws/:service/:opt` (`config/routes.rb:61`). It resolves the project by `Project.find_by_domain(request.domain)` when `params[:service]` is present, loads the service **with no context** (`s.load` at line 210), and calls `obj.send(params[:opt], params)` (line 213) **with no ACL/authorization check at all**. Every operation method of a service reachable via `/ws` is effectively public.

---

## Part 2 — Asynchronous execution path (Resque + Redis)

### 2.1 Enqueue

Async work is pushed onto Redis (namespace `resque:task`, set in `config/initializers/resque.rb:6`) through two mechanisms:

- **`Task.enqueue(params)`** → `Resque::Job.create(queue.to_sym, self, params)`; `queue` defaults to `'default'` or `params[:queue]` (`app/models/task.rb:29-33`).
- **`enqueue_job` helper** (callable from operation/template Ruby) → `Resque.enqueue(Job::JobTest, params)` (`app/helpers/service_helper.rb:292-299`); it `require`s `'resque'` and `'job'` at call time.

A running operation (sync path §1.4) is the typical producer: operation source calls `enqueue_job` or `Task.enqueue`, which serializes a JSON job onto a Redis list under `resque:task`.

### 2.2 Worker execution

A worker process (started out-of-band via `rake resque:work`, enabled by `lib/tasks/resque.rake`) reserves jobs and dispatches by class:

| Worker | `perform` behavior | Citation |
| --- | --- | --- |
| `Task` (base) | Stub — `self.perform` is effectively empty. | `app/models/task.rb:22-27` |
| `CMDTask` | Reads `params['cmd']` and runs **`eval cmd`** (arbitrary Ruby in the worker). The shell-out variant `` `#{cmd}` `` is commented out above it. | `app/models/workers/exec.rb:7-11` |
| `PdfGenerator` | `PDFKit.new(url, ...:javascript_delay => 1000).to_file('tmp/cache/<path>.<id>.pdf')` drives **wkhtmltopdf**; if `params['return']` is set, appends `&path=<file>` and runs `` `curl --insecure '<return_url>'` `` to notify a callback. | `app/models/workers/pdf_generator.rb:23-36` |
| `Job::JobTest` | Builds `/esm/<pkg>/<opt>?<params>` and replays it via `ActionDispatch::Integration::Session#get`, **re-entering the sync path in-process**, and prints the body to stdout. | `app/models/job.rb:11-26` |

### 2.3 Result handling

There is **no shared result store** for async work — results are side effects only:

- `CMDTask` prints `"FINISH"`.
- `PdfGenerator` writes a PDF under `tmp/cache/` and notifies via the `curl` callback (`pdf_generator.rb:35`).
- `Job::JobTest` puts the response body to stdout.

There is no DB persistence of job output and no completion callback into the web layer beyond `PdfGenerator`'s `curl`.

### 2.4 Async sequence diagram

```
ASYNC JOB EXECUTION

Operation(Ruby)      Resque/Redis (ns resque:task)      Worker process (rake resque:work)
   |  Resque.enqueue / Task.enqueue   |                          |
   |--------------------------------->| RPUSH job (JSON)         |
   |                                  |                          | reserve job
   |                                  |<-------------------------| poll
   |                                  |                          | dispatch by class:
   |                                  |                          |  - CMDTask.perform -> eval cmd
   |                                  |                          |  - PdfGenerator -> PDFKit/wkhtmltopdf -> file
   |                                  |                          |       -> `curl --insecure return_url&path=`
   |                                  |                          |  - Job::JobTest -> Integration GET /esm/... (re-enter SYNC)
   |                                  |                          | side-effects only (stdout / file / callback)

[resque-scheduler present but UNWIRED -> no enqueue_at/enqueue_in path exists]
```

### 2.5 Operational reality of the worker (important)

The findings consistently flag that **no Resque worker or scheduler process is started by `docker-compose`** — only `thin start --port 3000 --ssl` is launched (`docker-compose.yml:29`). The `Resque::Server` dashboard is mounted at `/resque` and jobs are enqueued, but with no consumer running in the Docker setup, **enqueued jobs will accumulate in Redis and never execute** unless a worker is started manually (e.g. `bundle exec rake resque:work QUEUE='*'`). Combined with the fact that the `redis` service mounts no persistent volume, a queued backlog is also lost on container recreation. See **"06 - Docker & Infrastructure / Deployment"** for the full deployment picture.

> **Unverified / to confirm:** What out-of-band command actually starts the workers in the real production deployment (and with which `QUEUE` list, and under which `RAILS_ENV`) is not in the repo. The presence of `nohup.out` in `.dockerignore` hints at a manual `nohup rake resque:work` on the host, but this cannot be confirmed from source. How the worker classes (`CMDTask`/`PdfGenerator`/`Job::JobTest`) are autoloaded in the standalone worker process was also not confirmed from an explicit `require`/`eager_load` setting.

---

## Part 3 — PDF generation

PDF output is produced **out-of-band by the `PdfGenerator` Resque worker**, not in the synchronous request cycle (`app/models/workers/pdf_generator.rb`). The flow:

1. An operation enqueues a job with a `params['url']` pointing at a rendered page URL (plus optional `id`, `path`, `return`).
2. The worker runs `PDFKit.new(url, :margin_* , :javascript_delay => 1000).to_file(File.join("tmp","cache","#{path}.#{id}.pdf"))` — i.e. **wkhtmltopdf via the `pdfkit` gem** (lines 23-24). The `javascript_delay` gives the target page's JS time to render before capture.
3. If `params['return']` is present, the worker appends `&path=<pdf_file>` and shells out `` `curl --insecure '#{return_url}'` `` to notify the caller of the file location (lines 33-35).

Notes:
- `prawn` and `wkhtmltopdf-binary` are also bundled, but the worker uses `pdfkit`/wkhtmltopdf; `prawn` is unused in this path.
- The native `wkhtmltopdf` binary is installed in the web image (`Dockerfile`), confirming the PDFKit dependency.

> **Unverified / to confirm:** Whether anything in live/seed data actually enqueues `PdfGenerator` (its `.perform` expects a specific param hash). A grep of `app/`/`lib/` enqueue call sites found only `Job::JobTest` (via `enqueue_job`) and the generic `Task.enqueue`; concrete `PdfGenerator` enqueues, if any, would live in DB-stored operation `command` text (`esm_operations`), which was not exhaustively parsed. The only inline/synchronous PDF code (a WickedPdf example in `HomeController#show`) is commented out.

---

## Part 4 — Scheduling

`resque-scheduler` (4.0.0) is declared in the `Gemfile` (line 101) but is **effectively dormant**:

- No `schedule.yml` (or equivalent schedule config) exists.
- There is no `require 'resque/scheduler'` and no scheduler rake load.
- There are **no `enqueue_at` / `enqueue_in` calls anywhere** in `app/`, `lib/`, or `config/`.

Therefore cron-style / delayed scheduling is **non-functional as shipped**. All async work is immediate enqueue only. Treat any claim of scheduled/recurring background jobs as unimplemented until proven otherwise.

---

## Part 5 — The dynamic-code security surface

This is the single most important thing for a new owner to internalize: in ESM, **executable behavior is data**. Operation `command` text, ScriptTemplate generators, table/field params, and job `cmd` strings are all stored in MySQL/Mongo/Redis and `eval`'d at runtime. The platform is therefore a metadata-driven engine and an enormous remote-code-execution surface simultaneously.

### Gotchas / risks

| Risk | Where | Detail |
| --- | --- | --- |
| **RCE via operation source (sync)** | `service.rb:259-262` | `Service#load` `eval`s a class body assembled from DB-stored `command` text. Anyone who can create/edit an operation (via `EsmOperationsController#new/#edit`) gets arbitrary Ruby execution inside the Rails process on the next request. Operation source is data, not reviewed code. |
| **RCE via `CMDTask` (async)** | `workers/exec.rb:11` | `CMDTask.perform` runs `eval cmd` on `params['cmd']`. Anyone able to enqueue a `CMDTask` (e.g. via the unauthenticated `/resque` dashboard, or any operation calling `Task.enqueue`) gets arbitrary Ruby in the worker. |
| **Command injection + TLS bypass (async)** | `workers/pdf_generator.rb:35` | `` `curl --insecure '#{return_url}'` `` interpolates `params['return']` into a shell command unescaped (shell-metacharacter injection) and `--insecure` disables certificate verification. |
| **No auth on `#ws`** | `esm_proxy_controller.rb:209-213` | `obj.send(params[:opt], params)` runs with **no ACL/auth check whatsoever**, exposing every operation method of a service. |
| **CSRF disabled on the dispatcher** | `esm_proxy_controller.rb:4` | `skip_before_filter :verify_authenticity_token` on the whole proxy controller — state-changing operations accept cross-site POST. |
| **Weak API auth** | `esm_proxy_controller.rb:60` | API callers authenticate by matching plaintext query-string `user_id`/`api_key` against `User.hashed_password` — the password hash *is* the API key, traveling in the URL (and into logs). See **"03 - Authentication & Authorization"**. |
| **Unauthenticated Resque dashboard** | `config/routes.rb:5` | `Resque::Server` mounted at `/resque` with no auth wrapper — leaks job/queue internals and can be abused to enqueue jobs. |
| **Mass-dispatch by param** | `esm_proxy_controller.rb:75` | `obj.send(params[:opt], ...)` lets the URL select any public method on the generated object, including inherited helpers; `method_missing` returns the literal `"No service"` (`service.rb:186`) instead of a 404, easing enumeration. |
| **No codegen caching** | `service.rb:195, 243-245` | The class cache is disabled (`cache=false`, file writes commented), so the full class hierarchy is regenerated and re-`eval`'d on every request — performance and repeated-eval risk. |
| **Errors swallowed into email** | `esm_proxy_controller.rb:82-99` | Operation exceptions are caught broadly (`rescue Exception`), emailed via `msg_report` with `backtrace[0..10]`, and rendered as `public/500.html`; no structured logging/observability of failures. |
| **Additional metadata `eval` surfaces** | `project.rb:240-253`; `service_helper.rb` relation helpers | `Project#get_params` `eval`s the stored params string; relation helpers `eval("{#{field.params}}")` — more DB-sourced `eval` feeding the same runtime. See **"07 - Metadata-Driven Architecture"**. |
| **Misleading JS-engine surface** | `Gemfile:80-81` | `therubyracer`/`execjs`/`libv8` are bundled but never referenced in `app`/`lib`. Operation logic is Ruby ERB/`eval` only; there is no JS sandbox. |

### Implication for a new owner

Because operation source is `eval`'d with full process privileges and ACLs default-open to `'user'`, **write access to the metadata catalog (esm_operations) is equivalent to remote code execution**. Any hardening effort should prioritize: (1) locking down who can author/edit operations, (2) authenticating `/resque` and the `#ws` route, (3) removing or gating `CMDTask`'s `eval`, and (4) fixing the `curl` shell-out in `PdfGenerator`. These should be coordinated with the dynamic-code and auth findings in **"03 - Authentication & Authorization"** and **"07 - Metadata-Driven Architecture"**.

---

## Quick reference: sync vs async

| Aspect | Synchronous | Asynchronous |
| --- | --- | --- |
| Entry point | `EsmProxyController#index` (`#ws` = no-auth variant) | Operation code calls `enqueue_job` / `Task.enqueue` |
| Transport | In-process Ruby method call (`obj.send`) | Redis list, namespace `resque:task` |
| Code mechanism | `Service#load` → `eval` of generated class; ERB inline render | Worker `.perform`; `CMDTask` `eval`s, `PdfGenerator` shells out |
| Auth/ACL | `Service#get_acl` gate in `#index` (none in `#ws`) | None at the queue layer; `/resque` UI unauthenticated |
| Result | Rendered HTTP response (HTML/JSON/PDF content-type via `params[:content_type]`) | Side effects only (stdout / file / `curl` callback) |
| Runs in Docker? | Yes (`thin`) | **No worker is started by compose** — jobs queue but do not run |
| Scheduling | n/a | `resque-scheduler` present but unwired (no `enqueue_at`/`enqueue_in`) |

