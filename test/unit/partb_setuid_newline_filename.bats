#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; _PM=none; THOROUGH=1; }

@test "setuid binary with a newline in its filename is reported intact, not split/garbled" {
  mkdir -p "$ROOT/opt"
  local weird="$ROOT/opt/innocent"$'\n'"evil"
  printf '#!/bin/sh\n' > "$weird"
  chmod 4755 "$weird"
  check_escalation
  # exactly one finding for this one file — a newline-unaware read (splitting
  # on \n instead of the NUL from find -print0) would instead misparse this
  # single setuid file into two bogus/garbled entries.
  [ "${#_ITEMS[@]}" -eq 1 ]
  # the raw record for that one finding still carries both halves of the
  # filename around the embedded newline — the name wasn't truncated.
  case "${_ITEMS[0]}" in
    *"innocent"*"evil"*) : ;;
    *) return 1 ;;
  esac
}
