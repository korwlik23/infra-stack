# Implementation Plan: Starter templates (`infra new shop cms-go`)

Design ref: `docs/specs/2026-11-27-starter-templates-design.md`

**สรุป design:** infra-stack ได้ alias/suite ใน `templates/starters.list`; `infra new` รับ alias /
suite / `owner/repo` แล้ว clone repo และใช้ `src/deploy/infra-stack/` เป็น template; token ใหม่
(`__GENERATE_B64__`, `__DB_RUNTIME_*__`, `__SUITE_ORIGIN:*__`, `__PROXY_CIDR__`); runtime role
`<role>_rt` แบบ DML-only; `DEPLOY_MIGRATE_SERVICE`; `infra deploy <suite>` ตามลำดับ.
go-lang-starter ย้ายไฟล์ deploy เข้า repo ลูก, API runtime เป็น alpine, drain hook, ชื่อ router
`__PROJECT__`, เลิก wrapper/pin. template เดิม (`go`, `laravel`, …) ต้องได้ผลเหมือนเดิมทุกไบต์.

**ข้อเท็จจริงจากโค้ดที่ plan อิง**
- `project_db_resolve` / `project_db_creds` (`backup/scripts/project-db-lib.sh`) อ่าน `DB_HOST`,
  `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `DATABASE_URL` เท่านั้น → `.env` ของ starter API
  ต้องใช้ชื่อเหล่านี้สำหรับ owner แล้ว map เป็น `DB_NAME`/`DB_USER` ของแอปใน compose
- `_db_run` ใช้ `docker compose run --entrypoint sh <svc>` → image ที่รัน migrate ต้องมี `sh`
- hash seed (`DEPLOY_SEED_PATHS`) คำนวณ **ใน image** → API ใช้ `/app/bootstrap`
  (`RunBootstrap` เจอ owner เดิม = `BootstrapPresent` → verify แล้วคืน `Created:false` — รันซ้ำได้)
- `setup-git.sh:21` บังคับให้มี `docker-compose.yml` ก่อน clone → ต้องแยก clone ออกเป็น lib
- site เดิมใช้ `SITE_API_BASE_URL=http://api:8080` — ชื่อ `api` ชนกันเมื่อมีหลาย suite บน network `proxy`
  → ใช้ origin สาธารณะ `__SUITE_ORIGIN:api__/api/v1`

**Branch:** infra-stack `feat/starter-templates` · go-lang-starter: parent + api/admin/site
`feat/infra-stack-standard-flow` (Task 0 ใช้ branch `chore/node-24-22` แยก)

**การรัน test ของ infra:** `bash tests/run.sh` (Git Bash บน Windows และบน VPS)
งานที่ต้องมี Docker/Postgres จริง ระบุ **Verify (VPS)** — ผู้ใช้รัน หรือให้สิทธิ์ SSH

---

## Part 0 — ก่อนเริ่ม (change แยก, go-lang-starter)

### Task 0 — อัปเกรด node ของ admin/site ให้ผ่าน baseline
- **Files:** `admin/Dockerfile`, `site/Dockerfile` (ทุกบรรทัด `FROM …node:24.8.0…`)
- **Change:** เปลี่ยนเป็น `node:24.<ล่าสุด ≥22.1>-bookworm-slim@sha256:<digest>` (ตรวจ tag + digest
  ล่าสุดจาก Docker Hub ตอนทำ, ใส่ comment เวอร์ชัน) · `engines`/`.nvmrc` ถ้ามีให้ตรงกัน · commit
  แยก branch `chore/node-24-22` ในแต่ละ repo
- **Verify:** `pnpm install --frozen-lockfile && pnpm build && pnpm test` ผ่านในทั้งสอง repo;
  `grep -n "node:24.8" */Dockerfile` ไม่เจอ · docker build (VPS)

---

## Part A — infra-stack

