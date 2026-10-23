#!/usr/bin/env bash
set -euo pipefail
# Shared logging library for OS Project shell scripts

# Prevent double-sourcing
if [[ -n "${_LIB_LOGGER_SH_INCLUDED:-}" ]]; then
  return 0
fi
_LIB_LOGGER_SH_INCLUDED=1

# Determine log file destination
_LOG_DIR="./logs"
if [[ -w "/var/log" ]]; then
  _LOG_DIR="/var/log"
fi
mkdir -p "${_LOG_DIR}" 2>/dev/null || true

# Default to sysadmin.log unless overridden by LOG_FILE
LOG_FILE="${LOG_FILE:-${_LOG_DIR}/sysadmin.log}"

# Colors for interactive TTY
if [[ -t 2 ]]; then
  COLOR_RESET="\033[0m"
  COLOR_INFO="\033[0;32m"   # Green
  COLOR_WARN="\033[0;33m"   # Yellow
  COLOR_ERROR="\033[0;31m"  # Red
  COLOR_DEBUG="\033[0;36m"  # Cyan
else
  COLOR_RESET=""
  COLOR_INFO=""
  COLOR_WARN=""
  COLOR_ERROR=""
  COLOR_DEBUG=""
fi

_log_write() {
  local level="$1"
  local color="$2"
  shift 2
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  local message="$*"

  # Formatted console output to stderr
  printf "%b[%s]%b [%s] %s\n" "${color}" "${level}" "${COLOR_RESET}" "${timestamp}" "${message}" >&2

  # Clean plain output appended to log file
  if [[ -n "${LOG_FILE:-}" ]]; then
    printf "[%s] [%s] %s\n" "${level}" "${timestamp}" "${message}" >> "${LOG_FILE}" 2>/dev/null || true
  fi
}

log_info()  { _log_write "INFO"  "${COLOR_INFO}"  "$@"; }
log_warn()  { _log_write "WARN"  "${COLOR_WARN}"  "$@"; }
log_error() { _log_write "ERROR" "${COLOR_ERROR}" "$@"; }
log_debug() {
  if [[ "${DEBUG:-0}" == "1" || "${VERBOSE:-0}" == "1" ]]; then
    _log_write "DEBUG" "${COLOR_DEBUG}" "$@";
  fi
}
