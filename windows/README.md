# Windows support

Windows support is planned and is not part of v1.0.0.

The intended implementation will use native PowerShell and Windows facilities such as CIM/WMI, `Get-ComputerInfo`, `Get-Process`, `Get-Volume`, `Get-NetAdapter`, `Get-Service` and `Get-WinEvent`.

The goal is to expose the same conceptual diagnostic areas as the Linux implementation while using Windows-native collectors.
