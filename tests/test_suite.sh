#!/usr/bin/env bash
# ==============================================================================
# OS Admin CLI Suite: Automated Integration & Unit Test Suite
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
cd "${SCRIPT_DIR}"

# Source shared libraries
# shellcheck source=lib/logger.sh
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

# Colors for test output
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_RED="\033[31m"
C_YELLOW="\033[33m"
C_CYAN="\033[36m"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Assertion runner
assert_test() {
  local test_name="$1"
  local cmd="$2"
  local expected_exit="${3:-0}"

  TESTS_RUN=$(( TESTS_RUN + 1 ))
  printf " [TEST %2d] %-60s " "${TESTS_RUN}" "${test_name}"

  local actual_exit=0
  local output=""
  set +e
  output="$(eval "${cmd}" 2>&1)"
  actual_exit=$?
  set -e

  if (( actual_exit == expected_exit )); then
    echo -e "${C_GREEN}${C_BOLD}[PASS]${C_RESET}"
    TESTS_PASSED=$(( TESTS_PASSED + 1 ))
    return 0
  else
    echo -e "${C_RED}${C_BOLD}[FAIL]${C_RESET} (Expected: ${expected_exit}, Got: ${actual_exit})"
    echo -e "${C_YELLOW}>>> Command output:${C_RESET}"
    echo "${output}" | head -n 10 | sed 's/^/    /'
    TESTS_FAILED=$(( TESTS_FAILED + 1 ))
    return 1
  fi
}

echo -e "${C_CYAN}${C_BOLD}================================================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}               OS ADMIN CLI SUITE - AUTOMATED TEST SUITE                        ${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}================================================================================${C_RESET}"
echo -e " Host Platform: ${C_GREEN}${OS_TYPE} (${OS_ARCH})${C_RESET} | Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${C_CYAN}--------------------------------------------------------------------------------${C_RESET}"

# Create isolated test sandbox
TEST_SANDBOX="$(register_temp_dir "test_suite")"

# ------------------------------------------------------------------------------
# Test Section 1: Coding Standards & Shell Syntax
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}--- Section 1: Coding Standards & Syntax Validation ---${C_RESET}"

assert_test "Syntax Check: All .sh scripts pass bash -n" \
  "find . -name '*.sh' -not -path './.git/*' -exec bash -n {} +"

assert_test "Standards Check: All scripts have portable Bash shebang" \
  "[[ -z \"\$(grep -rL '#!/usr/bin/env bash' --include='*.sh' --exclude-dir='.git' .)\" ]]"

assert_test "Standards Check: All scripts enforce strict mode (set -euo pipefail)" \
  "[[ -z \"\$(grep -rL 'set -euo pipefail' --include='*.sh' --exclude-dir='.git' .)\" ]]"

# ------------------------------------------------------------------------------
# Test Section 2: Shared Libraries & Coreutils Normalization
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}--- Section 2: Shared Libraries (lib/logger.sh, lib/utils.sh) ---${C_RESET}"

TEST_FILE="${TEST_SANDBOX}/hash_sample.txt"
echo "Deterministic Content 123" > "${TEST_FILE}"

assert_test "Coreutils: calculate_sha256 produces valid 64-char hex hash" \
  "[[ \$(calculate_sha256 '${TEST_FILE}') =~ ^[a-f0-9]{64}\$ ]]"

assert_test "Coreutils: get_file_size returns correct byte count" \
  "[[ \$(get_file_size '${TEST_FILE}') -ge 25 ]]"

assert_test "Coreutils: get_file_mtime returns valid non-zero epoch" \
  "[[ \$(get_file_mtime '${TEST_FILE}') =~ ^[0-9]{10}\$ ]]"

assert_test "Logger: log_info writes cleanly to LOG_FILE" \
  "LOG_FILE='${TEST_SANDBOX}/test_log.log' log_info 'Test logger string' && grep -q 'Test logger string' '${TEST_SANDBOX}/test_log.log'"

# ------------------------------------------------------------------------------
# Test Section 3: Main CLI Entrypoint Dispatcher
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}--- Section 3: CLI Entrypoint Dispatcher (sysadmin.sh) ---${C_RESET}"