### Task A1 — test harness
- **Files:** `tests/run.sh`, `tests/lib.sh`
- **Change:** `lib.sh` มี `assert_eq <got> <want> <msg>`, `assert_contains`, `assert_fail <cmd…>`,
  `mk_sandbox` (สร้าง temp dir ที่มี `scripts/`, `templates/`, `backup/` symlink/copy ของ repo +
  `.env` กลางปลอม `BASE_DOMAIN=example.com`, `REDIS_PASSWORD=r&|\\x`, `POSTGRES_USER=infra`) ·
  `run.sh` source ทุก `tests/test_*.sh` รันฟังก์ชัน `test_*` นับผ่าน/ล้ม exit ≠0 ถ้ามีล้ม
- **Verify:** `bash tests/run.sh` → `0 passed, 0 failed`, exit 0

### Task A2 — golden test ของ template เดิม (ก่อนแตะ create-project)
- **Files:** `tests/test_create_project_builtin.sh`
- **Change:** ใน sandbox ที่ไม่มี docker (stub `docker` ใน PATH คืน exit 1) รัน
  `scripts/create-project.sh blog go` และ `… shop laravel`; เทียบ `.env` (ตัดค่าสุ่ม hex 48 ตัวเป็น
  `<HEX>`) และ `docker-compose.yml` กับ snapshot ที่สร้างจาก `main` ตอนนี้ (`tests/golden/go.env`,
  `go.compose.yml`, `laravel.env`)
- **Verify:** `bash tests/run.sh` ผ่าน (test นี้ต้องผ่านต่อเนื่องทุก task หลังจากนี้)

### Task A3 — แยก token replacement ออกเป็น lib  (depends A2)
- **Files:** `scripts/lib/project-tokens.sh` (ใหม่), `scripts/create-project.sh`
- **Change:** ย้าย `resolve_root_tokens`, การแทน `__DB_USER__/__DB_PASSWORD__`, loop `__GENERATE__`
  ไปเป็นฟังก์ชัน `tokens_resolve_root <penv>`, `tokens_db_user <name> <penv>`,
  `tokens_generate <penv>` ใน lib; create-project.sh source แล้วเรียกตามลำดับเดิม (ไม่เปลี่ยนพฤติกรรม)
- **Verify:** golden test (A2) ผ่าน · `bash -n scripts/create-project.sh scripts/lib/project-tokens.sh`

### Task A4 — `__GENERATE_B64__`  (depends A3)
- **Files:** `scripts/lib/project-tokens.sh`, `tests/test_tokens.sh`
- **Change:** test ก่อน: `.env` มี `A=v1:__GENERATE_B64__` และ `B=v1:__GENERATE_B64__` → ค่าตรง
  `^v1:[A-Za-z0-9+/]{43}=$`, A≠B · implement `tokens_generate` ให้แทนทีละตัวด้วย
  `openssl rand -base64 32` ผ่าน bash string replace (base64 มี `/` `+` — ห้ามใช้ sed `s///`)
- **Verify:** `bash tests/run.sh` ผ่าน (เห็น test ล้มก่อน implement)

### Task A5 — `__DB_RUNTIME_USER__` / `__DB_RUNTIME_PASSWORD__`  (depends A3)
- **Files:** `scripts/lib/project-tokens.sh`, `tests/test_tokens.sh`
- **Change:** test ก่อน: project `my-shop` → `DB_RUNTIME_USER=my_shop_rt`, password hex 48 ตัว
  และ ≠ `DB_PASSWORD` · implement ใน `tokens_db_user` ใช้ `project_db_role_name` + `_rt`
- **Verify:** `bash tests/run.sh` ผ่าน

### Task A6 — `__SUITE_ORIGIN:*__` และ `__PROXY_CIDR__`  (depends A3)
- **Files:** `scripts/lib/project-tokens.sh`, `tests/test_tokens.sh`
- **Change:** `tokens_suite <penv> <suite|"">`: suite `shop` + `BASE_DOMAIN=example.com` →
  api=`https://shop-api.example.com`, admin=`https://shop-admin.example.com`,
  site=`https://shop.example.com`; `__SUITE_HOST:*__` = ค่าเดียวกันแบบไม่มี `https://`;
  ไม่มี suite → `CHANGE_ME` + เตือน · `tokens_proxy_cidr <penv>`:
  `docker network inspect proxy -f '{{(index .IPAM.Config 0).Subnet}}'`; ล้ม/ว่าง → `CHANGE_ME` + เตือน
  · test ใช้ stub `docker` ที่พิมพ์ `172.20.0.0/16`
