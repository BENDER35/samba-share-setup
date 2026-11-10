# Guía didáctica: compartir archivos e impresoras entre Linux y Windows con Samba

Esta guía acompaña a `samba-share-setup.sh` y explica **qué hace, por qué lo hace y cómo comprobarlo**. Está pensada para quien quiere entender el sistema, no solo ejecutar un comando.

[Read this guide in English](guia-didactica.en.md) · [README en español](../README.es.md)

---

## 1. A quién va dirigida

- Usuarios de Ubuntu o Debian que necesitan compartir una carpeta con un equipo Windows.
- Administradores noveles que quieren entender Samba sin perderse en documentación dispersa.
- Docentes o estudiantes que buscan un laboratorio reproducible.

Requisitos:

- Dos equipos en la misma red local (o dos máquinas virtuales en red interna).
- Linux con `sudo` y `apt`.
- Windows 10 u 11, o un cliente Linux con `smbclient`.

No necesitas conocimientos avanzados, pero sí manejar una terminal.

---

## 2. El modelo mental

Samba implementa el protocolo **SMB/CIFS** en Linux. Windows usa ese mismo protocolo para acceder a carpetas e impresoras compartidas.

```text
┌──────────────────────────┐         ┌──────────────────────────┐
│        Windows           │         │          Linux           │
│                          │         │                          │
│  Explorador de archivos  │  SMB2/3 │  smbd  ← /etc/samba/     │
│  \\192.168.1.50\Datos    │ ──────► │          smb.conf        │
│                          │  TCP445 │                          │
│  Panel de impresoras     │         │  CUPS ← impresoras       │
└──────────────────────────┘         └──────────────────────────┘
             │                                    │
             │        descubrimiento              │
             └──── wsdd (WS-Discovery) ───────────┘
                  Avahi/mDNS para .local
```

### Piezas clave

| Pieza | Papel |
|---|---|
| **SMB/CIFS** | Protocolo de compartición de archivos e impresoras. |
| **Samba** | Implementación libre de SMB para Linux. |
| **`smbd`** | Demonio que sirve archivos e impresoras (puerto 445). |
| **`nmbd`** | Resolución de nombres NetBIOS (puertos 137-139). Hoy suele ser opcional. |
| **`smb.conf`** | Archivo de configuración principal. |
| **CUPS** | Sistema de impresión de Linux (puerto 631). |
| **Avahi/mDNS** | Resolución de nombres `.local` en la red local. |
| **`wsdd`** | Anuncia el equipo a Windows 10/11 mediante WS-Discovery. |
| **`usershare`** | Compartición creada por un usuario sin editar `smb.conf`. |

### Tres formas de compartir

1. **Recurso del sistema**: sección en `smb.conf` (o en el bloque gestionado). Es la forma que usa el script por defecto. Persistente y centralizada.
2. **Usershare**: el usuario crea el recurso con `net usershare add`. No requiere editar `smb.conf`, pero depende de `sambashare` y de `usershare max shares > 0`.
3. **Plugin del escritorio**: la interfaz gráfica crea usershares por ti. Es cómoda, pero menos explícita.

---

## 3. Antes de empezar: conceptos que evitan errores

### 3.1 Permisos Unix y permisos Samba no son lo mismo

Para abrir un archivo deben pasar **dos filtros**:

1. **Samba**: ¿el usuario está en `valid users`? ¿el recurso es de solo lectura? ¿hay `guest ok`?
2. **Sistema de archivos**: ¿el usuario efectivo tiene permiso `r`/`w`/`x` sobre la carpeta y sus archivos?

Si Samba permite pero Unix niega, verás «acceso denegado». Si Unix permite pero Samba niega, el recurso ni siquiera aparece o pide credenciales.

El script genera:

```ini
create mask = 0664
directory mask = 0775
```

Estos valores definen los permisos de los archivos **nuevos** creados a través del recurso.

### 3.2 Usuario Linux, usuario Samba

Tu usuario de Linux (`bender`, por ejemplo) y tu cuenta Samba son cosas distintas:

