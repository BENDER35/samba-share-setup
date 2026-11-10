# samba-share-setup.sh

**Auditoría, instalación y configuración de Samba para compartir archivos e impresoras entre Linux y Windows en Ubuntu y Debian, con cualquier escritorio.**

[English version](README.en.md) · [Guía didáctica](docs/guia-didactica.es.md) · [Didactic guide (EN)](docs/guia-didactica.en.md)

---

## Qué hace

El script comprueba el estado del equipo, explica qué falta y, si se lo autorizas, deja Samba listo para compartir:

- Paquetes de Samba, cliente SMB/CIFS, Avahi/mDNS y CUPS.
- Servicios `smbd`, `nmbd`, `avahi-daemon`, `cups` y `wsdd`.
- Configuración de `/etc/samba/smb.conf` validada con `testparm`.
- Carpetas compartidas autenticadas o para invitados, de solo lectura o lectura/escritura.
- Impresoras mediante Samba + CUPS.
- Descubrimiento de equipos en Windows 10/11 con `wsdd`.
- Reglas de cortafuegos si `ufw` o `firewalld` están activos.
- Plugin de compartición del escritorio (Nautilus, Dolphin, Thunar, Caja, Nemo…).

Está pensado para **Ubuntu y Debian** (y derivadas como Linux Mint, Pop!_OS o Kali). Funciona con GNOME, KDE Plasma, XFCE, MATE, Cinnamon, LXQt, LXDE, Budgie, Unity y también sin entorno gráfico.

> La interfaz interactiva del script está en español. Esta documentación se ofrece en español e inglés.

---

## Requisitos

- Ubuntu, Debian o una derivada compatible.
- `bash`, `systemd` y `apt`.
- Privilegios de administrador (`sudo`).
- Conexión a la red local entre el equipo Linux y el equipo Windows.
- Opcional: una impresora configurada en CUPS para compartirla.

El script **no** necesita entorno gráfico. Si no hay terminal interactiva, usa `--yes`.

---

## Instalación

```bash
# 1. Descarga o copia el script
cd ~/Descargas/sc_samba

# 2. Dale permiso de ejecución
chmod +x samba-share-setup.sh

# 3. Auditoría inicial (no modifica nada)
./samba-share-setup.sh --check
```

El script se eleva solo con `sudo` cuando hace falta. También puedes ejecutarlo directamente como root:

```bash
sudo ./samba-share-setup.sh
```

---

## Uso rápido

### 1. Auditoría

```bash
./samba-share-setup.sh --check
```

Muestra una tabla con el estado de cada componente. Sale con código `1` si hay fallos críticos, lo que permite usarlo en automatizaciones.

Si no tienes `sudo` a mano y solo quieres una revisión limitada:

```bash
./samba-share-setup.sh --check --no-root
```

Algunas comprobaciones (cuenta Samba, cortafuegos) aparecerán como omitidas.

### 2. Modo interactivo

```bash
sudo ./samba-share-setup.sh
```

El flujo es:

1. Detecta distribución, escritorio y usuario real.
2. Ejecuta la auditoría y la muestra.
3. Pregunta si quieres compartir impresoras.
4. Pregunta si quieres compartir una carpeta (ruta, nombre, comentario, solo lectura, invitados).
5. Pide confirmación antes de aplicar cambios.
6. Instala lo que falte, escribe la configuración, abre el cortafuegos y reinicia servicios.
7. Vuelve a auditar y muestra un resumen con las direcciones de acceso.
8. Ofrece un menú para añadir o quitar recursos.

### 3. Modo desatendido

```bash
sudo ./samba-share-setup.sh --yes --printer --folder "$HOME/Compartida"
```

En modo `--yes` se usan los valores por defecto y **no se piden contraseñas interactivas**. Si la cuenta Samba no existe, el script te indicará el comando para crearla:

```bash
sudo smbpasswd -a "$USER"
```

### 4. Simulación

```bash
sudo ./samba-share-setup.sh --dry-run --printer --folder /srv/compartido
```

