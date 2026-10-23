#!/usr/bin/env bash
# ==============================================================================
# Module 2: Incremental Backup & Rotation Manager with SHA-256 Verification
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

# Source shared libraries
# shellcheck source=lib/logger.sh
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

# Default configuration
SOURCE_DIR=""
DEST_DIR=""
RETENTION=5
VERIFY_TARGET=""
FORCE_FULL=false
DRY_RUN=false

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
  Automates incremental and full directory backups with automated SHA-256
  checksum generation, archive verification, and chain-safe rotation.

Options:
  -s, --source PATH       Source directory to back up (required for backup)
  -d, --dest PATH         Destination directory for backup archives (required for backup)
  -r, --retention NUM     Maximum number of backup chains to retain (default: 5)
      --full              Force creation of a new Level-0 (full) base backup
  -v, --verify ARCHIVE    Verify SHA-256 checksum and tar integrity of an archive
      --dry-run           Simulate backup, manifest, and rotation without writing files
  -h, --help              Display this documentation and exit

Safety Guarantee:
  Level-0 base backups are never deleted while dependent incremental backups
  in their chain still exist. Older chains are only pruned when complete newer
  chains exceed the retention limit.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--source)
      SOURCE_DIR="${2:-}"
      shift 2
      ;;
    -d|--dest)
      DEST_DIR="${2:-}"
      shift 2
      ;;
    -r|--retention)
      RETENTION="${2:-5}"
      shift 2
      ;;
    --full)
      FORCE_FULL=true
      shift
      ;;
    -v|--verify)
      VERIFY_TARGET="${2:-}"
      shift 2
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

# ==============================================================================
# Archive Verification Subcommand
# ==============================================================================
verify_archive() {
  local archive_path="$1"
  if [[ ! -f "${archive_path}" ]]; then
    log_error "Archive file not found: ${archive_path}"
    return 1
  fi

  local archive_dir
  archive_dir="$(cd -- "$(dirname -- "${archive_path}")" &>/dev/null && pwd)"
  local archive_name
  archive_name="$(basename "${archive_path}")"
  local manifest_file="${archive_dir}/SHA256SUMS"

  log_info "Verifying archive: ${archive_name}..."

  # 1. Test Tar Integrity
  if ! tar -tzf "${archive_path}" &>/dev/null; then
    log_error "INTEGRITY FAILURE: Archive ${archive_name} is corrupted or not a valid gzip tarball."
    return 1
  fi
  log_info "Tar archive internal structure: VALID"

  # 2. Check SHA-256 Checksum
  local computed_hash
  computed_hash="$(calculate_sha256 "${archive_path}")"
  log_info "Computed SHA-256: ${computed_hash}"

  if [[ -f "${manifest_file}" ]]; then
    local recorded_hash
    recorded_hash="$(grep -F "${archive_name}" "${manifest_file}" 2>/dev/null | awk '{print $1}' | tail -n 1)"
    if [[ -n "${recorded_hash}" ]]; then
      if [[ "${computed_hash}" == "${recorded_hash}" ]]; then
        log_info "SHA-256 Manifest Match: VALID (Matches ${manifest_file})"
      else
        log_error "CHECKSUM MISMATCH! Recorded: ${recorded_hash} != Computed: ${computed_hash}"
        return 1
      fi
    else
      log_warn "Archive '${archive_name}' not found in ${manifest_file}. Cannot cross-verify against manifest."
    fi
  else
    log_warn "Manifest file ${manifest_file} not found. Checksum calculated but not cross-referenced."
  fi

  log_info "Verification PASSED for ${archive_name}."
  return 0
}

if [[ -n "${VERIFY_TARGET}" ]]; then
  if verify_archive "${VERIFY_TARGET}"; then
    exit 0
  else
    exit 1
  fi
fi

# ==============================================================================
# Backup Execution Flow
# ==============================================================================
if [[ -z "${SOURCE_DIR}" || -z "${DEST_DIR}" ]]; then
  log_error "Both --source and --dest are required to perform a backup."
  show_help
  exit 1
fi

if [[ ! -d "${SOURCE_DIR}" ]]; then
  log_error "Source directory does not exist: ${SOURCE_DIR}"
  exit 1
fi

if [[ "${DRY_RUN}" == false ]]; then
  mkdir -p "${DEST_DIR}" 2>/dev/null || true
  if [[ ! -d "${DEST_DIR}" ]]; then
    log_error "Destination directory could not be created or is not writable: ${DEST_DIR}"
    exit 1
  fi