- Linux autentica el inicio de sesión local.
- Samba usa su propia base de datos (`smbpasswd`, `pdbedit`).

Por eso hay que crear la cuenta Samba:

```bash
sudo smbpasswd -a bender
```

Sin ella, un recurso autenticado no funcionará aunque la carpeta sea tuya.

### 3.3 Grupos que importan

| Grupo | Para qué |
|---|---|
| `sambashare` | Permite crear usershares y acceder al directorio de usershares. |
| `lpadmin` | Permite administrar impresoras en CUPS. |

Los cambios de grupo **no se aplican a la sesión abierta**. Hay que cerrar sesión y volver a entrar.

### 3.4 El bloque gestionado

El script no reescribe todo `smb.conf`. Añade un bloque entre marcadores:

```ini
# ===== BEGIN samba-share-setup =====
...
# ===== END samba-share-setup =====
```

Así puede actualizar su propia configuración sin pisar tus ajustes manuales. Cada recurso del sistema tiene además un archivo en `/etc/samba/samba-share-setup.d/shares/`.

**Regla de oro:** no edites a mano dentro del bloque; edita los archivos de estado o usa el menú del script. Fuera del bloque, `smb.conf` es tuyo.

### 3.5 Por qué `testparm` es importante

`testparm` analiza la configuración y detecta errores antes de que Samba los sufra. El script **valida cada cambio** y solo lo aplica si `testparm` lo acepta. Si algo falla, conserva la configuración anterior y muestra el error.

Esto explica una decisión de diseño: en lugar de usar `include = /ruta/*.conf`, el script genera un bloque dentro de `smb.conf`. Los `include` con comodines y las secciones duplicadas (`[printers]`, `[print$]`) pueden confundir a `testparm` y a Samba. El bloque evita ese problema.

---

## 4. Laboratorio guiado

### Paso 0. Prepara el terreno

En Linux:

```bash
cd ~/Descargas/sc_samba
chmod +x samba-share-setup.sh
ip -4 addr show scope global
```

Apunta tu IP, por ejemplo `192.168.1.50`. En Windows, comprueba que estás en la misma red:

```powershell
ipconfig
ping 192.168.1.50
```

### Paso 1. Auditoría sin cambios

```bash
./samba-share-setup.sh --check
```

Lee la salida de arriba abajo. Cada línea tiene una etiqueta:

| Etiqueta | Significado | Acción típica |
|---|---|---|
| `[ OK ]` | Correcto. | Nada. |
| `[AVISO]` | Funciona, pero puede mejorarse. | Revisar; a veces no impide compartir. |
| `[FALLO]` | Impide el objetivo. | Corregir antes de continuar. |
| `[INFO]` | Informativo. | Ninguna. |
| `[OMIT]` | No se pudo comprobar (por ejemplo, sin root). | Ejecutar con `sudo` si importa. |

Al final verás un resumen:

```text
Resumen: 12 OK, 3 avisos, 1 fallos, 5 informativos, 0 omitidos
```

**Ejercicio 1:** identifica un `[FALLO]` y escribe qué comando o paquete lo resolvería. No lo ejecutes todavía.

### Paso 2. Simula el plan

```bash
sudo ./samba-share-setup.sh --dry-run --printer --folder /srv/compartido
```

El script muestra qué instalaría y qué escribiría, pero no modifica nada. Es la forma segura de ver el alcance antes de aplicar.

**Ejercicio 2:** compara el plan con la auditoría. ¿Qué acciones corresponden a fallos y cuáles son opcionales?

### Paso 3. Aplica con el asistente

```bash
sudo ./samba-share-setup.sh
```

Responde:

- Compartir impresoras: `s` si tienes una impresora en CUPS; `n` si no.
- Compartir carpeta: `s`.
- Ruta: `/srv/compartido` o `~/Compartida`.
- Nombre: `Compartido`.
- Comentario: el que quieras.
- Solo lectura: `s` para un primer experimento seguro.
- Invitados: `n` para practicar autenticación.

El script:

