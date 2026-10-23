#!/usr/bin/env bash
# ==============================================================================
# Module 5 / Component 6: Interactive Pure Bash ANSI TUI Menu Wrapper
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

# Source shared libraries
# shellcheck source=lib/logger.sh
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
  Interactive pure Bash TUI dashboard for the OS Admin CLI Suite.
  Provides full-screen keyboard-navigable access to all administration modules
  with zero external binary dependencies.

Options:
  -h, --help    Display this documentation and exit

Navigation:
  Up / Down, j / k : Move selection cursor
  1 - 6            : Direct shortcut to option
  Enter / Space    : Execute selected option
  q / Q / Esc      : Exit TUI
EOF
}

# Parse help argument
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  show_help
  exit 0
fi

# Terminal control sequences
ESC=$'\033'
C_RESET="${ESC}[0m"
C_BOLD="${ESC}[1m"
C_INVERT="${ESC}[7m"
C_CYAN="${ESC}[36m"
C_GREEN="${ESC}[32m"
C_YELLOW="${ESC}[33m"
C_RED="${ESC}[31m"
C_BLUE="${ESC}[34m"
C_MAGENTA="${ESC}[35m"

# Restore terminal on exit
cleanup_tui() {
  printf "%b" "${ESC}[?25h${C_RESET}" 2>/dev/null || true
}
trap cleanup_tui EXIT SIGINT SIGTERM

# Menu items definition
MENU_ITEMS=(
  "System Resource & Process Monitor"
  "Incremental Backup & Rotation Manager"
  "Automated File Organizer & Log Cleaner"
  "Bulk User & Permission Provisioning"
  "View System & Incident Logs"
  "Run Automated Integration Test Suite"
  "Exit to Shell"
)

TOTAL_ITEMS="${#MENU_ITEMS[@]}"
SELECTED_INDEX=0

draw_menu() {
  printf "%b" "${ESC}[H${ESC}[J" # Clear screen and move to top
  echo -e "${C_CYAN}${C_BOLD}================================================================================${C_RESET}"
  echo -e "${C_CYAN}${C_BOLD}                 OS ADMIN CLI SUITE - SYSTEM DASHBOARD                          ${C_RESET}"
  echo -e "${C_CYAN}${C_BOLD}================================================================================${C_RESET}"
  echo -e " Host: ${C_BOLD}$(hostname 2>/dev/null || echo "localhost")${C_RESET} | Platform: ${C_GREEN}${OS_TYPE} (${OS_ARCH})${C_RESET} | Date: $(date '+%Y-%m-%d %H:%M:%S')"
  echo -e " Log Target: ${LOG_FILE:-./logs/sysadmin.log}"
  echo -e "${C_CYAN}--------------------------------------------------------------------------------${C_RESET}"
  echo -e "${C_YELLOW} Use [Up/Down] or [1-7] to navigate, [Enter] to select, [q] to quit:${C_RESET}"
  echo ""

  for (( i=0; i<TOTAL_ITEMS; i++ )); do
    local item_num=$(( i + 1 ))
    local label="${MENU_ITEMS[i]}"
    if (( i == SELECTED_INDEX )); then
      echo -e "  ${C_INVERT}${C_BOLD} > [${item_num}] ${label} ${C_RESET}"
    else
      echo -e "    [${item_num}] ${label}"
    fi
  done

  echo ""
  echo -e "${C_CYAN}================================================================================${C_RESET}"
}

pause_for_user() {
  echo ""
  echo -e "${C_YELLOW}Press [Enter] to return to dashboard...${C_RESET}"
  read -r _
}