fi

# Resolve absolute paths
SOURCE_DIR="$(cd -- "${SOURCE_DIR}" &>/dev/null && pwd)"
if [[ -d "${DEST_DIR}" ]]; then
  DEST_DIR="$(cd -- "${DEST_DIR}" &>/dev/null && pwd)"
else
  # Pre-resolve parent path if dest does not exist yet under dry-run
  DEST_PARENT="$(cd -- "$(dirname "${DEST_DIR}")" &>/dev/null && pwd || echo "")"
  if [[ -n "${DEST_PARENT}" ]]; then
    DEST_DIR="${DEST_PARENT}/$(basename "${DEST_DIR}")"
  fi
fi

# Detect Tar Engine (GNU vs BSD)
IS_GNU_TAR=false
if tar --version 2>&1 | grep -iq "gnu"; then
  IS_GNU_TAR=true
fi

SNAR_FILE="${DEST_DIR}/.snapshot.snar"
MTIME_FILE="${DEST_DIR}/.last_backup_mtime"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"

# Determine Backup Level
BACKUP_LEVEL="L1"
if [[ "${FORCE_FULL}" == true ]]; then
  BACKUP_LEVEL="L0"
elif [[ "${IS_GNU_TAR}" == true && ! -f "${SNAR_FILE}" ]]; then
  BACKUP_LEVEL="L0"
elif [[ "${IS_GNU_TAR}" == false && ! -f "${MTIME_FILE}" ]]; then
  BACKUP_LEVEL="L0"
fi

SOURCE_BASE="$(basename "${SOURCE_DIR}")"
ARCHIVE_NAME="backup_${SOURCE_BASE}_${BACKUP_LEVEL}_${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${DEST_DIR}/${ARCHIVE_NAME}"
MANIFEST_FILE="${DEST_DIR}/SHA256SUMS"

log_info "Preparing ${BACKUP_LEVEL} backup of '${SOURCE_DIR}' -> '${ARCHIVE_PATH}'..."

# Pre-scan files
TMP_DIR="$(register_temp_dir "backup")"
FILE_LIST="${TMP_DIR}/files_to_pack.txt"

if [[ "${BACKUP_LEVEL}" == "L0" ]]; then
  log_info "Creating Level-0 (Full) Base Backup..."
else
  log_info "Creating Level-1 Incremental Backup..."
fi

if [[ "${DRY_RUN}" == true ]]; then
  log_info "[DRY-RUN] Would create archive: ${ARCHIVE_PATH}"
  if [[ "${IS_GNU_TAR}" == true ]]; then
    log_info "[DRY-RUN] Engine: GNU Tar (Snapshot SNAR: ${SNAR_FILE})"
  else
    log_info "[DRY-RUN] Engine: BSD Tar fallback (Mtime tracker: ${MTIME_FILE})"
  fi
  log_info "[DRY-RUN] Would compute SHA-256 and register in ${MANIFEST_FILE}"
else
  # Live Execution
  if [[ "${BACKUP_LEVEL}" == "L0" ]]; then
    if [[ "${IS_GNU_TAR}" == true ]]; then
      rm -f "${SNAR_FILE}"
      tar --create --gzip \
        --listed-incremental="${SNAR_FILE}" \
        --file="${ARCHIVE_PATH}" \
        -C "$(dirname "${SOURCE_DIR}")" "${SOURCE_BASE}"
    else
      # BSD Tar fallback
      tar -czf "${ARCHIVE_PATH}" -C "$(dirname "${SOURCE_DIR}")" "${SOURCE_BASE}"
      touch "${MTIME_FILE}"
    fi
  else
    # Incremental (L1)
    if [[ "${IS_GNU_TAR}" == true ]]; then
      tar --create --gzip \
        --listed-incremental="${SNAR_FILE}" \
        --file="${ARCHIVE_PATH}" \
        -C "$(dirname "${SOURCE_DIR}")" "${SOURCE_BASE}"
    else
      # BSD Tar fallback: find files modified since last mtime
      find "${SOURCE_DIR}" -type f -newer "${MTIME_FILE}" > "${FILE_LIST}"
      if [[ ! -s "${FILE_LIST}" ]]; then
        log_info "No modified files detected since last backup. Creating empty incremental snapshot."
      fi
      tar -czf "${ARCHIVE_PATH}" -C "$(dirname "${SOURCE_DIR}")" -T "${FILE_LIST}" "${SOURCE_BASE}" 2>/dev/null || \
      tar -czf "${ARCHIVE_PATH}" -C "$(dirname "${SOURCE_DIR}")" "${SOURCE_BASE}"
      touch "${MTIME_FILE}"
    fi
  fi

  # Calculate & Record Checksum
  CHECKSUM="$(calculate_sha256 "${ARCHIVE_PATH}")"
  echo "${CHECKSUM}  ${ARCHIVE_NAME}" >> "${MANIFEST_FILE}"
  log_info "Backup created successfully: ${ARCHIVE_NAME} (Size: $(get_file_size "${ARCHIVE_PATH}") bytes)"
  log_info "SHA-256 Registered: ${CHECKSUM}"
