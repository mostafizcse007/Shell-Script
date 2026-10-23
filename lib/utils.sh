#!/usr/bin/env bash
set -euo pipefail
# Shared platform utilities, coreutils normalization, and system abstraction

# Prevent double-sourcing
if [[ -n "${_LIB_UTILS_SH_INCLUDED:-}" ]]; then
  return 0
fi
_LIB_UTILS_SH_INCLUDED=1

# Ensure logger is loaded
_LIB_UTILS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [[ -f "${_LIB_UTILS_DIR}/logger.sh" ]]; then
  # shellcheck source=lib/logger.sh
  source "${_LIB_UTILS_DIR}/logger.sh"
fi

# ==============================================================================
# OS Platform Detection
# ==============================================================================
detect_os() {
  local uname_s
  uname_s="$(uname -s 2>/dev/null || echo "Unknown")"

  case "${uname_s}" in
    Linux*)
      echo "linux"
      ;;
    Darwin*)
      echo "macos"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "windows_gitbash"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

OS_TYPE="$(detect_os)"
OS_ARCH="$(uname -m 2>/dev/null || echo "unknown")"
export OS_TYPE OS_ARCH

# ==============================================================================
# Command & Utility Verification
# ==============================================================================
has_cmd() {
  command -v "$1" &>/dev/null
}

# ==============================================================================
# Coreutils Normalization
# ==============================================================================

# Calculate SHA-256 hash of a file
calculate_sha256() {
  local target_file="$1"
  if [[ ! -f "${target_file}" ]]; then
    log_error "calculate_sha256: File not found: ${target_file}"
    return 1
  fi

  if has_cmd sha256sum; then
    sha256sum "${target_file}" | awk '{print $1}'
  elif has_cmd shasum; then
    shasum -a 256 "${target_file}" | awk '{print $1}'
  elif has_cmd openssl; then
    openssl dgst -sha256 "${target_file}" | awk '{print $NF}'
  else
    log_error "No SHA-256 utility (sha256sum, shasum, or openssl) found in PATH."
    return 1
  fi
}

# Get file size in bytes
get_file_size() {
  local target_file="$1"
  if [[ ! -e "${target_file}" ]]; then
    echo "0"
    return 0
  fi

  if [[ "${OS_TYPE}" == "macos" ]]; then
    stat -f %z "${target_file}" 2>/dev/null || wc -c < "${target_file}" | tr -d ' '
  else
    stat -c %s "${target_file}" 2>/dev/null || wc -c < "${target_file}" | tr -d ' '
  fi
}

# Get file modification time in epoch seconds
get_file_mtime() {
  local target_file="$1"
  if [[ ! -e "${target_file}" ]]; then
    echo "0"
    return 0
  fi

  if [[ "${OS_TYPE}" == "macos" ]]; then
    stat -f %m "${target_file}" 2>/dev/null || echo "0"
  else
    stat -c %Y "${target_file}" 2>/dev/null || echo "0"
  fi
}

# Format epoch seconds to YYYY-MM-DD HH:MM:SS
format_epoch() {
  local epoch="$1"
  if [[ "${OS_TYPE}" == "macos" ]]; then
    date -r "${epoch}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S'
  else
    date -d "@${epoch}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S'
  fi
}

# ==============================================================================
# Cross-Platform System Metrics
# ==============================================================================