1. Instala paquetes que falten.
2. Escribe `/etc/samba/samba-share-setup.d/`.
3. Genera el bloque gestionado en `smb.conf`.
4. Crea la copia de seguridad.
5. Ajusta el cortafuegos si está activo.
6. Reinicia `smbd` y servicios relacionados.
7. Vuelve a auditar.

### Paso 4. Verifica desde Linux

```bash
# Ver la configuración efectiva
sudo testparm -s

# Comprobar el servicio
systemctl status smbd --no-pager

# Listar recursos (pide contraseña Samba)
smbclient -L //127.0.0.1 -U "$USER"

# Acceder al recurso
smbclient //127.0.0.1/Compartido -U "$USER"
```

Dentro de `smbclient`, prueba:

```text
ls
exit
```

Si no tienes cuenta Samba:

```bash
sudo smbpasswd -a "$USER"
```

### Paso 5. Verifica desde Windows

1. Abre el Explorador de archivos.
2. Escribe `\\192.168.1.50\Compartido`.
3. Introduce usuario y contraseña Samba si se piden.
4. Crea un archivo de prueba si el recurso es de escritura.

Si Windows no ve el equipo en «Red», prueba la ruta por IP. El descubrimiento (`wsdd`, mDNS) es una comodidad, no un requisito para que SMB funcione.

### Paso 6. Añade un segundo recurso con el menú

Al terminar, el script ofrece un menú. Elige `1` y crea otra carpeta, por ejemplo `/srv/publico`, con invitados y solo lectura.

Comprueba:

```bash
ls -l /etc/samba/samba-share-setup.d/shares/
sudo testparm -s
```

Deberías ver dos archivos `.conf` y dos secciones dentro del bloque. Vuelve a ejecutar el script: **no debe duplicar nada**.

### Paso 7. Elimina un recurso

En el menú, elige `4`, escribe el nombre y confirma. El script mueve el archivo, regenera el bloque y valida con `testparm`. Si la validación falla, restaura el archivo.

**Ejercicio 3:** después de eliminar, comprueba que la sección desapareció de `testparm -s` y que el archivo ya no está en `shares/`.

### Paso 8. Restaura si algo sale mal

```bash
sudo ls -l /etc/samba/smb.conf.bak.*
sudo cp -a /etc/samba/smb.conf.bak.FECHA.PID /etc/samba/smb.conf
sudo testparm -s
sudo systemctl restart smbd
```

---

## 5. Leer la auditoría como un profesional

### 5.1 Paquetes

- `samba` y `samba-common-bin`: servidor y herramientas.
- `smbclient` y `cifs-utils`: cliente para acceder a Windows y montar recursos.
- `avahi-daemon` y `libnss-mdns`: resolución `.local`.
- `cups` y `cups-client`: impresión.
- `wsdd`/`wsdd-server`/`wsdd2`: descubrimiento en Windows.

Un `[AVISO]` por `cifs-utils` no impide compartir **desde** Linux, pero sí montar recursos Windows.

### 5.2 Servicios

```bash
systemctl is-active smbd
systemctl is-enabled smbd
```

- **Activo** significa que funciona ahora.
- **Habilitado** significa que arrancará al iniciar el sistema.

Puede estar activo pero no habilitado: funciona hasta el próximo reinicio.

`nmbd` solo es necesario si NetBIOS está habilitado. Si `disable netbios = Yes`, su ausencia es normal.

### 5.3 Puertos

```bash
ss -ltnp | grep -E ':445|:139'
ss -lunp | grep -E ':137|:138|:5353|:3702'
```

| Puerto | Protocolo | Uso |
|---|---|---|
| 445/tcp | SMB | Archivos e impresoras modernos. |
| 139/tcp | NetBIOS | Compatibilidad antigua. |
| 137-138/udp | NetBIOS | Nombres y datagramas. |
| 631/tcp | IPP/CUPS | Impresión. |
| 5353/udp | mDNS | Descubrimiento `.local`. |
| 3702/udp, 5357/tcp | WS-Discovery | Descubrimiento en Windows 10/11. |

### 5.4 `smb.conf`

```bash
sudo testparm -s
```

