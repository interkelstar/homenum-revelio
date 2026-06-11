#!/usr/bin/env bats
load ../helpers

# Build a fixture image; skip cleanly if the build fails (no registry, no podman, etc.)
build_image() {
  local distro="$1"
  if ! podman build -q -f "$REPO_ROOT/test/integration/Dockerfile.$distro" \
       -t "revelio-it-$distro" "$REPO_ROOT" >/dev/null 2>&1; then
    skip "podman build unavailable (no registry access?)"
  fi
}

@test "fedora: surfaces rogue key + fetch-exec cron, exit 10" {
  command -v podman >/dev/null || skip "podman not installed"
  build_image fedora
  run podman run --rm "revelio-it-fedora"
  [ "$status" -eq 10 ]
  [[ "$output" == *"evil@attacker"* ]]
  [[ "$output" == *"fetch-exec"* ]]
  [[ "$output" == *"zz-backdoor"* ]]
}

@test "debian: surfaces rogue key + fetch-exec cron, exit 10" {
  command -v podman >/dev/null || skip "podman not installed"
  build_image debian
  run podman run --rm "revelio-it-debian"
  [ "$status" -eq 10 ]
  [[ "$output" == *"evil@attacker"* ]]
  [[ "$output" == *"fetch-exec"* ]]
  [[ "$output" == *"zz-backdoor"* ]]
}

@test "fedora: rpm-owned items land in distro-normal, planted backdoor in attention (-v)" {
  command -v podman >/dev/null || skip "podman not installed"
  build_image fedora
  run podman run --rm --entrypoint /usr/local/bin/revelio "revelio-it-fedora" -v --no-color
  [ "$status" -eq 10 ]
  # NON-ZERO distro-normal count proves real package-owned items (setuid binaries, etc.)
  # were classified normal via rpm -qf — not the vacuous "header always prints" case:
  local re='distro-normal \([1-9]'
  [[ "$output" =~ $re ]]
  # and the hand-dropped artifacts remain in the attention tier:
  [[ "$output" == *"evil@attacker"* ]]
  [[ "$output" == *"zz-backdoor"* ]]
}

teardown_file() {
  command -v podman >/dev/null && podman rmi -f revelio-it-fedora revelio-it-debian >/dev/null 2>&1 || true
}
