#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; _PM=none; }

@test "surfaces an authorized_keys entry as attention with its comment" {
  echo 'ssh-ed25519 AAAAC3Nz... deploy@laptop' > "$ROOT/root/.ssh/authorized_keys"
  check_ssh
  emitted attention "authorized_keys"
  emitted attention "deploy@laptop"
}

@test "unreadable authorized_keys blindspots, leaks no open error" {
  [ "$(id -u)" -eq 0 ] && skip "must run as non-root to make authorized_keys unreadable"
  echo 'ssh-ed25519 AAAAC3Nz... deploy@laptop' > "$ROOT/root/.ssh/authorized_keys"
  chmod 000 "$ROOT/root/.ssh/authorized_keys"
  reset_state
  run check_ssh
  [[ "$output" != *"Permission denied"* ]]
  reset_state
  check_ssh
  [[ " ${_BLINDSPOTS[*]:-} " == *"authorized_keys"* ]]
}

@test "flags PermitRootLogin yes and PasswordAuthentication yes" {
  printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' > "$ROOT/etc/ssh/sshd_config"
  check_ssh
  emitted attention "PermitRootLogin yes"
  emitted attention "PasswordAuthentication yes"
}

@test "flags AuthorizedKeysCommand and TrustedUserCAKeys as access vectors" {
  printf 'AuthorizedKeysCommand /usr/bin/fetchkeys\nTrustedUserCAKeys /etc/ssh/ca.pub\n' \
    > "$ROOT/etc/ssh/sshd_config"
  check_ssh
  emitted attention "AuthorizedKeysCommand"
  emitted attention "TrustedUserCAKeys"
}

@test "no keys, hardened config -> no ssh attention items" {
  printf 'PermitRootLogin no\nPasswordAuthentication no\n' > "$ROOT/etc/ssh/sshd_config"
  check_ssh
  run emitted attention "authorized_keys"
  [ "$status" -ne 0 ]
  run emitted attention "PermitRootLogin"
  [ "$status" -ne 0 ]
  run emitted attention "PasswordAuthentication"
  [ "$status" -ne 0 ]
}

@test "options-prefixed key: type is the algorithm, not the options blob" {
  echo 'command="/usr/bin/x",no-pty ssh-ed25519 AAAAC3Nz deploy@laptop' > "$ROOT/root/.ssh/authorized_keys"
  check_ssh
  emitted attention "type: ssh-ed25519"
  emitted attention "deploy@laptop"
  run emitted attention "type: command"
  [ "$status" -ne 0 ]
}

@test "key with no comment shows comment (none)" {
  echo 'ssh-rsa AAAAB3NzaC1yc2EAAAAD' > "$ROOT/root/.ssh/authorized_keys"
  check_ssh
  emitted attention "type: ssh-rsa"
  emitted attention "comment: (none)"
}
