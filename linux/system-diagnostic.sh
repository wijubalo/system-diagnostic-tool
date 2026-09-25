#!/usr/bin/env bash
set -uo pipefail

VERSION="1.0.0"
MODE="full"
NO_INSTALL=0
REPORT_DIR="${PWD}"
DISTRO_ID="unknown"
DISTRO_NAME="Unknown Linux"
DISTRO_FAMILY="unknown"
PACKAGE_MANAGER="unknown"
INIT_SYSTEM="unknown"

usage() {
  cat <<EOF
System Diagnostic Tool v${VERSION}
Usage: sudo $0 [options]
  --quick             Fast general diagnostic
  --full              Complete diagnostic (default)
  --memory            Memory, swap and pressure
  --storage           Storage, filesystem, SMART/NVMe
  --network           Network, Wi-Fi and DNS
  --no-install        Do not install missing dependencies
  --report-dir DIR    Report output directory
  --help              Show this help
EOF
}

while (($#)); do
  case "$1" in
    --quick|--full|--memory|--storage|--network) MODE="${1#--}" ;;
    --no-install) NO_INSTALL=1 ;;
    --report-dir) shift; [[ $# -gt 0 ]] || { echo "Missing --report-dir value" >&2; exit 2; }; REPORT_DIR="$1" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

mkdir -p "$REPORT_DIR" || exit 1
HOST="$(hostname 2>/dev/null || echo unknown)"
STAMP="$(date +%Y%m%d_%H%M%S)"
REPORT="${REPORT_DIR%/}/system-diagnostic_${HOST}_${STAMP}.txt"

section() { printf '\n==============================================================================\n%s\n==============================================================================\n' "$1"; }
subsection() { printf '\n--- %s ---\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
run() { printf '\n$ %s\n' "$*"; "$@" 2>&1 || printf '[WARN] command exited with status %s\n' "$?"; }

exec > >(tee -a "$REPORT") 2>&1

detect_platform() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
    local match="${DISTRO_ID} ${ID_LIKE:-}"
    case "$match" in
      *debian*|*ubuntu*) DISTRO_FAMILY="debian" ;;
      *fedora*|*rhel*|*centos*) DISTRO_FAMILY="rhel" ;;
      *arch*) DISTRO_FAMILY="arch" ;;
      *suse*) DISTRO_FAMILY="suse" ;;
      *alpine*) DISTRO_FAMILY="alpine" ;;
    esac
  fi
  for pm in apt-get dnf yum pacman zypper apk; do
    if have "$pm"; then PACKAGE_MANAGER="$pm"; break; fi
  done
  if have systemctl && [[ -d /run/systemd/system ]]; then INIT_SYSTEM="systemd";
  elif have rc-service; then INIT_SYSTEM="openrc"; fi
}

package_for() {
  local cap="$1"
  case "${PACKAGE_MANAGER}:${cap}" in
    apt-get:sensors) echo lm-sensors ;; dnf:sensors|yum:sensors|pacman:sensors) echo lm_sensors ;; zypper:sensors) echo sensors ;; apk:sensors) echo lm-sensors ;;
    *:smartctl) echo smartmontools ;;
    *:nvme) echo nvme-cli ;;
    *:lspci) echo pciutils ;;
    *:lsusb) echo usbutils ;;
    apt-get:iw|dnf:iw|yum:iw|pacman:iw|zypper:iw|apk:iw) echo iw ;;
    apt-get:dmidecode|dnf:dmidecode|yum:dmidecode|pacman:dmidecode|zypper:dmidecode|apk:dmidecode) echo dmidecode ;;
    *) return 1 ;;
  esac
}

install_package() {
  local pkg="$1"
  [[ $NO_INSTALL -eq 0 ]] || return 1
  [[ $EUID -eq 0 ]] || { echo "[INFO] Cannot install $pkg without root."; return 1; }
  echo "[INFO] Installing optional dependency: $pkg"
  case "$PACKAGE_MANAGER" in
    apt-get) apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" ;;
    dnf) dnf install -y "$pkg" ;; yum) yum install -y "$pkg" ;;
    pacman) pacman -Sy --needed --noconfirm "$pkg" ;;
    zypper) zypper --non-interactive install "$pkg" ;;
    apk) apk add "$pkg" ;;
    *) echo "[INFO] Unsupported package manager; continuing."; return 1 ;;
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
  echo "Tool version    : $VERSION"
  echo "Distribution    : $DISTRO_NAME"
  echo "Family          : $DISTRO_FAMILY"
  echo "Package manager : $PACKAGE_MANAGER"
  echo "Init system     : $INIT_SYSTEM"
  echo "Architecture    : $(uname -m)"
  echo "Kernel          : $(uname -r)"
  echo "Hostname        : $HOST"
  echo "Mode            : $MODE"
  run uptime
  section "CPU / HARDWARE"
  have lscpu && run lscpu
  ensure_command lspci lspci && run lspci -nn
  ensure_command lsusb lsusb && run lsusb
  if ensure_command dmidecode dmidecode && [[ $EUID -eq 0 ]]; then run dmidecode -t system; run dmidecode -t memory; fi
}

