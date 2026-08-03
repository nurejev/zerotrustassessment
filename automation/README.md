# ZTA Automation — scheduled multi-customer Zero Trust Assessments

Runs the official `ZeroTrustAssessment` PowerShell module unattended in GitHub Actions (no own
infrastructure), per customer, weekly or monthly, with drift control via git history, and delivers
the output into **each customer's own SharePoint site**.

> ⚠️ This `automation/` folder belongs in a **separate PRIVATE repo** (e.g. `limon-it/zta-automation`),
> not in the public web-app repo — results summaries and workflow logs are customer-specific.

## How it fits together

```
GitHub Actions (cron) ──run per customer──▶ Invoke-ZtAssessment (app-only cert auth)
        │                                          │
        │ commit results/<cust>/<date>.json        ├─▶ ZeroTrustAssessmentReport.html ─┐
        │ commit drift/<cust>/<date>.md            │                                   │
        ▼                                          ▼                                   ▼
   git history = drift control            customer SharePoint site  ◀── report + drift + json
                                          (their tenant, their access control)
```

## One-time setup (Limon-IT side)

1. **Create the private repo** and copy this folder into its root (so the workflow lives at
   `.github/workflows/assess.yml` — move `automation/.github` up one level).
2. **App registration:** run [`New-ZtaAutomationApp.ps1`](New-ZtaAutomationApp.ps1) in the Limon-IT
   tenant. Creates the multi-tenant `ZTA-Automation (Limon-IT)` app with application permissions
   (Graph read set + `Sites.Selected` + `Exchange.ManageAsApp`) and a self-signed certificate.
3. **GitHub secrets:** repo → Settings → Environments → create `assessment` (add protection rules)
   → secrets `ZTA_CLIENT_ID`, `ZTA_PFX_BASE64`, `ZTA_PFX_PASSWORD`. Delete the local PFX afterwards.
4. Create `automation/customers.json` from [`customers.sample.json`](customers.sample.json)
   (starts empty: `[]`).

## Per-customer onboarding (± 10 minutes)

**Q: can the SharePoint site be created "from the consent"?**
No — admin consent only creates the service principal in the customer tenant and grants the API
permissions. It cannot create sites, grant `Sites.Selected` on a specific site, or assign roles.
That's why onboarding is *consent + one script*, run back-to-back:

1. **Consent** — customer Global Admin opens:
   `https://login.microsoftonline.com/<customer-tenant>/adminconsent?client_id=<ZTA_CLIENT_ID>`
2. **Onboarding script** — run [`New-ZtaCustomerOnboarding.ps1`](New-ZtaCustomerOnboarding.ps1)
   signed in as an admin of the **customer** tenant (their GA on a call, or you via GDAP):

   ```powershell
   ./New-ZtaCustomerOnboarding.ps1 -CustomerTenantId contoso.onmicrosoft.com -ClientId <ZTA_CLIENT_ID>
   ```

   It does, in order (idempotent — safe to re-run):
   - verifies consent (waits and re-checks if the service principal isn't there yet);
   - **creates the delivery site**: a *private* M365 group `Zero Trust Assessment` → its team site
     is the report library (or pass `-ExistingSiteUrl` to reuse a site they already have);
   - grants `ZTA-Automation` **write on only that site** (`Sites.Selected` grant);
   - assigns the service principal **Global Reader** (read access for app-only Exchange Online /
     Security & Compliance; add SharePoint Administrator only if SPO checks turn out to need it);
   - uploads a test file to prove the delivery path;
   - prints the ready-made **customers.json entry** (`name, tenantId, siteId, driveId, siteUrl, schedule`).
3. **Who sees the reports:** add the customer's security contacts as *members* of the private
   M365 group. That's the entire access model — their tenant, their Entra ID, their audit log.
4. Optional: **Azure checks** (log export tests) — give the service principal `Reader` on their
   subscription(s). Optional: per-customer Teams webhook → secret `TEAMS_WEBHOOK_<NAME>` +
   `"teamsWebhookSecret"` in customers.json.
5. Commit the new `customers.json` entry. Test immediately: Actions → `assess` → *Run workflow* →
   customer name. The first run is the drift baseline.

## Cadence & drift

- `schedule: "weekly"` in customers.json → runs Mondays 04:00 UTC **and** on the monthly run;
  `"monthly"` → 1st of the month only.
- Every run commits `results/<customer>/<date>.json` (per-test status only — evidence stays out of
  git) and `drift/<customer>/<date>.md` (❌ regressed / ✅ fixed / 🆕 new / ➖ removed).
- The full HTML report is **not** committed: it goes to the customer's SharePoint (+ a 14-day
  workflow artifact for debugging).

## Certificate rotation (yearly)

Re-run `New-ZtaAutomationApp.ps1` (adds a new cert alongside the old), update the two PFX secrets,
remove the old key credential from the app after the next successful run. No customer action needed.

## Known limits / to verify on the pilot run

- [ ] Property names in `Export-ZtaResultsJson.ps1` (`TestId`, `TestStatus`, …) against the real
      `reportData` schema of the installed module version.
- [ ] Whether SPO-specific checks work app-only with Global Reader alone, or need the SharePoint
      Administrator role (upstream docs say "Exchange/SharePoint admin roles" for full coverage).
- [ ] GitHub-hosted job limit: 6 h. Fine for SMB tenants; a very large tenant needs a self-hosted
      runner or an Azure Container Apps Job.
- [ ] Windows runners consume 2× included minutes (private repo free tier = 2,000 min/month) —
      start monthly, promote individual customers to weekly as budget allows.
