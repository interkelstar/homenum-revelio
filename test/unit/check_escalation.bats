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
