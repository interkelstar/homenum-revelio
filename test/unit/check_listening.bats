#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; _PM=rpm; }

# ss -tlnpH / -ulnpH style lines: State Recv-Q Send-Q Local Peer Process
ss_fixture() {
cat <<'EOF'
LISTEN 0 128 0.0.0.0:22   0.0.0.0:* users:(("sshd",pid=800,fd=3))
LISTEN 0 128 0.0.0.0:4444 0.0.0.0:* users:(("nc",pid=1313,fd=4))
EOF
}

@test "package-owned listener (sshd) is normal; unowned (nc backdoor) is attention" {
  revelio_ss() { ss_fixture; }
  pkg_owns() { case "$1" in */sshd) return 0;; *) return 1;; esac; }
  # resolve binary path from process name for the test
  _resolve_bin() { case "$1" in sshd) echo /usr/sbin/sshd;; nc) echo /usr/bin/nc;; *) echo "";; esac; }
  check_listening
  emitted normal "sshd"
  emitted attention "4444"
  emitted attention "nc"
}

@test "REVELIO_ROOT (mounted image): live-only blindspot, no socket reads" {
  make_root
  revelio_ss() { echo "FIXTURE SHOULD NOT BE READ"; }
  check_listening
  [ "${#_BLINDSPOTS[@]}" -eq 1 ]
  [[ " ${_BLINDSPOTS[*]} " == *"live-only"* ]]
  [ "$_N_ATTENTION" -eq 0 ]
}

@test "socket with no process info: one blindspot + socket still surfaced" {
  revelio_ss() { echo 'LISTEN 0 128 0.0.0.0:9999 0.0.0.0:*'; }
  check_listening
  [[ " ${_BLINDSPOTS[*]:-} " == *"process names"* ]]
  emitted attention "9999"
  # the proc-info blindspot must appear exactly once despite two ss reads (tcp+udp)
  local count=0 b
  for b in "${_BLINDSPOTS[@]:-}"; do [[ "$b" == *"process names"* ]] && count=$((count+1)); done
  [ "$count" -eq 1 ]
}
