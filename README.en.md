# samba-share-setup.sh

**Audit, install, and configure Samba to share files and printers between Linux and Windows on Ubuntu and Debian, across desktop environments.**

[Versión en español](README.es.md) · [Guía didáctica (ES)](docs/guia-didactica.es.md) · [Didactic guide](docs/guia-didactica.en.md)

---

## What it does

The script inspects the machine, explains what is missing, and—if you allow it—gets Samba ready to share:

- Samba packages, SMB/CIFS client, Avahi/mDNS, and CUPS.
- `smbd`, `nmbd`, `avahi-daemon`, `cups`, and `wsdd` services.
- `/etc/samba/smb.conf` changes validated with `testparm`.
- Authenticated or guest folder shares, read-only or read/write.
- Printers through Samba + CUPS.
- Windows 10/11 network discovery via `wsdd`.
- Firewall rules when `ufw` or `firewalld` is active.
- Desktop file-sharing plugin (Nautilus, Dolphin, Thunar, Caja, Nemo…).

It targets **Ubuntu and Debian** (and derivatives such as Linux Mint, Pop!_OS, or Kali). It works with GNOME, KDE Plasma, XFCE, MATE, Cinnamon, LXQt, LXDE, Budgie, Unity, and headless systems.

> The interactive script UI is in Spanish. This documentation is available in Spanish and English.

---

## Requirements

- Ubuntu, Debian, or a compatible derivative.
- `bash`, `systemd`, and `apt`.
- Administrator privileges (`sudo`).
- Local network connectivity between the Linux and Windows machines.
- Optional: a printer already configured in CUPS.

No desktop environment is required. If there is no interactive terminal, use `--yes`.

---

## Installation

```bash
# 1. Download or copy the script
cd ~/Downloads/sc_samba

# 2. Make it executable
chmod +x samba-share-setup.sh

# 3. Initial audit (changes nothing)
./samba-share-setup.sh --check
```

The script elevates itself with `sudo` when needed. You can also run it directly as root:

```bash
sudo ./samba-share-setup.sh
```

---

## Quick start

### 1. Audit

```bash
./samba-share-setup.sh --check
```

It prints a table with the status of every component. It exits with `1` when critical failures are found, which makes it usable in automation.

For a limited review without `sudo`:

```bash
./samba-share-setup.sh --check --no-root
```

Some checks (Samba account, firewall) will be reported as skipped.

### 2. Interactive mode

```bash
sudo ./samba-share-setup.sh
```

The flow is:

1. Detect distribution, desktop, and the real user.
2. Run and display the audit.
3. Ask whether to share printers.
4. Ask whether to share a folder (path, name, comment, read-only, guests).
5. Ask for confirmation before applying changes.
6. Install missing packages, write configuration, open the firewall, restart services.
7. Re-audit and print a summary with access addresses.
8. Offer a menu to add or remove shares.

### 3. Unattended mode

```bash
sudo ./samba-share-setup.sh --yes --printer --folder "$HOME/Shared"
```

In `--yes` mode, defaults are used and **no interactive passwords are requested**. If the Samba account does not exist, the script prints the command to create it:

```bash
sudo smbpasswd -a "$USER"
```

### 4. Dry run

```bash
sudo ./samba-share-setup.sh --dry-run --printer --folder /srv/shared
```

Shows what would be installed and written without touching the system.

---

## Options

| Option | Description |
|---|---|
| `-c`, `--check` | Audit only. Changes nothing. Exits `1` if failures are found. |
| `--dry-run` | Audit + action plan, without applying changes. |
| `-y`, `--yes` | Unattended mode with defaults. |
| `-f`, `--force` | Continue on unrecognized distributions. |
| `--no-root` | Do not attempt privilege elevation (limited audit). |
| `-v`, `--verbose` | Show command output. |
| `--no-apt-update` | Skip `apt-get update` before installing. |
| `--log FILE` | Write the log to `FILE`. |
| `--printer` | Share printers (Samba + CUPS). |
| `--no-printer` | Do not configure printers. |
| `--printer-guest` | Allow guests to print without a password. |
| `--folder[=PATH]` | Share a folder. Without a path, you are prompted. |
| `--no-folder` | Do not share any folder. |
| `--share-name NAME` | Visible share name. |
| `--comment TEXT` | Share comment. |
| `--read-only` | Share the folder read-only. |
| `--guest` | Allow passwordless access to the folder. |
| `--all-users` | Allow any Samba user, not just the current one. |
| `--usershare` | Create the folder as a user *usershare* (without editing `smb.conf`). |
| `--menu` | Show the management menu at the end. |
| `--no-menu` | Do not show the menu at the end. |
| `--gui` | Install the desktop sharing plugin. |
| `--no-gui` | Do not install the desktop plugin. |
| `--wsdd` | Install/enable `wsdd` for Windows discovery. |
| `--no-wsdd` | Do not install or modify `wsdd`. |
| `-h`, `--help` | Show help. |
| `--version` | Show version. |

