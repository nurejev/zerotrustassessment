# ZTA Web — Zero Trust Assessment for the browser · TODO / build plan

**Goal:** bring Microsoft's [Zero Trust Assessment](https://github.com/microsoft/zerotrustassessment) (PowerShell module `Invoke-ZtAssessment`) to customers of Limon-IT as a web app at **https://zerotrustassessment.limon-it.nl** — same model as ENCA: 100% in the browser, static site, no backend, delegated read-only Graph token, no tenant data leaves the session.

**Decision (2026-07-27):** Browser-native, ENCA-style. No upload path, no server. Checks that cannot run in a browser are shown as *"run locally"* with instructions, not hidden.

---

## What we're porting (facts from the upstream repo, main @ July 2026)

- **328 tests** (`Test-Assessment.<id>.ps1`), each carrying a `[ZtTest()]` attribute with structured metadata: `TestId, Title, Pillar, RiskLevel (High 190 / Medium 112 / Low 19), UserImpact, ImplementationCost, Category, Service, CompatibleLicense, SfiPillar, TenantType (Workforce/External)`.
- **Pillars:** Identity 135 · Network 67 · Devices 43 · SecOps 18 · AI 14 · Data 7 · Infrastructure 1 (+2 untagged).
- **Data flow upstream:** an export phase pulls Graph/Azure data into a local **DuckDB** database; tests then query the DB. The HTML report is generated from test results (markdown per test).
- **Service dependency per test:** `Graph` 65 explicit + ~181 with no Service tag (DB-backed, Graph-sourced) → **~75% browser-feasible via Graph**. `Azure` (ARM) 40 → callable from the browser too (management.azure.com supports CORS + delegated token, needs `Azure Service Management user_impersonation` scope). **Not browser-feasible (~41):** `SecurityCompliance` 27, `ExchangeOnline` 9, `SharePointOnline` 4, `AipService` 1 — PowerShell-only endpoints.
- **Roles upstream:** first run Global Admin (consent), subsequent runs Global Reader + Security Reader (+ Exchange/SharePoint Admin for the PS-only parts we skip).
- **License:** upstream is MIT → we may port checks; keep attribution + upstream test IDs so results stay comparable and upstream doc links keep working.
- Upstream warns large tenants can take **>24 h** in PowerShell — driven mostly by log/report exports. Web version must scope these (see Risks).

## Architecture (mirrors ENCA)

