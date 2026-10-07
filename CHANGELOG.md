# Changelog

User-visible changes are recorded here. Release archives under
`releases/vVERSION/` remain the immutable record of exact shipped artifacts.

## 1.6.0 - 2026-10-07

- Add explicit `safe` and `fleet` profiles. Fresh installs choose safe defaults;
  existing no-profile installations keep their prior fleet behavior.
- Add `always`, `daily`, `missing-only`, and `never` update policies for
  deterministic or lower-latency launches.
- Add network-free `start status [--json]` and `start doctor --offline` modes
  with checked-in JSON schemas for agents and automation.
- Pass native agent arguments safely after `--`.
- Add `--resume last` using the Herdr `HERDR_RESUME_ID` and
  `HERDR_RESUME_AGENT` handoff contract.
- Diagnose unsafe config/profile ownership and modes, and document that
  `config.sh` is trusted arbitrary Bash.

## 1.5.1 - 2026-10-07

- Publish the v1.5.0 source state through the automated release workflow; no
  launcher behavior changed.

## 1.5.0 - 2026-10-05

- Add `start doctor` and the `harnessctl-doctor-v1` JSON diagnostic interface.
- Add `-C`/`--workdir` and make the caller's current directory the consistent
  default across bare-shell, tmux, and Herdr launches.
- Report the exact update stage that failed, including an unusable OpenSSL
  executable.
- Expand human, automation, security, troubleshooting, architecture, and
  release documentation.

## 1.4.0 - 2026-10-03

- Extract the launcher into the standalone `harnessctl` repository.
- Add signed automatic and explicit launcher updates.
- Add an authenticated installer and protected OpenBao Transit release flow.
- Support Claude Code and Codex selection and resume dispatch.
- Avoid nested tmux sessions inside tmux and Herdr.
- Preserve the original fleet model, permission, tmux, and working-directory
  defaults during extraction.