---

## Examples

```bash
# Full audit
sudo ./samba-share-setup.sh --check

# Interactive wizard
sudo ./samba-share-setup.sh

# Share a specific folder read-only
sudo ./samba-share-setup.sh --folder /srv/documents --share-name Documents --read-only

# Share a guest folder (read-only, recommended)
sudo ./samba-share-setup.sh --folder /srv/public --guest --read-only

# Share printers and a folder without prompts
sudo ./samba-share-setup.sh --yes --printer --folder /srv/shared

# Create a usershare without touching smb.conf
sudo ./samba-share-setup.sh --folder "$HOME/Projects" --usershare

# Plan without changes
sudo ./samba-share-setup.sh --dry-run --printer --folder /srv/shared

# Save a detailed log
sudo ./samba-share-setup.sh --check --log /tmp/samba-audit.log
```

---

## What changes on the system

### Managed configuration

The script **does not blindly rewrite** `smb.conf`. It appends a delimited block at the end:

```ini
# ===== BEGIN samba-share-setup =====
# Bloque gestionado por samba-share-setup.sh — no editar a mano.
[global]
   usershare allow guests = Yes
   usershare max shares = 100
   ...
[MyFolder]
   path = /home/user/Shared
   ...
# ===== END samba-share-setup =====
```

Per-share definitions live in:

```text
/etc/samba/samba-share-setup.d/
├── global.conf          # Managed global options
├── printer.enabled      # Printer-sharing marker
└── shares/
    ├── MyFolder.conf    # One file per system share
    └── Documents.conf
```

Benefits:

- You can keep editing the rest of `smb.conf` by hand.
- Re-running the script is idempotent: no duplicated sections.
- Removing a share from the menu deletes its file and regenerates the block.

### Backup

Before modifying `smb.conf`, a backup is created:

```text
/etc/samba/smb.conf.bak.YYYYMMDD-HHMMSS.PID
```

The exact path is printed in the final summary and written to the log.

### Printers

When printer sharing is enabled, the script:

- Updates `[printers]` and `[print$]` **in place**, without duplicating them.
- Enables `load printers`, `printing = cups`, and `printcap name = cups`.
- Runs `cupsctl --share-printers --remote-any`.
- Adds the user to `lpadmin` if needed.
- Opens `631/tcp` in the firewall when active.

### Windows discovery

`wsdd` lets Windows 10/11 see the machine under **Network**. The script tries `wsdd-server`, `wsdd2`, then `wsdd`, and enables the available systemd unit.

If the package is not in the repository, it warns and continues: Samba still works when you type the path directly.

### Firewall

It only acts when `ufw` or `firewalld` is **active**:

| Service | Ports |
|---|---|
| Samba | `137,138/udp`, `139,445/tcp` |
| mDNS (Avahi) | `5353/udp` |
| CUPS | `631/tcp` |
| WS-Discovery (wsdd) | `3702/udp`, `5357/tcp` |

### Desktop plugins

| Desktop | Package |
|---|---|
| GNOME / Unity / Budgie | `nautilus-share` |
| KDE Plasma | `kdenetwork-filesharing` |
| XFCE | `thunar-shares-plugin` |
| MATE | `caja-share` |
| Cinnamon | `nemo-share` |

If the package is unavailable on your release, the script says so and continues. You can still share through this script or `net usershare`.

---

## Access from Windows

1. Make sure both machines are on the same network.
2. Open File Explorer.
3. Type in the address bar:

   ```text
   \\192.168.1.50\MyFolder
   ```

   Replace the IP with your Linux machine's address. The script prints it in the final summary.

4. If prompted for credentials, use your Linux username and the Samba password created with `smbpasswd`.

You can also use `\\HOSTNAME\MyFolder` when discovery works.

### Access from Linux

