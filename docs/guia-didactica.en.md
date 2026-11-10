# Didactic guide: sharing files and printers between Linux and Windows with Samba

This guide accompanies `samba-share-setup.sh` and explains **what it does, why it does it, and how to verify it**. It is written for people who want to understand the system, not just run a command.

[Leer esta guía en español](guia-didactica.es.md) · [English README](../README.en.md)

---

## 1. Who this is for

- Ubuntu or Debian users who need to share a folder with a Windows machine.
- New administrators who want to understand Samba without drowning in scattered documentation.
- Teachers or students looking for a reproducible lab.

Requirements:

- Two machines on the same local network (or two virtual machines on an internal network).
- Linux with `sudo` and `apt`.
- Windows 10 or 11, or a Linux client with `smbclient`.

You do not need advanced knowledge, but you should be comfortable with a terminal.

---

## 2. The mental model

Samba implements the **SMB/CIFS** protocol on Linux. Windows uses the same protocol to access shared folders and printers.

```text
┌──────────────────────────┐         ┌──────────────────────────┐
│         Windows          │         │           Linux          │
│                          │         │                          │
│  File Explorer           │  SMB2/3 │  smbd  ← /etc/samba/     │
│  \\192.168.1.50\Data     │ ──────► │          smb.conf        │
│                          │  TCP445 │                          │
│  Printers panel          │         │  CUPS ← printers         │
└──────────────────────────┘         └──────────────────────────┘
             │                                    │
             │          discovery                 │
             └──── wsdd (WS-Discovery) ───────────┘
                  Avahi/mDNS for .local
```

### Key pieces

| Piece | Role |
|---|---|
| **SMB/CIFS** | File and printer sharing protocol. |
| **Samba** | Free SMB implementation for Linux. |
| **`smbd`** | Daemon serving files and printers (port 445). |
| **`nmbd`** | NetBIOS name resolution (ports 137-139). Usually optional today. |
| **`smb.conf`** | Main configuration file. |
| **CUPS** | Linux printing system (port 631). |
| **Avahi/mDNS** | `.local` name resolution on the local network. |
| **`wsdd`** | Announces the machine to Windows 10/11 via WS-Discovery. |
| **`usershare`** | A share created by a user without editing `smb.conf`. |

### Three ways to share

1. **System share**: a section in `smb.conf` (or in the managed block). This is the script's default. Persistent and centralized.
2. **Usershare**: the user creates the share with `net usershare add`. It does not edit `smb.conf`, but depends on `sambashare` and `usershare max shares > 0`.
3. **Desktop plugin**: the GUI creates usershares for you. Convenient, but less explicit.

---

## 3. Before you start: concepts that prevent mistakes

### 3.1 Unix permissions and Samba permissions are not the same

Two filters must allow access:

1. **Samba**: is the user in `valid users`? Is the share read-only? Is `guest ok` set?
2. **Filesystem**: does the effective user have `r`/`w`/`x` permission on the folder and its files?

If Samba allows but Unix denies, you get "access denied". If Unix allows but Samba denies, the share may not appear or may ask for credentials.

The script generates:

```ini
create mask = 0664
directory mask = 0775
```

These values define the permissions of **new** files created through the share.

### 3.2 Linux user vs. Samba user

Your Linux user (`bender`, for example) and your Samba account are different things:

- Linux authenticates the local login.
- Samba uses its own database (`smbpasswd`, `pdbedit`).

That is why you must create the Samba account:

```bash
sudo smbpasswd -a bender
```

Without it, an authenticated share will not work even if you own the folder.

### 3.3 Groups that matter

| Group | Purpose |
|---|---|
| `sambashare` | Allows creating usershares and accessing the usershare directory. |
| `lpadmin` | Allows managing printers in CUPS. |

Group changes **do not apply to an open session**. Log out and back in.

### 3.4 The managed block

The script does not rewrite all of `smb.conf`. It appends a block between markers:

```ini
# ===== BEGIN samba-share-setup =====
...
# ===== END samba-share-setup =====
```

This lets it update its own configuration without overwriting your manual settings. Each system share also has a file under `/etc/samba/samba-share-setup.d/shares/`.

**Golden rule:** do not edit inside the block by hand; edit the state files or use the script menu. Outside the block, `smb.conf` is yours.

