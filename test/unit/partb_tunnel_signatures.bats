#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; }

@test "ssh -o RemoteForward=... is flagged as a reverse tunnel" {
  revelio_ps() { echo '  900 ssh -o RemoteForward=2222:localhost:22 relay@example.com'; }
  check_tunnels
  emitted attention "tunnel"
}

@test "ssh -o ProxyCommand=... is flagged" {
  revelio_ps() { echo '  901 ssh -o ProxyCommand=/usr/bin/nc %h %p relay@example.com'; }
  check_tunnels
  emitted attention "tunnel"
}

@test "autossh invoked by absolute path is still flagged" {
  revelio_ps() { echo '  902 /usr/bin/autossh -M 0 -R 2222:localhost:22 relay@example.com'; }
  check_tunnels
  emitted attention "autossh"
}