# Returns CPU usage percentage (e.g. "12.5" or "15")
get_cpu_usage() {
  case "${OS_TYPE}" in
    linux)
      if [[ -r /proc/stat ]]; then
        # Read two samples of /proc/stat 0.4s apart
        local cpu1 idle1 total1 cpu2 idle2 total2
        read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
        idle1=$((idle + iowait))
        total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
        sleep 0.4
        read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
        idle2=$((idle + iowait))
        total2=$((user + nice + system + idle + iowait + irq + softirq + steal))

        local diff_idle=$((idle2 - idle1))
        local diff_total=$((total2 - total1))
        if (( diff_total > 0 )); then
          awk -v dt="${diff_total}" -v di="${diff_idle}" 'BEGIN { printf "%.1f", (100 * (dt - di) / dt) }'
          return 0
        fi
      fi
      # Fallback to top or vmstat
      if has_cmd top; then
        top -bn1 2>/dev/null | grep -E "Cpu\(s\)" | awk '{print $2 + $4}' || echo "0.0"
      else
        echo "0.0"
      fi
      ;;
    macos)
      if has_cmd top; then
        top -l 1 -n 0 2>/dev/null | awk '/CPU usage/ { gsub(/%/, "", $3); gsub(/%/, "", $5); print $3 + $5 }' || echo "0.0"
      else
        echo "0.0"
      fi
      ;;
    windows_gitbash)
      # Use PowerShell Get-CimInstance for accurate hardware metrics on Windows
      if has_cmd powershell.exe; then
        local psh_cpu
        psh_cpu="$(powershell.exe -NoProfile -NonInteractive -Command "(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average" 2>/dev/null | tr -d '\r\n ')"
        if [[ -n "${psh_cpu}" && "${psh_cpu}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          printf "%.1f\n" "${psh_cpu}"
          return 0
        fi
      fi
      # Fallback to loadavg if present in /proc
      if [[ -r /proc/loadavg ]]; then
        awk '{print $1 * 10}' /proc/loadavg 2>/dev/null || echo "0.0"
      else
        echo "0.0"
      fi
      ;;
    *)
      echo "0.0"
      ;;
  esac
}

# Returns: "<total_mb> <used_mb> <free_mb> <percent_used>"
get_memory_metrics() {
  case "${OS_TYPE}" in
    linux)
      if [[ -r /proc/meminfo ]]; then
        local total_kb avail_kb used_kb
        total_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
        avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
        if [[ -z "${avail_kb}" ]]; then
          local free_kb buffers_kb cached_kb
          free_kb="$(awk '/MemFree:/ {print $2}' /proc/meminfo)"
          buffers_kb="$(awk '/Buffers:/ {print $2}' /proc/meminfo)"
          cached_kb="$(awk '/^Cached:/ {print $2}' /proc/meminfo)"
          avail_kb=$((free_kb + buffers_kb + cached_kb))
        fi
        used_kb=$((total_kb - avail_kb))
        local total_mb=$((total_kb / 1024))
        local used_mb=$((used_kb / 1024))
        local free_mb=$((avail_kb / 1024))
        local pct
        pct="$(awk -v u="${used_mb}" -v t="${total_mb}" 'BEGIN { if (t > 0) printf "%.1f", (u/t)*100; else print "0.0" }')"
        echo "${total_mb} ${used_mb} ${free_mb} ${pct}"
        return 0
      fi
      echo "0 0 0 0.0"
      ;;
    macos)
      local total_bytes
      total_bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
      local total_mb=$((total_bytes / 1024 / 1024))
      local free_pages page_size
      page_size="$(vm_stat 2>/dev/null | awk '/page size of/ {print $8}')"
      page_size="${page_size:-4096}"
      free_pages="$(vm_stat 2>/dev/null | awk '/Pages free:/ {gsub(/\./, "", $3); print $3}')"
      free_pages="${free_pages:-0}"
      local free_mb=$(( (free_pages * page_size) / 1024 / 1024 ))
      local used_mb=$((total_mb - free_mb))
      local pct
      pct="$(awk -v u="${used_mb}" -v t="${total_mb}" 'BEGIN { if (t > 0) printf "%.1f", (u/t)*100; else print "0.0" }')"
      echo "${total_mb} ${used_mb} ${free_mb} ${pct}"
      ;;
    windows_gitbash)
      if has_cmd powershell.exe; then
        local psh_mem
        psh_mem="$(powershell.exe -NoProfile -NonInteractive -Command "
          \$os = Get-CimInstance Win32_OperatingSystem;
          \$tot = [math]::Round(\$os.TotalVisibleMemorySize / 1024, 0);
          \$free = [math]::Round(\$os.FreePhysicalMemory / 1024, 0);
          \$used = \$tot - \$free;
          \$pct = [math]::Round((\$used / \$tot) * 100, 1);
          Write-Output \"\$tot \$used \$free \$pct\"
        " 2>/dev/null | tr -d '\r')"
        if [[ -n "${psh_mem}" ]]; then
          echo "${psh_mem}"
          return 0
        fi
      fi
      echo "0 0 0 0.0"
      ;;
    *)
      echo "0 0 0 0.0"
      ;;
  esac
}