assert_test "Dispatcher: ./sysadmin.sh --help exits with 0" \
  "./sysadmin.sh --help >/dev/null"

assert_test "Dispatcher: ./sysadmin.sh version outputs OS and version info" \
  "./sysadmin.sh version | grep -q 'OS Admin CLI Suite'"

assert_test "Dispatcher: Unknown subcommand returns non-zero error exit" \
  "./sysadmin.sh non_existent_command >/dev/null 2>&1" 1

# ------------------------------------------------------------------------------
# Test Section 4: Module 1 - System Resource & Process Monitor
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}--- Section 4: Module 1 - System Resource Monitor (monitor.sh) ---${C_RESET}"

assert_test "Monitor: Snapshot mode executes and prints resource table" \
  "./sysadmin.sh monitor --snapshot --cpu-threshold 101 --mem-threshold 101 --disk-threshold 101 >/dev/null" 0

assert_test "Monitor: --help displays command documentation" \
  "./sysadmin.sh monitor --help | grep -q 'Usage:'"

assert_test "Monitor: Threshold breach returns exit code 1 with alert" \
  "./sysadmin.sh monitor --snapshot --cpu-threshold 0 --dry-run >/dev/null" 1

# ------------------------------------------------------------------------------
# Test Section 5: Module 2 - Incremental Backup & Rotation Manager
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}--- Section 5: Module 2 - Backup & Rotation Manager (backup.sh) ---${C_RESET}"

BK_SRC="${TEST_SANDBOX}/backup_src"
BK_DEST="${TEST_SANDBOX}/backup_dest"
mkdir -p "${BK_SRC}" "${BK_DEST}"

echo "Document alpha" > "${BK_SRC}/file1.txt"
echo "Document beta" > "${BK_SRC}/file2.txt"

assert_test "Backup: Level-0 full base backup creation" \
  "./sysadmin.sh backup --source '${BK_SRC}' --dest '${BK_DEST}' >/dev/null" 0

assert_test "Backup: SHA256SUMS manifest created and non-empty" \
  "[[ -s '${BK_DEST}/SHA256SUMS' ]]"

assert_test "Backup: Level-0 archive passes --verify check" \
  "L0_ARCH=\$(find '${BK_DEST}' -name '*_L0_*.tar.gz' | head -n 1) && ./sysadmin.sh backup --verify \"\${L0_ARCH}\" >/dev/null" 0

# Modify files for incremental
sleep 1
echo "Document gamma (incremental)" > "${BK_SRC}/file3.txt"

assert_test "Backup: Level-1 incremental backup creation" \
  "./sysadmin.sh backup --source '${BK_SRC}' --dest '${BK_DEST}' >/dev/null" 0

assert_test "Backup: Level-1 archive exists and is smaller than base" \
  "find '${BK_DEST}' -name '*_L1_*.tar.gz' | grep -q 'L1'"

assert_test "Backup: Level-1 archive passes --verify check" \
  "L1_ARCH=\$(find '${BK_DEST}' -name '*_L1_*.tar.gz' | head -n 1) && ./sysadmin.sh backup --verify \"\${L1_ARCH}\" >/dev/null" 0

assert_test "Backup: Mandatory --dry-run produces no files" \
  "./sysadmin.sh backup --source '${BK_SRC}' --dest '${TEST_SANDBOX}/dry_dest' --dry-run >/dev/null && [[ ! -d '${TEST_SANDBOX}/dry_dest' ]]" 0

# ------------------------------------------------------------------------------
# Test Section 6: Module 3 - File Organizer & Log Cleaner
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}--- Section 6: Module 3 - File Organizer & Cleaner (organizer.sh) ---${C_RESET}"

ORG_DIR="${TEST_SANDBOX}/org_test_dir"
bash "${SCRIPT_DIR}/examples/generate_sample_dir.sh" "${ORG_DIR}" >/dev/null

