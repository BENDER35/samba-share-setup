# v1.0.0 — Samba share setup

Primera versión estable del script y su documentación.

## Contenido

- `samba-share-setup.sh`: auditoría, instalación y configuración de Samba para Ubuntu/Debian.
- Compartición de carpetas autenticadas o para invitados, solo lectura o escritura.
- Compartición de impresoras con Samba + CUPS.
- Descubrimiento en Windows 10/11 con `wsdd`.
- Reglas automáticas para `ufw`/`firewalld`.
- Copia de seguridad de `smb.conf` y validación con `testparm`.
- `README.es.md`, `README.en.md`, `README.md`.
- Guías didácticas en español e inglés en `docs/`.

## Instalación rápida

```bash
chmod +x samba-share-setup.sh
./samba-share-setup.sh --check
sudo ./samba-share-setup.sh
```

## Verificación

```bash
bash -n samba-share-setup.sh
shellcheck -S warning samba-share-setup.sh
./samba-share-setup.sh --version
```

## Licencia

MIT.
