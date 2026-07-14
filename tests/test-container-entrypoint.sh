#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../bin/container-entrypoint
source "$ROOT_DIR/bin/container-entrypoint"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
parent="$tmp/workspaces"
checkout="$parent/arrusted-development"
fake_git="$tmp/git"
mkdir -p "$checkout"

cat > "$fake_git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${FAIL_CLONE:-}" == 1 && "$1" == clone ]]; then
  mkdir -p "$3/partial"
  exit 42
fi
if [[ "$1" == clone ]]; then
  mkdir -p "$3/.git" "$3/docs"
  touch "$3/AGENTS.md" "$3/WORKFLOW.md" "$3/docs/README.md"
  exit 0
fi
if [[ "$1" == -C && "$3" == remote && "$4" == get-url ]]; then
  printf '%s\n' "${ARRUSTED_REPOSITORY_URL:-https://github.com/withAutograph/arrusted-development.git}"
  exit 0
fi
exit 99
SH
chmod +x "$fake_git"

ARRUSTED_CHECKOUT="$checkout"
ARRUSTED_WORKSPACE_PARENT="$parent"
GIT_BIN="$fake_git"
GITHUB_TOKEN=test-token
export ARRUSTED_CHECKOUT ARRUSTED_WORKSPACE_PARENT GIT_BIN GITHUB_TOKEN
workspace_parent="$ARRUSTED_WORKSPACE_PARENT"
checkout="$ARRUSTED_CHECKOUT"
git_bin="$GIT_BIN"

bootstrap_checkout
test -f "$checkout/WORKFLOW.md"
verify_checkout_contract

rm -rf "$checkout"
mkdir -p "$checkout"
rc=0
FAIL_CLONE=1 bootstrap_checkout >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 42 ]]
[[ -z "$(find "$checkout" -mindepth 1 -maxdepth 1 -print -quit)" ]]
[[ -z "$(find "$parent" -mindepth 1 -maxdepth 1 -name '.arrusted-bootstrap.*' -print -quit)" ]]

touch "$checkout/sentinel"
if bootstrap_checkout >/dev/null 2>&1; then
  echo "bootstrap accepted a non-empty checkout" >&2
  exit 1
fi
test -f "$checkout/sentinel"

grep -q '^[[:space:]]*gh \\' "$ROOT_DIR/Dockerfile"
grep -q 'gh --version' "$ROOT_DIR/Dockerfile"
grep -q '"$gh_bin" auth status --hostname github.com' "$ROOT_DIR/bin/container-entrypoint"
grep -q '"$git_bin" ls-remote --exit-code' "$ROOT_DIR/bin/container-entrypoint"

echo "container entrypoint tests passed"