- **Verify:** `bash tests/run.sh` ผ่าน (ทั้งกรณีมี/ไม่มี suite, มี/ไม่มี docker)

### Task A7 — compose guard
- **Files:** `scripts/lib/compose-guard.sh` (ใหม่), `tests/test_compose_guard.sh`
- **Change:** `compose_guard <compose-file>` exit 1 + ข้อความ ถ้าเจอ `docker.sock`,
  `privileged:\s*true`, `network_mode:\s*host`, `pid:\s*host`, `cap_add:` ที่มี `SYS_ADMIN`/`ALL`
  · test: ไฟล์ปลอดภัยผ่าน, แต่ละกรณีอันตรายล้ม
- **Verify:** `bash tests/run.sh` ผ่าน

### Task A8 — แยก clone ออกจาก setup-git.sh
- **Files:** `scripts/lib/git-clone.sh` (ใหม่), `scripts/setup-git.sh`
- **Change:** ย้าย `clone_repo` (public https / deploy key + exit 2) และขั้น "เปิด build: ./src" เป็น
  `git_clone_into <name> <repo> <branch> <dest>` และ `enable_local_build <dir> <name>`;
  `git_clone_into` **ไม่** อ่าน compose (ตรวจ Dockerfile ให้ caller ทำ) · setup-git.sh เรียกผ่าน lib,
  ข้อความ/exit code เดิม
- **Verify:** `bash -n` ทั้งสองไฟล์ · test: `setup-git.sh x` บน sandbox ที่ไม่มี compose ยัง error เดิม
  · **(VPS)** `infra git <project-เดิม>` บน project ที่ clone แล้ว → "ข้ามการ clone" เหมือนเดิม

### Task A9 — `templates/starters.list` + parser
- **Files:** `templates/starters.list`, `scripts/lib/starters.sh` (ใหม่), `tests/test_starters.sh`
- **Change:** list ตาม design ข้อ 3.1 (`cms-api-go`, `cms-admin`, `cms-site`, suite `cms-go`) ·
  `starter_repo <alias>` → `owner/repo` หรือ exit 1 · `starter_suite <suite>` → บรรทัด
  `api cms-api-go` / `admin cms-admin` / `site cms-site` ตามลำดับ · ข้าม comment/บรรทัดว่าง
  · test: alias, suite, ชื่อที่ไม่มี, ชื่อ template ในตัว (`go`) ไม่ใช่ alias
- **Verify:** `bash tests/run.sh` ผ่าน
- **Note:** `templates/starters.list` เป็นไฟล์ ไม่ใช่โฟลเดอร์ → `ls templates` ใน error message ของ
  create-project ต้องกรองเป็น `find templates -mindepth 1 -maxdepth 1 -type d`

### Task A10 — `infra new <ชื่อ> <alias|owner/repo>`  (depends A3–A9)
- **Files:** `scripts/create-project.sh`
- **Change:** หลัง parse args: ถ้า `templates/$2` เป็นโฟลเดอร์ → ทางเดิม · ถ้า `starter_repo $2` เจอ
  หรือ `$2` ตรง `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$` → `git_clone_into` ลง `projects/$NAME/src`
  (exit 2 = รอ deploy key: ส่งต่อ exit 2 พร้อมบอกให้รันคำสั่งเดิมซ้ำ) · ต้องมี
  `src/deploy/infra-stack/docker-compose.yml` และ `src/Dockerfile` ไม่งั้นหยุด · `compose_guard` ·
  คัดลอก `src/deploy/infra-stack/.` เข้า `projects/$NAME/` (ไม่ทับ `src/`) · ขั้นเดิม (token, DB,
  db-user) + `tokens_suite`/`tokens_proxy_cidr` · `enable_local_build` · `APP_IMAGE=$NAME:latest`
  · `--mysql` กับ repo template = error (นอกขอบเขต) · แก้ USAGE + ข้อความ next steps