memory_diag() {
  section "MEMORY / SWAP"
  run free -h
  have swapon && run swapon --show
  have sysctl && run sysctl vm.swappiness
  subsection "Top processes by memory"
  ps -eo pid,user,comm,%cpu,%mem,rss --sort=-rss 2>/dev/null | head -n 25 || true
  if have vmstat; then subsection "vmstat (2s x 10)"; run vmstat 2 10; fi
  subsection "Pressure Stall Information"
  for f in /proc/pressure/memory /proc/pressure/cpu /proc/pressure/io; do [[ -r "$f" ]] && { echo "$f"; cat "$f"; }; done
  if [[ "$INIT_SYSTEM" == systemd ]] && have journalctl; then
    subsection "OOM / memory events"
    journalctl -b --no-pager 2>/dev/null | grep -Ei 'out of memory|oom|killed process' | tail -n 100 || true
  fi
}

storage_diag() {
  section "STORAGE / FILESYSTEM"
  have lsblk && run lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,MODEL
  run df -hT
  run df -ih
  subsection "SMART"
  if ensure_command smartctl smartctl; then
    while read -r disk; do [[ -n "$disk" ]] && run smartctl -a "$disk"; done < <(lsblk -dpno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}')
  else echo "smartctl unavailable."; fi
  subsection "NVMe"
  if ensure_command nvme nvme; then run nvme list; else echo "nvme-cli unavailable."; fi
  if [[ "$INIT_SYSTEM" == systemd ]] && have journalctl; then
    subsection "Storage/kernel events"
    journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'nvme|ata|i/o error|filesystem|ext4|btrfs|xfs' | tail -n 150 || true
  fi
}

temperature_battery() {
  section "TEMPERATURES"
  if ensure_command sensors sensors; then run sensors; else echo "sensors unavailable."; fi
  subsection "Thermal zones"
  for z in /sys/class/thermal/thermal_zone*; do
    [[ -d "$z" ]] || continue
    type="$(cat "$z/type" 2>/dev/null || echo unknown)"; temp="$(cat "$z/temp" 2>/dev/null || true)"
    [[ "$temp" =~ ^[0-9]+$ ]] && awk -v z="$z" -v t="$type" -v v="$temp" 'BEGIN{printf "%s | %s | %.1f C\n",z,t,v/1000}'
  done
  section "BATTERY / POWER"
  local found=0 p
  for p in /sys/class/power_supply/*; do
    [[ -d "$p" ]] || continue
    [[ "$(cat "$p/type" 2>/dev/null || true)" == Battery ]] || continue
    found=1; echo "Battery: $(basename "$p")"
    for f in manufacturer model_name status capacity cycle_count energy_now energy_full energy_full_design charge_now charge_full charge_full_design voltage_now charge_control_end_threshold; do
      [[ -r "$p/$f" ]] && printf '%-30s %s\n' "$f:" "$(cat "$p/$f")"
    done
  done
  [[ $found -eq 1 ]] || echo "No battery detected (normal for desktops/servers)."
}

network_diag() {
  section "NETWORK"
  have ip && run ip -brief address
  have ip && run ip route
  have nmcli && run nmcli device status
  subsection "Wi-Fi"
  if ensure_command iw iw; then run iw dev; else echo "iw unavailable or no Wi-Fi tooling."; fi
  if have resolvectl; then run resolvectl status; elif [[ -r /etc/resolv.conf ]]; then cat /etc/resolv.conf; fi
  subsection "Connectivity"
  have ping && run ping -c 4 -W 2 1.1.1.1
  if [[ "$INIT_SYSTEM" == systemd ]] && have journalctl; then
    subsection "Network/Wi-Fi events"
    journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'iwlwifi|wifi|wlan|firmware|disconnect|deauth|network' | tail -n 150 || true
  fi
}

system_logs() {
  section "SYSTEM HEALTH"
  if [[ "$INIT_SYSTEM" == systemd ]]; then
    run systemctl --failed --no-pager
    if have journalctl; then
      subsection "Kernel warnings/errors"
      journalctl -k -b -p warning..alert --no-pager 2>/dev/null | tail -n 200 || true
    fi
  else
    echo "systemd diagnostics not applicable (init: $INIT_SYSTEM)."
  fi
  if have docker; then subsection "Docker"; run docker info; run docker ps -a; fi
}

summary() {
  section "QUICK SUMMARY"
  free -h 2>/dev/null || true
  swapon --show 2>/dev/null || true
  df -h / 2>/dev/null || true
  uptime 2>/dev/null || true
  echo
  echo "Report: $REPORT"
}

detect_platform
section "SYSTEM DIAGNOSTIC TOOL"
echo "Starting read-oriented diagnostic at $(date -Is)"

case "$MODE" in
  quick) basic; memory_diag; summary ;;
  memory) basic; memory_diag; summary ;;
  storage) basic; storage_diag; temperature_battery; summary ;;
  network) basic; network_diag; summary ;;
  full) basic; memory_diag; storage_diag; temperature_battery; network_diag; system_logs; summary ;;
esac

section "END OF DIAGNOSTIC"
echo "Completed at $(date -Is)"