### 3.5 Why `testparm` matters

`testparm` parses the configuration and finds errors before Samba suffers from them. The script **validates every change** and applies it only if `testparm` accepts it. If something fails, it keeps the previous configuration and shows the error.

This explains a design decision: instead of `include = /path/*.conf`, the script generates a block inside `smb.conf`. Wildcard includes and duplicate sections (`[printers]`, `[print$]`) can confuse `testparm` and Samba. The block avoids that problem.

---

## 4. Guided lab

### Step 0. Prepare the ground

On Linux:

```bash
cd ~/Downloads/sc_samba
chmod +x samba-share-setup.sh
ip -4 addr show scope global
```

Note your IP, for example `192.168.1.50`. On Windows, confirm you are on the same network:

```powershell
ipconfig
ping 192.168.1.50
```

### Step 1. Audit without changes

```bash
./samba-share-setup.sh --check
```

Read the output from top to bottom. Each line has a label:

| Label | Meaning | Typical action |
|---|---|---|
| `[ OK ]` | Correct. | None. |
| `[AVISO]` | Works, but can be improved. | Review; sometimes it does not block sharing. |
| `[FALLO]` | Blocks the goal. | Fix before continuing. |
| `[INFO]` | Informational. | None. |
| `[OMIT]` | Could not be checked (for example, no root). | Run with `sudo` if it matters. |

At the end you will see a summary:

```text
Resumen: 12 OK, 3 avisos, 1 fallos, 5 informativos, 0 omitidos
```

**Exercise 1:** identify one `[FALLO]` and write down which command or package would fix it. Do not run it yet.

### Step 2. Simulate the plan

```bash
sudo ./samba-share-setup.sh --dry-run --printer --folder /srv/shared
```

The script shows what it would install and write, but changes nothing. This is the safe way to see the scope before applying.

**Exercise 2:** compare the plan with the audit. Which actions correspond to failures, and which are optional?

### Step 3. Apply with the wizard

```bash
sudo ./samba-share-setup.sh
```

Answer:

- Share printers: `s` if you have a printer in CUPS; `n` otherwise.
- Share a folder: `s`.
- Path: `/srv/shared` or `~/Shared`.
- Name: `Shared`.
- Comment: whatever you like.
- Read-only: `s` for a safe first experiment.
- Guests: `n` to practice authentication.

The script:

1. Installs missing packages.
2. Writes `/etc/samba/samba-share-setup.d/`.
3. Generates the managed block in `smb.conf`.
4. Creates the backup.
5. Adjusts the firewall if active.
6. Restarts `smbd` and related services.
7. Re-runs the audit.

### Step 4. Verify from Linux

```bash
# Show the effective configuration
sudo testparm -s

# Check the service
systemctl status smbd --no-pager

# List shares (asks for the Samba password)
smbclient -L //127.0.0.1 -U "$USER"

# Access the share
smbclient //127.0.0.1/Shared -U "$USER"
```

Inside `smbclient`, try:

```text
ls
exit
```

If you do not have a Samba account:

```bash
sudo smbpasswd -a "$USER"
```

### Step 5. Verify from Windows

1. Open File Explorer.
2. Type `\\192.168.1.50\Shared`.
3. Enter the Samba username and password if prompted.
4. Create a test file if the share is writable.

If Windows does not see the machine under "Network", try the IP path. Discovery (`wsdd`, mDNS) is a convenience, not a requirement for SMB to work.

### Step 6. Add a second share with the menu

When the script finishes, it offers a menu. Choose `1` and create another folder, for example `/srv/public`, with guests and read-only access.

Check:

```bash
ls -l /etc/samba/samba-share-setup.d/shares/
sudo testparm -s
```

You should see two `.conf` files and two sections inside the block. Run the script again: it **must not duplicate anything**.

### Step 7. Remove a share

In the menu, choose `4`, type the name, and confirm. The script moves the file, regenerates the block, and validates with `testparm`. If validation fails, it restores the file.

**Exercise 3:** after removing it, confirm the section is gone from `testparm -s` and the file is no longer in `shares/`.

### Step 8. Restore if something goes wrong

