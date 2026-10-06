# Changelog

User-visible changes are recorded here. Release archives under
`releases/vVERSION/` remain the immutable record of exact shipped artifacts.

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
