#!/usr/bin/env bash
# Tests for scripts/task-worktree: one worktree and branch per plan task, with
# deterministic naming, reuse on repeat calls, and refusal on inconsistent state.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TW="$REPO_ROOT/skills/subagent-driven-development/scripts/task-worktree"

FAILURES=0
TEST_ROOT=""

pass() { echo "  [PASS] $1"; }
fail() {
    echo "  [FAIL] $1"
    FAILURES=$((FAILURES + 1))
}

cleanup() {
    if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
        rm -rf "$TEST_ROOT"
    fi
}

GIT_ID=(-c user.email=t@example.com -c user.name=t -c commit.gpgsign=false)

expect_exit() {
    local want=$1 desc=$2
    shift 2
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if [[ "$rc" -eq "$want" ]]; then
        pass "$desc"
    else
        fail "$desc"
        echo "    exit: $rc (wanted $want)"
    fi
}

main() {
    echo "=== Test: task-worktree ==="

    TEST_ROOT="$(mktemp -d)"
    trap cleanup EXIT

    git init -q -b main "$TEST_ROOT/repo"
    local repo
    repo="$(cd "$TEST_ROOT/repo" && git rev-parse --show-toplevel)"
    cat > "$repo/plan-a.md" <<'PLAN'
# Plan A

### Task 1: First thing

Do the first thing.
PLAN
    ( cd "$repo" && git add plan-a.md && git "${GIT_ID[@]}" commit -qm c1 )
    local c1
    c1="$(cd "$repo" && git rev-parse HEAD)"

    # --- argument validation ---
    expect_exit 2 "no arguments errors with exit 2" bash -c "cd '$repo' && '$TW'"
    expect_exit 2 "missing plan file errors with exit 2" bash -c "cd '$repo' && '$TW' nope.md 1"
    expect_exit 2 "non-integer task number errors with exit 2" bash -c "cd '$repo' && '$TW' plan-a.md one"
    expect_exit 2 "unknown BASE errors with exit 2" bash -c "cd '$repo' && '$TW' plan-a.md 1 no-such-ref"

    # --- plan basename must be usable in a branch name ---
    cp "$repo/plan-a.md" "$repo/a..b.md"
    expect_exit 2 "plan basename unusable in a branch name errors with exit 2" \
        bash -c "cd '$repo' && '$TW' 'a..b.md' 1"
    if [[ ! -e "$repo/.worktrees/a..b" ]]; then
        pass "creates nothing when refusing on branch-name check"
    else
        fail "creates nothing when refusing on branch-name check"
    fi

    # --- .worktrees must be ignored ---
    expect_exit 3 "refuses when .worktrees is not git-ignored" bash -c "cd '$repo' && '$TW' plan-a.md 1"
    if [[ ! -e "$repo/.worktrees" ]]; then
        pass "creates nothing when refusing on ignore check"
    else
        fail "creates nothing when refusing on ignore check"
    fi

    ( cd "$repo" && printf '.worktrees/\n' > .gitignore && git add .gitignore && git "${GIT_ID[@]}" commit -qm ignore )
    local c2
    c2="$(cd "$repo" && git rev-parse HEAD)"

    # --- create ---
    local out
    out="$(cd "$repo" && "$TW" plan-a.md 1)"
    if [[ "$out" == "$repo/.worktrees/plan-a/task-1" ]]; then
        pass "prints <main-root>/.worktrees/<plan>/task-<N>"
    else
        fail "prints <main-root>/.worktrees/<plan>/task-<N>"
        echo "    got: $out"
    fi
    if [[ "$(cd "$out" && git rev-parse --abbrev-ref HEAD)" == "sdd/plan-a/task-1" ]]; then
        pass "worktree is on branch sdd/<plan>/task-<N>"
    else
        fail "worktree is on branch sdd/<plan>/task-<N>"
    fi
    if [[ "$(cd "$out" && git rev-parse HEAD)" == "$c2" ]]; then
        pass "default BASE is the caller's HEAD"
    else
        fail "default BASE is the caller's HEAD"
    fi

    # --- reuse ---
    local again
    again="$(cd "$repo" && "$TW" plan-a.md 1)"
    local count
    count="$(cd "$repo" && git worktree list --porcelain | grep -c '^worktree ')"
    if [[ "$again" == "$out" && "$count" -eq 2 ]]; then
        pass "second call reuses the worktree and adds nothing"
    else
        fail "second call reuses the worktree and adds nothing"
        echo "    got: $again, worktrees: $count"
    fi

    # --- explicit BASE ---
    local t2
    t2="$(cd "$repo" && "$TW" plan-a.md 2 "$c1")"
    if [[ "$(cd "$t2" && git rev-parse HEAD)" == "$c1" ]]; then
        pass "explicit BASE is honoured"
    else
        fail "explicit BASE is honoured"
    fi

    # --- inconsistent states ---
    mkdir -p "$repo/.worktrees/plan-a/task-3"
    expect_exit 4 "unregistered directory at the target path errors with exit 4" \
        bash -c "cd '$repo' && '$TW' plan-a.md 3"

    ( cd "$repo" && git worktree add -q "$TEST_ROOT/elsewhere" -b sdd/plan-a/task-4 )
    expect_exit 4 "branch checked out at another path errors with exit 4" \
        bash -c "cd '$repo' && '$TW' plan-a.md 4"
    if [[ ! -e "$repo/.worktrees/plan-a/task-4" ]]; then
        pass "creates nothing when refusing on branch-checked-out-elsewhere check"
    else
        fail "creates nothing when refusing on branch-checked-out-elsewhere check"
    fi

    ( cd "$repo" && git worktree add -q "$repo/.worktrees/plan-a/task-5" -b unrelated )
    expect_exit 4 "target path on the wrong branch errors with exit 4" \
        bash -c "cd '$repo' && '$TW' plan-a.md 5"

    # --- recreate after the directory is removed, keeping the branch's commits ---
    ( cd "$out" && printf 'w\n' > work && git add work && git "${GIT_ID[@]}" commit -qm work )
    local work_sha
    work_sha="$(cd "$out" && git rev-parse HEAD)"
    rm -rf "$out"
    local back
    back="$(cd "$repo" && "$TW" plan-a.md 1)"
    if [[ "$back" == "$out" && -d "$back" && "$(cd "$back" && git rev-parse HEAD)" == "$work_sha" ]]; then
        pass "re-adds a removed worktree on its existing branch, commits intact"
    else
        fail "re-adds a removed worktree on its existing branch, commits intact"
        echo "    got: $back"
    fi

    # --- called from a linked worktree: path under the main root, BASE from the caller ---
    local plan_wt="$TEST_ROOT/plan-wt"
    ( cd "$repo" && git worktree add -q "$plan_wt" -b feature )
    ( cd "$plan_wt" && printf 'f\n' > f && git add f && git "${GIT_ID[@]}" commit -qm feature )
    local feature_sha
    feature_sha="$(cd "$plan_wt" && git rev-parse HEAD)"
    local t6
    t6="$(cd "$plan_wt" && "$TW" plan-a.md 6)"
    if [[ "$t6" == "$repo/.worktrees/plan-a/task-6" && "$(cd "$t6" && git rev-parse HEAD)" == "$feature_sha" ]]; then
        pass "from a linked worktree: path under main root, BASE is the linked worktree's HEAD"
    else
        fail "from a linked worktree: path under main root, BASE is the linked worktree's HEAD"
        echo "    got: $t6"
    fi

    echo ""
    if [[ "$FAILURES" -ne 0 ]]; then
        echo "FAILED: $FAILURES assertion(s)."
        exit 1
    fi
    echo "PASS"
}

main "$@"