`testparm` imprime la configuración efectiva, ya con valores por defecto aplicados. Es la fuente de verdad, no lo que crees que dice el archivo.

Para consultar un parámetro concreto:

```bash
testparm -s --parameter-name='server min protocol'
testparm -s --section-name=Compartido --parameter-name=path
```

### 5.5 Usershares

```bash
testparm -s --parameter-name='usershare max shares'
ls -ld /var/lib/samba/usershares
id -nG "$USER"
net usershare list
```

Debe existir el grupo `sambashare`, el directorio debe ser `root:sambashare 1770` y el usuario debe pertenecer al grupo.

### 5.6 Impresoras

```bash
cupsctl | grep -E '_share_printers|_remote_any'
lpstat -p
systemctl status cups --no-pager
```

`_share_printers=1` y `_remote_any=1` indican que CUPS comparte y acepta conexiones remotas.

---

## 6. Ejercicios con respuestas

### Ejercicio A: recurso autenticado de escritura

Crea `/srv/equipo` para el usuario `ana`, con acceso solo para ella y escritura.

```bash
sudo mkdir -p /srv/equipo
sudo chown ana:ana /srv/equipo
sudo chmod 2775 /srv/equipo
sudo ./samba-share-setup.sh --folder /srv/equipo --share-name Equipo --all-users
```

Después, crea la cuenta Samba de `ana`:

```bash
sudo smbpasswd -a ana
```

**Por qué `--all-users`?** Sin esa opción, el script añade `valid users = <usuario actual>`. Si ejecutas el script como `bender`, solo `bender` podría entrar. `--all-users` elimina esa restricción y deja que Samba autentique a cualquier cuenta válida; los permisos Unix de `/srv/equipo` siguen limitando el acceso a `ana`.

### Ejercicio B: carpeta pública de solo lectura

```bash
sudo mkdir -p /srv/publico
sudo chmod 755 /srv/publico
sudo ./samba-share-setup.sh --folder /srv/publico --guest --read-only
```

**Por qué solo lectura?** Un recurso de invitados con escritura permite que cualquiera en la red modifique archivos, y además se ejecuta como el propietario (`force user`). Para un primer contacto, solo lectura elimina ese riesgo.

### Ejercicio C: usershare

```bash
mkdir -p "$HOME/Proyectos"
sudo ./samba-share-setup.sh --folder "$HOME/Proyectos" --usershare
```

Requisitos:

- `usershare max shares` mayor que 0.
- Directorio `/var/lib/samba/usershares` con propietario `root:sambashare` y modo `1770`.
- El usuario pertenece a `sambashare` y es propietario de la carpeta.

Si acabas de añadir el grupo, cierra sesión y vuelve a entrar.

### Ejercicio D: diagnosticar un «acceso denegado»

1. `sudo testparm -s --section-name=MiRecurso` → ¿`valid users` incluye al usuario?
2. `sudo smbpasswd -a usuario` → ¿existe la cuenta Samba?
3. `namei -l /ruta/compartida` → ¿puede el usuario atravesar y leer la carpeta?
4. `sudo tail -n 50 /var/log/samba/log.smbd` → ¿qué dice el servidor?
5. `sudo journalctl -u smbd -n 50 --no-pager` → errores recientes.

La causa más común es no tener cuenta Samba. La segunda, permisos Unix insuficientes en algún directorio padre.

---

## 7. Seguridad: decisiones que debes tomar conscientemente

| Decisión | Riesgo | Recomendación |
|---|---|---|
| Invitados con escritura | Cualquiera en la red escribe como el propietario. | Evítalo salvo en redes aisladas. |
| `server min protocol = NT1` | Protocolo obsoleto e inseguro. | Mantén SMB2 o superior. |
| Compartir en red pública | Exposición a otros dispositivos. | Usa redes de confianza o cortafuegos. |
| `--all-users` | Amplía quién puede autenticarse. | Úsalo solo si los permisos Unix están bien definidos. |
| Abrir 445 a Internet | Riesgo grave de seguridad. | Nunca. Usa VPN si necesitas acceso remoto. |
| Contraseña Samba débil | Acceso no autorizado. | Contraseña robusta y única. |

