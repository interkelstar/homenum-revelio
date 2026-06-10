#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; _PM=none; }

@test "surfaces an authorized_keys entry as attention with its comment" {
  echo 'ssh-ed25519 AAAAC3Nz... deploy@laptop' > "$ROOT/root/.ssh/authorized_keys"
  check_ssh
  emitted attention "authorized_keys"
  emitted attention "deploy@laptop"
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
  ! emitted attention "authorized_keys"
}
