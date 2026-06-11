#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; }

@test "setuid binary NOT owned by a package is attention; owned is normal" {
  _PM=rpm
  mkdir -p "$ROOT/usr/bin" "$ROOT/opt"
  install -m 4755 /bin/true "$ROOT/usr/bin/sudo"      # pretend distro setuid
  install -m 4755 /bin/true "$ROOT/opt/rootme"        # hand-dropped setuid
  pkg_owns() { case "$1" in */usr/bin/sudo) return 0;; *) return 1;; esac; }
  check_escalation
  emitted attention "rootme"
  emitted normal "/usr/bin/sudo"
}

@test "clean root produces no escalation attention items" {
  reset_state
  check_escalation
  [ "$_N_ATTENTION" -eq 0 ]
}

@test "setgid-only binary is also surfaced" {
  _PM=rpm
  pkg_owns() { return 1; }
  mkdir -p "$ROOT/opt"
  install -m 2755 /bin/true "$ROOT/opt/sgid_helper"
  reset_state
  check_escalation
  emitted attention "sgid_helper"
}
