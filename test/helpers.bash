# shared bats helpers
REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
REVELIO="$REPO_ROOT/revelio"

# build an empty fixture root and point REVELIO_ROOT at it
make_root() {
  ROOT="$(mktemp -d)"
  export REVELIO_ROOT="$ROOT"
  mkdir -p "$ROOT/etc/ssh" "$ROOT/root/.ssh" "$ROOT/home" "$ROOT/etc/cron.d" \
           "$ROOT/etc/pam.d" "$ROOT/etc/profile.d"
}

teardown() { [ -n "${ROOT:-}" ] && rm -rf "$ROOT" || true; }

# source the tool WITHOUT running main (guard sees BASH_SOURCE != $0)
src() { # shellcheck disable=SC1090
  source "$REVELIO"; }

# reset finding state between calls
reset_state() { _ITEMS=(); _N_ATTENTION=0; _N_NORMAL=0; _BLINDSPOTS=(); _PM=""; }

# did any record of TIER contain SUBSTR (in title or detail)?
emitted() {
  local t="$1" sub="$2" rec tier cat title pd rem
  for rec in "${_ITEMS[@]}"; do
    IFS=$'\x1f' read -r tier cat title pd rem <<<"$rec"
    [ "$tier" = "$t" ] || continue
    case "$title"$'\x1e'"$pd" in *"$sub"*) return 0 ;; esac
  done
  return 1
}
