# Homenum Revelio — design spec

- **Date:** 2026-06-10
- **Status:** design approved (brainstorm); not yet implemented
- **Command:** `revelio` · **Brand:** Homenum Revelio · **Repo:** `homenum-revelio` (public, standalone)
- **Author framing:** built by the agents-deployed team; provably independent of it

---

## 1. Summary

`revelio` is a single, readable Bash script you run on a host someone handed you (a bought/inherited
VPS, a contractor's leftover box, an agents-deployed client box). It produces a **complete, plain-language
inventory of every way into the machine** and distinguishes "this belongs here" from "a human put this
here — do you recognise it?".

It never prints `SAFE`. It makes **zero network calls**, **writes nothing** (report → stdout; `--save` is
the only, explicit write), runs **without root** (and says exactly what it couldn't see), and is meant to
be **read before it is run**. It has **zero knowledge of agents-deployed** — verifiably, by reading it.

The name comes from the *Homenum Revelio* charm (reveals human presence concealed in a location): the tool
answers "who else is hidden in this box that I can't see?".

## 2. Why it exists (two jobs, one tool)

1. **A genuinely useful free tool** for anyone in a host-handover situation. People share tools that
   solved a real problem; this is the shareable artifact.
2. **Trust verification for agents-deployed clients.** The product's entire thesis is "no backdoor
   suspicion" (`project_agents_deployed`). A free, readable tool that lets a client *verify* — rather
   than *believe* — that nobody kept a key turns the weakest sales objection into a demonstrable fact.

The reputation benefit flows back **without** the tool vouching for the product: because `revelio` has no
agents-deployed-specific logic, a skeptic can read it and confirm it cannot special-case the maker's boxes
to hide things. "A general tool that works on any box and provably doesn't favour its author's boxes" is a
stronger trust story than "the vendor's own tool says the vendor is safe."

## 3. Locked decisions (with rationale)

| Decision | Choice | Why |
|---|---|---|
| **Scope** | Handover **trust audit** (provenance), *not* security posture | "Did they leave a way back in?" is a sharp question with a provable answer; "is this box secure?" is bottomless and a crowded market. |
| **Verdict model** | **Disclose, don't judge** | A `SAFE` verdict just moves the trust from the box to the tool, and a false all-clear is silent + unrecoverable (`feedback_asymmetric_confidence_invalidation`). Authority comes from a *complete inventory*, not a say-so. |
| **Self-trust** | **Trustworthy by construction** | A backdoor-checker that you blind-pipe / phones home / runs as root sight-unseen performs the exact behaviour it warns against. Must meet the standard it audits for. |
| **Positioning** | **Neutral, openly authored, zero product logic, own public repo** | Provable neutrality > borrowed credibility. The support state-diff *reuses* this engine; the tool never depends on anything downstream. |
| **Language** | **Bash** (not strict POSIX `sh`) | Readability is a trust feature; arrays/`[[ ]]`/functions read cleanly. Loses only busybox/Alpine, which aren't handover scenarios. |

## 4. Threat model & non-goals

**In scope — standing access / control a *prior owner* could retain:**
SSH keys & authorized_keys, extra/abnormal accounts & privilege, listening services, outbound tunnels,
scheduled fetch-exec, login/PAM hooks, boot persistence, escalation artifacts (setuid/capabilities).

**Explicitly OUT of scope (so every claim stays provable):**
- **Rootkit / kernel-level / modified-system-binary detection.** A userspace script cannot credibly claim
  this without a trusted baseline or offline forensics. Claiming it would invite debunking.
- **General security posture / hardening** (firewall, updates, fail2ban, password policy). Ruled out in §3.
- **Malware / antivirus signature scanning.** Naming or scoping it as AV over-promises; the narrow,
  provable claim is the stronger one.

The tool states these boundaries in its own output and README. It is honest about what it can and cannot prove.

## 5. The provenance engine (core mechanism)

The "disclose, don't judge" model needs a non-rotting, offline way to tell "distro-normal" from
"a human placed this". The answer: **ask the package manager.**

- `pkg_owns <path>` → true if the file/unit/binary belongs to an installed package
  (`rpm -qf` · `dpkg -S` · `pacman -Qo` · `apk info -W`). A timer owned by `chrony` is *provably*
  distro-normal; a cron file in `/etc/cron.d/` that **no package owns** was dropped in by a human.
- This is **current by construction** — it reads the system's own install DB, which ships with the box —
  unlike an allowlist that rots the day a new distro ships. It's a **local** query: no network.

**Degradation rule (load-bearing, honest):** if the package manager is unknown/unavailable, the tool does
**not** get to call anything "normal". It surfaces everything as needs-attention and says provenance was
undeterminable. Failing loud beats faking a clean tier. (Mirrors asymmetric-confidence: never silently
downgrade to "normal".)

**Where package managers don't reach** — SSH keys, accounts, sudoers — there is *no* distro-normal: every
authorized_key is a human decision, so **all keys are surfaced** (with owning user/home, type, comment,
fingerprint, file mtime). The tool does **not** assert which key is "yours" — it can't reliably know which
key authenticated the current session; the human recognises their own. Accounts split on UID range
(system `<1000` vs human `≥1000`) and login-shell validity.

## 6. Check catalog (7 buckets)

Each bucket is one self-contained function emitting items through a common `emit()`. Every item carries
forensic context so the human can decide.

1. **SSH remote access** — every `authorized_keys` (all homes + `/root` + any `AuthorizedKeysFile` /
   `AuthorizedKeysCommand` location); each key: type + comment + fingerprint + file mtime. sshd_config
   danger knobs: `PermitRootLogin`, `PasswordAuthentication`, **`AuthorizedKeysCommand`** (fetches keys at
   login), **`TrustedUserCAKeys`** (cert-based access — the support mechanism itself), `Match` blocks,
   `~/.ssh/rc` (runs every login).
2. **Accounts & privilege** — human-capable accounts; empty-password accounts; UID-0 aliases; `sudoers` +
   `sudoers.d` (NOPASSWD called out); membership in `wheel` / `sudo` / **`docker`** (docker group =
   root-equivalent); recently-created homes.
3. **Listening services** — `ss -tlnp` / `ss -ulnp` sockets → process → binary path → package owner.
4. **Outbound tunnels** — autossh, `ssh -R` reverse tunnels, ngrok / frp / cloudflared / tailscale /
   zerotier daemons (legitimate, but they *are* remote-access planes — surfaced, not condemned).
5. **Scheduled execution** — all crontabs (per-user + `/etc/cron.d` + `/etc/cron.*` + `/var/spool/cron`),
   systemd timers (with the target unit's `ExecStart`), at/anacron; each tagged package-owned vs
   hand-dropped; **loud flag** on fetch-exec (`curl|sh`, `wget -O- | …`, base64-pipe-decode).
6. **Login/PAM & boot persistence** — `/etc/pam.d/*` for non-distro `pam_exec` / `pam_python` (PAM runs
   code on *every* auth); `/etc/rc.local`; `/etc/profile.d/*`; per-user shell rc files
   (`.bashrc`/`.bash_profile`/`.zshrc`/`.profile`); **`/etc/ld.so.preload`** (LD_PRELOAD persistence).
7. **Escalation artifacts** — setuid/setgid binaries **not owned by a package** (a setuid backdoor); file
   capabilities (`getcap -r`). Default scans common dirs (PATH + `/usr` + `/opt` + homes); `--thorough`
   walks all of `/` (slower).

## 7. Output & UX

- **Default view:** two tiers.
  - `✓ distro-normal (N) — collapsed` (expand with `-v`)
  - `↑ NEEDS YOUR EYES (M)` — each item shown loud, with full forensic context + the **exact removal
    command** (the tool prints it; it does not run it).
- **`-v` / `--verbose`:** expands distro-normal items too — important, because a clever mimic hides among
  them; a paranoid user should be able to audit that set.
- **Colour:** auto-detect TTY; honour `NO_COLOR` and `--no-color`; plain-ASCII fallback.
- **`--save <path>`:** explicit-only; writes the report to a user-named path. The *only* write the tool
  ever performs. Default output is stdout.
- **Blind spots, never silent:** when run as non-root, a `COULDN'T CHECK WITHOUT ROOT (N)` section lists
  exactly what was skipped + the `sudo` re-run command. A silently-skipped check reads as "clean", which
  is the dangerous lie (`feedback_helper_logs_on_entry`).
- **Exit codes** (no SAFE/UNSAFE, so this is an *attention count*, not a safety verdict):
  - `0` — nothing needs your eyes
  - `10` — items need your eyes (CI/scripts can gate on this)
  - `1` — tool error
  Documented in `--help` as "an attention count, not a safety verdict".

## 8. Architecture & code shape

One file, internally organised for readability and reuse:

- **Core:** TTY/colour helpers; `pkg_owns()` provenance helper (detects the package manager once);
  a single `emit()` that centralises the quiet-vs-loud classification (the disclose-don't-judge logic
  lives in exactly one place).
- **One function per bucket:** `check_ssh`, `check_accounts`, `check_listening`, `check_tunnels`,
  `check_scheduled`, `check_persistence`, `check_escalation` — each ~30–60 lines, doing one job, routing
  every finding through `emit()`.
- **Item model (internal):** `category`, `title`, `tier` (`NORMAL` | `ATTENTION`), context key/values,
  optional remediation command.
- **Sourceable:** the file guards its main block (`[ "${BASH_SOURCE[0]}" = "$0" ]`) so the support
  state-diff can `source` it and call individual `check_*` functions. Single-file for distribution,
  engine for reuse. **Reuse direction is one-way:** support depends on `revelio`; `revelio` depends on
  nothing.

## 9. Distribution & the trust pitch

- **Read-before-run, never blind pipe:** documented flow is `curl -O <raw>` → `less revelio` → `bash
  revelio`. Pinned to a commit hash.
- **Integrity:** publish `SHA256SUMS` alongside releases. *(Deferred to a later version, mirroring the
  support design: a detached signature + a second-channel checksum over TLS. v1 = commit-pinned + sums.)*
- **The README pitch (verbatim spirit):** "Don't trust me. Read me. Then run me unplugged if you like — I
  never phone home. `grep` the source for `curl`/`wget`/`nc`/`/dev/tcp` — there are none."
- **No auto-update, no phone-home** — consistent with the agents-deployed trust model (auto-update from a
  server is indistinguishable from a backdoor).

## 10. Relationship to agents-deployed & support

- `revelio` is standalone and product-agnostic. Its spec lives in its own repo, not in the (private)
  agents-deployed repo.
- The **support session state-diff** (`project_agents_support_remote_access`) computes a before/after delta
  of attack surface; it **reuses `revelio`'s `check_*` functions** as its inventory engine. That is the
  only coupling, and it points *toward* `revelio`, never away from it.
- agents-deployed merely *recommends* `revelio` in its handover docs; the tool gains nothing special on an
  agents-deployed box (verifiable by reading it).

## 11. Testing

A security audit tool cannot be validated by "run it on a clean box". Use **container fixtures** (podman,
already in use):

- Spin throwaway boxes; **plant known-bad** artifacts (rogue authorized_key, `curl|sh` cron, NOPASSWD
  sudoers entry, non-package setuid binary, `pam_exec` line, `ld.so.preload` entry) and assert each
  surfaces in the correct bucket as `ATTENTION`.
- **Plant distro-normal** artifacts (package-owned timers/cron) and assert they stay in the `NORMAL` tier
  (quiet by default, visible under `-v`).
- **Positive + negative per check.** Cover at least Fedora/RPM and Debian/dpkg bases (the two primary VPS
  families) so `pkg_owns()` is exercised on both.
- Assert the **degradation rule**: on a base with no detectable package manager, everything is surfaced as
  `ATTENTION` and the provenance-undeterminable notice prints.

This applies the project's own rule — test detection logic against real fixtures, not assumptions
(`feedback_test_prompt_empirically_before_shipping`).

## 12. Decided-for-you / open items

- **Bash over POSIX `sh`** — veto-able; chosen for readability.
- **GitHub availability** — confirm `homenum-revelio` repo name + (optional) a domain before public launch.
  Not blocking design.
- **Signing** — deferred to a post-v1 hardening pass (SHA256SUMS in v1).
- **`--thorough` full-`/` setuid scan** — opt-in due to runtime; default scans common dirs.

## 13. Non-goals recap (do not let scope creep back in)

No posture/hardening checks · no AV/signature scanning · no rootkit/kernel claims · no network · no writes
(except `--save`) · no auto-update · no agents-deployed-specific logic.
