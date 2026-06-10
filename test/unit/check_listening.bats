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