- **Verify:** test ด้วย repo ปลอม (`git init` ใน temp + `deploy/infra-stack/` + `Dockerfile`, ส่งเป็น
  `file://` ผ่านตัวแปร test `INFRA_TEST_REPO_URL`) → ได้ compose/.env ครบ, token ถูกแทน, `src/` ไม่ถูก
  แทน `__PROJECT__` · repo ไม่มี `deploy/infra-stack` → exit 1 · compose มี docker.sock → exit 1 ·
  golden test (A2) ยังผ่าน

### Task A11 — suite ใน `infra new`  (depends A10)
- **Files:** `scripts/create-project.sh`, `tests/test_create_project_repo.sh`
- **Change:** `starter_suite $2` เจอ → ตรวจชื่อ `<ชื่อ>-api|admin|site` ว่างทั้งหมดก่อนเริ่ม · วน
  `create-project.sh <ชื่อ>-<suffix> <alias>` ด้วย env `INFRA_SUITE=<ชื่อ>` (ให้ `tokens_suite` ใช้) ·
  ตัวใดล้ม → หยุดและบอกว่าสร้างตัวไหนไปแล้ว (ไม่ลบเอง) · สำเร็จ → เขียน `projects/<ชื่อ>.suite`
  (บรรทัดละชื่อ ตามลำดับ api, admin, site) · next steps: DNS 3 record + `infra deploy <ชื่อ>`
- **Verify:** test ด้วย repo ปลอม 3 ตัว → 3 project + `.suite` · origin ใน `.env` ทั้ง 3 ตรงกัน ·
  ชื่อชน → ไม่สร้างอะไรเลย

### Task A12 — runtime role ใน `db-user.sh`
- **Files:** `scripts/db-user.sh`
- **Change:** หลังขั้น owner + ก่อนทดสอบ login: ถ้า `penv DB_RUNTIME_USER` ไม่ว่าง → validate ชื่อ
  `^[a-z_][a-z0-9_]*$` และ ≠ owner/superuser · สร้าง/ALTER role `LOGIN NOSUPERUSER NOCREATEDB
  NOCREATEROLE NOINHERIT` ด้วย `DB_RUNTIME_PASSWORD` (escape `'`) · SQL ใน database ของ project:
  `GRANT CONNECT ON DATABASE`, `GRANT USAGE ON SCHEMA public`,
  `GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public`,
  `GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public`,
  `ALTER DEFAULT PRIVILEGES FOR ROLE <owner> IN SCHEMA public GRANT … ON TABLES / ON SEQUENCES`
  · ทดสอบ login ด้วย runtime role แบบเดียวกับ owner · ไม่มี key → ไม่ทำอะไรเพิ่ม
- **Verify:** `bash -n` · **(VPS)** project ทดสอบ: login ด้วย `_rt` แล้ว `SELECT` ได้,
  `CREATE TABLE x()` / `DROP TABLE` ถูกปฏิเสธ, ตารางที่ owner สร้างหลังจากนั้น `_rt` `INSERT` ได้ ·
  รัน `infra db-user <project>` ซ้ำได้ · project เดิม (ไม่มี key) ผลเหมือนเดิม

### Task A13 — `DEPLOY_MIGRATE_SERVICE`
- **Files:** `scripts/lib/deploy-db.sh`
- **Change:** ใน `deploy_db` หลังรับ `$2`: `svc="$(_db_env DEPLOY_MIGRATE_SERVICE)"; [ -z "$svc" ] || _DB_SVC="$svc"`
  · เพิ่มบรรทัดใน comment หัวไฟล์ · `_db_run` เดิมใช้ได้ (`compose run` รัน service ใน profile ได้)
- **Verify:** `bash -n` · **(VPS)** deploy starter API → log migrate มาจาก `api-migrate` และ
  `docker inspect <api container>` ไม่มี `DB_PASSWORD` ของ owner

