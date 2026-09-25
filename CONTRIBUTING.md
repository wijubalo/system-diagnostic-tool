# Contributing

Contributions are welcome.

## Development principles

- Diagnostics should be read-oriented and safe by default.
- Missing hardware or optional commands must not abort the complete diagnostic.
- Avoid distribution-specific assumptions in collectors.
- New package dependencies must be mapped by package manager where necessary.
- Do not collect secrets, credentials, tokens or private file contents.
- Keep output useful when executed on desktops, laptops, virtual machines and servers.

## Workflow

1. Fork the repository.
2. Create a focused branch.
3. Make the change.
4. Run ShellCheck against changed shell scripts.
5. Test on the distributions/environments available to you.
6. Open a pull request describing the environment used for testing.

## Bug reports

Please include:

- Distribution and version
- Kernel version
- Architecture
- Command/mode used
- Relevant error output

Before attaching a diagnostic report publicly, review it for hostnames, IP addresses, MAC addresses, serial numbers or other information you do not want to disclose.