fi

# ==============================================================================
# Chain-Safe Retention & Rotation Manager
# ==============================================================================
rotate_backups() {
  log_info "Evaluating retention policies (Limit: ${RETENTION} backup chains)..."

  # Find all Level-0 archives
  local l0_archives=()
  while IFS= read -r archive; do
    if [[ -n "${archive}" ]]; then
      l0_archives+=("${archive}")
    fi
  done < <(find "${DEST_DIR}" -maxdepth 1 -name "backup_${SOURCE_BASE}_L0_*.tar.gz" 2>/dev/null | sort)

  local total_l0="${#l0_archives[@]}"
  log_info "Found ${total_l0} Level-0 base backup chain(s)."

  if (( total_l0 <= RETENTION )); then
    log_info "Backup count (${total_l0}) is within retention limit (${RETENTION}). No rotation needed."
    return 0
  fi

  local to_prune_count=$(( total_l0 - RETENTION ))
  log_info "Pruning ${to_prune_count} oldest backup chain(s)..."

  for (( i=0; i<to_prune_count; i++ )); do
    local base_l0="${l0_archives[i]}"
    local base_ts
    base_ts="$(basename "${base_l0}" | sed -E "s/^backup_${SOURCE_BASE}_L0_([0-9_]+)\.tar\.gz/\1/")"

    # Find the next L0 archive timestamp if any to establish chain boundary
    local next_ts="99999999_999999"
    if (( i + 1 < total_l0 )); then
      next_ts="$(basename "${l0_archives[i+1]}" | sed -E "s/^backup_${SOURCE_BASE}_L0_([0-9_]+)\.tar\.gz/\1/")"
    fi

    # Find all L1 incremental backups belonging to this L0 chain
    local dependent_l1=()
    while IFS= read -r inc_file; do
      if [[ -n "${inc_file}" ]]; then
        local inc_ts
        inc_ts="$(basename "${inc_file}" | sed -E "s/^backup_${SOURCE_BASE}_L1_([0-9_]+)\.tar\.gz/\1/")"
        if [[ "${inc_ts}" > "${base_ts}" && "${inc_ts}" < "${next_ts}" ]]; then
          dependent_l1+=("${inc_file}")
        fi
      fi
    done < <(find "${DEST_DIR}" -maxdepth 1 -name "backup_${SOURCE_BASE}_L1_*.tar.gz" 2>/dev/null | sort)

    # Prune dependent incrementals FIRST
    for inc_archive in "${dependent_l1[@]:-}"; do
      if [[ -f "${inc_archive}" ]]; then
        if [[ "${DRY_RUN}" == true ]]; then
          log_info "[DRY-RUN] Would prune dependent incremental: $(basename "${inc_archive}")"
        else
          log_info "Pruning dependent incremental: $(basename "${inc_archive}")"
          rm -f "${inc_archive}"
          # Remove from SHA256SUMS
          if [[ -f "${MANIFEST_FILE}" ]]; then
            sed -i.bak "/$(basename "${inc_archive}")/d" "${MANIFEST_FILE}" 2>/dev/null || true
            rm -f "${MANIFEST_FILE}.bak" 2>/dev/null || true
          fi
        fi
      fi
    done

    # Prune the base Level-0 archive
    if [[ -f "${base_l0}" ]]; then
      if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Would prune Level-0 base archive: $(basename "${base_l0}")"
      else
        log_info "Pruning Level-0 base archive: $(basename "${base_l0}")"
        rm -f "${base_l0}"
        if [[ -f "${MANIFEST_FILE}" ]]; then
          sed -i.bak "/$(basename "${base_l0}")/d" "${MANIFEST_FILE}" 2>/dev/null || true
          rm -f "${MANIFEST_FILE}.bak" 2>/dev/null || true
        fi
      fi
    fi
  done

  log_info "Rotation completed successfully."
}

rotate_backups
log_info "Backup job finished successfully."