### Task A14 — `infra deploy <suite>`
- **Files:** `scripts/deploy-suite.sh` (ใหม่), `scripts/infra`
- **Change:** `deploy-suite.sh <ชื่อ> [args]` อ่าน `projects/<ชื่อ>.suite` แล้วรัน
  `scripts/deploy.sh <member> [args]` ทีละตัว, ล้ม → หยุด พิมพ์ว่าตัวไหนล้ม/ตัวไหนยังไม่ deploy ·
  ใน `scripts/infra` บรรทัด `deploy)`: ถ้า `$1` ตรงกับ `projects/$1.suite` → exec deploy-suite.sh
  ไม่งั้นทางเดิม
- **Verify:** test ด้วย stub `deploy.sh` (ตัวที่ 2 คืน 1) → ตัวที่ 3 ไม่ถูกเรียก, exit ≠0 ·
  `infra deploy <project-เดิม>` ทางเดิม

### Task A15 — `infra list` / help / completion
- **Files:** `scripts/infra` (`cmd_list`, help text ของ `new`/`deploy`), `scripts/infra-completion.bash`
- **Change:** `cmd_list` แสดง suite (ชื่อ → สมาชิก) · help `new <ชื่อ> <template|starter|suite|owner/repo>`
  · completion ของ `new` ตัวที่ 2 = โฟลเดอร์ใน `templates/` + alias + suite จาก `starters.list`;
  ของ `deploy` เพิ่มชื่อ suite
- **Verify:** `bash -n` ทั้งสองไฟล์ · test: `cmd_list` ใน sandbox ที่มี `.suite` แสดงชื่อ suite

### Task A16 — เอกสาร
- **Files:** `docs/32-starters.md` (ใหม่), `README.md`, `GUIDE.md`, `scripts/README.md`, `CHANGELOG.md`
- **Change:** `docs/32`: สำหรับมือใหม่ — `infra new shop cms-go`, DNS 3 record (Proxied), `infra deploy shop`,
  login ครั้งแรก (`BOOTSTRAP_EMAIL`/`PASSWORD` อยู่ที่ `infra env shop-api` → เปลี่ยนรหัสทันที),
  ข้อตกลงของ repo ที่จะทำเป็น starter (`deploy/infra-stack/`, Dockerfile ที่ root, image มี `sh`+`wget`,
  `/tmp` เขียนได้, token ที่ใช้ได้), runtime role, ข้อควรระวัง repo ภายนอก · เพิ่มคำสั่งใน
  รายการคำสั่งทุกที่ที่ `infra new` ถูกกล่าวถึง · CHANGELOG หัวข้อ Unreleased
- **Verify:** `grep -rn "infra new" README.md GUIDE.md docs/ scripts/README.md` — ทุกที่ที่อธิบาย
  syntax ตรงกับ USAGE ใหม่

---

## Part B — go-lang-starter (branch `feat/infra-stack-standard-flow`)

### Task B1 — API runtime image เป็น alpine
- **Files:** `api/Dockerfile`
- **Change:** stage สุดท้าย `FROM scratch` → `FROM docker.io/library/alpine:<ล่าสุด>@sha256:<digest>`
  (comment เวอร์ชัน) · `RUN apk add --no-cache ca-certificates tzdata && adduser -D -H -u 65532 app`
  · ลบ COPY ca-certificates/zoneinfo จาก build stage · `WORKDIR /app`, binaries เดิม, `USER 65532:65532`,
  HEALTHCHECK เดิม
- **Verify:** `go test ./...` ผ่าน · `tests/container` ผ่าน (ถ้าตรวจ Dockerfile ให้แก้ test ตาม design
  พร้อมเหตุผลใน commit) · **(VPS)** `docker build` แล้ว `docker run --rm --entrypoint sh <img> -c 'id -u; which wget'`
  → `65532` และ path ของ wget

