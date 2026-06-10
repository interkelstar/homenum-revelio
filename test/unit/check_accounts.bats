#!/usr/bin/env bats
load ../helpers
setup() {
  src; reset_state; make_root; _PM=none
  # minimal passwd/shadow/group fixtures
  cat > "$ROOT/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
alice:x:1000:1000:alice:/home/alice:/bin/bash
backdoor:x:0:0:backdoor:/root:/bin/bash
EOF
  cat > "$ROOT/etc/shadow" <<'EOF'
root:$6$abc:19000:0:99999:7:::
alice:$6$xyz:19000:0:99999:7:::
ghost::19000:0:99999:7:::
EOF
  cat > "$ROOT/etc/group" <<'EOF'
wheel:x:10:alice
docker:x:990:alice
sudo:x:27:
EOF
  mkdir -p "$ROOT/etc/sudoers.d"
}

@test "flags a second UID-0 account" {
  check_accounts
  emitted attention "backdoor"
  emitted attention "UID 0"
}

@test "flags an empty-password account" {
  check_accounts
  emitted attention "empty password"
  emitted attention "ghost"
}

@test "flags NOPASSWD sudoers entries" {
  echo 'alice ALL=(ALL) NOPASSWD: ALL' > "$ROOT/etc/sudoers.d/alice"
  check_accounts
  emitted attention "NOPASSWD"
}

@test "flags membership in docker group (root-equivalent)" {
  check_accounts
  emitted attention "docker group"
}

@test "unreadable /etc/shadow emits a blindspot, not a silent skip" {
  [ "$(id -u)" -eq 0 ] && skip "must run as non-root to make shadow unreadable"
  printf 'root:$6$abc:19000:0:99999:7:::\n' > "$ROOT/etc/shadow"
  chmod 000 "$ROOT/etc/shadow"
  reset_state
  check_accounts
  [[ " ${_BLINDSPOTS[*]:-} " == *"/etc/shadow"* ]]
}

@test "clean accounts fixture -> no attention items" {
  cat > "$ROOT/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
alice:x:1000:1000:alice:/home/alice:/bin/bash
EOF
  cat > "$ROOT/etc/shadow" <<'EOF'
root:$6$abc:19000:0:99999:7:::
alice:$6$xyz:19000:0:99999:7:::
EOF
  cat > "$ROOT/etc/group" <<'EOF'
wheel:x:10:
sudo:x:27:
EOF
  reset_state
  check_accounts
  [ "$_N_ATTENTION" -eq 0 ]
}
