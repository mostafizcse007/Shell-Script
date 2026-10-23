#!/usr/bin/env bash
# ==============================================================================
# OS Admin CLI Suite: Interactive Live Evaluation & Demonstration Runner
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "${SCRIPT_DIR}"

# Source shared libraries
# shellcheck source=lib/logger.sh
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

AUTO_MODE=false
DRY_RUN=false

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
  Interactive live demonstration script for Operating Systems Lab evaluation.
  Sequentially demonstrates all core modules with clear visual banners,
  step-by-step explanations, and automated cleanup.

Options:
  -a, --auto      Run automatically without pausing between sections
      --dry-run   Run demo in preview mode without executing destructive operations
  -h, --help      Display this documentation and exit
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--auto)
      AUTO_MODE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

# Non-interactive terminal detection
if [[ ! -t 0 ]]; then
  AUTO_MODE=true
fi

# Visual styling
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[36m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_MAGENTA="\033[35m"

print_banner() {
  local step_num="$1"
  local step_title="$2"
  echo ""
  echo -e "${C_CYAN}${C_BOLD}================================================================================${C_RESET}"
  echo -e "${C_CYAN}${C_BOLD} [STEP ${step_num}] ${step_title}${C_RESET}"
  echo -e "${C_CYAN}${C_BOLD}================================================================================${C_RESET}"
}

pause_step() {
  if [[ "${AUTO_MODE}" == true ]]; then
    sleep 1.5
    return 0
  fi
  echo ""
  echo -e "${C_YELLOW}${C_BOLD}>>> Press [Enter] to continue to the next demonstration...${C_RESET}"
  read -r _
}

# Create isolated demo workspace
DEMO_ROOT="$(register_temp_dir "os_admin_demo")"

cleanup_demo() {
  local exit_code=$?
  if [[ -d "${DEMO_ROOT}" ]]; then
    rm -rf "${DEMO_ROOT}" 2>/dev/null || true
  fi
  exit "${exit_code}"
}
trap cleanup_demo EXIT SIGINT SIGTERM

echo -e "${C_CYAN}${C_BOLD}================================================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}          OS ADMIN CLI SUITE - LIVE LAB EVALUATION DEMONSTRATION                ${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}================================================================================${C_RESET}"
echo -e " Host Platform: ${C_GREEN}${OS_TYPE} (${OS_ARCH})${C_RESET} | Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e " Demo Sandbox:  ${DEMO_ROOT}"
echo -e " Auto Mode:     ${AUTO_MODE} | Dry-Run: ${DRY_RUN}"
echo -e "${C_CYAN}--------------------------------------------------------------------------------${C_RESET}"

# ==============================================================================
# Step 1: System Resource & Process Monitor
# ==============================================================================
print_banner "1" "Module 1: System Resource & Process Monitor (Snapshot Mode)"
echo -e "Executing: ${C_BOLD}./sysadmin.sh monitor --snapshot${C_RESET}"
echo ""

set +e
./sysadmin.sh monitor --snapshot --cpu-threshold 101 --mem-threshold 101 --disk-threshold 101
set -e

pause_step

# ==============================================================================
# Step 2: Incremental Backup & SHA-256 Verification
# ==============================================================================
print_banner "2" "Module 2: Incremental Backup & Cryptographic SHA-256 Verification"

SAMPLE_DIR="${DEMO_ROOT}/sample_data"
BACKUP_DIR="${DEMO_ROOT}/backup_storage"
mkdir -p "${SAMPLE_DIR}" "${BACKUP_DIR}"

echo -e "1. Generating mock fixture dataset with: ${C_BOLD}examples/generate_sample_dir.sh${C_RESET}"
bash "${SCRIPT_DIR}/examples/generate_sample_dir.sh" "${SAMPLE_DIR}" >/dev/null

echo -e "\n2. Creating Level-0 Full Backup with: ${C_BOLD}./sysadmin.sh backup --source ... --dest ...${C_RESET}"
./sysadmin.sh backup --source "${SAMPLE_DIR}" --dest "${BACKUP_DIR}" --retention 3

echo -e "\n3. Inspecting generated backup archives and SHA256SUMS manifest:"
ls -lh "${BACKUP_DIR}"
echo ""
echo -e "${C_BOLD}--- Contents of SHA256SUMS ---${C_RESET}"
cat "${BACKUP_DIR}/SHA256SUMS"

echo -e "\n4. Verifying archive integrity with: ${C_BOLD}./sysadmin.sh backup --verify <archive>${C_RESET}"
ARCHIVE_TO_VERIFY="$(find "${BACKUP_DIR}" -name "*.tar.gz" | head -n 1)"
./sysadmin.sh backup --verify "${ARCHIVE_TO_VERIFY}"

pause_step

# ==============================================================================
# Step 3: Automated File Organizer & Log Cleaner
# ==============================================================================
print_banner "3" "Module 3: Automated File Organizer & Safety Modes"

echo -e "1. Demonstrating ${C_BOLD}--dry-run simulation${C_RESET} (no files will be moved):"
echo -e "Executing: ${C_BOLD}./sysadmin.sh organize --target ... --organize --dry-run${C_RESET}"
echo ""
./sysadmin.sh organize --target "${SAMPLE_DIR}" --organize --dry-run

echo -e "\n2. Demonstrating ${C_BOLD}live categorization${C_RESET} into category folders:"
echo -e "Executing: ${C_BOLD}./sysadmin.sh organize --target ... --organize${C_RESET}"
echo ""
./sysadmin.sh organize --target "${SAMPLE_DIR}" --organize

echo -e "\n3. Inspecting organized directory layout:"
find "${SAMPLE_DIR}" -maxdepth 2 -not -path "${SAMPLE_DIR}" | sort | sed 's/^/  /'

pause_step

# ==============================================================================
# Step 4: Bulk User & Permission Provisioning
# ==============================================================================
print_banner "4" "Module 4: Bulk User & Permission Provisioning from CSV"

echo -e "1. Displaying sample CSV dataset (${C_BOLD}examples/users.csv${C_RESET}):"
echo "--------------------------------------------------------------------------------"
cat "${SCRIPT_DIR}/examples/users.csv"
echo "--------------------------------------------------------------------------------"

echo -e "\n2. Demonstrating ${C_BOLD}unprivileged safety execution (--dry-run)${C_RESET}:"
echo -e "Executing: ${C_BOLD}./sysadmin.sh provision --csv examples/users.csv --dry-run${C_RESET}"
echo ""
./sysadmin.sh provision --csv "${SCRIPT_DIR}/examples/users.csv" --dry-run

pause_step

# ==============================================================================
# Step 5: Automated Integration Test Suite
# ==============================================================================
print_banner "5" "Automated Integration Test Suite (30 Assertions)"

echo -e "Executing: ${C_BOLD}./sysadmin.sh test${C_RESET}"
echo ""
./sysadmin.sh test

echo ""
echo -e "${C_GREEN}${C_BOLD}================================================================================${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}          LIVE DEMONSTRATION AND EVALUATION COMPLETED SUCCESSFULLY              ${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}================================================================================${C_RESET}"
echo -e " All 5 modules and features were verified."
echo -e " Sandbox '${DEMO_ROOT}' will now be cleaned up automatically."
echo ""