### Task B2 — API `deploy/infra-stack/docker-compose.yml`  (depends B1)
- **Files:** `api/deploy/infra-stack/docker-compose.yml`
- **Change:** จาก `ops/infra-stack/api/docker-compose.yml` เดิม: `image: ${APP_IMAGE}` + `# build: ./src` ·
  router/service = `__PROJECT__` · เพิ่ม `healthcheck` (`test ! -f /tmp/drain && wget -qO /dev/null
  http://localhost:8080/readyz || exit 1`, interval 10s, retries 3, start_period 20s) และ label
  `docker-rollout.pre-stop-hook=touch /tmp/drain && sleep 35` · environment ของ `api`:
  `DB_NAME: ${DB_DATABASE}`, `DB_USER: ${DB_RUNTIME_USER}`, `DB_PASSWORD: ${DB_RUNTIME_PASSWORD}` ·
  `api-migrate`: `image: ${APP_IMAGE}`, `profiles: [tools]`, `DB_USER: ${DB_USERNAME}`,
  `DB_PASSWORD: ${DB_PASSWORD}` + ทุก key ที่ `config.Validate` ต้องใช้ตอน `bootstrap`
  (ตรวจจาก `internal/platform/config` — ใส่ให้ครบ) + `BOOTSTRAP_*` · ไม่มี `container_name`
- **Verify:** ใน project ปลอมที่มี `.env` จาก B3: `docker compose config -q` ผ่าน (VPS หรือ Docker local) ·
  `compose_guard` (A7) ผ่าน

### Task B3 — API `deploy/infra-stack/.env.example` + README  (depends B2)
- **Files:** `api/deploy/infra-stack/.env.example`, `api/deploy/infra-stack/README.md`
- **Change:** ตาม design ข้อ 4.2 โดยใช้ key ของ infra สำหรับ owner:
  `DB_HOST=postgres`, `DB_PORT=5432`, `DB_DATABASE=__PROJECT___db`, `DB_USERNAME=__DB_USER__`,
  `DB_PASSWORD=__DB_PASSWORD__`, `DB_RUNTIME_USER=__DB_RUNTIME_USER__`,
  `DB_RUNTIME_PASSWORD=__DB_RUNTIME_PASSWORD__`, `DB_SSLMODE=disable`, `DB_DRIVER=postgres`,
  `APP_IMAGE=__PROJECT__:latest`, `APP_DOMAIN` จาก `__SUITE_ORIGIN:api__` (ไม่มี scheme — ใช้ token
  `__SUITE_HOST:api__` แทน → **เพิ่มใน A6**), peppers `__GENERATE__`, keyrings `v1:__GENERATE_B64__`,
  `TRUSTED_PROXY_CIDRS=__PROXY_CIDR__`, `ROLLOUT_SERVICE=api`, `HEALTHCHECK_PATH=/readyz`,
  `DEPLOY_MIGRATE=1`, `DEPLOY_MIGRATE_SERVICE=api-migrate`, `DEPLOY_MIGRATE_CMD=/app/migrate`,
  `DEPLOY_SEED_CMD=/app/bootstrap`, `DEPLOY_SEED_PATHS=/app/bootstrap`,
  `BOOTSTRAP_EMAIL=admin@__ROOT:BASE_DOMAIN__`, `BOOTSTRAP_PASSWORD=__GENERATE__` · README = ข้อตกลง
- **Verify:** ทุก token ใน `.env.example` เป็น token ที่ A3–A6 รองรับ:
  `grep -oE '__[A-Z_]+(:[A-Za-z_]+)?__' .env.example | sort -u` ตรงกับรายการใน `project-tokens.sh`

### Task B4 — admin `deploy/infra-stack/`
- **Files:** `admin/deploy/infra-stack/{docker-compose.yml,.env.example,README.md}`
- **Change:** จาก ops เดิม: `image: ${APP_IMAGE}` + `# build: ./src`, router = `__PROJECT__`,
  healthcheck (`test ! -f /tmp/drain && wget -qO /dev/null http://localhost:8080/healthz`) + drain hook ·
  `.env`: `APP_IMAGE=__PROJECT__:latest`, `APP_DOMAIN=__SUITE_HOST:admin__`, `ROLLOUT_SERVICE=admin`,
  `HEALTHCHECK_PATH=/healthz`, `DEPLOY_MIGRATE=0`, `PUBLIC_API_BASE_URL=__SUITE_ORIGIN:api__/api/v1`