Buenas prácticas:

- Comparte solo las carpetas necesarias.
- Prefiere solo lectura para contenido público.
- Revisa `valid users` y permisos Unix.
- Mantén el sistema actualizado.
- Guarda las copias de seguridad de `smb.conf`.
- No ejecutes el script en producción sin probar antes con `--dry-run`.

---

## 8. Metodología de diagnóstico

Cuando algo no funcione, sigue este orden. Cada paso descarta una capa:

1. **¿El servicio está vivo?**
   `systemctl status smbd`
2. **¿La configuración es válida?**
   `sudo testparm -s`
3. **¿El puerto escucha?**
   `ss -ltnp | grep 445`
4. **¿El cortafuegos lo permite?**
   `sudo ufw status verbose` o `sudo firewall-cmd --list-all`
5. **¿El recurso existe?**
   `smbclient -L //127.0.0.1 -U "$USER"`
6. **¿La autenticación funciona?**
   `smbclient //127.0.0.1/Recurso -U "$USER"`
7. **¿Los permisos Unix permiten?**
   `namei -l /ruta`
8. **¿Qué dicen los logs?**
   `/var/log/samba/log.smbd`, `journalctl -u smbd`

No cambies varias cosas a la vez. Cambia una, valida, y continúa.

---

## 9. Glosario

| Término | Definición |
|---|---|
| **SMB** | Server Message Block: protocolo de compartición de archivos e impresoras. |
| **CIFS** | Common Internet File System: nombre antiguo de una variante de SMB. |
| **Samba** | Implementación de SMB para sistemas Unix. |
| **smbd** | Demonio SMB de Samba. |
| **nmbd** | Demonio de nombres NetBIOS. |
| **Workgroup** | Grupo de trabajo de red (por defecto `WORKGROUP`). |
| **Share** | Recurso compartido: carpeta o impresora publicada. |
| **Usershare** | Recurso creado por un usuario sin privilegios. |
| **CUPS** | Common Unix Printing System. |
| **mDNS/Avahi** | Resolución de nombres en la red local (`.local`). |
| **WS-Discovery** | Protocolo que Windows usa para descubrir dispositivos en la red. |
| **wsdd** | Implementación de WS-Discovery para Linux. |
| **testparm** | Validador y visor de configuración de Samba. |
| **smbpasswd** | Herramienta para gestionar cuentas Samba. |
| **pdbedit** | Herramienta avanzada de gestión de cuentas Samba. |
| **mask** | Permisos aplicados a archivos nuevos. |

---

## 10. Lista de comprobación final

Antes de dar por terminada la configuración:

- [ ] `systemctl is-active smbd` devuelve `active`.
- [ ] `systemctl is-enabled smbd` devuelve `enabled`.
- [ ] `sudo testparm -s` no muestra errores.
- [ ] El recurso aparece en `smbclient -L //127.0.0.1 -U usuario`.
- [ ] El usuario tiene cuenta Samba (`sudo pdbedit -L`).
- [ ] Los permisos Unix de la carpeta permiten el acceso esperado.
- [ ] El cortafuegos permite 445/tcp (y 631/tcp si hay impresoras).
- [ ] Windows accede por IP aunque el descubrimiento falle.
- [ ] Existe una copia de seguridad de `smb.conf`.
- [ ] Sabes cómo eliminar el bloque gestionado y restaurar la copia.

Si todo lo anterior se cumple, la compartición es funcional y reversible.

---

## 11. Para seguir aprendiendo

- Documentación oficial de Samba: <https://www.samba.org/samba/docs/>
- `man smb.conf`, `man smbpasswd`, `man testparm`, `man net`
- Documentación de CUPS: <https://www.cups.org/documentation.html>
- `man ufw`, `man firewall-cmd`
- Registro de Samba: `/var/log/samba/`

La mejor forma de aprender es reproducir el laboratorio, romperlo a propósito en una máquina virtual y arreglarlo siguiendo la metodología de la sección 8.