Muestra qué se instalaría y qué se escribiría, sin tocar el sistema.

---

## Opciones

| Opción | Descripción |
|---|---|
| `-c`, `--check` | Solo auditoría. No modifica nada. Sale con `1` si hay fallos. |
| `--dry-run` | Auditoría + plan de acciones, sin aplicar cambios. |
| `-y`, `--yes` | Modo desatendido con valores por defecto. |
| `-f`, `--force` | Continúa en distribuciones no reconocidas. |
| `--no-root` | No intenta elevar privilegios (auditoría limitada). |
| `-v`, `--verbose` | Muestra la salida de los comandos. |
| `--no-apt-update` | No ejecuta `apt-get update` antes de instalar. |
| `--log ARCHIVO` | Guarda el registro en `ARCHIVO`. |
| `--printer` | Comparte impresoras (Samba + CUPS). |
| `--no-printer` | No configura impresoras. |
| `--printer-guest` | Permite imprimir a invitados sin contraseña. |
| `--folder[=RUTA]` | Comparte una carpeta. Sin ruta, se pregunta. |
| `--no-folder` | No comparte ninguna carpeta. |
| `--share-name NOMBRE` | Nombre visible del recurso compartido. |
| `--comment TEXTO` | Comentario del recurso. |
| `--read-only` | Carpeta compartida en solo lectura. |
| `--guest` | Permite acceso sin contraseña a la carpeta. |
| `--all-users` | Permite a cualquier usuario de Samba, no solo al actual. |
| `--usershare` | Crea la carpeta como *usershare* del usuario (sin editar `smb.conf`). |
| `--menu` | Muestra el menú de gestión al terminar. |
| `--no-menu` | No muestra el menú al terminar. |
| `--gui` | Instala el plugin de compartición del escritorio. |
| `--no-gui` | No instala el plugin del escritorio. |
| `--wsdd` | Instala/activa `wsdd` para el descubrimiento en Windows. |
| `--no-wsdd` | No instala ni modifica `wsdd`. |
| `-h`, `--help` | Muestra la ayuda. |
| `--version` | Muestra la versión. |

---

## Ejemplos

```bash
# Auditoría completa
sudo ./samba-share-setup.sh --check

# Asistente interactivo
sudo ./samba-share-setup.sh

# Compartir una carpeta concreta en solo lectura
sudo ./samba-share-setup.sh --folder /srv/documentos --share-name Documentos --read-only

# Compartir una carpeta para invitados (solo lectura, recomendado)
sudo ./samba-share-setup.sh --folder /srv/publico --guest --read-only

# Compartir impresoras y carpeta, sin preguntas
sudo ./samba-share-setup.sh --yes --printer --folder /srv/compartido

# Crear un usershare sin tocar smb.conf
sudo ./samba-share-setup.sh --folder "$HOME/Proyectos" --usershare

# Plan sin cambios
sudo ./samba-share-setup.sh --dry-run --printer --folder /srv/compartido

# Guardar un registro detallado
sudo ./samba-share-setup.sh --check --log /tmp/samba-audit.log
```

---

## Qué cambia en el sistema

### Configuración gestionada

El script **no reescribe** `smb.conf` a ciegas. Añade un bloque delimitado al final:

```ini
# ===== BEGIN samba-share-setup =====
# Bloque gestionado por samba-share-setup.sh — no editar a mano.
[global]
   usershare allow guests = Yes
   usershare max shares = 100
   ...
[MiCarpeta]
   path = /home/usuario/Compartida
   ...
# ===== END samba-share-setup =====
```

Las definiciones de cada recurso se guardan en:

```text
/etc/samba/samba-share-setup.d/
├── global.conf          # Opciones globales gestionadas
├── printer.enabled      # Marca de impresoras activadas
└── shares/
    ├── MiCarpeta.conf   # Un archivo por recurso del sistema
    └── Documentos.conf
```

Ventajas:

- Puedes seguir editando el resto de `smb.conf` a mano.
- Volver a ejecutar el script es idempotente: no duplica secciones.
- Eliminar un recurso desde el menú borra su archivo y regenera el bloque.

### Copia de seguridad

Antes de modificar `smb.conf` se crea una copia:

```text
/etc/samba/smb.conf.bak.AAAAAMMDD-HHMMSS.PID
```

La ruta exacta se muestra en el resumen final y se registra en el log.

### Impresoras

Al activar impresoras, el script:

- Ajusta `[printers]` y `[print$]` **en su sitio**, sin duplicarlas.
- Activa `load printers`, `printing = cups` y `printcap name = cups`.
- Ejecuta `cupsctl --share-printers --remote-any`.
- Añade el usuario a `lpadmin` si hace falta.
- Abre `631/tcp` en el cortafuegos si está activo.

### Descubrimiento en Windows

`wsdd` permite que Windows 10/11 vea el equipo en **Red**. El script intenta instalar `wsdd-server`, `wsdd2` o `wsdd`, en ese orden, y activa la unidad systemd disponible.

Si el paquete no existe en el repositorio, avisa y continúa: Samba seguirá funcionando escribiendo la ruta directamente.

### Cortafuegos

Solo actúa si `ufw` o `firewalld` están **activos**:

| Servicio | Puertos |
|---|---|
| Samba | `137,138/udp`, `139,445/tcp` |
| mDNS (Avahi) | `5353/udp` |
| CUPS | `631/tcp` |
| WS-Discovery (wsdd) | `3702/udp`, `5357/tcp` |

### Plugins de escritorio

| Escritorio | Paquete |
|---|---|
| GNOME / Unity / Budgie | `nautilus-share` |
| KDE Plasma | `kdenetwork-filesharing` |
| XFCE | `thunar-shares-plugin` |
| MATE | `caja-share` |
| Cinnamon | `nemo-share` |

Si el paquete no está disponible en tu versión, el script lo indica y sigue adelante. Puedes compartir igualmente desde este script o con `net usershare`.

---

## Acceso desde Windows

1. Asegúrate de que ambos equipos están en la misma red.
2. Abre el Explorador de archivos.
3. Escribe en la barra de direcciones:

   ```text
   \\192.168.1.50\MiCarpeta
   ```

   Sustituye la IP por la de tu equipo Linux. El script la muestra en el resumen final.

4. Si se pide usuario y contraseña, usa tu usuario de Linux y la contraseña de Samba creada con `smbpasswd`.

También puedes escribir `\\NOMBRE_DEL_EQUIPO\MiCarpeta` si el descubrimiento funciona.

### Acceso desde Linux

```bash
smbclient -L //192.168.1.50 -U usuario
smbclient //192.168.1.50/MiCarpeta -U usuario
```

O monta el recurso:

```bash
sudo mount -t cifs //192.168.1.50/MiCarpeta /mnt/compartida \
  -o username=usuario,uid=$(id -u),gid=$(id -g)
```

En el gestor de archivos: `smb://192.168.1.50/MiCarpeta`.

---

## Seguridad

- **Evita invitados con escritura.** Cualquiera en la red podría modificar archivos. El script avisa y pide confirmación.
- **Usa contraseñas Samba.** Crea o cambia la cuenta con:

  ```bash
  sudo smbpasswd -a usuario
  ```

- **SMB2 como mínimo.** El bloque gestionado fija `server min protocol = SMB2`. No lo bajes a `NT1` salvo por compatibilidad muy antigua.
- **Solo lectura por defecto recomendada** para carpetas públicas.
- **Cortafuegos**: comparte solo en redes de confianza. No expongas Samba a Internet.
- **`--all-users`** amplía el acceso a cualquier cuenta Samba válida; úsalo con criterio.
- **Invitados con escritura** se ejecutan como el usuario propietario (`force user`), lo que puede permitir escribir en sus archivos. Es una decisión consciente, no un valor por defecto.

---

## Solución de problemas