```bash
sudo ls -l /etc/samba/smb.conf.bak.*
sudo cp -a /etc/samba/smb.conf.bak.DATE.PID /etc/samba/smb.conf
sudo testparm -s
sudo systemctl restart smbd
```

---

## 5. Reading the audit like a professional

### 5.1 Packages

- `samba` and `samba-common-bin`: server and tools.
- `smbclient` and `cifs-utils`: client for accessing Windows and mounting shares.
- `avahi-daemon` and `libnss-mdns`: `.local` resolution.
- `cups` and `cups-client`: printing.
- `wsdd`/`wsdd-server`/`wsdd2`: Windows discovery.

An `[AVISO]` for `cifs-utils` does not prevent sharing **from** Linux, but it does prevent mounting Windows shares.

### 5.2 Services

```bash
systemctl is-active smbd
systemctl is-enabled smbd
```

- **Active** means it is running now.
- **Enabled** means it will start at boot.

It can be active but not enabled: it works until the next reboot.

`nmbd` is only needed if NetBIOS is enabled. If `disable netbios = Yes`, its absence is normal.

### 5.3 Ports

```bash
ss -ltnp | grep -E ':445|:139'
ss -lunp | grep -E ':137|:138|:5353|:3702'
```

| Port | Protocol | Purpose |
|---|---|---|
| 445/tcp | SMB | Modern file and printer sharing. |
| 139/tcp | NetBIOS | Legacy compatibility. |
| 137-138/udp | NetBIOS | Names and datagrams. |
| 631/tcp | IPP/CUPS | Printing. |
| 5353/udp | mDNS | `.local` discovery. |
| 3702/udp, 5357/tcp | WS-Discovery | Windows 10/11 discovery. |

### 5.4 `smb.conf`

```bash
sudo testparm -s
```

`testparm` prints the effective configuration, with defaults already applied. It is the source of truth, not what you think the file says.

To query a specific parameter:

```bash
testparm -s --parameter-name='server min protocol'
testparm -s --section-name=Shared --parameter-name=path
```

### 5.5 Usershares

```bash
testparm -s --parameter-name='usershare max shares'
ls -ld /var/lib/samba/usershares
id -nG "$USER"
net usershare list
```

The `sambashare` group must exist, the directory must be `root:sambashare 1770`, and the user must belong to the group.

### 5.6 Printers

```bash
cupsctl | grep -E '_share_printers|_remote_any'
lpstat -p
systemctl status cups --no-pager
```

`_share_printers=1` and `_remote_any=1` mean CUPS is sharing and accepting remote connections.

---

## 6. Exercises with answers

### Exercise A: authenticated writable share

Create `/srv/team` for user `ana`, accessible only to her, with write access.

```bash
sudo mkdir -p /srv/team
sudo chown ana:ana /srv/team
sudo chmod 2775 /srv/team
sudo ./samba-share-setup.sh --folder /srv/team --share-name Team --all-users
```

Then create Ana's Samba account:

```bash
sudo smbpasswd -a ana
```

**Why `--all-users`?** Without it, the script adds `valid users = <current user>`. If you run the script as `bender`, only `bender` could log in. `--all-users` removes that restriction and lets Samba authenticate any valid account; the Unix permissions on `/srv/team` still limit access to `ana`.

### Exercise B: public read-only folder

```bash
sudo mkdir -p /srv/public
sudo chmod 755 /srv/public
sudo ./samba-share-setup.sh --folder /srv/public --guest --read-only
```

**Why read-only?** A guest-writable share lets anyone on the network modify files, and it runs as the owner (`force user`). For a first contact, read-only removes that risk.

### Exercise C: usershare

```bash
mkdir -p "$HOME/Projects"
sudo ./samba-share-setup.sh --folder "$HOME/Projects" --usershare
```

Requirements:

- `usershare max shares` greater than 0.
- `/var/lib/samba/usershares` owned by `root:sambashare` with mode `1770`.
- The user belongs to `sambashare` and owns the folder.

If you just added the group, log out and back in.

### Exercise D: diagnose "access denied"

1. `sudo testparm -s --section-name=MyShare` → does `valid users` include the user?
2. `sudo smbpasswd -a user` → does the Samba account exist?
3. `namei -l /path/to/share` → can the user traverse and read the folder?
4. `sudo tail -n 50 /var/log/samba/log.smbd` → what does the server say?
5. `sudo journalctl -u smbd -n 50 --no-pager` → recent errors.