- Static SPA, vanilla JS, no build step, GitHub Pages, `CNAME` = `zerotrustassessment.limon-it.nl`.
- MSAL.js (PKCE, SPA), **multi-tenant** Entra app registration, incremental consent: sign-in asks only `User.Read` + `Directory.Read.All`; each pillar requests its scopes when you run it.
- New app registration (do **not** reuse ENCA's — permission set is much bigger): `ZTA (Limon-IT)`. Script it like `New-EncaAppRegistration.ps1` → `New-ZtaAppRegistration.ps1`.
- Test catalog = generated JSON (`js/testCatalog.js`), produced by a script that parses the upstream `[ZtTest()]` attributes → we can re-run it on every upstream release to detect drift (new/changed/removed tests).
- Check engine: `fetch → normalize → evaluate` per test, in-memory only. No DuckDB-wasm in v1 — most tests reduce to filters/joins over a handful of Graph collections; plain JS is enough. Revisit if porting proves painful.
- Results object = `{testId, status: passed|failed|investigate|skipped, detailMarkdown, evidence[]}` → rendered report + JSON download (which doubles as input for "compare with previous run" later).

## Phases

### P0 — Scaffold ☐
- [ ] Repo layout like ENCA (`index.html`, `css/app.css`, `js/*`, `vendor/msal`, `assets`), CNAME file, `.gitignore`
- [ ] `New-ZtaAppRegistration.ps1` — multi-tenant SPA, redirect URIs `https://zerotrustassessment.limon-it.nl` + `http://localhost:8080`, delegated read-only scopes (the ~21 Graph scopes the PS module lists + ARM `user_impersonation`), writes `js/authConfig.js`
- [ ] MSAL sign-in / sign-out / tenant display, CSP meta tag (`connect-src graph.microsoft.com login.microsoftonline.com management.azure.com`)
- [ ] GitHub Pages + DNS CNAME `zerotrustassessment` → `<account>.github.io.`, enforce HTTPS
- [ ] `?demo=1` mode with bundled sample results (mockup data is the seed)

### P1 — Test catalog ☐
- [ ] Script (`scripts/build-catalog.ps1` or node) that walks upstream `src/powershell/**/tests/Test-Assessment.*.ps1`, extracts `[ZtTest()]` metadata + doc link (`aka.ms/zta/<id>`?) → `testCatalog.js`
- [ ] Tag each test: `webable: graph | arm | local-only` (from Service attribute)
- [ ] Map each webable test → the Graph/ARM endpoints it needs (derive from upstream export layer + test body; store as `datasets: []` so fetches are shared across tests)
- [ ] Pin upstream commit hash in the catalog; add a `diff-upstream` script for release drift

### P2 — Engine ☐
- [ ] Graph client: `$batch`, paging, retry/backoff on 429/503, beta+v1 fallback (reuse ENCA's `graph.js` patterns)
- [ ] Dataset loader: fetch-once shared datasets (users*, apps, service principals, CA policies, auth methods policy, Intune configs, risk detections, …), progress events per dataset
- [ ] Run orchestrator: select pillars → resolve scopes → incremental consent → fetch datasets → evaluate tests → stream results into the UI as they finish
- [ ] Scoping controls for big tenants: date-window for log-based tests, count caps with "partial — refine locally" flag
- [ ] Skipped-handling: license-gated (detect tenant SKUs), permission-denied (list scope + role needed, like ENCA's "Not read"), local-only (show the exact PS one-liner)

### P3 — Port the checks (by pillar, descending value) ☐
- [ ] Identity wave 1 (~40 highest-Risk Graph tests: CA baseline, break-glass, legacy auth, PIM, auth methods, app/consent hygiene — incl. 21770-series app permission checks)
- [ ] Identity wave 2 (rest of 135)
- [ ] Devices (43 — Intune: compliance, enrollment restrictions, LAPS, update rings)
- [ ] Network (67 — mostly Global Secure Access via Graph `networkAccess`)
- [ ] AI (14) + Data-via-Graph subset + SecOps Graph subset
- [ ] Azure/ARM tests (40 — audit/sign-in log export etc.) behind an opt-in "Azure checks" toggle
- [ ] Each ported test: fixture JSON + expected verdict (mini test harness in `tests/`), parity note vs upstream (exact / approximated / partial)

### P4 — Report UI (mockup = spec, see `mockup.html`) ☐
- [ ] Screens: sign-in → scope/run → live progress → report (Overview + pillar tabs + detail drawer)
- [ ] Overview: score per pillar, status donut, tenant info, top failed High-risk items
- [ ] Test table: search, pillar/status/risk filters, sort; detail drawer with evidence tables + remediation + doc link
- [ ] Exports: standalone HTML report (self-contained, light theme), Markdown, CSV, results-JSON; neutral branding on exports like ENCA
- [ ] Compare: load a previous results-JSON → delta view (fixed / regressed / new)

### P5 — Later / nice-to-have ☐
- [ ] History in localStorage (scores only, no tenant data) for trend line
- [ ] NL/EN
- [ ] "Run the missing 41 locally" helper: generates the exact PowerShell snippet, and (later?) accepts the official report's JSON to merge those results in
- [ ] Per-tool version stamps + build number à la ENCA

### P6 — Multi-customer scheduled runs + drift control (no own infrastructure) — **scaffolded, see `automation/README.md`** ☐

Recurring engine = the **official PowerShell module in GitHub Actions**; the web app stays the interactive front-end and becomes the drift viewer. Enabler: `Connect-ZtAssessment -ClientId … -TenantId … -Certificate 'CN=ZeroTrustAssessment'` = app-only CBA for **all** services → unattended + full 328-check coverage (including the 41 the browser can't run).

- [ ] Second app registration `ZTA-Automation (Limon-IT)` — multi-tenant, **application** permissions (the Application twins of the delegated scopes), certificate credential, no secrets
- [ ] Self-signed cert (1y), private key only as GitHub **environment secret** (base64 pfx), imported into the runner cert store at job start; rotation reminder
- [ ] Per-customer onboarding (one-time): admin-consent URL + assign the service principal Exchange Administrator/SharePoint roles where needed; store `{name, tenantId}` in `customers.json`
- [ ] Workflow `assess.yml`: `schedule:` cron weekly/monthly + `workflow_dispatch`, matrix over `customers.json`, runner `windows-latest` (DuckDB/VCRedist), steps: import cert → `Connect-ZtAssessment` (app-only) → `Invoke-ZtAssessment` → normalize results to `results/<customer>/<date>.json`
- [ ] **Drift = git.** Commit the per-test status JSON per run; a diff step compares with the previous run → `drift/<customer>/<date>.md` (regressed ❌ / fixed ✅ / new checks 🆕) → Teams webhook / email / GitHub issue on regressions
- [ ] Store only the status+summary JSON in the repo (private!), not the full HTML report (sensitive evidence) — full report as short-retention workflow artifact
- [ ] Web app: "Compare" loads two results-JSONs → same drift view interactively
- [ ] Caveats: GitHub-hosted job limit 6 h (fine for SMB tenants; very large tenant → fall back to an Azure Container Apps Job or self-hosted runner later), Windows runners cost 2× minutes (private repo free tier = 2,000 min/mo → monthly cadence for most customers, weekly for the few that need it)

### P7 — Customer access to their own results — **scaffolded: onboarding script creates the site (consent can't), see `automation/README.md`** ☐

Principle: **deliver results into the customer's own tenant** — no Limon-IT storage, no accounts to manage, access control is their own Entra ID, and each customer can only ever see their own data.

- [ ] Per customer, one SharePoint site/library in *their* tenant (e.g. `Security Reports/Zero Trust Assessment`), created at onboarding
- [ ] Give `ZTA-Automation` **`Sites.Selected` (application)** + a grant on only that site → the Actions run uploads per assessment: the self-contained **HTML report** (instantly viewable, zero extra work), the **drift report** (`drift-<date>.md`) and the **results JSON**; add retention guidance (report contains sensitive evidence)
- [ ] Optional notification step: Teams webhook / mail into the customer channel — "new assessment, score 73% (+2), 3 regressions" with a link to the report
- [ ] Web app integration (later): customer signs in on zerotrustassessment.limon-it.nl → tenantId from the token → reads the JSON history from their own SharePoint via delegated Graph (`Sites.Read.All` or Sites.Selected) → renders score trend + drift interactively. The SPA stays storage-free; it's a viewer over data that lives with the customer
- [ ] `customers.json` gains `{siteId, driveId}` per customer; onboarding script creates the site grant and validates upload

## Risks / open points

- **App-only power:** `ZTA-Automation` holds broad read permissions in every consented customer tenant and its key lives in GitHub secrets. Mitigate: private repo, environment protection rules, cert rotation, per-customer consent is revocable, document it in the customer agreement.

- **Consent weight:** ~21 read scopes needs one-time GA admin consent per customer tenant (same URL pattern as ENCA §6). Incremental consent softens the first-run screen but the full set is unavoidable for a full run.
- **Parity drift:** upstream moves fast; the catalog-diff script is the guard. Keep upstream TestIds visible in the UI.
- **Large tenants:** browser cannot chew 24 h of export — cap log-based tests by window/count and mark partial.
- **CA policies for External tenants** (`TenantType`): v1 targets Workforce tenants only.
- **Licensing display:** `CompatibleLicense` gating so customers aren't failed on features they don't own.
- **Where this repo lives:** this folder is the fresh repo for the web app (currently only `git init`). Vendor nothing from upstream except the generated catalog + attribution in README/LICENSE.

## Deliverables so far

- `TODO.md` — this plan
- `mockup.html` — clickable full-flow mockup (sign-in → run → report), ENCA look & feel, sample data. Open directly in a browser; the "▶ demo" controls bottom-right jump between screens.
