#!/usr/bin/env bats
load ../helpers
setup() { make_root; }

@test "--save refuses to write through a pre-existing symlink, target unchanged, exits non-zero" {
  local target; target="$(mktemp)"
  echo 'ORIGINAL-LIVE-HOST-CONTENT' > "$target"
  local link="$ROOT/report-link"
  ln -s "$target" "$link"
  run bash "$REVELIO" --no-color --save "$link"
  [ "$status" -ne 0 ]
  [ "$(cat "$target")" = "ORIGINAL-LIVE-HOST-CONTENT" ]
  rm -f "$target"
}

@test "--save to a normal new path succeeds and creates the file mode 0600" {
  local out="$ROOT/report.txt"
  run bash "$REVELIO" --no-color --save "$out"
  [ -f "$out" ]
  local mode; mode="$(stat -c '%a' "$out")"
  [ "$mode" = "600" ]
}

@test "--save to a path that exists as a directory is refused" {
  local d="$ROOT/adir"
  mkdir -p "$d"
  run bash "$REVELIO" --no-color --save "$d"
  [ "$status" -ne 0 ]
}
