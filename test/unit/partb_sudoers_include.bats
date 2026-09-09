#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; _PM=none; }

@test "passwordless rule reached only via sudoers @includedir is reported" {
  mkdir -p "$ROOT/etc/other-sudoers.d"
  echo '@includedir /etc/other-sudoers.d' > "$ROOT/etc/sudoers"
  echo 'alice ALL=(ALL) NOPASSWD: ALL' > "$ROOT/etc/other-sudoers.d/alice"
  check_accounts
  emitted attention "NOPASSWD"
}

@test "passwordless rule reached only via sudoers @include of a single file is reported" {
  echo '@include /etc/extra-sudoers' > "$ROOT/etc/sudoers"
  echo 'bob ALL=(ALL) NOPASSWD: ALL' > "$ROOT/etc/extra-sudoers"
  check_accounts
  emitted attention "NOPASSWD"
}

@test "legacy #include directive (older sudo syntax) is also followed" {
  echo '#include /etc/extra-sudoers2' > "$ROOT/etc/sudoers"
  echo 'carol ALL=(ALL) NOPASSWD: ALL' > "$ROOT/etc/extra-sudoers2"
  check_accounts
  emitted attention "NOPASSWD"
}
