#!/usr/bin/env bats
load ../helpers

@test "--version prints a semver-ish version and exits 0" {
  run bash "$REVELIO" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ [0-9]+\.[0-9]+ ]]
}

@test "--help prints usage incl. the no-judgement promise and exits 0" {
  run bash "$REVELIO" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"attention count, not a safety verdict"* ]]
  [[ "$output" == *"--save"* ]]
}

@test "unknown flag exits 1 with an error" {
  run bash "$REVELIO" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "--save without a filename (followed by a flag) exits 1 with an error" {
  run bash "$REVELIO" --save --verbose
  [ "$status" -eq 1 ]
  [[ "$output" == *"--save needs a FILE"* ]]
}

@test "--save at end of args exits 1 with an error" {
  run bash "$REVELIO" --save
  [ "$status" -eq 1 ]
  [[ "$output" == *"--save needs a FILE"* ]]
}
