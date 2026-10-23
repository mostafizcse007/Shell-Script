#!/usr/bin/env bash
# ==============================================================================
# Module 3: Automated File Organizer & Log Cleaner with Quarantine Safety
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

# Source shared libraries
# shellcheck source=lib/logger.sh
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

# Default configuration
TARGET_DIR="."
DO_ORGANIZE=false
DO_CLEAN_LOGS=false
OLDER_THAN_DAYS=14
MAX_SIZE_MB=50
QUARANTINE_DIR=""
DRY_RUN=false

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
  Automatically organizes loose files into categorized directories by file
  extension, and purges or compresses stale log files based on age and size.

Options:
  -t, --target PATH       Directory to organize or inspect for logs (default: .)
  -o, --organize          Sort loose files into category folders (Docs, Images, etc.)
  -c, --clean-logs        Find and clean .log files matching age and size criteria
      --older-than DAYS   Purge/quarantine log files older than DAYS (default: 14)
      --max-size MB       Compress log files exceeding MB megabytes (default: 50)
  -q, --quarantine PATH   Move purged files to quarantine directory instead of deleting
      --dry-run           Simulate all actions without modifying, moving, or deleting files
  -h, --help              Display this documentation and exit

Categories:
  Documents:  pdf, doc, docx, txt, md, rtf, odt, xls, xlsx, ppt, pptx, csv
  Images:     png, jpg, jpeg, gif, bmp, svg, webp, ico
  Media:      mp4, mkv, avi, mov, mp3, wav, flac, aac
  Archives:   zip, tar, gz, bz2, xz, 7z, rar, tgz
  Code:       c, cpp, h, py, sh, js, ts, html, css, java, go, rs, json, yaml, yml
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)
      TARGET_DIR="${2:-.}"
      shift 2
      ;;
    -o|--organize)
      DO_ORGANIZE=true
      shift
      ;;
    -c|--clean-logs)
      DO_CLEAN_LOGS=true
      shift
      ;;
    --older-than)
      OLDER_THAN_DAYS="${2:-14}"
      shift 2
      ;;
    --max-size)
      MAX_SIZE_MB="${2:-50}"
      shift 2
      ;;
    -q|--quarantine)
      QUARANTINE_DIR="${2:-}"
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

if [[ "${DO_ORGANIZE}" == false && "${DO_CLEAN_LOGS}" == false ]]; then
  log_error "No action specified. Please pass --organize, --clean-logs, or both."
  show_help
  exit 1
fi

if [[ ! -d "${TARGET_DIR}" ]]; then
  log_error "Target directory does not exist: ${TARGET_DIR}"
  exit 1
fi

TARGET_DIR="$(cd -- "${TARGET_DIR}" &>/dev/null && pwd)"

# ==============================================================================
# File Extension Classification Map
# ==============================================================================
get_category() {
  local ext
  ext="$(echo "$1" | tr '[:upper:]' '[:lower:]')"

  case "${ext}" in
    pdf|doc|docx|txt|md|rtf|odt|xls|xlsx|ppt|pptx|csv)
      echo "Documents"
      ;;
    png|jpg|jpeg|gif|bmp|svg|webp|ico)
      echo "Images"
      ;;
    mp4|mkv|avi|mov|mp3|wav|flac|aac)
      echo "Media"
      ;;
    zip|tar|gz|bz2|xz|7z|rar|tgz)
      echo "Archives"
      ;;
    c|cpp|h|py|sh|js|ts|html|css|java|go|rs|json|yaml|yml)
      echo "Code"
      ;;
    *)
      echo "Miscellaneous"
      ;;
  esac
}

