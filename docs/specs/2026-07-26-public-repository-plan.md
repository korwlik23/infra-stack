# InfraStack Public Repository Implementation Plan

Design reference: `docs/specs/2026-07-26-public-repository-design.md`

The approved design preserves `D:\infra-stack` and its existing history as a private
archive, sanitizes a review branch, keeps the personal checklist as an ignored local
file, replaces the tracked checklist with reusable installation guidance, and exports
only the validated tracked snapshot into a new one-commit repository at
`D:\infra-stack-public` with no remote.

## Task 1 — Preserve the private checklist

- **Files:** `TODO.md`, `TODO.private.md`, `.gitignore`
- **Change:** Copy the current operator-specific `TODO.md` to `TODO.private.md`; add
  `/TODO.private.md` to `.gitignore`; verify the private copy remains local and ignored.
- **Verify:** `git check-ignore -v TODO.private.md` reports the root ignore rule and
  `git status --short` does not list `TODO.private.md`.
- **Dependency:** Sequential; must run before replacing `TODO.md`.

## Task 2 — Replace the public installation checklist

- **Files:** `TODO.md`
- **Change:** Replace server-specific status notes with an unchecked, reusable
  installation checklist covering prerequisites, hardening, `.env`, core/database/
  monitoring stacks, optional services, backups and restore drills, application
  deployment, validation, and routine maintenance.
- **Verify:** The known-private-identifier scan returns no matches in `TODO.md`; every
  checklist section contains commands or links that exist in the repository.
- **Dependency:** Depends on Task 1.

## Task 3 — Add the public license

- **Files:** `LICENSE`
- **Change:** Add the standard MIT license with copyright holder `korwlik23` and year
  2026.
- **Verify:** `Test-Path LICENSE` is true and `rg -n '^MIT License$' LICENSE` returns
  exactly one match.
- **Dependency:** Independent after Task 1.

## Task 4 — Refresh public entry documentation

- **Files:** `README.md`, `GUIDE.md`, `docs/02-security.md`
- **Change:** Align the displayed release with `VERSION`, describe a public-code/
  private-runtime configuration model, update the documented `docs/00`–`docs/26`
  coverage, link the installation checklist and license, remove advice that the
  reusable code repository itself must be private, and replace the personal Windows
  prompt path with the existing `<user>` placeholder convention.
- **Verify:** `rg -n 'v2\.1\.0|repo.*Private|repository.*Private|00.?25|C:\\Users\\kil' README.md GUIDE.md docs/02-security.md`
  returns no stale/private matches and `rg -n 'v2\.3\.0|TODO\.md|LICENSE' README.md`
  finds the expected public entry points.
- **Dependency:** Independent after Task 1.

## Task 5 — Normalize environment examples

- **Files:** `environments/README.md`, `environments/production.env.example`
- **Change:** Replace the provider/location-specific production wording with generic
  VPS/production terminology while preserving all environment variables and
  placeholder semantics.
- **Verify:** `rg -n -i 'Contabo|Singapore|tewarach|217\.216|20\.63' environments`
  returns no matches.
- **Dependency:** Independent after Task 1.

## Task 6 — Generalize database and service examples

- **Files:** `docs/06-postgresql.md`, `services/postgres/init/01-create-databases.sql`,
  `docs/20-rabbitmq.md`, `services/loki/README.md`, `docs/22-loki.md`
- **Change:** Replace private database/container names with neutral `app_db` and
  `app-app` examples; keep `n8n_db` only where it represents the bundled n8n template;
  replace copyable weak URL credentials with explicit placeholders.
- **Verify:** The known-private-identifier and literal-credential scans over these files
  return no matches; SQL statements end with semicolons.
- **Dependency:** Independent after Task 1.

## Task 7 — Generalize application operation examples

- **Files:** `scripts/artisan.sh`, `scripts/rollback.sh`,
  `docs/15-deploy-laravel.md`, `docs/25-zero-downtime.md`
- **Change:** Replace private project names with the neutral project name `app` without
  changing script logic or deployment behavior.
- **Verify:** Run `bash -n scripts/artisan.sh scripts/rollback.sh`; run the private-name
  scan over the four files and expect no matches.
- **Dependency:** Independent after Task 1.

## Task 8 — Generalize CI/CD and project bootstrap guidance

- **Files:** `docs/19-cicd.md`, `docs/26-new-project.md`,
  `templates/ai-worker/.env.example`, `templates/laravel/.env.example`,
  `templates/nextjs/.env.example`
- **Change:** Replace private repository names, account-specific registry paths,
  production domains, and real IP addresses with `<github-user>`, `<repo>`,
  `example.com`, and RFC 5737 documentation address `203.0.113.10`.
- **Verify:** The known-private-identifier scan returns no matches; every template still
  contains `__PROJECT__` and root-token placeholders required by `create-project.sh`.
- **Dependency:** Independent after Task 1.

## Task 9 — Sanitize architecture and release narrative

- **Files:** `CHANGELOG.md`, `docs/architecture.md`, `docs/roadmap.md`
- **Change:** Replace private application/provider references with generic deployment
  language while preserving feature history, architecture, and roadmap intent.
- **Verify:** The known-private-identifier scan returns no matches and Markdown heading
  structure remains intact.
- **Dependency:** Independent after Task 1.

## Task 10 — Validate the sanitized private snapshot

- **Files:** all tracked files on `codex/public-repo-cleanup`
- **Change:** Run privacy, strong-secret, credential-like value, Markdown-link, shell
  syntax, file-size, and Docker Compose configuration checks; correct only findings
  within the approved file layout.
- **Verify:** No known private identifiers or strong secret candidates; no broken local
  Markdown links; all available syntax/configuration commands exit zero; no file reaches
  500 lines.
- **Dependency:** Depends on Tasks 2–9.

## Task 11 — Commit the sanitized snapshot

- **Files:** all approved cleanup files
- **Change:** Review the focused diff, stage only approved files, and commit with
  `chore: prepare clean public repository snapshot`.
- **Verify:** `git status --short` is clean and `git show --stat --oneline HEAD` lists
  only approved files.
- **Dependency:** Depends on Task 10.

## Task 12 — Export a clean public repository

- **Files:** `D:\infra-stack-public\**`
- **Change:** Confirm `D:\infra-stack-public` does not exist; copy only files returned
  by `git ls-files` from the sanitized branch, excluding `.git`; initialize `main`, add
  the snapshot, and create one root commit named
  `chore: publish initial InfraStack snapshot`.
- **Verify:** `git -C D:\infra-stack-public rev-list --count HEAD` returns `1`;
  `git -C D:\infra-stack-public log --max-parents=0 --oneline` returns one root commit;
  `git -C D:\infra-stack-public remote` returns no output.
- **Dependency:** Depends on Task 11 and is blocked if the target directory exists.

## Task 13 — Verify public history and handoff

- **Files:** all files and Git objects under `D:\infra-stack-public`
- **Change:** Repeat snapshot and complete-history scans, check ignored/private-file
  absence, validate shell and Compose files, verify required public documentation, and
  report any unavailable tooling as unverified.
- **Verify:** `git -C D:\infra-stack-public ls-files TODO.private.md` returns no output;
  one-commit/no-remote checks pass; privacy and strong-secret scans return no findings;
  available syntax/configuration checks pass.
- **Dependency:** Depends on Task 12.

## Parallelizable Work

Tasks 3–9 are content-independent after Task 1 and may be performed in any order.
Tasks 1–2 and Tasks 10–13 are strictly sequential. This execution will remain local to
one agent because no delegated or parallel-agent work was requested.
