#!/usr/bin/env bash
# Detect rhdh-plugins workspaces affected by work on the current branch.
#
# Scope: all commits on the current branch since it was created (reflog),
# plus staged/unstaged/untracked working-tree changes.
# Does not compare against main, upstream, or any other branch.
#
# Outputs one workspace name per line. Root-level changes are ignored.
# Prints scope metadata (base ref, branch commits) to stderr.
#
# Usage (from rhdh-plugins repo root):
#   bash <skill-root>/scripts/detect-workspaces.sh
#   <skill-root> is .cursor/skills/validate-changes (project) or
#   ~/.cursor/skills/validate-changes or ~/.cursor/skills/rhdh-plugins-skills/validate-changes (global).
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

CURRENT_BRANCH="$(git branch --show-current 2>/dev/null || true)"

resolve_branch_creation_base() {
  local branch="${1:-$CURRENT_BRANCH}"
  [[ -z "$branch" ]] && return 1

  local creation_commit
  creation_commit="$(
    git reflog show --format='%H %gs' "$branch" 2>/dev/null \
      | grep -E 'branch: Created from' \
      | tail -1 \
      | awk '{print $1}'
  )"

  if [[ -n "$creation_commit" ]] && git rev-parse --verify "$creation_commit" >/dev/null 2>&1; then
    echo "$creation_commit"
    return 0
  fi

  return 1
}

SCOPE_REASON=""
RESOLVED_REF=""

if base="$(resolve_branch_creation_base)"; then
  RESOLVED_REF="$base"
  SCOPE_REASON="all commits since branch was created"
else
  SCOPE_REASON="working-tree changes only (branch creation point not found)"
fi

if [[ -n "$RESOLVED_REF" ]]; then
  short_ref="$(git rev-parse --short "$RESOLVED_REF")"
  subject="$(git log -1 --format='%s' "$RESOLVED_REF" 2>/dev/null || true)"
  echo "scope: ${SCOPE_REASON}" >&2
  echo "base: ${short_ref} ${subject}" >&2

  commit_count="$(git rev-list --count "${RESOLVED_REF}..HEAD" 2>/dev/null || echo 0)"
  echo "branch commits (${commit_count}):" >&2
  if [[ "$commit_count" -gt 0 ]]; then
    git log --oneline "${RESOLVED_REF}..HEAD" >&2
  else
    echo "  (none — only working-tree changes may apply)" >&2
  fi
else
  echo "scope: ${SCOPE_REASON}" >&2
fi

collect_changed_files() {
  if [[ -n "$RESOLVED_REF" ]] && git rev-parse --verify "$RESOLVED_REF" >/dev/null 2>&1; then
    git diff --name-only "${RESOLVED_REF}...HEAD" 2>/dev/null || true
  fi

  git diff --cached --name-only 2>/dev/null || true
  git diff --name-only 2>/dev/null || true

  git status --porcelain | while IFS= read -r line; do
    local path="${line:3}"
    case "$path" in
      *" -> "*) path="${path#* -> }" ;;
    esac
    printf '%s\n' "$path"
  done
}

workspaces_tmp="$(mktemp)"

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  if [[ "$file" == workspaces/*/* ]]; then
    ws="${file#workspaces/}"
    ws="${ws%%/*}"
    if [[ -f "workspaces/${ws}/package.json" ]]; then
      printf '%s\n' "$ws" >> "$workspaces_tmp"
    fi
  fi
done < <(collect_changed_files | sort -u)

sort -u "$workspaces_tmp"
rm -f "$workspaces_tmp"
