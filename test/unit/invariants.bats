#!/usr/bin/env bats
load ../helpers

@test "source contains no network primitives" {
  run grep -nE 'curl|wget|/dev/tcp|/dev/udp|(^| )nc( |$)|ncat|telnet|ftp ' "$REVELIO"
  # the only allowed matches are (a) comment lines and (b) the two named signature
  # regexes (FETCHEXEC_RE / REVSHELL_RE) — data the tool searches for, not calls it makes.
  filtered="$(printf '%s\n' "$output" \
    | grep -vE '^\s*[0-9]+:\s*#' \
    | grep -vE 'FETCHEXEC_RE=|REVSHELL_RE=' || true)"
  [ -z "$filtered" ]
}

@test "default run performs no writes outside REVELIO_ROOT" {
  make_root
  # strace the run; assert no openat for write outside the fixture root and /dev,/proc,/sys
  if command -v strace >/dev/null 2>&1; then
    run strace -f -e trace=openat -o "$ROOT/strace.out" bash "$REVELIO" --no-color
    # writes look like O_WRONLY/O_RDWR/O_CREAT
    bad="$(grep -E 'O_WRONLY|O_RDWR|O_CREAT' "$ROOT/strace.out" \
            | grep -vE "$ROOT|/dev/|/proc/|/sys/|pipe:|socket:" || true)"
    [ -z "$bad" ]
  else
    skip "strace not installed"
  fi
}
