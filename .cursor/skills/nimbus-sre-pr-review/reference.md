# Nimbus SRE PR Review — Reference

## Final review output format

Return reviews in this exact structure:

```
PR Review Result:
PASS / BLOCKED / NEEDS MANUAL REVIEW

Repository:
se-wdpr-infrastructure/nimbus_deploy

PR Summary:
- Briefly summarise what changed.
- Mention number of changed files.
- Mention changed file categories.

Changed Files:
- File:
  Type:
  Status:
  Risk:

JSON Validation:
- PASS / FAIL / NOT APPLICABLE
- Details:

Secret Scan:
- PASS / FAIL
- Details:
- Do not expose full secret values.

Nimbus Configuration Review:
- PASS / FAIL / NEEDS MANUAL REVIEW
- Details:

Production Risk Review:
- Production Impact:
  YES / NO / UNKNOWN
- Risk Level:
  Critical / High / Medium / Low / Info
- Details:

Infrastructure/Security Findings:
1. Finding:
   Severity:
   File:
   Line:
   Details:
   Recommendation:

YAML/Workflow Review:
- PASS / FAIL / NOT APPLICABLE
- Details:

Shell Script Review:
- PASS / FAIL / NOT APPLICABLE
- Details:

Terraform/IaC Review:
- PASS / FAIL / NOT APPLICABLE
- Details:

Required Fixes:
- List fixes required before approval or merge.

Manual Review Notes:
- List anything the human SRE reviewer must verify.

Final Decision:
- Explain why the PR is PASS, BLOCKED, or NEEDS MANUAL REVIEW.
```

## Decision rules

### PASS

- All changed JSON files are valid
- No hardcoded secrets found
- No high-risk security issue found
- Nimbus configuration appears consistent
- Production risk is understood and acceptable
- No destructive or unrelated change present
- Required checks are passing or expected to pass
- Human review is still required before merge

### BLOCKED

- JSON syntax is invalid
- Hardcoded password or secret is found
- Production config has high-risk change without justification
- Infrastructure security risk is critical
- Workflow exposes secrets
- Shell script contains dangerous destructive logic
- Required deployment information missing for high-risk prod change

### NEEDS MANUAL REVIEW

- Context is insufficient
- Change is large or complex
- Production impact cannot be determined
- Template output cannot be fully validated
- Approval or CTASK information is unclear
- Agent cannot confidently determine safety

## JSON validation failure format

```
File:
Line:
Error:
Suggested Fix:
```

## Secret masking

Never print full credentials. Mask suspicious values: `abc********xyz`

If genuinely committed, mark **BLOCKED**. Recommend:

1. Remove value from Git
2. Rotate the credential
3. Store secrets in approved vault/secret management only

## Secret scan patterns

Keys or values containing:

- password, passwd, pwd, secret, token
- api_key, apikey, access_key, secret_key, client_secret
- private_key, credential, auth, bearer, basic, key, cert, certificate
- aws_access_key_id, aws_secret_access_key, session_token

Also detect: AWS access keys, GitHub tokens, JWT tokens, PEM/RSA private keys, connection strings, database credentials, keystore/truststore passwords.

## Nimbus configuration checks

| Field | Check |
|-------|-------|
| app_env | Matches environment folder |
| app_name | Consistent with service path |
| image_tag | Appropriate for env |
| cfg_file / task_def_file / template_var_file | Paths exist and resolve |
| region | Matches folder structure |
| cluster_name | Consistent naming |
| service_count | Justified if changed |
| autoscaling min/max | Justified if changed |
| LB / TG / SG / subnet | Justified if changed |
| IAM role / task role ARN | Consistent with env |
| container/host port | Valid and consistent |
| log group | Naming consistent |

## Production-impacting indicators

Path or value contains: `prod`, `production`, `live`, `prd`

Required in PR description or commits for prod changes:

- CTASK or change request reference
- Reason for change
- Implementation and validation plan
- Backout/rollback plan
- Deployment window
- Affected service or CI

## Deployment risk indicators

| Change | Typical risk |
|--------|-------------|
| ECS service restart / task def replacement | High |
| Image version change (prod) | High |
| Autoscaling min/max change | High |
| ALB / target group change | High |
| Security group / subnet change | Critical–High |
| IAM permission change | Critical–High |
| Env var change | Medium–High |
| Service count reduction | High |
| Non-prod config only | Medium |
| Docs / formatting | Low |

## Infrastructure security — critical flags

- AdministratorAccess
- Action = *
- Resource = *
- 0.0.0.0/0 ingress
- Public access enabled
- Encryption disabled

## Validation commands (read-only)

```bash
# Changed files
git diff --name-only origin/master...HEAD
git diff --name-status origin/master...HEAD

# JSON
jq empty path/to/file.json
python3 -m json.tool path/to/file.json > /dev/null

# Secret scan (changed files only)
git diff origin/master...HEAD | rg -n -i "(password|secret|token|api[_-]?key|private[_-]?key|credential|aws_access_key)"

# YAML (if yamllint available)
yamllint path/to/file.yml

# Shell (if shellcheck available)
shellcheck path/to/file.sh

# PR helper
.cursor/skills/nimbus-sre-pr-review/scripts/validate-pr.sh <PR-or-branch>
```

## Scheduled merge checklist

Only after **PASS**. Verify before merge:

- [ ] Required manual approval exists
- [ ] Required status checks passed
- [ ] No unresolved conversations
- [ ] Branch protection satisfied
- [ ] No new commits after review
- [ ] No blocking labels
- [ ] JSON validation still passes
- [ ] Secret scan still passes
- [ ] Production risk decision unchanged

If any fail: *"Scheduled merge is blocked because one or more required conditions are not satisfied."*

## Common file categories in nimbus_deploy

- `nimbus_cfg.json` — Nimbus service configuration
- `taskdef_vars.json` — Task definition template variables
- `taskdef.json` / `taskdef.json.erb` — ECS task definitions
- `nimbus_config.yaml` — Lambda/other Nimbus YAML config
- `deploy-*.sh`, `additional_env.sh` — Deployment scripts
- `.github/workflows/*` — CI/CD workflows

## ERB template patterns in this repo

When reviewing `awsfirelens` templates, compare against established services such as:

- `wdw-lodging-corecashless-webapi/taskdef.json.erb`

Common elements:

- Conditional `logDriver == "awsfirelens"`
- Splunk options with `<%= splunk_host %>` and `<%= splunk_token %>` placeholders
- `log_router` Fluent Bit sidecar container
- Default fallback to `awslogs` with `mode: non-blocking`

Template variables must not hardcode secrets — values belong in `taskdef_vars.json` or approved secret stores.
