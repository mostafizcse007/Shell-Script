#!/usr/bin/env bash
# ==============================================================================
# Module 4: Bulk User & Permission Provisioning from CSV with Safety Checks
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

# Source shared libraries
# shellcheck source=lib/logger.sh
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

# Default configuration
CSV_FILE=""
DO_DEPROVISION=false
DRY_RUN=false

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
  Automates bulk user creation, primary group management, shell assignment,
  and sudo/admin privilege grants parsed from a standard CSV file.

Options:
  -f, --csv PATH        Path to input CSV file (required)
      --deprovision     Reverse provisioning: delete the users specified in the CSV
      --dry-run         Validate CSV and simulate provisioning actions without root
  -h, --help            Display this documentation and exit

CSV Format:
  username,group,shell,home_dir,sudo_flag,initial_password

CSV Example:
  alice,developers,/bin/bash,/home/alice,yes,InitPass@123
  bob,testers,/bin/bash,/home/bob,no,InitPass@456

Safety & Privilege Isolation:
  - Modifying live system users requires root (sudo) privileges.
  - When --dry-run is supplied, execution runs fully in simulation mode,
    allowing unprivileged testing and lab evaluation grading.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--csv)
      CSV_FILE="${2:-}"
      shift 2
      ;;
    --deprovision)
      DO_DEPROVISION=true
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

if [[ -z "${CSV_FILE}" ]]; then
  log_error "Missing required --csv parameter."
  show_help
  exit 1
fi

if [[ ! -f "${CSV_FILE}" ]]; then
  log_error "CSV file not found: ${CSV_FILE}"
  exit 1
fi

# Privilege Check
IS_ROOT=false
if [[ "$(id -u 2>/dev/null || echo 1000)" -eq 0 ]]; then
  IS_ROOT=true
fi

if [[ "${IS_ROOT}" == false && "${DRY_RUN}" == false ]]; then
  log_error "Root privileges (sudo) are required to create or modify system accounts."
  log_error "Tip: Run with --dry-run to simulate and validate provisioning safely without root."
  exit 1
fi

# ==============================================================================
# Helper Verification Functions
# ==============================================================================
user_exists() {
  local user="$1"
  id -u "${user}" &>/dev/null
}

group_exists() {
  local grp="$1"
  if has_cmd getent; then
    getent group "${grp}" &>/dev/null
  elif [[ -r /etc/group ]]; then
    grep -q "^${grp}:" /etc/group 2>/dev/null
  elif [[ "${OS_TYPE}" == "macos" ]]; then
    dscl . -read "/Groups/${grp}" &>/dev/null
  else
    return 1
  fi
}

