#!/usr/bin/env bash
set -uo pipefail

TOOL_VERSION="1.0.0-rc1"
MODE="full"
NO_INSTALL=0
REDACT=1
REPORT_DIR="${PWD}"
DISTRO_ID="unknown"
DISTRO_NAME="Unknown Linux"
DISTRO_FAMILY="unknown"
PACKAGE_MANAGER="unknown"
INIT_SYSTEM="unknown"
RAW_HOST="$(hostname 2>/dev/null || echo unknown)"

usage() {
  cat <<EOF
System Diagnostic Tool v${TOOL_VERSION}
Usage: sudo $0 [options]
  --quick             Fast general diagnostic
  --full              Complete diagnostic (default)
  --memory            Memory, swap and pressure
  --storage           Storage, filesystem, SMART/NVMe
  --network           Network, Wi-Fi and DNS
  --no-install        Do not install missing dependencies
  --no-redact         Include identifying values in report
  --report-dir DIR    Report output directory
  --help              Show this help
EOF
}

while (($#)); do
  case "$1" in
    --quick|--full|--memory|--storage|--network) MODE="${1#--}" ;;
    --no-install) NO_INSTALL=1 ;;
    --no-redact) REDACT=0 ;;
    --report-dir) shift; [[ $# -gt 0 ]] || { echo "Missing --report-dir value" >&2; exit 2; }; REPORT_DIR="$1" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

mkdir -p "$REPORT_DIR" || exit 1
STAMP="$(date +%Y%m%d_%H%M%S)"
REPORT_HOST="$RAW_HOST"
[[ $REDACT -eq 1 ]] && REPORT_HOST="redacted"
REPORT="${REPORT_DIR%/}/system-diagnostic_${REPORT_HOST}_${STAMP}.txt"

section() { printf '\n==============================================================================\n%s\n==============================================================================\n' "$1"; }
subsection() { printf '\n--- %s ---\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
run() { printf '\n$ %s\n' "$*"; "$@" 2>&1 || printf '[INFO] command exited with status %s\n' "$?"; }

redact_stream() {
  if [[ $REDACT -eq 0 ]]; then cat; return; fi
  sed -E \
    -e 's/([Ss]erial [Nn]umber:|[Ss]erial:)[[:space:]]*[^[:space:]]+/\1 <redacted>/g' \
    -e 's/(UUID:)[[:space:]]*[^[:space:]]+/\1 <redacted>/g' \
    -e 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/<redacted-mac>/g' \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<redacted-ip>/g' \
    -e 's#(/home/)[^/[:space:]]+#\1<redacted-user>#g' \
    -e "s/${RAW_HOST//\//\\/}/<redacted-host>/g"
}

exec > >(redact_stream | tee -a "$REPORT") 2>&1

detect_platform() {
  if [[ -r /etc/os-release ]]; then
    local os_id os_name os_like
    os_id="$(. /etc/os-release; printf '%s' "${ID:-unknown}")"
    os_name="$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-${NAME:-Unknown Linux}}")"
    os_like="$(. /etc/os-release; printf '%s' "${ID_LIKE:-}")"
    DISTRO_ID="$os_id"; DISTRO_NAME="$os_name"
    case "${os_id} ${os_like}" in
      *debian*|*ubuntu*) DISTRO_FAMILY="debian" ;;
      *fedora*|*rhel*|*centos*) DISTRO_FAMILY="rhel" ;;
      *arch*) DISTRO_FAMILY="arch" ;;
      *suse*) DISTRO_FAMILY="suse" ;;
      *alpine*) DISTRO_FAMILY="alpine" ;;
    esac
  fi
  for pm in apt-get dnf yum pacman zypper apk; do have "$pm" && { PACKAGE_MANAGER="$pm"; break; }; done
  if have systemctl && [[ -d /run/systemd/system ]]; then INIT_SYSTEM="systemd"; elif have rc-service; then INIT_SYSTEM="openrc"; fi
}

package_for() {
  case "${PACKAGE_MANAGER}:$1" in
    apt-get:sensors) echo lm-sensors ;; dnf:sensors|yum:sensors|pacman:sensors) echo lm_sensors ;; zypper:sensors) echo sensors ;; apk:sensors) echo lm-sensors ;;
    *:smartctl) echo smartmontools ;; *:nvme) echo nvme-cli ;; *:lspci) echo pciutils ;; *:lsusb) echo usbutils ;;
    *:iw) echo iw ;; *:dmidecode) echo dmidecode ;; *) return 1 ;;
  esac
}

