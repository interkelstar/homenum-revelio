#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; }

@test "_validate_revelio_root accepts empty REVELIO_ROOT" {
  REVELIO_ROOT=""
  run _validate_revelio_root
  [ "$status" -eq 0 ]
}

@test "_validate_revelio_root accepts an absolute existing directory" {
  local d; d="$(mktemp -d)"
  REVELIO_ROOT="$d"
  run _validate_revelio_root
  [ "$status" -eq 0 ]
  rmdir "$d"
}

@test "_validate_revelio_root rejects a relative path" {
  REVELIO_ROOT="-delete"
  run _validate_revelio_root
  [ "$status" -ne 0 ]
  [[ "$output" == *"absolute path"* ]]
}

@test "_validate_revelio_root rejects a value beginning with a dash (find-flag-like)" {
  REVELIO_ROOT="-delete"
  run _validate_revelio_root
  [ "$status" -ne 0 ]
}

@test "_validate_revelio_root rejects a non-existent absolute path" {
  REVELIO_ROOT="/no/such/dir/xyz123"
  run _validate_revelio_root
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "REVELIO_ROOT=-delete in --thorough exits non-zero, deletes nothing, no error crash" {
  local cwd; cwd="$(mktemp -d)"
  local canary="$cwd/canary"
  echo keep > "$canary"
  run bash -c "cd '$cwd' && REVELIO_ROOT=-delete bash '$REVELIO' --thorough"
  [ "$status" -ne 0 ]
  [ -f "$canary" ]
  rm -rf "$cwd"
}

@test "REVELIO_ROOT with a relative value (not starting with dash) is also rejected" {
  local cwd; cwd="$(mktemp -d)"
  run bash -c "cd '$cwd' && REVELIO_ROOT=some/relative/path bash '$REVELIO' --thorough"
  [ "$status" -ne 0 ]
  [[ "$output" == *"absolute path"* ]]
  rm -rf "$cwd"
}