- **Verify:** `docker compose config -q` · `compose_guard` · image มี `wget` (nginx alpine มี busybox wget)

### Task B5 — site `deploy/infra-stack/`
- **Files:** `site/deploy/infra-stack/{docker-compose.yml,.env.example,README.md}`
- **Change:** แบบเดียวกับ B4, port 4321, `APP_DOMAIN=__SUITE_HOST:site__`,
  `SITE_API_BASE_URL=__SUITE_ORIGIN:api__/api/v1`, `PUBLIC_SITE_URL=__SUITE_ORIGIN:site__` ·
  healthcheck ใช้ `node /app/healthcheck.mjs` เมื่อไม่มี `/tmp/drain` (image เป็น node slim — ไม่มี wget)
- **Verify:** `docker compose config -q` · `compose_guard`

### Task B6 — ลบ flow เดิมใน parent + docs  (depends B2–B5)
- **Files:** ลบ `ops/infra-stack/`, `scripts/deploy-infra-stack.sh` (+ test/CI ที่อ้างถึง);
  `releases/*.yaml` + `docs/contracts/release-manifest.md` (เอา field InfraStack revision ออก);
  `docs/operations/infra-stack.md` (เขียนใหม่: `infra new shop cms-go` → DNS → `infra deploy shop`);
  `README.md` (ลิงก์); submodule pointers ของ api/admin/site
- **Verify:** `grep -rn "deploy-infra-stack\|ops/infra-stack\|ee4df17" --exclude-dir=node_modules .`
  ไม่เจอ (ยกเว้น CHANGELOG) · CI workflows ของ parent ผ่าน (`pnpm test` / vitest ที่ root)

---

## Part C — End-to-end (VPS) — depends A, B (push branch ของ starter ก่อน)

### Task C1 — ติดตั้งทั้งชุด
- **Verify:** `infra new demo cms-go` → 3 project + `projects/demo.suite` · เพิ่ม DNS 3 record ·
  `infra deploy demo` ผ่าน (ถาม seed → y) · `curl -fsS https://demo-api.<BASE>/readyz` = 200 ·
  admin login ด้วย `BOOTSTRAP_*` ได้ · `https://demo.<BASE>/th/` แสดงผล

### Task C2 — ความปลอดภัยและ zero-downtime
- **Verify:** `infra psql` เป็น `demo_api_rt` → `DROP TABLE` ถูกปฏิเสธ · `docker inspect` container
  api ไม่มีรหัส owner · ยิง `curl` วนต่อเนื่องระหว่าง `infra deploy demo-api` → ไม่มี non-2xx ·
  `infra rollback demo-api` ใช้ได้ · `infra audit` ไม่มี finding ใหม่ · `infra deploy` ซ้ำ
  (bootstrap รันซ้ำ) ผ่าน

---

### ลำดับ / ทำคู่ขนานได้
- Part 0 อิสระ ทำก่อน Part B
- A1 → A2 → A3 → {A4, A5, A6} · A7, A8, A9, A12, A13, A14 อิสระต่อกัน (หลัง A1)
- A10 ต้องรอ A3–A9 · A11 ต้องรอ A10 · A15 รอ A9 + A14 · A16 ท้ายสุดของ Part A
- B1 → B2 → B3 · B4, B5 อิสระ (ทำหลัง A6 เพราะใช้ `__SUITE_HOST__`) · B6 ท้ายสุดของ Part B
- Part C ท้ายสุด

### แก้จาก design ระหว่างเขียน plan
- เพิ่ม token `__SUITE_HOST:api|admin|site__` (host ไม่มี scheme สำหรับ `APP_DOMAIN`) — ส่วนหนึ่งของ A6
- site ใช้ origin สาธารณะแทน `http://api:8080` (ชื่อชนเมื่อมีหลาย suite)
- `api/.env` ใช้ชื่อ key ของ infra (`DB_DATABASE`/`DB_USERNAME`/`DB_PASSWORD`) สำหรับ owner เพื่อให้
  backup / db-user / restore ที่มีอยู่ทำงานได้โดยไม่ต้องแก้