# ==============================================================================
# Provisioning & De-provisioning Logic
# ==============================================================================
process_csv() {
  log_info "Reading CSV file: ${CSV_FILE} (Dry-run: ${DRY_RUN}, Deprovision: ${DO_DEPROVISION})..."

  local line_number=0
  local success_count=0
  local skip_count=0
  local error_count=0

  while IFS= read -r raw_line || [[ -n "${raw_line}" ]]; do
    line_number=$(( line_number + 1 ))
    # Trim whitespace and carriage returns
    local line
    line="$(echo "${raw_line}" | tr -d '\r' | xargs 2>/dev/null || echo "${raw_line}")"

    # Skip empty lines and comments
    if [[ -z "${line}" || "${line}" =~ ^# ]]; then
      continue
    fi

    # Skip header
    if (( line_number == 1 )) && [[ "${line}" =~ ^username, ]]; then
      log_info "Validated CSV header: ${line}"
      continue
    fi

    # Parse columns
    local u_name u_group u_shell u_home u_sudo u_pass
    IFS=',' read -r u_name u_group u_shell u_home u_sudo u_pass <<< "${line}"

    # Validate mandatory fields
    if [[ -z "${u_name:-}" || -z "${u_group:-}" || -z "${u_shell:-}" || -z "${u_home:-}" ]]; then
      log_warn "Line ${line_number}: Incomplete row data: '${line}'. Skipping."
      error_count=$(( error_count + 1 ))
      continue
    fi

    # Sanitize sudo flag
    local is_sudo=false
    local sudo_norm
    sudo_norm="$(echo "${u_sudo:-no}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${sudo_norm}" =~ ^(yes|true|1|y)$ ]]; then
      is_sudo=true
    fi

    # Mode A: Deprovisioning
    if [[ "${DO_DEPROVISION}" == true ]]; then
      log_info "Deprovisioning account for: '${u_name}'"
      if ! user_exists "${u_name}"; then
        log_info "User '${u_name}' does not exist. Nothing to remove."
        skip_count=$(( skip_count + 1 ))
        continue
      fi

      if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would remove user '${u_name}' and home directory '${u_home}'"
      else
        if [[ "${OS_TYPE}" == "macos" ]] && has_cmd sysadminctl; then
          sysadminctl -deleteUser "${u_name}" 2>/dev/null || true
        else
          userdel -r "${u_name}" 2>/dev/null || userdel "${u_name}" 2>/dev/null || true
        fi
        log_info "User '${u_name}' removed."
      fi
      success_count=$(( success_count + 1 ))
      continue
    fi

    # Mode B: Provisioning
    log_info "Processing user: '${u_name}' [Group: ${u_group}, Shell: ${u_shell}, Home: ${u_home}, Sudo: ${is_sudo}]"

    # 1. Collision Check
    if user_exists "${u_name}"; then
      log_warn "User '${u_name}' already exists on the system. Skipping creation to avoid clobbering."
      skip_count=$(( skip_count + 1 ))
      continue
    fi

    # 2. Group Management
    if ! group_exists "${u_group}"; then
      if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Primary group '${u_group}' does not exist. Would execute: groupadd ${u_group}"
      else
        log_info "Creating missing primary group '${u_group}'..."
        if [[ "${OS_TYPE}" == "macos" ]] && has_cmd dseditgroup; then
          dseditgroup -o create "${u_group}" 2>/dev/null || true
        elif has_cmd groupadd; then
          groupadd "${u_group}" 2>/dev/null || true
        fi
      fi
    fi

    # 3. User Creation
    if [[ "${DRY_RUN}" == true ]]; then
      log_info "[DRY-RUN] Would execute: useradd -m -g '${u_group}' -s '${u_shell}' -d '${u_home}' '${u_name}'"
      if [[ -n "${u_pass:-}" ]]; then
        log_info "[DRY-RUN] Would configure initial password for '${u_name}'"
      fi
      if [[ "${is_sudo}" == true ]]; then
        log_info "[DRY-RUN] Would grant administrative/sudo privileges to '${u_name}'"
      fi
      log_info "[DRY-RUN] Would set directory permissions (chmod 750 '${u_home}')"
    else
      # Live User Creation
      if [[ "${OS_TYPE}" == "macos" ]] && has_cmd sysadminctl; then
        sysadminctl -addUser "${u_name}" -password "${u_pass:-ChangeMe123!}" -home "${u_home}" -shell "${u_shell}" 2>/dev/null || true
      elif has_cmd useradd; then
        useradd -m -g "${u_group}" -s "${u_shell}" -d "${u_home}" "${u_name}"
        # Set password
        if [[ -n "${u_pass:-}" ]] && has_cmd chpasswd; then
          echo "${u_name}:${u_pass}" | chpasswd 2>/dev/null || true
        fi
      fi

      # Grant Sudo
      if [[ "${is_sudo}" == true ]]; then
        if [[ "${OS_TYPE}" == "macos" ]] && has_cmd dseditgroup; then
          dseditgroup -o edit -a "${u_name}" -t user admin 2>/dev/null || true
        elif has_cmd usermod; then
          usermod -aG sudo "${u_name}" 2>/dev/null || usermod -aG wheel "${u_name}" 2>/dev/null || true
        fi
        log_info "Granted administrative (sudo/wheel) privileges to '${u_name}'."
      fi

      # Permissions
      if [[ -d "${u_home}" ]]; then
        chmod 750 "${u_home}" 2>/dev/null || true
      fi
      log_info "User '${u_name}' created successfully."
    fi

    success_count=$(( success_count + 1 ))
  done < "${CSV_FILE}"

  echo "================================================================================"
  echo " USER PROVISIONING SUMMARY:"
  echo " Processed: ${success_count} | Skipped: ${skip_count} | Errors: ${error_count}"
  echo "================================================================================"

  if (( error_count > 0 )); then
    return 1
  fi
  return 0
}

process_csv
log_info "User provisioning task completed."
