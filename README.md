# ZTA — Zero Trust Assessment for the browser · Limon-IT

Web version of Microsoft's open-source [Zero Trust Assessment](https://github.com/microsoft/zerotrustassessment) for customers of Limon-IT. Static SPA in the ENCA style: 100% in the browser, delegated read-only Microsoft Graph, no backend, no telemetry — nothing leaves the session.

**Target:** https://zerotrustassessment.limon-it.nl

## What works now (v0.1)

- **Sign-in** (MSAL PKCE, multi-tenant) or **demo mode** (`?demo=1` — sample data through the real engine, no setup needed)
- **Check engine**: 17 checks (Identity baseline + Intune compliance coverage) — a curated subset of the 328 upstream checks; incremental consent per pillar
- **Report**: score, per-pillar bars, filterable table, detail drawer with evidence and remediation
- **Download**: self-contained HTML report + results JSON (JSON is also embedded in the report HTML)
- **Save to SharePoint**: uploads report + JSON to a site in the assessed tenant (delegated `Sites.ReadWrite.All`, on demand); history listing
- **Drift compare**: current run vs any previous results JSON (file upload or SharePoint history) — regressed / fixed / new / removed

## Try it now

```bash
python3 -m http.server 8080   # from the repo root
# open http://localhost:8080/?demo=1        ← runs immediately, no app registration
```

Real tenant: run `./New-ZtaAppRegistration.ps1`, paste the client id into `CONFIG.clientId` in `index.html`, grant admin consent, open http://localhost:8080.

## Monthly runs & full coverage

The browser app is interactive and covers the v1 subset. **Unattended monthly runs with all 328 checks + automatic drift reports** are handled by the GitHub Actions automation (official PowerShell module, app-only certificate auth, delivery into each customer's own SharePoint site) — see [`automation/README.md`](automation/README.md). Both paths produce compatible results JSON, so the in-app drift compare works across them.

## Repo map

| Path | What |
|---|---|
| `index.html` | The app (single file: UI + engine + auth) |
| `mockup.html` | Original clickable design mockup |
| `New-ZtaAppRegistration.ps1` | SPA app registration (delegated, read-only) |
| `automation/` | Scheduled multi-customer runs — move to a private repo |
| `TODO.md` | Full build plan |
| `SETUP-GITHUB.md` | Push, Pages, DNS, private automation repo |
| `CNAME` | Custom domain for GitHub Pages |

License note: check engine inspired by and mapped to the MIT-licensed microsoft/zerotrustassessment; keep attribution.
