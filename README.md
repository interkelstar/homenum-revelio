# Homenum Revelio

`revelio` reveals who else still has a way into a Linux host you were just handed —
a bought/inherited VPS, a contractor's leftover box, a server someone set up for you.
It prints a **complete inventory** of every standing-access path and tells you which
entries are package-owned (distro-normal) versus placed by a human. It never says
"SAFE" — it hands you the facts and you decide which you recognise.

## Don't trust me. Read me.

This is a tool for checking that nobody left a backdoor — so it would be absurd to
ask you to blindly trust it. It's one readable Bash file:

```sh
curl -O https://raw.githubusercontent.com/agents-deployed/homenum-revelio/<commit>/revelio
less revelio          # read it — it's ~600 lines
sh revelio            # then run it
```

- **No network.** `grep -nE 'curl|wget|/dev/tcp|/dev/udp|nc |ncat|telnet' revelio` → nothing.
- **No writes.** Output goes to your terminal; `--save FILE` is the only write, and it's yours.
- **No root required.** It runs as you and tells you exactly what it couldn't see without root.
- **Safe to read.** Hostile content (a crafted key comment, a malicious filename) can't inject terminal escape sequences into your screen or the saved report — control bytes are neutralized to `?`, and over-long lines are capped with `[...]`.

## Usage

```
revelio [-v] [--no-color] [--save FILE] [--thorough]
```

Exit code is an **attention count, not a verdict**: `0` nothing needs your eyes,
`10` items need your eyes, `1` tool error.

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