The most common cause is a missing Samba account. The second is insufficient Unix permissions on a parent directory.

---

## 7. Security: decisions you must make consciously

| Decision | Risk | Recommendation |
|---|---|---|
| Guest write access | Anyone on the network writes as the owner. | Avoid except on isolated networks. |
| `server min protocol = NT1` | Obsolete, insecure protocol. | Keep SMB2 or higher. |
| Sharing on a public network | Exposure to other devices. | Use trusted networks or a firewall. |
| `--all-users` | Widens who can authenticate. | Use only when Unix permissions are well defined. |
| Exposing 445 to the Internet | Serious security risk. | Never. Use a VPN for remote access. |
| Weak Samba password | Unauthorized access. | Strong, unique password. |

Best practices:

- Share only the folders you need.
- Prefer read-only for public content.
- Review `valid users` and Unix permissions.
- Keep the system updated.
- Keep backups of `smb.conf`.
- Do not run the script in production without testing with `--dry-run` first.

---

## 8. Troubleshooting methodology

When something fails, follow this order. Each step rules out one layer:

1. **Is the service alive?**
   `systemctl status smbd`
2. **Is the configuration valid?**
   `sudo testparm -s`
3. **Is the port listening?**
   `ss -ltnp | grep 445`
4. **Does the firewall allow it?**
   `sudo ufw status verbose` or `sudo firewall-cmd --list-all`
5. **Does the share exist?**
   `smbclient -L //127.0.0.1 -U "$USER"`
6. **Does authentication work?**
   `smbclient //127.0.0.1/Share -U "$USER"`
7. **Do Unix permissions allow it?**
   `namei -l /path`
8. **What do the logs say?**
   `/var/log/samba/log.smbd`, `journalctl -u smbd`

Do not change several things at once. Change one, validate, then continue.

---

## 9. Glossary

| Term | Definition |
|---|---|
| **SMB** | Server Message Block: file and printer sharing protocol. |
| **CIFS** | Common Internet File System: an old name for an SMB variant. |
| **Samba** | SMB implementation for Unix systems. |
| **smbd** | Samba's SMB daemon. |
| **nmbd** | NetBIOS name daemon. |
| **Workgroup** | Network workgroup (default `WORKGROUP`). |
| **Share** | Shared resource: a published folder or printer. |
| **Usershare** | A share created by an unprivileged user. |
| **CUPS** | Common Unix Printing System. |
| **mDNS/Avahi** | Local network name resolution (`.local`). |
| **WS-Discovery** | Protocol Windows uses to discover devices on the network. |
| **wsdd** | WS-Discovery implementation for Linux. |
| **testparm** | Samba configuration validator and viewer. |
| **smbpasswd** | Tool for managing Samba accounts. |
| **pdbedit** | Advanced Samba account management tool. |
| **mask** | Permissions applied to new files. |

---

## 10. Final checklist

Before considering the setup complete:

- [ ] `systemctl is-active smbd` returns `active`.
- [ ] `systemctl is-enabled smbd` returns `enabled`.
- [ ] `sudo testparm -s` shows no errors.
- [ ] The share appears in `smbclient -L //127.0.0.1 -U user`.
- [ ] The user has a Samba account (`sudo pdbedit -L`).
- [ ] The folder's Unix permissions allow the intended access.
- [ ] The firewall allows 445/tcp (and 631/tcp if printers are shared).
- [ ] Windows can access it by IP even if discovery fails.
- [ ] A backup of `smb.conf` exists.
- [ ] You know how to remove the managed block and restore the backup.

If all of the above is true, sharing works and is reversible.

---

## 11. Keep learning

- Official Samba documentation: <https://www.samba.org/samba/docs/>
- `man smb.conf`, `man smbpasswd`, `man testparm`, `man net`
- CUPS documentation: <https://www.cups.org/documentation.html>
- `man ufw`, `man firewall-cmd`
- Samba logs: `/var/log/samba/`

The best way to learn is to reproduce the lab, break it on purpose in a virtual machine, and fix it using the methodology in section 8.
