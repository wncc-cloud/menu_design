---
name: check-bug-logs
description: Check the café menu app's logged bugs (Admin → Bug logs / Firestore clientLogs) from PROD, read-only. Fetches the logs, groups them, finds the cause in the code, gives the owner a report with examples, why it happened and possible fixes, discusses, and fixes only after the owner approves. Use whenever the owner says "check logged bugs", "check bug logs", "any errors in prod?", "what went wrong today", "did customers have problems", or runs /check-bug-logs.
---

# Check bug logs (PROD, read-only)

Five phases, in order: **Ask → Fetch → Analyse → Report & discuss → Fix (only after approval)**.
Never skip the approval gate. Write to the owner in plain, simple English.

This app has ONE Firebase project (`cafe-countryside-menu`) and no dev project: the local emulator is the dev
environment (see `.wolf/cerebrum.md`). So there is no "which app?" question.

## 1. Ask

If the owner has not already said it, ask with AskUserQuestion (one question):
- **How far back?** `Last 24 hours` / `Last 3 days` / `Everything stored (≈7 days)`.
  Map to `-Hours 24` / `-Hours 72` / `-Hours 0`.
If `$ARGUMENTS` already says it (e.g. `24h`), don't ask.

## 2. Fetch (read-only)

```powershell
.\scripts\fetch-bug-logs.ps1 -Hours 24        # -> client-logs/prod-latest.json
node scripts/summarize-bug-logs.mjs            # distinct problems, ranked
```
- The script uses the read-only service account `bug-log-reader@cafe-countryside-menu` (Cloud Datastore
  Viewer only). Never swap in the owner's own token, `firebase` CLI writes, or the Admin SDK. The helper
  refuses anything except `runQuery` and document GET.
- If it fails with "Could not get a read-only token": tell the owner the one-time setup
  (`.\scripts\setup-bug-log-reader.ps1`) is missing. It changes Google Cloud IAM, so **ask before running it**
  and explain what it does (script header). It can be undone with the commands in the script header.
- 0 logs → say so, and stop. (Quiet is good news.)
- `client-logs/` is git-ignored (admin emails, page paths, user agents). Never commit or publish it.
- Test mode without PROD: `node scripts/test/seed-logs.mjs 8080` then `.\scripts\fetch-bug-logs.ps1 -Emulator -Port 8080`
  and `node scripts/summarize-bug-logs.mjs emu` (needs the local Firestore emulator running).

## 3. Analyse

Work from most to least serious (ERROR > WARN) and most to least frequent. Remember the logging is
**bounded for customers** (rules: one log per source and slot per 30 min, ≤ 2,448 a day), so counts
are a *floor*, not exact totals; the first log of a burst is kept.

For each distinct problem:
1. **Read 1–3 full examples** from `client-logs/prod-latest.json` by log id: `message`, `errorCode`,
   `breadcrumbs` (what the user did just before), `stackTrace`, `build`, `userAgent`, `appUrl`, `createdAtIst`.
   Customer log ids look like `<source>~<slot>~<bucket>`; admin ids are random.
2. **Which code?** Look the `source` up in `references/sources.md` first (file + meaning + expected noise),
   then read only that function. Check `.wolf/anatomy.md` before opening files.
3. **Which build?** `build` is `<commit>[+wip]@<time>`. Compare with `git log`: the bug may already be fixed in
   a later commit that is not deployed. What is live: `deploy_backups/builds.log` lines marked **DEPLOYED**
   (a `built` line only means it was built) and `CHANGELOG.md`. If unsure, ask the owner.
4. **Minified stacks** (`main.dart.js:L:C`) cannot be decoded (no source maps are kept). Say so and use
   `source` + `breadcrumbs`; the catalogue is enough for most cases.
5. **Fix status (required for every problem)** – exactly ONE of:
   - ✅ **Fixed & live** – the fix commit is in the deployed build (`git merge-base --is-ancestor <fix> <buildCommit>`).
   - 🟡 **Fixed in code, not deployed** – commit + date, and "not deployed anywhere".
   - 🔁 **Fixed, but still happening** – the log's own `build` already contains the fix. Top priority.
   - 📋 **Planned, not built** – plan file + section (`plan/phase1a.md`, `plan/phase1.md` …).
   - ❌ **Not handled** – new, or known with no fix and no plan.
   - ➖ **Expected / no fix needed** (see "Usually means" in `references/sources.md`).
   Search `.wolf/buglog.json` (by source / message words), `plan/`, `CHANGELOG.md` and `git log --oneline -30`
   (or `git log -S"<code word>"`).
