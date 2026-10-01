#!/bin/bash
# Existing project files can retain the retired store setting, including empty values.
set -euo pipefail
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/lib/assert.sh"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
assert_tmpdir PROJECT
PROJECT="$(cd -- "$PROJECT" && pwd -P)"
git -C "$PROJECT" init -q -b main
git -C "$PROJECT" config gc.auto 0
git -C "$PROJECT" config maintenance.auto false
for value in '' 'obsolete-directory'; do
    printf '[env]\nLINEAR_CACHE_ROOT = "%s"\n' "$value" >"$PROJECT/kendex.settings.toml"
    out=$(cd -- "$PROJECT" && env -i PATH="$PATH" HOME="$PROJECT" bash -c 'source "$1"' bash "$SKILL_DIR/scripts/lib/common.sh" 2>"$PROJECT/error") && rc=0 || rc=$?
    assert_ne 'retired setting refuses' "$rc" 0
    assert_eq 'retired setting has no stdout' "$out" ''
    assert_file_contains 'retired setting identifies key' "$PROJECT/error" 'linear-setting: retired=LINEAR_CACHE_ROOT'
done
