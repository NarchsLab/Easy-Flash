# Easy-Flash

[![Language](https://img.shields.io/badge/Language-Python%203-blue.svg)](https://www.python.org/)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux-orange.svg)](#)

Easy-Flash is a lightweight, cross-platform command-line tool written in Python that makes flashing firmware to your Android devices incredibly simple. 

Instead of relying on heavy, bloated GUI software like RSA (Rescue and Smart Assistant) or RSD Lite, Easy-Flash parses standard flashfile.xml or servicefile.xml configurations and executes the corresponding fastboot commands sequentially with safety checks.

---

## Features

* Zero-Configuration Flashing: Just type "flash" in your ROM directory, and it does the rest.
* Typo-Proof Flag Matching: Built-in fuzzy matching catches typos (e.g., "flash --kep-dat" auto-corrects to "flash --keep-data").
* Keep Data Option: Skip user data wiping easily using the -k or --keep-data flags.
* Remote Path Support: Run flashing scripts targeting files in another directory using the -d flag.
* Safety First: Automatically verifies that required files exist before initiating any fastboot commands.

---

## Installation

Clone this repository to your local machine:
```bash
git clone https://github.com/NarchsLab/Easy-Flash.git
cd Easy-Flash
```
To run the install file for windows you need to open powershell and run:
```bash
Set-ExecutionPolicy Bypass -Scope Process -Force; .\install.ps1
```
To run the instlal file for linux you need to open your terminal and run:
``` bash
chmod +x install.sh
./install.sh
```