6. **Compare with the last check:** if an earlier `client-logs/prod-report-*.md` exists, read the newest:
   which problems are **new**, which **stopped**, which **continue**.
7. **Need the data behind it?** Read-only, only when it really helps (each read costs quota):
   `.\scripts\read-firestore-doc.ps1 -Path menu/current` (or `menuDraft/data`, `businesses/default`).
8. Decide: **real bug**, **expected/handled**, **network/device** (café Wi-Fi, old phone, ad blocker),
   or **logging noise** (should be WARN or deduped).

**Customers cannot place an order** (`Checkout.submit`, `OrderRequest.create`) is always the top priority,
whatever the count.

## 4. Report, then discuss

Show the report in chat (and save the same text to `client-logs/prod-report-<yyyyMMdd-HHmm>.md`):

```
## Bug logs — PROD, last 24 h (fetched <time> IST)
<N> logs → <M> distinct problems. <one-line verdict: e.g. "1 real bug, 2 expected, 1 noise">
Running build: <build> (= commit <x>, <date>). Newer code not on the live app: <commits / phases, or "none">.

### Fix status at a glance
- ✅ Fixed & live: …            - 🟡 Fixed in code, not deployed: … (commit)
- 🔁 Fixed but still happening: … (top priority)
- 📋 Planned, not built: …      - ❌ Not handled: …      - ➖ Expected: …
- Since last check (<date of previous report>): new #… · stopped: … · continuing #…

| # | Problem (plain words) | Type · source | Times | Devices / who | Fix status | Verdict |
|---|---|---|---|---|---|---|

### 1. <plain title>
**What the customer / admin saw:** …
**Example:** log `<id>` at <IST time>, <device>: "<message>". Before it: <breadcrumbs, short>.
**Why it happened:** … (`cafe_countryside_menu/lib/…dart:LINE`). Confidence: confirmed / likely / guess.
**Fix status:** ✅/🟡/🔁/📋/❌/➖ + proof (bug-NNN, plan §, commit, deployed where).
**Possible fixes:**
  A. … (+ / −)
  B. … (+ / −)
**My suggestion:** A, because …
**Question for you:** … (only if the choice is the owner's)
```
- Use "a customer on an iPhone" / "the owner", not emails, in the chat report.
- Don't pad: expected/noise problems get one line in the table, no section, unless the owner asks.
  ✅ / 🟡 problems with nothing to decide also get just the table line.
- Then **stop and wait**. Discuss as long as the owner wants. Do not edit any file until the owner
  approves specific items (e.g. "fix 1 and 3 with A").

## 5. Fix (after approval only)

For each approved item:
1. Follow `CLAUDE.md` / OpenWolf: `.wolf/cerebrum.md` Do-Not-Repeat, read `.wolf/buglog.json` for known fixes.
2. Every error must still reach Bug Logs (source + stack, no silent catch). A new customer-reachable `source`
   needs the allow-list in `firestore.rules` AND `kCustomerLogSources` updated together (a test checks they match),
   and a rules deploy before the app deploy.
3. Make the fix + a test that fails before / passes after. Run `cd cafe_countryside_menu; flutter test` and
   `flutter analyze` (the baseline is in the latest commit message / CHANGELOG).
4. Log each fix in `.wolf/buglog.json` (mention the clientLogs id), add a `.wolf/memory.md` line.
5. **Do not commit unless asked. Do not deploy unless asked. PROD: ask every single time**, with the steps
   (`firebase deploy --only firestore:rules` first if rules changed, then `--only hosting`; never a bare
   `firebase deploy`), and remind the owner that the fix only reaches customers after the deploy.
   After a deploy, append a `DEPLOYED` line to `deploy_backups/builds.log`.
6. Finish with: what was fixed, test results, what is still open, and how to check it locally (emulator).
