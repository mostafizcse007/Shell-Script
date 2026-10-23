# Shell Scripting Standards & Guardrails

All Bash scripts created or maintained in this repository must strictly adhere to the following four standards:

## 1. Shebang & Strict Mode
Every Bash script must start with the portable Bash shebang and strict execution flags:
```bash
#!/usr/bin/env bash
set -euo pipefail
```
- `-e`: Exit immediately if a pipeline, list, or compound command exits with a non-zero status.
- `-u`: Treat unset variables and parameters as errors when performing parameter expansion.
- `-o pipefail`: Return the exit status of the last command in the pipe that failed, rather than the status of the final command.

## 2. Shared Logging with `lib/logger.sh`
- All scripts must source the shared logger:
  ```bash
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
  # Source logger relative to script or repo root
  if [[ -f "${SCRIPT_DIR}/../lib/logger.sh" ]]; then
    source "${SCRIPT_DIR}/../lib/logger.sh"
  elif [[ -f "${SCRIPT_DIR}/lib/logger.sh" ]]; then
    source "${SCRIPT_DIR}/lib/logger.sh"
  fi
  ```
- Use standardized logging functions: `log_info`, `log_warn`, and `log_error`.
- Logs must feature:
  - Color-coded output for interactive terminals: Green for `[INFO]`, Yellow for `[WARN]`, Red for `[ERROR]`.
  - Timestamps formatted as `YYYY-MM-DD HH:MM:SS`.
  - Dual logging: output to stdout/stderr and append to log files at `/var/log/<script_name>.log` (if writable/root) or fallback to `./logs/<script_name>.log`.

## 3. Mandatory `--dry-run` Flag for Destructive Operations
- Any script performing destructive actions (e.g., removing files/directories, altering users/groups, modifying system packages, overwriting backups, partition/disk operations) **must** implement a `--dry-run` flag.
- When `--dry-run` is active:
  - No destructive changes may be executed on the system.
  - The script must log the exact commands or actions that *would* have been performed, prefixed with `[DRY-RUN]`.

## 4. CLI Documentation & Trap Cleanup
- **CLI Documentation (`--help` / `-h`)**: Every script must provide structured usage documentation with description, options, flags, and usage examples.
- **Signal & Exit Traps**: Every script that creates temporary files, sockets, or directories must declare a cleanup trap covering `SIGINT`, `SIGTERM`, and `EXIT`:
  ```bash
  TMP_DIR="$(mktemp -d -t "$(basename "$0")-XXXXXX")"
  cleanup() {
    local exit_code=$?
    rm -rf "${TMP_DIR}"
    exit "${exit_code}"
  }
  trap cleanup EXIT SIGINT SIGTERM
  ```
