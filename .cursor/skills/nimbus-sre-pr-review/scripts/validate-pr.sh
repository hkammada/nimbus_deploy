#!/usr/bin/env bash
# Nimbus Deploy — read-only PR validation helper
# Usage:
#   validate-pr.sh <PR_NUMBER>
#   validate-pr.sh --branch <BRANCH_NAME>
#   validate-pr.sh --merge <PR_NUMBER>   # diff merge commit (for merged PRs)
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: Not inside a git repository." >&2
  exit 1
}

cd "$REPO_ROOT"

BASE_REF="${BASE_REF:-origin/master}"
MODE="pr"
TARGET=""

usage() {
  cat <<EOF
Usage:
  $(basename "$0") <PR_NUMBER>
  $(basename "$0") --branch <BRANCH_NAME>
  $(basename "$0") --merge <PR_NUMBER>

Environment:
  BASE_REF   Base branch for diff (default: origin/master)

Examples:
  $(basename "$0") 126602
  $(basename "$0") --branch fix/cast-portals-awsfirelens-log-driver
  $(basename "$0") --merge 126602
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

case "${1:-}" in
  --branch)
    MODE="branch"
    TARGET="${2:-}"
    ;;
  --merge)
    MODE="merge"
    TARGET="${2:-}"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    MODE="pr"
    TARGET="$1"
    ;;
esac

if [[ -z "$TARGET" ]]; then
  echo "ERROR: Missing PR number or branch name." >&2
  usage
  exit 1
fi

echo "==> Fetching origin..."
git fetch origin --quiet 2>/dev/null || git fetch origin

DIFF_RANGE=""
PR_REF=""

resolve_pr_ref() {
  local pr="$1"
  local ref="pr-${pr}"
  if git fetch origin "pull/${pr}/head:${ref}" 2>/dev/null; then
    PR_REF="$ref"
    DIFF_RANGE="${BASE_REF}...${ref}"
  else
    echo "ERROR: Could not fetch pull/${pr}/head" >&2
    exit 1
  fi
}

resolve_merge_ref() {
  local pr="$1"
  local merge_commit
  merge_commit="$(git log "${BASE_REF}" --grep="#${pr}" --merges --oneline | head -1 | awk '{print $1}')"
  if [[ -z "$merge_commit" ]]; then
    echo "ERROR: No merge commit found for PR #${pr}" >&2
    exit 1
  fi
  PR_REF="$merge_commit"
  DIFF_RANGE="${merge_commit}^1...${merge_commit}^2"
  echo "==> Found merge commit: ${merge_commit}"
}

case "$MODE" in
  pr)
    resolve_pr_ref "$TARGET"
    ;;
  merge)
    resolve_merge_ref "$TARGET"
    ;;
  branch)
    PR_REF="$TARGET"
    DIFF_RANGE="${BASE_REF}...${TARGET}"
    git fetch origin "${TARGET}:${TARGET}" 2>/dev/null || true
    ;;
esac

# Detect if PR branch is fully merged (ancestor of base)
if [[ "$MODE" == "pr" ]] && git merge-base --is-ancestor "$PR_REF" "$BASE_REF" 2>/dev/null; then
  echo "WARN: PR ref is already contained in ${BASE_REF}. Trying merge-commit diff..."
  if resolve_merge_ref "$TARGET" 2>/dev/null; then
    :
  else
    echo "WARN: Could not find merge commit; diff may be empty."
  fi
fi

echo ""
echo "==> Repository: se-wdpr-infrastructure/nimbus_deploy"
echo "==> Diff range: ${DIFF_RANGE}"
echo ""

CHANGED_FILES="$(git diff --name-status "$DIFF_RANGE" 2>/dev/null || true)"
if [[ -z "$CHANGED_FILES" ]]; then
  echo "No changed files found."
  exit 0
fi

FILE_COUNT="$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')"
echo "==> Changed files (${FILE_COUNT}):"
echo "$CHANGED_FILES"
echo ""

# Categorize
echo "==> File categories:"
echo "$CHANGED_FILES" | awk '{print $2}' | while read -r f; do
  case "$f" in
    *.json) echo "  JSON: $f" ;;
    *.json.erb|*.erb) echo "  ERB/TEMPLATE: $f" ;;
    *nimbus_cfg.json|*nimbus_config.yaml) echo "  NIMBUS CONFIG: $f" ;;
    *taskdef*) echo "  TASK DEFINITION: $f" ;;
    *.yaml|*.yml) echo "  YAML: $f" ;;
    *.sh) echo "  SHELL: $f" ;;
    .github/*) echo "  WORKFLOW: $f" ;;
    *.tf|*.tfvars) echo "  TERRAFORM: $f" ;;
    *.md) echo "  DOCS: $f" ;;
    *) echo "  OTHER: $f" ;;
  esac
done
echo ""

# JSON validation
echo "==> JSON validation:"
JSON_FAIL=0
echo "$CHANGED_FILES" | awk '{print $2}' | while read -r f; do
  [[ "$f" == *.json ]] || continue
  if jq empty "$f" 2>/dev/null; then
    echo "  PASS: $f"
  elif python3 -m json.tool "$f" > /dev/null 2>&1; then
    echo "  PASS: $f"
  else
    echo "  FAIL: $f"
    JSON_FAIL=1
  fi
done

# If jq not available, try python for each json file
if ! command -v jq >/dev/null 2>&1; then
  :
fi
echo ""

# Secret scan on diff
echo "==> Secret scan (changed diff only):"
SECRET_PATTERN='(password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|secret[_-]?key|client[_-]?secret|private[_-]?key|credential|bearer|aws_access_key|aws_secret_access_key|BEGIN RSA|BEGIN PRIVATE)'

if git diff "$DIFF_RANGE" | grep -Ein "$SECRET_PATTERN" | grep -Ev 'splunk_token.*<%=' | head -20; then
  echo "  WARN: Potential secret patterns found (review manually — template placeholders may be false positives)."
else
  echo "  PASS: No obvious secret patterns in diff."
fi
echo ""

# Production impact
echo "==> Production impact check:"
PROD_FILES="$(echo "$CHANGED_FILES" | awk '{print $2}' | grep -Ei '/prod/|production|/live/|/prd/' || true)"
if [[ -n "$PROD_FILES" ]]; then
  echo "  YES — production paths changed:"
  echo "$PROD_FILES" | sed 's/^/    /'
else
  echo "  NO direct prod path changes detected (template-only changes may still affect prod indirectly)."
fi
echo ""

echo "==> Done. Run @nimbus-sre-pr-review in Cursor Agent for full SRE review."
