# System Diagnostic Tool

Cross-platform system diagnostic tool for hardware, memory, storage, battery, temperature, network, firmware, and overall system health analysis.

> **Current status:** Linux is implemented. Windows support is planned.

## Features

- System, kernel and hardware inventory
- CPU, RAM, swap and memory-pressure diagnostics
- Storage, filesystem, SMART and NVMe health
- Temperature and thermal-zone inspection
- Battery health when available
- Network, Wi-Fi and DNS diagnostics
- Kernel/OOM logs and failed services on systemd systems
- Optional Docker information
- Automatic Linux distribution and package-manager detection
- Graceful degradation when hardware or commands are unavailable
- Timestamped text reports

## Linux support

Primary targets:

- Debian / Ubuntu / Linux Mint / Pop!_OS (`apt`)
- Fedora / RHEL / Rocky Linux / AlmaLinux (`dnf`/`yum`)
- Arch Linux / Manjaro (`pacman`)
- openSUSE (`zypper`)

Experimental/partial: Alpine Linux (`apk`), non-systemd systems and other distributions.

## Usage

```bash
git clone https://github.com/wijubalo/system-diagnostic-tool.git
cd system-diagnostic-tool
chmod +x linux/system-diagnostic.sh
sudo ./linux/system-diagnostic.sh --full
```

Options:

```text
--quick             Fast general diagnostic
--full              Complete diagnostic (default)
--memory            Memory, swap and pressure
--storage           Filesystems, disks, SMART/NVMe
--network           Network, Wi-Fi and DNS
--no-install        Never install missing optional dependencies
--report-dir DIR    Directory where reports are written
--help              Show help
```

Reports are named `system-diagnostic_HOSTNAME_YYYYMMDD_HHMMSS.txt`.

## Safety

The tool is read-oriented. It does not change swap, kernel tuning, firmware, battery thresholds, network configuration, storage configuration or services. Package installation is the only optional modification and can be disabled with `--no-install`.

Some hardware and SMART information requires root privileges, so `sudo` is recommended for a complete report.

## Roadmap

- Improve Linux coverage and automated tests
- Add machine-readable JSON output
- Add Windows diagnostics with PowerShell
- Consider macOS support

## License

MIT. See [LICENSE](LICENSE).
