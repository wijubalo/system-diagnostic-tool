# Changelog

All notable changes to this project will be documented here.

The project follows Semantic Versioning.

## [1.0.0] - 2026-09-25

### Added

- Initial public Linux implementation.
- Automatic distribution, package-manager and init-system detection.
- Support for apt, dnf, yum, pacman, zypper and apk dependency installation.
- Quick, full, memory, storage and network diagnostic modes.
- CPU and hardware inventory.
- Memory, swap, vmstat and PSI diagnostics.
- Filesystem, SMART and NVMe diagnostics.
- Temperature and battery inspection.
- Network, Wi-Fi and DNS diagnostics.
- systemd service, kernel, OOM and storage/network log inspection.
- Optional Docker diagnostics.
- Timestamped text reports.
- Privacy redaction enabled by default, with `--no-redact` for intentional full-detail reports.
- Locale-independent numeric diagnostics.
- ShellCheck validation with GitHub Actions.
- Safe `--no-install` mode.

### Validated

- Full diagnostic execution validated on Ubuntu 24.04.
- SMART/NVMe, memory, swap, temperature, battery, network and system-health reporting validated on real hardware.
- Release candidate passed ShellCheck CI before promotion to v1.0.0.
