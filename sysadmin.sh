#!/usr/bin/env bash
# ==============================================================================
# OS Admin CLI Suite: Main Entrypoint & Dispatcher
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Source shared libraries
# shellcheck source=lib/logger.sh
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

VERSION="1.0.0"

show_help() {
  cat <<EOF
OS Admin CLI Suite - Unified System Administration Toolset (v${VERSION})
Target Platform: ${OS_TYPE} (${OS_ARCH})

Usage:
  $(basename "$0") <command> [options...]
  $(basename "$0") [menu]

Core Commands:
  monitor       System resource & process monitor with threshold alerts
  backup        Incremental backup & rotation manager with SHA-256 verification
  organize      Automated file organizer by category
  clean         Log cleaner (age & size based pruning with quarantine safety)
  provision     Bulk user & permission provisioning from CSV
  menu          Interactive pure Bash TUI menu launcher
  test          Run automated integration test suite
  version       Display toolset version and detected OS platform

Global Options:
  -d, --dry-run  Simulate destructive actions without modifying system state
  -h, --help     Display this help documentation
  -v, --version  Display version information

Examples:
  ./sysadmin.sh monitor --snapshot
  ./sysadmin.sh monitor --watch 2 --cpu-threshold 75
  ./sysadmin.sh backup --source ./data --dest ./backups --retention 3
  ./sysadmin.sh backup --verify ./backups/backup_L0_latest.tar.gz
  ./sysadmin.sh organize --target ~/Downloads --organize --dry-run
  ./sysadmin.sh clean --target ./logs --older-than 7 --max-size 10
  ./sysadmin.sh provision --csv examples/users.csv --dry-run
  ./sysadmin.sh menu
EOF
}

# Check if no arguments provided -> Default to TUI or Help
if [[ $# -eq 0 ]]; then
  if [[ -f "${SCRIPT_DIR}/modules/tui_menu.sh" ]]; then
    exec bash "${SCRIPT_DIR}/modules/tui_menu.sh"
  else
    show_help
    exit 0
  fi
fi

COMMAND="$1"
shift

case "${COMMAND}" in
  monitor)
    MODULE_SCRIPT="${SCRIPT_DIR}/modules/monitor.sh"
    if [[ ! -f "${MODULE_SCRIPT}" ]]; then
      log_error "Module not found: ${MODULE_SCRIPT}"
      exit 1
    fi
    exec bash "${MODULE_SCRIPT}" "$@"
    ;;

  backup)
    MODULE_SCRIPT="${SCRIPT_DIR}/modules/backup.sh"
    if [[ ! -f "${MODULE_SCRIPT}" ]]; then
      log_error "Module not found: ${MODULE_SCRIPT}"
      exit 1
    fi
    exec bash "${MODULE_SCRIPT}" "$@"
    ;;

  organize)
    MODULE_SCRIPT="${SCRIPT_DIR}/modules/organizer.sh"
    if [[ ! -f "${MODULE_SCRIPT}" ]]; then
      log_error "Module not found: ${MODULE_SCRIPT}"
      exit 1
    fi
    exec bash "${MODULE_SCRIPT}" "$@"
    ;;

  clean)
    MODULE_SCRIPT="${SCRIPT_DIR}/modules/organizer.sh"
    if [[ ! -f "${MODULE_SCRIPT}" ]]; then
      log_error "Module not found: ${MODULE_SCRIPT}"
      exit 1
    fi
    exec bash "${MODULE_SCRIPT}" --clean-logs "$@"
    ;;

  provision)
    MODULE_SCRIPT="${SCRIPT_DIR}/modules/provision.sh"
    if [[ ! -f "${MODULE_SCRIPT}" ]]; then
      log_error "Module not found: ${MODULE_SCRIPT}"
      exit 1
    fi
    exec bash "${MODULE_SCRIPT}" "$@"
    ;;

  menu|tui)
    MODULE_SCRIPT="${SCRIPT_DIR}/modules/tui_menu.sh"
    if [[ ! -f "${MODULE_SCRIPT}" ]]; then
      log_warn "TUI module not yet implemented (${MODULE_SCRIPT}). Showing CLI menu:"
      show_help
      exit 0
    fi
    exec bash "${MODULE_SCRIPT}" "$@"
    ;;

  test)
    TEST_SCRIPT="${SCRIPT_DIR}/tests/test_suite.sh"
    if [[ ! -f "${TEST_SCRIPT}" ]]; then
      log_error "Test suite script not found: ${TEST_SCRIPT}"
      exit 1
    fi
    exec bash "${TEST_SCRIPT}" "$@"
    ;;

  version|-v|--version)
    echo "OS Admin CLI Suite v${VERSION}"
    echo "Detected OS: ${OS_TYPE} (${OS_ARCH})"
    echo "Bash Version: ${BASH_VERSION:-unknown}"
    exit 0
    ;;

  help|-h|--help)
    show_help
    exit 0
    ;;

  *)
    log_error "Unknown command: '${COMMAND}'"
    echo ""
    show_help
    exit 1
    ;;
esac
