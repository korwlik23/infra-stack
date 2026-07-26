# InfraStack Public Repository Design

Date: 2026-07-26
Status: Approved

## Problem and Goal

The current repository contains reusable infrastructure code mixed with a private
operator checklist and deployment-specific examples. Publishing its existing Git
history would disclose server addresses, domains, project names, and operational
details.

The goal is to create a new public repository from a sanitized snapshot while
preserving the existing repository and its history as a private archive. The public
repository must be useful to a new InfraStack operator, contain no private checklist,
and start with a clean Git history.

## Approaches Considered

1. Create a clean repository from a sanitized snapshot. This is the selected approach
   because it prevents old private history from becoming public and avoids rewriting
   the private archive.
2. Rewrite the existing repository history. This preserves commits but requires a
   force-push and carries a higher disclosure and recovery risk.
3. Sanitize only the current working tree. This leaves private data in reachable Git
   history and is not acceptable for a public repository.

## Repository Boundaries

### Private archive

- `D:\infra-stack` remains the private source repository and retains its existing Git
  history.
- Work is isolated on `codex/public-repo-cleanup`.
- The current personal checklist is preserved locally as `TODO.private.md`.
- `.gitignore` excludes `/TODO.private.md` so it cannot enter future snapshots by
  accident.

### Public repository

- `D:\infra-stack-public` is created from the sanitized tracked snapshot.
- It receives a new `.git` directory and one root commit.
- It has no remote until the owner explicitly configures and pushes one.
- No branch, tag, object, or remote from the private repository is copied.

## File Layout and Responsibilities

### New files

- `TODO.private.md` — local-only copy of the operator-specific checklist.
- `LICENSE` — MIT license for public reuse.
- `docs/specs/2026-07-26-public-repository-design.md` — approved scope and safety
  contract for this cleanup.

### Replaced public checklist

- `TODO.md` — generic InfraStack installation checklist covering prerequisites,
  server hardening, configuration, core services, databases, monitoring, backup and
  restore, optional services, application deployment, validation, and maintenance.

### Public entry points

- `README.md` — public positioning, current version, quick start, security guidance,
  repository structure, documentation links, and license.
- `GUIDE.md` — replace the private-repository recommendation with guidance that keeps
  runtime configuration private while allowing the code repository to be public.
- `.gitignore` — exclude the local private checklist in addition to runtime secrets and
  generated data.

### Sanitized history and examples

- `CHANGELOG.md` — retain feature history while replacing private application names
  with generic descriptions.
- `environments/README.md`
- `environments/production.env.example`
- `docs/02-security.md`
- `docs/06-postgresql.md`
- `docs/15-deploy-laravel.md`
- `docs/19-cicd.md`
- `docs/20-rabbitmq.md`
- `docs/22-loki.md`
- `docs/25-zero-downtime.md`
- `docs/26-new-project.md`
- `docs/architecture.md`
- `docs/roadmap.md`
- `scripts/artisan.sh`
- `scripts/rollback.sh`
- `services/loki/README.md`
- `services/postgres/init/01-create-databases.sql`
- `templates/ai-worker/.env.example`
- `templates/laravel/.env.example`
- `templates/nextjs/.env.example`

These files use neutral values such as `app`, `app_db`, `example.com`, documentation
IP ranges, and configurable registry owners. The repository owner in the canonical
README clone URL may remain because it identifies the public repository itself; private
application repositories and infrastructure identifiers may not.

## Content Rules

- Never include real credentials, private keys, tokens, server IPs, private domains,
  internal repository names, personal deployment state, or incident-specific operator
  notes.
- Example credentials must be explicit placeholders or clearly local-only development
  values.
- Public instructions must not imply that `.env`, certificate material, backup data,
  or application source clones are safe to commit.
- The installation checklist must be reusable and must not contain pre-completed tasks
  tied to one server.
- Documentation and examples must agree with `VERSION` and the actual `docs/00` through
  `docs/26` layout.

## Data Flow

1. Preserve the private checklist as an ignored local file.
2. Sanitize the tracked working tree on the cleanup branch.
3. Validate the private branch snapshot before export.
4. Copy only tracked, sanitized files into `D:\infra-stack-public`.
5. Initialize a new repository and create one root commit.
6. Re-run privacy, secret, syntax, configuration, and documentation checks against the
   new repository and its complete one-commit history.

## Failure and Recovery

- The private `main` branch and `origin/main` are not rewritten or pushed.
- If sanitization is incomplete, the public repository is not considered ready and is
  not connected to a remote.
- If public repository creation fails, it can be recreated from the validated cleanup
  branch without affecting the private archive.
- Destructive replacement of an existing `D:\infra-stack-public` directory is not
  allowed without separate confirmation.

## Validation

- Confirm the private repository state before and after changes.
- Scan the sanitized snapshot and all public Git objects for strong secret patterns and
  static credential-like values without printing secret contents.
- Confirm that private IPs, domains, project names, and repository names found during
  discovery no longer occur in the public snapshot.
- Run `bash -n` for all shell scripts when Bash is available.
- Run Docker Compose configuration checks when Docker Compose is available.
- Check Markdown links and required public files.
- Confirm `TODO.private.md` is ignored and absent from public tracked files.
- Confirm the public repository contains exactly one root history and has no remote.

## Acceptance Criteria

- The private checklist remains available locally but is not tracked in the public
  repository.
- `TODO.md` guides a new operator through a complete InfraStack installation.
- No evidence-backed private identifiers or strong secret candidates remain in the
  public snapshot or history.
- Public documentation is internally consistent and licensed under MIT.
- The public repository is locally ready for owner review before any remote or
  visibility change.

## Open Questions

None. Remote creation, push, and GitHub visibility changes are explicitly outside this
design and require a later owner instruction.
