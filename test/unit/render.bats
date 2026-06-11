#!/usr/bin/env bats
load ../helpers

setup() { src; reset_state; USE_COLOR=0; setup_color; }

@test "emit buffers into tiers and bumps counters" {
  emit attention ssh "rogue key" "comment: deploy@x" "sed -i ..."
  emit normal cron "chrony timer" "owned by chrony" ""
  [ "$_N_ATTENTION" -eq 1 ]
  [ "$_N_NORMAL" -eq 1 ]
}

@test "render shows ATTENTION items always, hides normal without -v" {
  emit attention ssh "rogue key" "comment: deploy@x" "rm it"
  emit normal cron "chrony timer" "owned by chrony" ""
  VERBOSE=0
  out="$(revelio_render)"
  [[ "$out" == *"NEEDS YOUR EYES (1)"* ]]
  [[ "$out" == *"rogue key"* ]]
  [[ "$out" == *"distro-normal (1)"* ]]
  [[ "$out" != *"chrony timer"* ]]
}

@test "render expands normal items with -v" {
  emit normal cron "chrony timer" "owned by chrony" ""
  VERBOSE=1
  out="$(revelio_render)"
  [[ "$out" == *"chrony timer"* ]]
}

@test "render shows remediation and multi-line detail" {
  emit attention cron "hourly curl|sh" $'cmd: curl x | sh\nuser: root' "crontab -r"
  out="$(revelio_render)"
  [[ "$out" == *"cmd: curl x | sh"* ]]
  [[ "$out" == *"user: root"* ]]
  [[ "$out" == *"if not yours: crontab -r"* ]]
}

@test "render lists blind spots when present" {
  blindspot "other users' crontabs (need root)"
  out="$(revelio_render)"
  [[ "$out" == *"COULDN'T CHECK WITHOUT ROOT (1)"* ]]
  [[ "$out" == *"other users' crontabs"* ]]
}

@test "exit 0 when nothing needs eyes, 10 when something does" {
  make_root
  run bash "$REVELIO" --no-color
  [ "$status" -eq 0 ]
}

@test "--save writes a colour-free report and nothing else" {
  make_root
  run bash "$REVELIO" --no-color --save "$ROOT/report.txt"
  [ -f "$ROOT/report.txt" ]
  run grep -c $'\x1b' "$ROOT/report.txt"
  [ "$output" -eq 0 ]
}

@test "strip_ansi removes real ANSI escape sequences" {
  run bash -c 'source "$1"; printf "\033[1;31mred\033[0m and \033[2mdim\033[0m\n" | strip_ansi' _ "$REVELIO"
  [ "$status" -eq 0 ]
  [ "$output" = "red and dim" ]
}

@test "exit 10 when an attention item is present" {
  run bash -c 'source "$1"; emit attention test "planted" "detail" ""; revelio_main --no-color' _ "$REVELIO"
  [ "$status" -eq 10 ]
}

@test "render names the package manager used for provenance" {
  reset_state; _PM=rpm
  out="$(revelio_render)"
  [[ "$out" == *"provenance checked against the rpm package database"* ]]
}

@test "render warns when no package manager is detected" {
  reset_state; _PM=none
  out="$(revelio_render)"
  [[ "$out" == *"no package manager detected"* ]]
}

@test "blindspot deduplicates identical messages" {
  reset_state
  blindspot "same message"
  blindspot "same message"
  blindspot "other"
  [ "${#_BLINDSPOTS[@]}" -eq 2 ]
}

@test "control/escape bytes in hostile content are neutralized" {
  reset_state
  emit attention test "title" "$(printf 'evil\033[2Jmore\rtail\007')" ""
  out="$(revelio_render)"
  [[ "$out" != *$'\033'* ]]   # no raw ESC reaches output
  [[ "$out" != *$'\r'* ]]     # no raw CR
  [[ "$out" != *$'\007'* ]]   # no raw BEL
  [[ "$out" == *"evil"* ]]    # printable text survives
  [[ "$out" == *"more"* ]]
  [[ "$out" == *"tail"* ]]
}

@test "record-delimiter bytes in hostile content don't corrupt the record" {
  reset_state
  emit attention test "$(printf 'a\037b')" "detail" ""   # \037 = our field delimiter \x1f
  out="$(revelio_render)"
  [[ "$out" == *"a?b"* ]]     # the \x1f was neutralized to ? and stayed in the title field
}

@test "over-long detail line is truncated" {
  reset_state
  local long; long="$(printf 'x%.0s' {1..500})"
  emit attention test "title" "$long" ""
  out="$(revelio_render)"
  [[ "$out" == *"[...]"* ]]
}