# Sub-wizards
run_monitor_wizard() {
  printf "%b" "${ESC}[H${ESC}[J"
  echo -e "${C_BOLD}--- Module 1: System Resource Monitor ---${C_RESET}"
  echo "1) Diagnostic Snapshot (Single report)"
  echo "2) Continuous Watch Mode (Live monitoring)"
  echo "3) Back to Main Menu"
  echo ""
  read -rp "Select mode [1-3]: " sub_choice
  case "${sub_choice}" in
    1)
      bash "${SCRIPT_DIR}/modules/monitor.sh" --snapshot || true
      pause_for_user
      ;;
    2)
      read -rp "Refresh interval in seconds (default: 3): " int_sec
      int_sec="${int_sec:-3}"
      bash "${SCRIPT_DIR}/modules/monitor.sh" --watch "${int_sec}" || true
      pause_for_user
      ;;
    *)
      ;;
  esac
}

run_backup_wizard() {
  printf "%b" "${ESC}[H${ESC}[J"
  echo -e "${C_BOLD}--- Module 2: Incremental Backup & Rotation ---${C_RESET}"
  echo "1) Create Backup (Full/Incremental)"
  echo "2) Verify Archive Integrity"
  echo "3) Back to Main Menu"
  echo ""
  read -rp "Select action [1-3]: " sub_choice
  case "${sub_choice}" in
    1)
      read -rp "Source directory to back up: " src
      read -rp "Destination directory for archives: " dest
      read -rp "Retention limit (default: 5): " ret
      ret="${ret:-5}"
      read -rp "Simulate with --dry-run? (y/N): " dry
      local dry_flag=""
      if [[ "${dry}" =~ ^[yY]$ ]]; then dry_flag="--dry-run"; fi
      
      if [[ -n "${src}" && -n "${dest}" ]]; then
        bash "${SCRIPT_DIR}/modules/backup.sh" --source "${src}" --dest "${dest}" --retention "${ret}" ${dry_flag} || true
      else
        log_error "Source and Destination directories are required."
      fi
      pause_for_user
      ;;
    2)
      read -rp "Path to archive (.tar.gz): " arch
      if [[ -n "${arch}" ]]; then
        bash "${SCRIPT_DIR}/modules/backup.sh" --verify "${arch}" || true
      fi
      pause_for_user
      ;;
    *)
      ;;
  esac
}

run_organizer_wizard() {
  printf "%b" "${ESC}[H${ESC}[J"
  echo -e "${C_BOLD}--- Module 3: File Organizer & Log Cleaner ---${C_RESET}"
  read -rp "Target directory to process: " target_dir
  echo "1) Organize files into categories (Docs, Images, Media, etc.)"
  echo "2) Clean stale / oversized .log files"
  echo "3) Both (Organize + Clean Logs)"
  echo "4) Back to Main Menu"
  echo ""
  read -rp "Select action [1-4]: " act_choice

  local act_flag=""
  case "${act_choice}" in
    1) act_flag="--organize" ;;
    2) act_flag="--clean-logs" ;;
    3) act_flag="--organize --clean-logs" ;;
    *) return 0 ;;
  esac

  read -rp "Simulate with --dry-run? (y/N): " dry
  local dry_flag=""
  if [[ "${dry}" =~ ^[yY]$ ]]; then dry_flag="--dry-run"; fi

  if [[ -n "${target_dir}" ]]; then
    # shellcheck disable=SC2086
    bash "${SCRIPT_DIR}/modules/organizer.sh" --target "${target_dir}" ${act_flag} ${dry_flag} || true
  else
    log_error "Target directory is required."
  fi
  pause_for_user
}

