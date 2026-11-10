# samba-share-setup.sh

**Audita, instala y configura Samba para compartir archivos e impresoras entre Linux y Windows en Ubuntu/Debian.**
**Audit, install, and configure Samba to share files and printers between Linux and Windows on Ubuntu/Debian.**

---

## Documentación / Documentation

| Español | English |
|---|---|
| [README completo](README.es.md) | [Full README](README.en.md) |
| [Guía didáctica paso a paso](docs/guia-didactica.es.md) | [Step-by-step didactic guide](docs/guia-didactica.en.md) |

---

## Inicio rápido / Quick start

```bash
chmod +x samba-share-setup.sh

# Auditoría sin cambios / Audit without changes
./samba-share-setup.sh --check

# Asistente interactivo / Interactive wizard
sudo ./samba-share-setup.sh

# Compartir carpeta e impresoras sin preguntas
# Share a folder and printers without prompts
sudo ./samba-share-setup.sh --yes --printer --folder /srv/compartido
```

---

## Características / Features

- Ubuntu, Debian y derivadas / Ubuntu, Debian, and derivatives.
- GNOME, KDE, XFCE, MATE, Cinnamon, LXQt, LXDE, Budgie, Unity, CLI.
- Auditoría, instalación, configuración y verificación / Audit, install, configure, and verify.
- Carpetas autenticadas o para invitados, solo lectura o escritura / Authenticated or guest folders, read-only or writable.
- Impresoras con Samba + CUPS / Printers with Samba + CUPS.
- Descubrimiento en Windows con `wsdd` / Windows discovery with `wsdd`.
- Cortafuegos `ufw`/`firewalld` / `ufw`/`firewalld` firewall.
- Copia de seguridad y configuración reversible / Backup and reversible configuration.

---

## Licencia / License

MIT.