# ==============================================================================
# Feature A: File Organization
# ==============================================================================
organize_files() {
  log_info "Scanning '${TARGET_DIR}' for files to organize..."
  local moved_count=0

  # Category directory names to avoid recursing into them
  local ignored_dirs=("Documents" "Images" "Media" "Archives" "Code" "Miscellaneous" ".git" ".agents" "lib" "logs" "modules" "tests" "examples")

  while IFS= read -r -d '' file_path; do
    if [[ ! -f "${file_path}" ]]; then
      continue
    fi

    local file_name
    file_name="$(basename "${file_path}")"
    local file_ext="${file_name##*.}"
    if [[ "${file_name}" == "${file_ext}" ]]; then
      file_ext=""
    fi

    local category
    category="$(get_category "${file_ext}")"
    local dest_dir="${TARGET_DIR}/${category}"
    local dest_file="${dest_dir}/${file_name}"

    # Handle collision
    if [[ -e "${dest_file}" ]]; then
      local base_name="${file_name%.*}"
      dest_file="${dest_dir}/${base_name}_$(date '+%Y%m%d%H%M%S').${file_ext}"
    fi

    if [[ "${DRY_RUN}" == true ]]; then
      log_info "[DRY-RUN] Would move: '${file_name}' -> '${category}/$(basename "${dest_file}")'"
    else
      mkdir -p "${dest_dir}"
      mv "${file_path}" "${dest_file}"
      log_info "Moved: '${file_name}' -> '${category}/$(basename "${dest_file}")'"
    fi
    (( moved_count++ )) || true
  done < <(find "${TARGET_DIR}" -maxdepth 1 -type f -print0)

  log_info "File organization completed. Total files processed: ${moved_count}"
}

# ==============================================================================
# Feature B: Log Cleaner with Age & Size Pruning
# ==============================================================================
clean_logs() {
  log_info "Scanning '${TARGET_DIR}' for .log files (Thresholds: >${OLDER_THAN_DAYS} days, >${MAX_SIZE_MB} MB)..."
  local cleaned_count=0
  local compressed_count=0

  if [[ -n "${QUARANTINE_DIR}" ]]; then
    mkdir -p "${QUARANTINE_DIR}" 2>/dev/null || true
    QUARANTINE_DIR="$(cd -- "${QUARANTINE_DIR}" &>/dev/null && pwd)"
    log_info "Quarantine staging enabled: '${QUARANTINE_DIR}'"
  fi

  local current_epoch
  current_epoch="$(date '+%s')"
  local age_limit_seconds=$(( OLDER_THAN_DAYS * 86400 ))
  local max_size_bytes=$(( MAX_SIZE_MB * 1024 * 1024 ))

  while IFS= read -r -d '' log_file; do
    if [[ ! -f "${log_file}" ]]; then
      continue
    fi

    local file_name
    file_name="$(basename "${log_file}")"
    local file_size
    file_size="$(get_file_size "${log_file}")"
    local file_mtime
    file_mtime="$(get_file_mtime "${log_file}")"
    local file_age_seconds=$(( current_epoch - file_mtime ))

    # 1. Age Pruning Check
    if (( file_age_seconds >= age_limit_seconds )); then
      local age_days=$(( file_age_seconds / 86400 ))
      if [[ -n "${QUARANTINE_DIR}" ]]; then
        local q_dest="${QUARANTINE_DIR}/${file_name}"
        if [[ "${DRY_RUN}" == true ]]; then
          log_info "[DRY-RUN] Stale log (${age_days} days old): Would quarantine '${file_name}' -> '${q_dest}'"
        else
          mv "${log_file}" "${q_dest}"
          log_info "Quarantined stale log (${age_days} days old): '${file_name}' -> '${q_dest}'"
        fi
      else
        if [[ "${DRY_RUN}" == true ]]; then
          log_info "[DRY-RUN] Stale log (${age_days} days old): Would delete '${file_name}'"
        else
          rm -f "${log_file}"
          log_info "Deleted stale log (${age_days} days old): '${file_name}'"
        fi
      fi
      (( cleaned_count++ )) || true
      continue
    fi

    # 2. Size Check (Compress if exceeding limit)
    if (( file_size >= max_size_bytes )); then
      local size_mb=$(( file_size / 1024 / 1024 ))
      if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Oversized log (${size_mb} MB): Would compress '${file_name}' to '${file_name}.gz'"
      else
        log_info "Compressing oversized log (${size_mb} MB): '${file_name}'"
        gzip -f "${log_file}"
      fi
      (( compressed_count++ )) || true
    fi
  done < <(find "${TARGET_DIR}" -type f -name "*.log" -print0)

  log_info "Log cleaning finished. Stale logs purged/quarantined: ${cleaned_count}, Oversized logs compressed: ${compressed_count}"
}

# Execution
if [[ "${DO_ORGANIZE}" == true ]]; then
  organize_files
fi

if [[ "${DO_CLEAN_LOGS}" == true ]]; then
  clean_logs
fi

log_info "Organizer & Log Cleaner finished successfully."
