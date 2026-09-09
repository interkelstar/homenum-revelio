#!/usr/bin/env bats
load ../helpers
setup() {
  src; reset_state; make_root; _PM=none
  mkdir -p "$ROOT/etc/sudoers.d"
}

@test "UID<1000 non-system account with a login shell and a password hash is reported" {
  cat > "$ROOT/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
backdoor:x:999:999:backdoor:/home/backdoor:/bin/bash
EOF
  cat > "$ROOT/etc/shadow" <<'EOF'
root:$6$abc:19000:0:99999:7:::
backdoor:$6$xyz:19000:0:99999:7:::
EOF
  check_accounts
  emitted attention "backdoor"
}

@test "UID>=1000 account with /bin/bash but home outside /home is reported" {
  cat > "$ROOT/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
sneaky:x:1500:1500:sneaky:/opt/sneaky:/bin/bash
EOF
  cat > "$ROOT/etc/shadow" <<'EOF'
root:$6$abc:19000:0:99999:7:::
sneaky:$6$xyz:19000:0:99999:7:::
EOF
  check_accounts
  emitted attention "sneaky"
}

@test "normal /home account with a login shell is NOT flagged as an extra login-capable account" {
  cat > "$ROOT/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
alice:x:1000:1000:alice:/home/alice:/bin/bash
EOF
  cat > "$ROOT/etc/shadow" <<'EOF'
root:$6$abc:19000:0:99999:7:::
alice:$6$xyz:19000:0:99999:7:::
EOF
  check_accounts
  run emitted attention "alice"
  [ "$status" -ne 0 ]
}

@test "system account with nologin shell is NOT flagged" {
  cat > "$ROOT/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
EOF
  cat > "$ROOT/etc/shadow" <<'EOF'
root:$6$abc:19000:0:99999:7:::
daemon:*:19000:0:99999:7:::
EOF
  check_accounts
  run emitted attention "daemon"
  [ "$status" -ne 0 ]
}