# Returns disk metrics for target path: "<total_human> <used_human> <avail_human> <percent_num> <mount_point>"
get_disk_metrics() {
  local target_path="${1:-.}"
  if [[ ! -e "${target_path}" ]]; then
    target_path="."
  fi

  # df -Pk outputs POSIX standard 1-line format in 1024-byte blocks
  local df_line
  df_line="$(df -Pk "${target_path}" 2>/dev/null | tail -n 1)"
  if [[ -n "${df_line}" ]]; then
    local total_k used_k avail_k pct_str mount
    total_k="$(echo "${df_line}" | awk '{print $2}')"
    used_k="$(echo "${df_line}" | awk '{print $3}')"
    avail_k="$(echo "${df_line}" | awk '{print $4}')"
    pct_str="$(echo "${df_line}" | awk '{print $5}' | tr -d '%')"
    mount="$(echo "${df_line}" | awk '{print $6}')"

    # Format human readable
    local total_h used_h avail_h
    total_h="$(awk -v k="${total_k}" 'BEGIN { if (k >= 1048576) printf "%.1fG", k/1048576; else printf "%.0fM", k/1024 }')"
    used_h="$(awk -v k="${used_k}" 'BEGIN { if (k >= 1048576) printf "%.1fG", k/1048576; else printf "%.0fM", k/1024 }')"
    avail_h="$(awk -v k="${avail_k}" 'BEGIN { if (k >= 1048576) printf "%.1fG", k/1048576; else printf "%.0fM", k/1024 }')"

    echo "${total_h} ${used_h} ${avail_h} ${pct_str} ${mount}"
    return 0
  fi
  echo "0G 0G 0G 0 /"
}

# Returns top processes table by CPU usage
get_top_processes() {
  local count="${1:-5}"
  if [[ "${OS_TYPE}" == "macos" ]]; then
    ps aux -r 2>/dev/null | head -n "$((count + 1))"
  else
    # Linux & Git Bash
    ps aux 2>/dev/null | sort -k3 -nr | head -n "$((count + 1))"
  fi
}

# ==============================================================================
# Desktop Notifications Fallback
# ==============================================================================
send_desktop_notification() {
  local title="$1"
  local message="$2"

  if [[ "${OS_TYPE}" == "linux" ]] && has_cmd notify-send; then
    notify-send "${title}" "${message}" 2>/dev/null || true
  elif [[ "${OS_TYPE}" == "macos" ]] && has_cmd osascript; then
    osascript -e "display notification \"${message}\" with title \"${title}\"" 2>/dev/null || true
  elif [[ "${OS_TYPE}" == "windows_gitbash" ]] && has_cmd powershell.exe; then
    powershell.exe -NoProfile -NonInteractive -Command "
      [void] [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms');
      \$notify = New-Object System.Windows.Forms.NotifyIcon;
      \$notify.Icon = [System.Drawing.SystemIcons]::Information;
      \$notify.BalloonTipTitle = '${title}';
      \$notify.BalloonTipText = '${message}';
      \$notify.Visible = \$True;
      \$notify.ShowBalloonTip(3000);
    " 2>/dev/null || true
  fi
}

# ==============================================================================
# Temporary Directory & Cleanup Trap Management
# ==============================================================================
_REGISTERED_TEMP_DIRS=()

register_temp_dir() {
  local prefix="${1:-sysadmin}"
  local tmp_dir
  tmp_dir="$(mktemp -d -t "${prefix}-XXXXXX" 2>/dev/null || mktemp -d 2>/dev/null)"
  _REGISTERED_TEMP_DIRS+=("${tmp_dir}")
  echo "${tmp_dir}"
}

cleanup_temp_dirs() {
  local exit_code=$?
  for dir in "${_REGISTERED_TEMP_DIRS[@]:-}"; do
    if [[ -d "${dir}" ]]; then
      rm -rf "${dir}" 2>/dev/null || true
    fi
  done
  exit "${exit_code}"
}

trap cleanup_temp_dirs EXIT SIGINT SIGTERM
