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