install_package() {
  local pkg="$1"
  [[ $NO_INSTALL -eq 0 && $EUID -eq 0 ]] || return 1
  case "$PACKAGE_MANAGER" in
    apt-get) apt-get update >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" ;;
    dnf) dnf install -y "$pkg" ;; yum) yum install -y "$pkg" ;; pacman) pacman -Sy --needed --noconfirm "$pkg" ;;
    zypper) zypper --non-interactive install "$pkg" ;; apk) apk add "$pkg" ;; *) return 1 ;;
  esac
}

ensure_command() {
  local cmd="$1" cap="${2:-$1}" pkg
  have "$cmd" && return 0
  pkg="$(package_for "$cap" 2>/dev/null || true)"
  [[ -n "$pkg" ]] && install_package "$pkg" >/dev/null 2>&1 || true
  have "$cmd"
}

basic() {
  section "SYSTEM / PLATFORM"
  echo "Tool version    : $TOOL_VERSION"
  echo "Distribution    : $DISTRO_NAME"
  echo "Family          : $DISTRO_FAMILY"
  echo "Package manager : $PACKAGE_MANAGER"
  echo "Init system     : $INIT_SYSTEM"
  echo "Architecture    : $(uname -m)"
  echo "Kernel          : $(uname -r)"
  echo "Hostname        : $RAW_HOST"
  echo "Privacy mode    : $([[ $REDACT -eq 1 ]] && echo enabled || echo disabled)"
  echo "Mode            : $MODE"
  run uptime
  section "CPU / HARDWARE"
  have lscpu && run lscpu
  ensure_command lspci lspci && run lspci -nn
  ensure_command lsusb lsusb && run lsusb
  if ensure_command dmidecode dmidecode && [[ $EUID -eq 0 ]]; then run dmidecode -t system; run dmidecode -t memory; fi
}

memory_diag() {
  section "MEMORY / SWAP"; run free -h; have swapon && run swapon --show; have sysctl && run sysctl vm.swappiness
  subsection "Top processes by memory"; ps -eo pid,user,comm,%cpu,%mem,rss --sort=-rss 2>/dev/null | head -n 25 || true
  if have vmstat; then subsection "vmstat (2s x 10)"; run vmstat 2 10; fi
  subsection "Pressure Stall Information"
  for f in /proc/pressure/memory /proc/pressure/cpu /proc/pressure/io; do [[ -r "$f" ]] && { echo "$f"; cat "$f"; }; done
  if [[ "$INIT_SYSTEM" == systemd ]] && have journalctl; then
    subsection "OOM / memory events"
    journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'Out of memory:|oom-kill:|Killed process [0-9]+|Memory cgroup out of memory' | tail -n 50 || true
  fi
}

smart_report() {
  local disk="$1" output rc health
  set +e; output="$(smartctl -a "$disk" 2>&1)"; rc=$?; set -e 2>/dev/null || true
  printf '%s\n' "$output"
  health="$(printf '%s\n' "$output" | grep -Ei 'SMART overall-health.*(PASSED|OK)|SMART Health Status: OK' | head -1 || true)"
  if [[ -n "$health" ]]; then echo "[OK] SMART overall health passed (smartctl status=$rc; unsupported optional logs may set non-zero bits)."
  elif (( rc & 8 || rc & 16 || rc & 32 || rc & 64 || rc & 128 )); then echo "[WARNING] SMART reports a device/attribute error (status=$rc)."
  else echo "[INFO] SMART completed with status=$rc."; fi
}

storage_diag() {
  section "STORAGE / FILESYSTEM"
  if have lsblk; then subsection "Block devices (loop devices excluded)"; lsblk -e 7 -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,MODEL; fi
  run df -hT; run df -ih
  subsection "SMART"
  if ensure_command smartctl smartctl; then while read -r disk; do [[ -n "$disk" ]] && { echo; echo "### $disk"; smart_report "$disk"; }; done < <(lsblk -dpno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}'); else echo "smartctl unavailable."; fi
  subsection "NVMe"; if ensure_command nvme nvme; then run nvme list; else echo "nvme-cli unavailable."; fi
  if [[ "$INIT_SYSTEM" == systemd ]] && have journalctl; then
    subsection "Storage error events"
    journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'I/O error|medium error|uncorrectable|nvme.*(error|critical|timeout|reset)|EXT4-fs error|BTRFS.*error|XFS.*error' | tail -n 100 || true
  fi
}

