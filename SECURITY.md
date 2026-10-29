# Security policy

## Supported versions

Only the latest tagged release is supported. Fixes land on `main` and ship as a new tag; older tags
are not patched.

## Reporting a vulnerability

Please report privately, not in a public issue.

- GitHub private vulnerability reporting: https://github.com/interkelstar/homenum-revelio/security/advisories/new

Include the version, what you did, and what happened. Expect an acknowledgement; there is no
formal response-time promise.

## In scope

- The `revelio` script: bugs in how it reads a host, ways hostile content (a crafted key comment, a
  malicious filename, a symlink) can inject output or make it read or write outside what it should,
  and standing-access paths it should list but does not.

## Out of scope

- It never says SAFE. `revelio` prints an inventory of the standing-access paths it could read and
  leaves the judgement to you. A userland script cannot prove the absence of a rootkit, so there are
  no rootkit or kernel-integrity claims, and "it did not list my backdoor because the backdoor hides
  from userland" is a known limit, not a vulnerability.
- Hardening or posture scoring, and antivirus or signature scanning. The tool deliberately does none of it.

## Past reviews

- 2026-09 pass by two independent scanners: [VVAH](https://github.com/visa/visa-vulnerability-agentic-harness)
  (Visa) read the script for bugs, and OpenAI codex-security read it as a control and looked for what it
  misses. Nine fixes landed in commit 5be2d01 (2026-09-09): root validation, symlink guards, `--save`
  safety, and a wider inventory (timers, `at`, anacron, sudoers includes, more accounts).

## Automated checks on every push

- The unit test suite (bats).
- ShellCheck at warning level, with results uploaded to GitHub code scanning.
- OpenSSF Scorecard (on push to `main` and weekly), published at
  https://scorecard.dev/viewer/?uri=github.com/interkelstar/homenum-revelio
- Dependabot keeps the GitHub Actions versions current.
