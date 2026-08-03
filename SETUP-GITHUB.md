# GitHub setup — zerotrustassessment.limon-it.nl

Two repos: this one (**public**, the web app, served by GitHub Pages) and the automation (**private**). Same recipe as ENCA.

## 1 · Web app repo (this one, public)

```bash
cd ~/REPO/zerotrustassessment
git remote add origin https://github.com/<your-account>/zerotrustassessment.git
git push -u origin main
```

> Name clash with `microsoft/zerotrustassessment` is fine — it lives under your account. Rename to `zta-web` if you prefer.

## 2 · GitHub Pages

Repo → **Settings → Pages** → Source: **Deploy from a branch** → branch `main`, folder `/ (root)` → Save.

The `CNAME` file in the repo root (`zerotrustassessment.limon-it.nl`) makes Pages pick up the custom domain automatically after the DNS record exists.

## 3 · DNS record at your registrar

For `limon-it.nl`, add:

| Type  | Name                  | Value                        |
|-------|-----------------------|------------------------------|
| CNAME | `zerotrustassessment` | `<your-account>.github.io.`  |

Back in **Settings → Pages**: confirm the custom domain shows `zerotrustassessment.limon-it.nl`, wait for the certificate (minutes to ~1 h), then tick **Enforce HTTPS**.

## 4 · App registration ↔ site

`New-ZtaAppRegistration.ps1` already registers both SPA redirect URIs (`https://zerotrustassessment.limon-it.nl` and `http://localhost:8080`), so no change needed. Just make sure `CONFIG.clientId` in `index.html` is filled **before** pushing.

Self-host MSAL before go-live (independent of CDNs):

```bash
mkdir -p vendor/msal
curl -L -o vendor/msal/msal-browser.min.js https://cdn.jsdelivr.net/npm/@azure/msal-browser@3.28.1/lib/msal-browser.min.js
git add vendor && git commit -m "vendor MSAL" && git push
```

## 5 · Test

- Local: `python3 -m http.server 8080` → http://localhost:8080 (`?demo=1` = no sign-in needed)
- Production: https://zerotrustassessment.limon-it.nl — sign in, run, download, save to SharePoint

## 6 · Automation repo (private!)

The `automation/` folder must NOT stay in the public repo — it's for a **private** repo (results summaries + drift history are customer data).

```bash
mkdir ~/REPO/zta-automation && cd ~/REPO/zta-automation
git init -b main
cp -R ~/REPO/zerotrustassessment/automation/. .
mv .github ./.github 2>/dev/null; ls .github/workflows/assess.yml   # workflow must be at repo root: .github/workflows/
echo '[]' > customers.json
git add -A && git commit -m "ZTA automation v1"
# create the PRIVATE repo on GitHub first, then:
git remote add origin https://github.com/<your-account>/zta-automation.git
git push -u origin main
```

Then, per `automation/README.md`:

1. **Settings → General**: confirm repo is Private.
2. **Settings → Environments** → new environment `assessment` (add yourself as required reviewer if you want manual approval per run) → secrets `ZTA_CLIENT_ID`, `ZTA_PFX_BASE64`, `ZTA_PFX_PASSWORD` (from `New-ZtaAutomationApp.ps1`).
3. **Settings → Actions → General** → Workflow permissions: **Read and write** (the workflow commits results).
4. Onboard a customer (`New-ZtaCustomerOnboarding.ps1`), add the printed entry to `customers.json`, push.
5. **Actions → assess → Run workflow** → customer name → first run = drift baseline.

Optionally remove `automation/` from the public repo once the private repo runs:

```bash
cd ~/REPO/zerotrustassessment
git rm -r automation && git commit -m "automation moved to private repo zta-automation" && git push
```

## Checklist

- [ ] Public repo pushed, Pages enabled, DNS CNAME set, HTTPS enforced
- [ ] `CONFIG.clientId` filled, MSAL vendored
- [ ] Private `zta-automation` repo with environment secrets
- [ ] First customer onboarded + baseline run
- [ ] `automation/` removed from the public repo
