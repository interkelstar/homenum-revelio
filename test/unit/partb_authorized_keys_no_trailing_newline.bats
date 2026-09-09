#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; _PM=none; }

@test "authorized_keys last line with no trailing newline is still counted" {
  printf 'ssh-ed25519 AAAAC3Nz... deploy@laptop' > "$ROOT/root/.ssh/authorized_keys"
  check_ssh
  emitted attention "deploy@laptop"
}