| Síntoma | Qué revisar |
|---|---|
| Windows no ve el equipo en «Red» | `systemctl status wsdd-server`; prueba `\\IP\recurso` directamente. Revisa que `5353/udp` y `3702/udp` no estén bloqueados. |
| «Acceso denegado» al abrir el recurso | Crea la cuenta Samba: `sudo smbpasswd -a usuario`. Comprueba `valid users` y los permisos Unix de la carpeta. |
| El recurso no aparece en la lista | `sudo testparm -s`; revisa que `smbd` esté activo: `systemctl status smbd`. |
| `testparm` detecta errores | El script no aplica configuraciones inválidas. Revisa el mensaje, corrige `smb.conf` y vuelve a ejecutar. |
| La carpeta compartida no se puede escribir | Revisa `read only`, permisos de la carpeta (`ls -ld`) y el usuario efectivo (`force user`). |
| Impresoras no aparecen en Windows | `cupsctl \| grep share`; `systemctl status cups`; añade la impresora en CUPS. |
| `usershare` falla | El usuario debe pertenecer a `sambashare` y ser propietario de la carpeta. Cierra sesión y entra de nuevo tras añadirlo al grupo. |
| Cambios de grupo sin efecto | Los grupos se aplican al iniciar sesión. Cierra sesión o reinicia. |
| El cortafuegos bloquea | `sudo ufw status verbose` o `sudo firewall-cmd --list-all`. Vuelve a ejecutar el script con root. |
| `wsdd` no está en el repositorio | Instala `wsdd-server` o `wsdd2` si están disponibles, o accede por IP. |

Logs útiles:

```bash
sudo tail -n 50 /var/log/samba-share-setup.log
sudo journalctl -u smbd -n 50 --no-pager
sudo testparm -s
```

---

## Revertir cambios

### Restaurar `smb.conf`

```bash
sudo ls -l /etc/samba/smb.conf.bak.*
sudo cp -a /etc/samba/smb.conf.bak.FECHA.PID /etc/samba/smb.conf
sudo testparm -s
sudo systemctl restart smbd
```

### Quitar el bloque gestionado

El bloque está entre estos marcadores:

```text
# ===== BEGIN samba-share-setup =====
# ===== END samba-share-setup =====
```

Puedes eliminarlo con un editor o con:

```bash
sudo sed -i '/^# ===== BEGIN samba-share-setup =====$/,/^# ===== END samba-share-setup =====$/d' /etc/samba/smb.conf
sudo testparm -s
sudo systemctl restart smbd
```

### Eliminar el estado del script

```bash
sudo rm -rf /etc/samba/samba-share-setup.d
```

Esto no borra las carpetas compartidas ni sus datos; solo la configuración gestionada.

### Desinstalar paquetes (opcional)

```bash
sudo apt remove samba wsdd-server
```

Revisa antes qué más depende de ellos. No es necesario para dejar de compartir.

---

## Estructura del proyecto

```text
sc_samba/
├── samba-share-setup.sh          # Script principal
├── README.md                     # Índice bilingüe
├── README.es.md                  # Este documento
├── README.en.md                  # English README
└── docs/
    ├── guia-didactica.es.md      # Guía paso a paso (ES)
    └── guia-didactica.en.md      # Step-by-step guide (EN)
```

---

## Códigos de salida

| Código | Significado |
|---|---|
| `0` | Todo correcto o auditoría sin fallos críticos. |
| `1` | La auditoría detectó fallos, o hubo un error de configuración. |
| `2` | Error de uso (opción desconocida, falta un argumento). |

---

## Limitaciones

- La interfaz del script está en español; la documentación es bilingüe.
- No configura un controlador de dominio ni autenticación contra Active Directory.
- No crea usuarios de Windows ni administra equipos remotos.
- `wsdd` y algunos plugins pueden no estar en todas las versiones de Ubuntu/Debian.
- El modo `--yes` no puede introducir contraseñas interactivas de `smbpasswd`.

---

## Licencia

MIT. Puedes usar, modificar y redistribuir el script, conservando el aviso de licencia.