temperature_battery() {
  section "TEMPERATURES"; if ensure_command sensors sensors; then run sensors; else echo "sensors unavailable."; fi
  subsection "Thermal zones"
  local z type temp p found=0
  for z in /sys/class/thermal/thermal_zone*; do [[ -d "$z" ]] || continue; type="$(cat "$z/type" 2>/dev/null || echo unknown)"; temp="$(cat "$z/temp" 2>/dev/null || true)"; [[ "$temp" =~ ^[0-9]+$ ]] && awk -v z="$z" -v t="$type" -v v="$temp" 'BEGIN{printf "%s | %s | %.1f C\n",z,t,v/1000}'; done
  section "BATTERY / POWER"
  for p in /sys/class/power_supply/*; do [[ -d "$p" ]] || continue; [[ "$(cat "$p/type" 2>/dev/null || true)" == Battery ]] || continue; found=1; echo "Battery: $(basename "$p")"; for f in manufacturer model_name status capacity cycle_count energy_now energy_full energy_full_design charge_now charge_full charge_full_design voltage_now charge_control_end_threshold; do [[ -r "$p/$f" ]] && printf '%-30s %s\n' "$f:" "$(cat "$p/$f")"; done; done
  [[ $found -eq 1 ]] || echo "No battery detected (normal for desktops/servers)."
}

network_diag() {
  section "NETWORK"; have ip && run ip -brief address; have ip && run ip route; have nmcli && run nmcli device status
  subsection "Wi-Fi"; if ensure_command iw iw; then run iw dev; else echo "iw unavailable or no Wi-Fi tooling."; fi
  if have resolvectl; then run resolvectl status; elif [[ -r /etc/resolv.conf ]]; then cat /etc/resolv.conf; fi
  subsection "Connectivity"; have ping && run ping -c 4 -W 2 1.1.1.1
  if [[ "$INIT_SYSTEM" == systemd ]] && have journalctl; then
    subsection "Network/Wi-Fi noteworthy events"
    journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'iwlwifi.*(Unhandled alg|error|fail|timeout|microcode)|deauth|disassoc|disconnected|firmware.*(fail|error)' | tail -n 100 || true
  fi
}

system_logs() {
  section "SYSTEM HEALTH"
  if [[ "$INIT_SYSTEM" == systemd ]]; then run systemctl --failed --no-pager; if have journalctl; then subsection "Kernel warnings/errors"; journalctl -k -b -p warning..alert --no-pager 2>/dev/null | tail -n 120 || true; fi
  else echo "systemd diagnostics not applicable (init: $INIT_SYSTEM)."; fi
  if have docker; then subsection "Docker summary"; docker version --format 'Client={{.Client.Version}} Server={{.Server.Version}}' 2>/dev/null || true; docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null || true; fi
}

health_summary() {
  section "HEALTH SUMMARY"
  local mem_total mem_avail mem_pct root_pct swap_total swap_free swap_used_pct failed=0 oom_count=0 battery_health="" max_temp=""
  mem_total="$(awk '/MemTotal/{print $2}' /proc/meminfo)"; mem_avail="$(awk '/MemAvailable/{print $2}' /proc/meminfo)"; mem_pct="$(awk -v a="$mem_avail" -v t="$mem_total" 'BEGIN{printf "%.0f",a*100/t}')"
  if (( mem_pct < 10 )); then echo "[CRITICAL] Memory     ${mem_pct}% available"; elif (( mem_pct < 20 )); then echo "[WARNING]  Memory     ${mem_pct}% available"; else echo "[OK]       Memory     ${mem_pct}% available"; fi
  swap_total="$(awk '/SwapTotal/{print $2}' /proc/meminfo)"; swap_free="$(awk '/SwapFree/{print $2}' /proc/meminfo)"; if (( swap_total > 0 )); then swap_used_pct="$(awk -v t="$swap_total" -v f="$swap_free" 'BEGIN{printf "%.0f",(t-f)*100/t}')"; echo "[INFO]     Swap       ${swap_used_pct}% allocated; evaluate with PSI/vmstat, not percentage alone"; else echo "[INFO]     Swap       not configured"; fi
  root_pct="$(df -P / | awk 'NR==2{gsub("%","",$5);print $5}')"; if (( root_pct >= 90 )); then echo "[CRITICAL] Filesystem root ${root_pct}% used"; elif (( root_pct >= 80 )); then echo "[WARNING]  Filesystem root ${root_pct}% used"; else echo "[OK]       Filesystem root ${root_pct}% used"; fi
  if ensure_command sensors sensors; then max_temp="$(sensors 2>/dev/null | grep -oE '\+[0-9]+([.][0-9]+)?°C' | tr -d '+°C' | sort -nr | head -1)"; fi
  if [[ -n "$max_temp" ]]; then if awk "BEGIN{exit !($max_temp>=95)}"; then echo "[CRITICAL] Temperature max ${max_temp} C"; elif awk "BEGIN{exit !($max_temp>=85)}"; then echo "[WARNING]  Temperature max ${max_temp} C"; else echo "[OK]       Temperature max ${max_temp} C"; fi; else echo "[INFO]     Temperature unavailable"; fi
  local p full design
  for p in /sys/class/power_supply/*; do [[ -d "$p" && "$(cat "$p/type" 2>/dev/null || true)" == Battery ]] || continue; full="$(cat "$p/energy_full" 2>/dev/null || cat "$p/charge_full" 2>/dev/null || true)"; design="$(cat "$p/energy_full_design" 2>/dev/null || cat "$p/charge_full_design" 2>/dev/null || true)"; [[ "$full" =~ ^[0-9]+$ && "$design" =~ ^[0-9]+$ && $design -gt 0 ]] && battery_health="$(awk -v f="$full" -v d="$design" 'BEGIN{printf "%.0f",f*100/d}')"; break; done
  if [[ -n "$battery_health" ]]; then if (( battery_health < 50 )); then echo "[CRITICAL] Battery    ${battery_health}% estimated health"; elif (( battery_health < 70 )); then echo "[WARNING]  Battery    ${battery_health}% estimated health"; else echo "[OK]       Battery    ${battery_health}% estimated health"; fi; else echo "[INFO]     Battery    unavailable/not present"; fi
  if [[ "$INIT_SYSTEM" == systemd ]]; then failed="$(systemctl --failed --no-legend --plain 2>/dev/null | grep -c . || true)"; oom_count="$(journalctl -k -b --no-pager 2>/dev/null | grep -Eic 'Out of memory:|oom-kill:|Killed process [0-9]+|Memory cgroup out of memory' || true)"; [[ $failed -eq 0 ]] && echo "[OK]       Services   no failed systemd units" || echo "[WARNING]  Services   ${failed} failed unit(s)"; [[ $oom_count -eq 0 ]] && echo "[OK]       OOM        no OOM events this boot" || echo "[CRITICAL] OOM        ${oom_count} event(s) this boot"; fi
  if ensure_command smartctl smartctl; then local bad=0 disk out; while read -r disk; do out="$(smartctl -H "$disk" 2>/dev/null || true)"; printf '%s' "$out" | grep -Eqi 'FAILED|FAILING|BAD' && bad=$((bad+1)); done < <(lsblk -dpno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}'); [[ $bad -eq 0 ]] && echo "[OK]       SMART      no global health failures" || echo "[CRITICAL] SMART      ${bad} disk(s) report failure"; fi
}

summary() { section "QUICK SUMMARY"; free -h 2>/dev/null || true; swapon --show 2>/dev/null || true; df -h / 2>/dev/null || true; uptime 2>/dev/null || true; echo; echo "Report: $REPORT"; }

detect_platform
section "SYSTEM DIAGNOSTIC TOOL"
echo "Starting read-oriented diagnostic at $(date -Is)"
case "$MODE" in
  quick) basic; memory_diag ;;
  memory) basic; memory_diag ;;
  storage) basic; storage_diag; temperature_battery ;;
  network) basic; network_diag ;;
  full) basic; memory_diag; storage_diag; temperature_battery; network_diag; system_logs ;;
esac
health_summary
summary
section "END OF DIAGNOSTIC"
echo "Completed at $(date -Is)"