```bash
smbclient -L //192.168.1.50 -U user
smbclient //192.168.1.50/MyFolder -U user
```

Or mount it:

```bash
sudo mount -t cifs //192.168.1.50/MyFolder /mnt/share \
  -o username=user,uid=$(id -u),gid=$(id -g)
```

In a file manager: `smb://192.168.1.50/MyFolder`.

---

## Security

- **Avoid guest write access.** Anyone on the network could modify files. The script warns and asks for confirmation.
- **Use Samba passwords.** Create or change the account with:

  ```bash
  sudo smbpasswd -a user
  ```

- **SMB2 minimum.** The managed block sets `server min protocol = SMB2`. Do not lower it to `NT1` unless you need very old compatibility.
- **Prefer read-only** for public folders.
- **Firewall:** share only on trusted networks. Never expose Samba to the Internet.
- **`--all-users`** widens access to any valid Samba account; use it deliberately.
- **Guest write access** runs as the owning user (`force user`), which may allow writing to their files. That is a conscious choice, not a default.

---

## Troubleshooting

| Symptom | What to check |
|---|---|
| Windows does not see the machine in "Network" | `systemctl status wsdd-server`; try `\\IP\share` directly. Ensure `5353/udp` and `3702/udp` are not blocked. |
| "Access denied" when opening the share | Create the Samba account: `sudo smbpasswd -a user`. Check `valid users` and Unix folder permissions. |
| The share does not appear in the list | `sudo testparm -s`; check `smbd` is running: `systemctl status smbd`. |
| `testparm` reports errors | The script refuses invalid configurations. Read the message, fix `smb.conf`, and run it again. |
| The shared folder is not writable | Check `read only`, folder permissions (`ls -ld`), and the effective user (`force user`). |
| Printers do not appear in Windows | `cupsctl \| grep share`; `systemctl status cups`; add the printer in CUPS. |
| `usershare` fails | The user must belong to `sambashare` and own the folder. Log out and back in after adding the group. |
| Group changes have no effect | Groups apply at login. Log out or reboot. |
| The firewall blocks access | `sudo ufw status verbose` or `sudo firewall-cmd --list-all`. Re-run the script as root. |
| `wsdd` is not in the repository | Install `wsdd-server` or `wsdd2` if available, or connect by IP. |

Useful logs:

```bash
sudo tail -n 50 /var/log/samba-share-setup.log
sudo journalctl -u smbd -n 50 --no-pager
sudo testparm -s
```

---

## Rollback

### Restore `smb.conf`

```bash
sudo ls -l /etc/samba/smb.conf.bak.*
sudo cp -a /etc/samba/smb.conf.bak.DATE.PID /etc/samba/smb.conf
sudo testparm -s
sudo systemctl restart smbd
```

### Remove the managed block

The block is delimited by:

```text
# ===== BEGIN samba-share-setup =====
# ===== END samba-share-setup =====
```

Delete it with an editor or:

```bash
sudo sed -i '/^# ===== BEGIN samba-share-setup =====$/,/^# ===== END samba-share-setup =====$/d' /etc/samba/smb.conf
sudo testparm -s
sudo systemctl restart smbd
```

### Remove the script state

```bash
sudo rm -rf /etc/samba/samba-share-setup.d
```

This does not delete shared folders or their data; only the managed configuration.

### Uninstall packages (optional)

```bash
sudo apt remove samba wsdd-server
```

Check what else depends on them first. This is not required to stop sharing.

---

## Project layout

```text
sc_samba/
├── samba-share-setup.sh          # Main script
├── README.md                     # Bilingual index
├── README.es.md                  # Spanish README
├── README.en.md                  # This document
└── docs/
    ├── guia-didactica.es.md      # Step-by-step guide (ES)
    └── guia-didactica.en.md      # Step-by-step guide (EN)
```

---

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Everything is fine, or the audit found no critical failures. |
| `1` | The audit found failures, or a configuration error occurred. |
| `2` | Usage error (unknown option, missing argument). |

---

## Limitations

- The script UI is in Spanish; documentation is bilingual.
- It does not configure a domain controller or Active Directory authentication.
- It does not create Windows users or manage remote machines.
- `wsdd` and some desktop plugins may be unavailable on every Ubuntu/Debian release.
- `--yes` cannot enter interactive `smbpasswd` passwords.

---

## License

MIT. You may use, modify, and redistribute the script, keeping the license notice.