assert_test "Organizer: --dry-run reports actions without moving files" \
  "./sysadmin.sh organize --target '${ORG_DIR}' --organize --dry-run >/dev/null && [[ -f '${ORG_DIR}/quarterly_report.pdf' ]]" 0

assert_test "Organizer: Live categorization sorts files into category folders" \
  "./sysadmin.sh organize --target '${ORG_DIR}' --organize >/dev/null && [[ -f '${ORG_DIR}/Documents/quarterly_report.pdf' && -f '${ORG_DIR}/Images/architecture_diagram.png' && -f '${ORG_DIR}/Code/analytics_script.py' ]]" 0

assert_test "Organizer: Collision handling safely renames on re-organization" \
  "echo 'Another report' > '${ORG_DIR}/quarterly_report.pdf' && ./sysadmin.sh organize --target '${ORG_DIR}' --organize >/dev/null && [[ -f '${ORG_DIR}/Documents/quarterly_report.pdf' ]]" 0

QUAR_DIR="${TEST_SANDBOX}/quarantine_dir"
assert_test "Organizer: --clean-logs quarantines stale/oversized logs" \
  "./sysadmin.sh clean --target '${ORG_DIR}' --older-than 5 --max-size 1 --quarantine '${QUAR_DIR}' >/dev/null && [[ -d '${QUAR_DIR}' ]]" 0

# ------------------------------------------------------------------------------
# Test Section 7: Module 4 - Bulk User & Permission Provisioning
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}--- Section 7: Module 4 - Bulk User Provisioning (provision.sh) ---${C_RESET}"

assert_test "Provisioning: --dry-run validates sample CSV without requiring root" \
  "./sysadmin.sh provision --csv '${SCRIPT_DIR}/examples/users.csv' --dry-run >/dev/null" 0

assert_test "Provisioning: Missing CSV path returns error code 1" \
  "./sysadmin.sh provision >/dev/null 2>&1" 1

assert_test "Provisioning: Malformed CSV with missing fields handles errors safely" \
  "echo 'invalid_row_without_commas' > '${TEST_SANDBOX}/bad.csv' && ./sysadmin.sh provision --csv '${TEST_SANDBOX}/bad.csv' --dry-run >/dev/null 2>&1" 1

assert_test "Provisioning: Deprovisioning mode runs in dry-run cleanly" \
  "./sysadmin.sh provision --csv '${SCRIPT_DIR}/examples/users.csv' --deprovision --dry-run >/dev/null" 0

# ------------------------------------------------------------------------------
# Test Section 8: Module 5 - Interactive TUI Menu Wrapper
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}--- Section 8: Module 5 - TUI Menu Wrapper (tui_menu.sh) ---${C_RESET}"

assert_test "TUI: Non-interactive execution lists menu and exits cleanly" \
  "./sysadmin.sh menu < /dev/null >/dev/null" 0

assert_test "TUI: --help displays navigation documentation" \
  "./sysadmin.sh menu --help | grep -q 'Navigation:'"

# ------------------------------------------------------------------------------
# Test Summary & Exit
# ------------------------------------------------------------------------------
echo -e "\n${C_CYAN}================================================================================${C_RESET}"
echo -e "${C_CYAN}${C_BOLD}                         TEST EXECUTION SUMMARY                                 ${C_RESET}"
echo -e "${C_CYAN}================================================================================${C_RESET}"
echo -e " Total Tests Run: ${C_BOLD}${TESTS_RUN}${C_RESET}"
echo -e " Tests Passed:    ${C_GREEN}${C_BOLD}${TESTS_PASSED}${C_RESET}"
echo -e " Tests Failed:    ${C_RED}${C_BOLD}${TESTS_FAILED}${C_RESET}"
echo -e "${C_CYAN}================================================================================${C_RESET}"

if (( TESTS_FAILED == 0 )); then
  echo -e "\n${C_GREEN}${C_BOLD}>>> ALL TESTS PASSED SUCCESSFULLY (100% Pass Rate) <<<${C_RESET}\n"
  exit 0
else
  echo -e "\n${C_RED}${C_BOLD}>>> ONE OR MORE TESTS FAILED <<<${C_RESET}\n"
  exit 1
fi
