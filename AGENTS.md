# Nimbus Deploy — Agent Guide

This repository includes a **Senior SRE Pull Request Review Agent** for automated Level-1 PR validation before human review and merge.

## Trigger on every new PR

You have two options. Use **both** for best coverage: Cursor Automation for full AI review, GitHub Actions for deterministic checks in CI.

### Option A — Cursor Automation (recommended for full agent review)

This runs the full `@nimbus-sre-pr-review` agent automatically when a PR is opened.

1. Open **Cursor → Automations → New automation**
2. **Trigger:** GitHub → **Pull request opened**
3. **Repository:** `se-wdpr-infrastructure/nimbus_deploy`
4. **Tools:** enable **Comment on PRs**
5. **Instructions (prompt):**

   ```
   @nimbus-sre-pr-review

   Perform Level-1 SRE review for this pull request in se-wdpr-infrastructure/nimbus_deploy.

   Use the PR diff against the base branch. Follow the workflow in:
   - .cursor/skills/nimbus-sre-pr-review/SKILL.md
   - .cursor/skills/nimbus-sre-pr-review/reference.md

   Post the review as a PR comment using the exact output format in reference.md.
   Do not merge. Human SRE approval remains mandatory.
   ```

6. **Cloud agent:** enable if the repo is not checked out locally (recommended for team use)
7. Save and enable the automation

To draft this in the Automations editor from chat, say: *"Create a Cursor Automation to run @nimbus-sre-pr-review on every PR opened in nimbus_deploy"*

### Option B — GitHub Actions (automatic script validation)

The workflow `.github/workflows/nimbus-sre-pr-review.yml` runs on every PR open/update and posts Level-1 script output as a PR comment (JSON validation, secret pattern scan, prod path check).

Commit and push the workflow:

```bash
git add .github/workflows/nimbus-sre-pr-review.yml
git commit -m "Add automated Level-1 PR validation workflow"
git push
```

**Note:** On GitHub Enterprise, confirm Actions are enabled for the org/repo and that `actions/checkout` and `actions/github-script` are allowed.

### Option C — Cursor SDK in GitHub Actions (advanced)

For programmatic full agent runs from CI, use the [Cursor SDK](https://cursor.com/docs/sdk) with a `CURSOR_API_KEY` secret. This is optional; most teams use Option A + B.

---

## Quick start (manual)

In Cursor Agent chat, invoke the skill:

```
@nimbus-sre-pr-review Review PR #12345
```

Or paste a PR URL:

```
@nimbus-sre-pr-review https://github.disney.com/se-wdpr-infrastructure/nimbus_deploy/pull/12345
```

Or provide a branch name:

```
@nimbus-sre-pr-review Review branch fix/cast-portals-awsfirelens-log-driver
```

## What the agent does

1. Changed file analysis (grouped by category)
2. JSON syntax validation (`*.json`)
3. Secret and password scanning
4. Nimbus deployment configuration review
5. Environment alignment and production safety checks
6. Shell / YAML / workflow / Terraform review where applicable
7. Infrastructure risk classification
8. Scheduled merge preparation (only after **PASS**)

## What the agent does NOT do

- Merge PRs or bypass branch protection
- Approve changes on behalf of humans
- Deploy infrastructure
- Review any repository other than `se-wdpr-infrastructure/nimbus_deploy`

## Human approval

**Human SRE approval remains mandatory.** This agent performs Level-1 validation only.

## Repository layout

```
.cursor/skills/nimbus-sre-pr-review/
├── SKILL.md              # Agent instructions (primary)
├── reference.md          # Full output format and decision rules
└── scripts/
    └── validate-pr.sh    # Read-only validation helper
```

## Manual validation script

Run locally before opening a PR or to pre-check a branch:

```bash
# By PR number
.cursor/skills/nimbus-sre-pr-review/scripts/validate-pr.sh 126602

# By branch name (diff against origin/master)
.cursor/skills/nimbus-sre-pr-review/scripts/validate-pr.sh --branch fix/my-branch
```

## Scheduled merge (GitHub Actions — `workflow_dispatch`)

After Level-1 checks pass and **human SRE approves** the PR on GitHub, merge at the agreed change window by running the **Nimbus SRE Scheduled Merge** workflow manually (GitHub does not wait for a clock time — the SRE starts the workflow when the window opens).

Workflow file: `.github/workflows/nimbus-sre-scheduled-merge.yml`

### One-time activation on github.disney.com

1. **Merge both workflow files** to the default branch (`main` or `master`):
   - `.github/workflows/nimbus-sre-pr-review.yml`
   - `.github/workflows/nimbus-sre-scheduled-merge.yml`

2. **Repo → Settings → Actions → General**
   - Enable Actions (if not already).
   - Under **Workflow permissions**, choose **Read and write permissions** (needed for `gh pr merge` and PR comments).

3. **Create deployment environment** (second approval gate):
   - **Settings → Environments → New environment**
   - Name: `nimbus-sre-merge`
   - Enable **Required reviewers** and add your SRE team (or yourself for testing).
   - Optional: restrict to `main` / `master` only.

4. **Branch protection** on the default branch (recommended):
   - Require pull request reviews before merging.
   - Require status checks (include **Nimbus SRE PR Review (Level-1)** when ready).
   - Do not allow bypassing protections for normal users.

5. **Who can run workflows**
   - **Settings → Actions → General → Fork pull request workflows** — follow org policy.
   - Ensure SREs have permission to run **workflow_dispatch** (default: write access to the repo).

6. **Self-hosted runners** (if `ubuntu-latest` is unavailable):
   - Change `runs-on: ubuntu-latest` to your Disney runner label in both workflow files.

### How to merge an approved PR (each change)

1. Confirm on the PR:
   - Human review **Approved**
   - Required checks **green** (including Level-1 review)
   - No merge conflicts

2. At the scheduled change window, open:
   `https://github.disney.com/<org>/<repo>/actions/workflows/nimbus-sre-scheduled-merge.yml`

3. Click **Run workflow**

4. Fill inputs:

   | Input | Example |
   |-------|---------|
   | `pr_number` | `126602` |
   | `expected_head_sha` | Copy from PR **Commits** (optional but recommended) |
   | `change_reference` | `CTASK12781687` |
   | `confirm_human_approval` | `true` |

5. Approve the **nimbus-sre-merge** environment if prompted.

6. Outcome:
   - **Success** — PR merged; audit comment on the PR.
   - **Failure** — no merge; blocked comment with link to logs.

### What the merge workflow verifies

- PR is open
- No `CHANGES_REQUESTED` / `REVIEW_REQUIRED`
- No failing required checks (best effort via API)
- No merge conflicts
- Changed `*.json` files still parse
- Optional head SHA unchanged since review
- Branch protection still enforced by GitHub (`gh pr merge` without admin bypass)

### Disable the environment gate (testing only)

In `nimbus-sre-scheduled-merge.yml`, remove the line `environment: nimbus-sre-merge` and commit. Not recommended for production.

## Scope

Repository: **se-wdpr-infrastructure/nimbus_deploy** only.

Common file types reviewed:

- `*.json`, `*.json.erb`, `*.erb`
- `*.yaml`, `*.yml`
- `*.sh`
- `*.tf`, `*.tfvars`
- GitHub workflow files
- Nimbus deployment and task definition configuration
