# Homenum Revelio

[![CI](https://github.com/interkelstar/homenum-revelio/actions/workflows/ci.yml/badge.svg)](https://github.com/interkelstar/homenum-revelio/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/interkelstar/homenum-revelio/badge)](https://scorecard.dev/viewer/?uri=github.com/interkelstar/homenum-revelio)
· [Security policy](SECURITY.md)

`revelio` reveals who else still has a way into a Linux host you were just handed —
a bought/inherited VPS, a contractor's leftover box, a server someone set up for you.
It prints a **complete inventory** of every standing-access path and tells you which
entries are package-owned (distro-normal) versus placed by a human. It never says
"SAFE" — it hands you the facts and you decide which you recognise.

## Don't trust me. Read me.

This is a tool for checking that nobody left a backdoor — so it would be absurd to
ask you to blindly trust it. It's one readable Bash file:

```sh
curl -O https://raw.githubusercontent.com/interkelstar/homenum-revelio/v0.1.0/revelio
less revelio          # read it — it's ~730 lines
bash revelio          # then run it (it is bash, not POSIX sh)
```

The link pins a tag, never main — read exactly what you run.

- **No network.** `grep -nE 'curl|wget|/dev/tcp|/dev/udp|nc |ncat|telnet' revelio` → only the two detection-signature regexes (`FETCHEXEC_RE`, `REVSHELL_RE`, patterns searched for in *other* files) and the comment that says so; no command line.
- **No writes.** Output goes to your terminal; `--save FILE` is the only write, and it's yours.
- **No root required.** It runs as you and tells you exactly what it couldn't see without root.
- **Safe to read.** Hostile content (a crafted key comment, a malicious filename) can't inject terminal escape sequences into your screen or the saved report — control bytes are neutralized to `?`, and over-long lines are capped with `[...]`.

## Usage

```
revelio [-v] [--no-color] [--save FILE] [--thorough]
```

Exit code is a flag, not a count and not a verdict: `0` nothing needs your attention,
`10` at least one finding needs your attention (always `10`, however many there are),
`1` the tool's own error (bad option, bad `REVELIO_ROOT`, refused `--save` target).

`REVELIO_ROOT=/mnt revelio` audits a mounted disk image instead of the live system.

## What it checks

SSH keys & sshd danger knobs · extra/abnormal accounts, empty passwords, sudoers,
docker group · listening services · outbound tunnels (autossh, `ssh -R`,
cloudflared/ngrok/frp/tailscale/zerotier) · scheduled execution (cron, cron.d,
systemd timers; loud on `curl|sh`) · login/boot persistence (PAM, `ld.so.preload`,
rc.local, profile.d, shell rc) · non-package setuid binaries & capabilities.

## What it deliberately does NOT do

No hardening/posture scoring · no antivirus/signature scanning · no rootkit or
kernel-integrity claims (a userspace script can't prove those honestly). It makes
one narrow, provable claim: *here is every way in we could read.*

## Who made it

Built by the [agents-deployed](https://agents-deployed.com) team. We run it on every
box we hand over. It has **no special knowledge of our boxes** — read the source and
confirm it treats every host the same.

MIT licensed.
