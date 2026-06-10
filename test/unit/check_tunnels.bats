#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; }

ps_fixture() {
cat <<'EOF'
  800 /usr/sbin/sshd -D
 1500 autossh -M 0 -R 2222:localhost:22 relay@example.com
 1600 ssh -R 9000:localhost:80 user@1.2.3.4
 1700 /usr/bin/cloudflared tunnel run
EOF
}

@test "flags autossh, reverse-tunnel ssh -R, and cloudflared" {
  revelio_ps() { ps_fixture; }
  check_tunnels
  emitted attention "autossh"
  emitted attention "reverse tunnel"
  emitted attention "cloudflared"
}

@test "plain sshd -D is not flagged as a tunnel" {
  revelio_ps() { echo '  800 /usr/sbin/sshd -D'; }
  check_tunnels
  [ "$_N_ATTENTION" -eq 0 ]
}

@test "REVELIO_ROOT (mounted image): live-only blindspot, no ps reads" {
  make_root
  check_tunnels
  [ "${#_BLINDSPOTS[@]}" -eq 1 ]
  [ "$_N_ATTENTION" -eq 0 ]
}
