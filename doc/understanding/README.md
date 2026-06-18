# ESM Legacy Platform — Project Understanding

> Read-only senior-engineer analysis of the ESM metadata-driven EMR/EHR platform (Rails 4.2 / Ruby 2.3, MySQL + MongoDB + Redis + Resque, Docker). Generated 2026-06-16. Every claim is backed by `file:line` evidence. Items that could not be confirmed from source are flagged **(unverified / to confirm)**.

## Documents

- [00 - System Overview](00-system-overview.md) — Start here. Orientation, tech stack, domain hierarchy, glossary, document map.
- [01 - Architecture](01-architecture.md) — Boot sequence, dual-ORM (ActiveRecord/MongoMapper), initializers, gems, server/SSL.
- [02 - Request Flow & Routing](02-request-flow-and-routing.md) — routes.rb patterns, the EsmProxyController dispatcher, manage CRUD, full URL→response trace.
- [03 - Authentication & Authorization](03-authentication-and-authorization.md) — Login/session, current_user, Role/Permission/ACL, and the security smells.
- [04 - Database Structure](04-database-structure.md) — MySQL metadata schema (ER), MongoDB per-tenant model, GridFS, Redis, migration timeline.
- [05 - Core Domain Models](05-core-domain-models.md) — Every domain model, persistence layer, associations; deep dive on document.rb / project.rb / service.rb.
- [06 - Docker & Infrastructure](06-docker-and-infrastructure.md) — Container topology, ports/volumes, build flow, SSL, and operational gotchas (workers, MySQL8 driver).
- [07 - Metadata-Driven Architecture](07-metadata-driven-architecture.md) — The centerpiece: how metadata becomes a running app at runtime via ERB + eval.
- [08 - Operation Execution Flow](08-operation-execution-flow.md) — Sync vs async (Resque) execution, dynamic-code engine, PDF generation, scheduling, security surface.
- [09 - Development Guide](09-development-guide.md) — How to work on this codebase: coding standards, Ruby 2.3 / Rails 4.2 constraints, Docker & DB-safety workflows, deployment checklist, debugging, git, and the feature-implementation contract.

## How to read

Start with **00 - System Overview**, then follow the document map. Docs 07 (Metadata) and 08 (Operation Execution) explain the runtime `eval` engine that is the heart — and the chief risk — of the platform.


## ⚠️ Top cross-cutting risk

The platform `eval`s operator-editable metadata at runtime (`Operation.command`, `Table.data`, `Field.params`), disables CSRF on the main proxy, uses weak SHA-1 auth with credentials in URLs, exposes an unauthenticated Resque dashboard at `/resque`, and shells out with `curl --insecure` in the PDF worker. The metadata-edit surface is effectively shell access. See docs 03, 07, 08.

