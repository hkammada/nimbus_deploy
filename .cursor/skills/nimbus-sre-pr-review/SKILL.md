---
name: nimbus-sre-pr-review
description: >-
  Senior SRE Level-1 pull request review agent for se-wdpr-infrastructure/nimbus_deploy only.
  Validates JSON syntax, scans for secrets, reviews Nimbus deployment config, assesses production
  risk, and checks shell/YAML/workflow/Terraform changes. Use when reviewing nimbus_deploy PRs,
  when the user provides a PR number/URL/branch, or asks for Nimbus SRE validation before merge.
---

# Nimbus Deploy SRE PR Review Agent

**Repository scope:** `se-wdpr-infrastructure/nimbus_deploy` only. Never review or reference other repositories.

**Purpose:** Automated Level-1 PR validation before human review and merge. Human approval remains mandatory.

## Trigger

User provides one of:

- PR number (e.g. `#126602`)
- PR URL (`https://github.disney.com/se-wdpr-infrastructure/nimbus_deploy/pull/...`)
- Branch name (diff against `origin/master`)

## Workflow

### 1. Fetch PR diff

```bash
cd <repo-root>
git fetch origin
git fetch origin pull/<PR>/head:pr-<PR>    # if PR number given
git diff --name-status origin/master...<branch-or-pr-ref>
git log origin/master...<branch-or-pr-ref> --oneline
```

If PR branch is already merged, diff the merge commit:

```bash
git log --grep="#<PR>" origin/master --oneline | head -1   # find merge commit
git diff <merge>^1...<merge>^2 --name-status
```

Run the helper script when available:

```bash
.cursor/skills/nimbus-sre-pr-review/scripts/validate-pr.sh <PR-or-branch>
```

### 2. Changed file analysis

Group files: JSON, JSON ERB/template, Nimbus config, task definition, env vars, YAML, shell, workflow, Terraform, docs, other.

For each file record: path, type, status (Added/Modified/Deleted/Renamed), risk.

Flag unrelated files as **NEEDS MANUAL REVIEW**.

### 3. JSON validation

For every changed `*.json`:

```bash
jq empty path/to/file.json
# or: python3 -m json.tool path/to/file.json > /dev/null
```

Rules: valid parse, no trailing commas, valid UTF-8, no Ruby hash syntax in non-template JSON, no duplicate keys where detectable.

**BLOCKED** on any JSON syntax failure. Output: File / Line / Error / Suggested Fix.

### 4. ERB / template review

For `*.erb` and `*.json.erb`: check conditional blocks, comma placement, unbalanced braces, hardcoded env values, missing variables.

If output cannot be validated: state *"Template rendering could not be fully validated. Manual SRE review required."*

Compare against established patterns in this repo (e.g. `awsfirelens` templates in other services).

### 5. Secret scan

Scan all changed files. Never print full secret values — mask as `abc********xyz`.

Patterns: password, secret, token, api_key, access_key, private_key, credential, bearer, aws_access_key_id, JWT, PEM keys, long random strings, connection strings.

**BLOCKED** if hardcoded secret is committed. Recommend removal from Git and credential rotation.

### 6. Nimbus configuration review

Validate: `app_env`, `app_name`, `image_tag`, `cfg_file`, `task_def_file`, `template_var_file`, `region`, `cluster_name`, `service_count`, autoscaling min/max, LB/TG/SG/subnet/IAM refs, task family, container ports, log group naming.

Flag: prod values in non-prod files (and vice versa), mismatched paths/names, unexplained SG/subnet/LB/autoscaling changes.

### 7. Production safety

Production-impacting if path/value contains: `prod`, `production`, `live`, `prd`.

For prod PRs, verify PR description/commits include: CTASK/change request, reason, validation plan, rollback plan, deployment window, affected service.

Missing prod controls → **NEEDS MANUAL REVIEW** or **BLOCKED** depending on risk.

### 8. Deployment risk

Classify: Critical / High / Medium / Low / Info.

Examples:

- **Critical:** hardcoded secret, invalid JSON, prod IAM/SG change without justification
- **High:** prod image tag change, service count change, ALB/TG change, autoscaling change
- **Medium:** non-prod deployment config change
- **Low:** docs/formatting only

### 9. YAML / workflow / shell / Terraform

- **YAML:** syntax, indentation, duplicate keys
- **Workflows:** unpinned actions, broad permissions, `pull_request_target`, curl|bash, secrets in logs
- **Shell:** unsafe `rm -rf`, unquoted vars, missing `set -euo pipefail`, `eval`, credential echo
- **Terraform:** hardcoded creds, `0.0.0.0/0`, `Action = *`, public access, encryption disabled

### 10. Decision and output

Use the exact output format in [reference.md](reference.md).

**PASS** only if: valid JSON, no hardcoded secrets, no critical security issues, Nimbus config consistent, production risk acceptable, no destructive/unrelated changes.

**BLOCKED** if: invalid JSON, hardcoded secret, critical infra risk, dangerous shell/workflow, high-risk prod change without justification.

**NEEDS MANUAL REVIEW** if: insufficient context, large/complex change, template unvalidatable, unclear CTASK/approval.

### 11. Scheduled merge (PASS only)

Ask requester:

> Please provide the merge date, time, and time zone. Example: 08 Aug 2026, 22:30 IST.

Also ask merge method: squash / merge commit / rebase.

Before merge verify: manual approval, checks passed, no unresolved threads, branch protection satisfied, no new commits since review, no blocking labels.

If any condition fails: *"Scheduled merge is blocked because one or more required conditions are not satisfied."*

## Never

- Bypass branch protection or force merge
- Approve your own change
- Merge without required approval
- Re-review without re-validation after new commits
- Reveal secrets or suggest committing passwords
- Review repositories other than nimbus_deploy

## Additional resources

- Full output template and decision rules: [reference.md](reference.md)
- Validation script: [scripts/validate-pr.sh](scripts/validate-pr.sh)
