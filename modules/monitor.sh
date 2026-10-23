#!/usr/bin/env bash
# ==============================================================================
# Module 1: System Resource & Process Monitor with Threshold Alerts
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

# Source shared libraries
# shellcheck source=lib/logger.sh
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

# Default configuration
MODE="snapshot"
INTERVAL=3
CPU_THRESHOLD=80
MEM_THRESHOLD=85
DISK_THRESHOLD=90
TOP_N=5
TARGET_PATH="."
DRY_RUN=false

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
  Monitors system resources (CPU, Memory, Swap, Disk) and active processes,
  providing one-shot diagnostic snapshots or continuous monitoring with
  configurable threshold alerts.

Options:
  -s, --snapshot            Run a one-shot system diagnostic report (default)
  -w, --watch [SECONDS]     Run in continuous watch mode (default: 3 seconds)
  -c, --cpu-threshold NUM   Alert if CPU usage exceeds NUM% (default: 80)
  -m, --mem-threshold NUM   Alert if Memory usage exceeds NUM% (default: 85)
  -d, --disk-threshold NUM  Alert if Disk usage exceeds NUM% (default: 90)
  -n, --top-n COUNT         Number of top resource-consuming processes (default: 5)
  -t, --target PATH         Directory/mount point to inspect for disk usage (default: .)
      --dry-run             Simulate monitoring and alert detection without triggering notifications
  -h, --help                Display this documentation and exit

Exit Status:
  0  All metrics normal or within thresholds
  1  One or more resource thresholds were breached
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--snapshot)
      MODE="snapshot"
      shift
      ;;
    -w|--watch)
      MODE="watch"
      if [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]]; then
        INTERVAL="$2"
        shift 2
      else
        shift
      fi
      ;;
    -c|--cpu-threshold)
      CPU_THRESHOLD="${2:-80}"
      shift 2
      ;;
    -m|--mem-threshold)
      MEM_THRESHOLD="${2:-85}"
      shift 2
      ;;
    -d|--disk-threshold)
      DISK_THRESHOLD="${2:-90}"
      shift 2
      ;;
    -n|--top-n)
      TOP_N="${2:-5}"
      shift 2
      ;;
    -t|--target)
      TARGET_PATH="${2:-.}"
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

# Render diagnostic metrics and evaluate thresholds
check_metrics() {
  local has_breach=0
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  local hostname_str
  hostname_str="$(hostname 2>/dev/null || echo "localhost")"

  # Gather metrics via lib/utils.sh
  local cpu_pct
  cpu_pct="$(get_cpu_usage)"
  
  local mem_info
  mem_info="$(get_memory_metrics)"
  local mem_total mem_used mem_free mem_pct
  read -r mem_total mem_used mem_free mem_pct <<< "${mem_info}"

  local disk_info
  disk_info="$(get_disk_metrics "${TARGET_PATH}")"
  local disk_total disk_used disk_avail disk_pct disk_mount
  read -r disk_total disk_used disk_avail disk_pct disk_mount <<< "${disk_info}"

  # Header
  echo "================================================================================"
  echo " SYSTEM RESOURCE & PROCESS MONITOR - ${timestamp}"
  echo " Host: ${hostname_str} | Platform: ${OS_TYPE} (${OS_ARCH})"
  echo "================================================================================"

  # CPU Display & Threshold
  local cpu_status="OK"
  local cpu_int="${cpu_pct%.*}"
  cpu_int="${cpu_int:-0}"
  if (( cpu_int >= CPU_THRESHOLD )); then
    cpu_status="BREACH (>=${CPU_THRESHOLD}%)"
    has_breach=1
  fi
  printf " [CPU]    Usage: %5s%%  | Threshold: %2d%% | Status: %s\n" \
    "${cpu_pct}" "${CPU_THRESHOLD}" "${cpu_status}"

  # Memory Display & Threshold
  local mem_status="OK"
  local mem_int="${mem_pct%.*}"
  mem_int="${mem_int:-0}"
  if (( mem_int >= MEM_THRESHOLD )); then
    mem_status="BREACH (>=${MEM_THRESHOLD}%)"
    has_breach=1
  fi
  printf " [MEMORY] Used: %s MB / %s MB (%s%%) | Free: %s MB | Status: %s\n" \
    "${mem_used}" "${mem_total}" "${mem_pct}" "${mem_free}" "${mem_status}"

  # Disk Display & Threshold
  local disk_status="OK"
  local disk_int="${disk_pct%.*}"
  disk_int="${disk_int:-0}"
  if (( disk_int >= DISK_THRESHOLD )); then
    disk_status="BREACH (>=${DISK_THRESHOLD}%)"
    has_breach=1
  fi
  printf " [DISK]   Mount: %s | Used: %s / %s (%s%%) | Free: %s | Status: %s\n" \
    "${disk_mount}" "${disk_used}" "${disk_total}" "${disk_pct}" "${disk_avail}" "${disk_status}"

  echo "--------------------------------------------------------------------------------"
  echo " TOP ${TOP_N} PROCESSES (BY CPU USAGE):"
  echo "--------------------------------------------------------------------------------"
  get_top_processes "${TOP_N}"
  echo "================================================================================"

  # Handle Alerts
  if (( has_breach == 1 )); then
    local alert_msg="Resource threshold breach on ${hostname_str} - CPU: ${cpu_pct}%, MEM: ${mem_pct}%, DISK: ${disk_pct}%"
    if [[ "${DRY_RUN}" == true ]]; then
      log_warn "[DRY-RUN] Threshold breach detected. Simulated alert: ${alert_msg}"
    else
      log_error "THRESHOLD ALERT: ${alert_msg}"
      send_desktop_notification "OS Admin Alert" "${alert_msg}"
    fi
    return 1
  fi

  return 0
}

# Main Execution
if [[ "${MODE}" == "watch" ]]; then
  log_info "Starting continuous monitoring every ${INTERVAL}s (Press Ctrl+C to stop)..."
  while true; do
    clear 2>/dev/null || printf "\033[2J\033[H"
    check_metrics || true
    sleep "${INTERVAL}"
  done
else
  # Snapshot mode
  if [[ "${DRY_RUN}" == true ]]; then
    log_info "Running monitor diagnostic in DRY-RUN mode..."
  fi
  if check_metrics; then
    exit 0
  else
    exit 1
  fi
fi