run_provision_wizard() {
  printf "%b" "${ESC}[H${ESC}[J"
  echo -e "${C_BOLD}--- Module 4: Bulk User & Permission Provisioning ---${C_RESET}"
  read -rp "Path to CSV file (e.g. examples/users.csv): " csv_path
  echo "1) Provision Accounts (Create Users/Groups)"
  echo "2) Deprovision Accounts (Delete Users in CSV)"
  echo "3) Back to Main Menu"
  echo ""
  read -rp "Select mode [1-3]: " sub_choice

  local dep_flag=""
  case "${sub_choice}" in
    1) ;;
    2) dep_flag="--deprovision" ;;
    *) return 0 ;;
  esac

  read -rp "Simulate with --dry-run? (recommended if non-root) (y/N): " dry
  local dry_flag=""
  if [[ "${dry}" =~ ^[yY]$ ]]; then dry_flag="--dry-run"; fi

  if [[ -n "${csv_path}" ]]; then
    # shellcheck disable=SC2086
    bash "${SCRIPT_DIR}/modules/provision.sh" --csv "${csv_path}" ${dep_flag} ${dry_flag} || true
  else
    log_error "CSV path is required."
  fi
  pause_for_user
}

run_log_viewer() {
  printf "%b" "${ESC}[H${ESC}[J"
  echo -e "${C_BOLD}--- Recent System Logs (${LOG_FILE:-./logs/sysadmin.log}) ---${C_RESET}"
  echo "--------------------------------------------------------------------------------"
  if [[ -f "${LOG_FILE:-./logs/sysadmin.log}" ]]; then
    tail -n 25 "${LOG_FILE:-./logs/sysadmin.log}"
  else
    echo "No log file found at ${LOG_FILE:-./logs/sysadmin.log}"
  fi
  echo "--------------------------------------------------------------------------------"
  pause_for_user
}

run_test_suite_wrapper() {
  printf "%b" "${ESC}[H${ESC}[J"
  echo -e "${C_BOLD}--- Running Automated Test Suite ---${C_RESET}"
  if [[ -f "${SCRIPT_DIR}/tests/test_suite.sh" ]]; then
    bash "${SCRIPT_DIR}/tests/test_suite.sh" || true
  else
    echo "Test suite script not found at tests/test_suite.sh"
  fi
  pause_for_user
}

execute_action() {
  case "${SELECTED_INDEX}" in
    0) run_monitor_wizard ;;
    1) run_backup_wizard ;;
    2) run_organizer_wizard ;;
    3) run_provision_wizard ;;
    4) run_log_viewer ;;
    5) run_test_suite_wrapper ;;
    6) exit 0 ;;
  esac
}

# Non-interactive fallback
if [[ ! -t 0 ]]; then
  echo "Non-interactive terminal detected. Showing menu options:"
  for (( i=0; i<TOTAL_ITEMS; i++ )); do
    echo "  $(( i + 1 ))) ${MENU_ITEMS[i]}"
  done
  exit 0
fi

# Main interactive event loop
printf "%b" "${ESC}[?25l" # Hide cursor

while true; do
  draw_menu

  # Read 1 character
  IFS= read -rsn1 key

  # Handle Escape sequences (Arrows)
  if [[ "${key}" == "${ESC}" ]]; then
    read -rsn2 -t 0.1 seq || seq=""
    if [[ "${seq}" == "[A" ]]; then
      # Up Arrow
      (( SELECTED_INDEX = (SELECTED_INDEX - 1 + TOTAL_ITEMS) % TOTAL_ITEMS ))
    elif [[ "${seq}" == "[B" ]]; then
      # Down Arrow
      (( SELECTED_INDEX = (SELECTED_INDEX + 1) % TOTAL_ITEMS ))
    fi
  elif [[ "${key}" == "k" || "${key}" == "K" ]]; then
    (( SELECTED_INDEX = (SELECTED_INDEX - 1 + TOTAL_ITEMS) % TOTAL_ITEMS ))
  elif [[ "${key}" == "j" || "${key}" == "J" ]]; then
    (( SELECTED_INDEX = (SELECTED_INDEX + 1) % TOTAL_ITEMS ))
  elif [[ "${key}" == "" ]]; then
    # Enter key pressed
    execute_action
  elif [[ "${key}" =~ ^[1-7]$ ]]; then
    SELECTED_INDEX=$(( key - 1 ))
    execute_action
  elif [[ "${key}" == "q" || "${key}" == "Q" ]]; then
    break
  fi
done
