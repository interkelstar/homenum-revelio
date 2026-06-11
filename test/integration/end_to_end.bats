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
}

@test "fedora: a real rpm-owned cron file lands in distro-normal (-v)" {
  command -v podman >/dev/null || skip "podman not installed"
  build_image fedora
  # crontabs package owns /etc/crontab on Fedora; run with -v and assert it's normal-tiered
  run podman run --rm --entrypoint /usr/local/bin/revelio "revelio-it-fedora" -v --no-color
  [[ "$output" == *"distro-normal"* ]]
}
