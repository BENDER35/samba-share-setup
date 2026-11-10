#!/usr/bin/env bash
# =============================================================================
#  samba-share-setup.sh
#  Comprueba, instala y configura Samba + recursos compartidos de red en
#  Ubuntu y Debian (cualquier escritorio: GNOME, KDE, XFCE, MATE, Cinnamon,
#  LXDE, LXQt, Budgie, Unity, etc.).
#
#  Uso normal:
#      sudo ./samba-share-setup.sh
#
#  Auditoría sin cambios:
#      sudo ./samba-share-setup.sh --check
#
#  Modo desatendido:
#      sudo ./samba-share-setup.sh --yes --printer --folder "$HOME/Compartida"
#
#  Licencia: MIT (puede usarlo, modificarlo y redistribuirlo).
# =============================================================================

set -uo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
SCRIPT_VERSION="1.0.0"

SMB_CONF="/etc/samba/smb.conf"
STATE_DIR="/etc/samba/samba-share-setup.d"
STATE_SHARES="$STATE_DIR/shares"
PRINTER_STATE="$STATE_DIR/printer.enabled"
BEGIN_MARKER="# ===== BEGIN samba-share-setup ====="
END_MARKER="# ===== END samba-share-setup ====="
USHARE_DIR="/var/lib/samba/usershares"
SMB_BACKUP=""
TMP_FILES=()

# --- Opciones ---------------------------------------------------------------
CHECK_ONLY=0
DRY_RUN=0
ASSUME_YES=0
FORCE=0
VERBOSE=0
NO_ROOT=0
NO_MENU=0
MENU_FORCE=0
APT_UPDATE=1
APT_UPDATED=0
INSTALL_GUI=-1          # -1 preguntar, 0 no, 1 sí
INSTALL_WSDD=-1         # -1 preguntar, 0 no, 1 sí

SHARE_PRINTER=""        # vacío = preguntar
SHARE_FOLDER=""         # vacío = preguntar
FOLDER_PATH=""
SHARE_NAME=""
SHARE_COMMENT=""
READ_ONLY=0
GUEST_OK=0
ALL_USERS=0
USE_USERSHARE=0
PRINTER_GUEST=0
LOG_FILE_OPT=""

# --- Estado global ----------------------------------------------------------
OS_ID=""
OS_LIKE=""
OS_PRETTY=""
OS_VERSION=""
DISTRO_SUPPORTED=0
DESKTOP_NAME="desconocido"
DESKTOP_RAW=""
GUI_PLUGIN=""
REAL_USER=""
REAL_HOME=""
REAL_GROUP=""
PRINTER_ENABLED=0
PRINTER_SHARING_DETECTED=0

COUNT_OK=0
COUNT_WARN=0
COUNT_FAIL=0
COUNT_INFO=0
COUNT_SKIP=0

CHECK_ORDER=()
declare -A CHECK_LABEL=()
declare -A CHECK_STATUS=()
declare -A CHECK_DETAIL=()

# --- Colores ---------------------------------------------------------------
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'
  CYAN=$'\033[0;36m'
  BOLD=$'\033[1m'
  NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; BOLD=""; NC=""
fi

# =============================================================================
#  Utilidades básicas
# =============================================================================

log() {
  [[ -n "${LOG_FILE:-}" ]] || return 0
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

say() {
  printf '%s\n' "$*"
  log "$*"
}

ok()   { printf '%s[ OK ]%s %s\n' "$GREEN" "$NC" "$*"; log "OK: $*"; }
warn() { printf '%s[AVISO]%s %s\n' "$YELLOW" "$NC" "$*"; log "AVISO: $*"; }
info() { printf '%s[INFO]%s %s\n' "$BLUE" "$NC" "$*"; log "INFO: $*"; }
err()  { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; log "ERROR: $*"; }

die() {
  err "$*"
  exit 1
}

section() {
  printf '\n%s%s== %s ==%s\n' "$BOLD" "$CYAN" "$*" "$NC"
  log "== $* =="
}

pause() {
  [[ -t 0 ]] || return 0
  read -r -p "Pulse Enter para continuar..." _ || true
}

run() {
  log "CMD: $(printf '%q ' "$@")"
  if [[ $VERBOSE -eq 1 ]]; then
    "$@" 2>&1 | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
  fi
  "$@" >>"$LOG_FILE" 2>&1
}

run_visible() {
  log "CMD: $(printf '%q ' "$@")"
  "$@" 2>&1 | tee -a "$LOG_FILE"
  return "${PIPESTATUS[0]}"
}

run_as_user() {
  local user="$1"; shift
  if command -v runuser >/dev/null 2>&1; then
    run runuser -u "$user" -- "$@"
  else
    run su -s /bin/bash -c "$(printf '%q ' "$@")" "$user"
  fi
}

ask_yn() {
  local prompt="$1" default="${2:-n}" answer hint
  if [[ $ASSUME_YES -eq 1 ]]; then
    [[ "$default" =~ ^[sSyY] ]] && return 0 || return 1
  fi
  if [[ ! -t 0 ]]; then
    die "No hay terminal interactiva. Use --yes y los parámetros adecuados."
  fi
  if [[ "$default" =~ ^[sSyY] ]]; then hint="S/n"; else hint="s/N"; fi
  while true; do
    read -r -p "$prompt [$hint] " answer || answer="$default"
    answer="${answer:-$default}"
    case "$answer" in
      s|S|si|Si|SI|sí|Sí|y|Y|yes|Yes|YES) return 0 ;;
      n|N|no|No|NO) return 1 ;;
      *) printf 'Responda s o n.\n' ;;
    esac
  done
}

ask_text() {
  local prompt="$1" default="${2:-}" answer
  if [[ $ASSUME_YES -eq 1 ]]; then
    printf '%s' "$default"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    printf '%s' "$default"
    return 0
  fi
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " answer || answer=""
  else
    read -r -p "$prompt: " answer || answer=""
  fi
  printf '%s' "${answer:-$default}"
}

cleanup_tmp() {
  local f
  for f in "${TMP_FILES[@]:-}"; do
    [[ -n "$f" && -e "$f" ]] && rm -f "$f"
  done
}

# =============================================================================
#  Ayuda y argumentos
# =============================================================================

usage() {
  cat <<EOF
$SCRIPT_NAME v$SCRIPT_VERSION — Compartición de red Linux ↔ Windows (Samba)

USO:
  sudo ./$SCRIPT_NAME [opciones]

MODO DE EJECUCIÓN:
  -c, --check             Solo auditoría. No modifica nada. Sale con 1 si hay fallos.
      --dry-run           Auditoría + plan de acciones, sin aplicar cambios.
  -y, --yes               Modo desatendido (acepta los valores por defecto).
  -f, --force             Continúa aunque la distro no sea Ubuntu/Debian.
      --no-root           No intentar elevar privilegios (auditoría limitada).
  -v, --verbose           Muestra la salida de los comandos.
      --no-apt-update     No ejecutar 'apt-get update' antes de instalar.
      --log ARCHIVO       Guarda el registro en ARCHIVO.

COMPARTICIÓN:
      --printer           Compartir impresoras (Samba + CUPS).
      --no-printer        No configurar impresoras.
      --printer-guest     Permitir imprimir a invitados (sin contraseña).
      --folder[=RUTA]     Compartir una carpeta. Sin ruta, se pregunta.
      --no-folder         No compartir ninguna carpeta.
      --share-name NOMBRE Nombre visible del recurso compartido.
      --comment TEXTO     Comentario del recurso compartido.
      --read-only         Carpeta compartida en solo lectura.
      --guest             Permitir acceso sin contraseña a la carpeta.
      --all-users         Permitir a cualquier usuario de Samba (no solo al actual).
      --usershare         Crear la carpeta como 'usershare' del usuario actual
                          (sin tocar smb.conf) en lugar de recurso del sistema.
      --menu              Mostrar el menú de gestión al terminar.
      --no-menu           No mostrar el menú al terminar.

INTEGRACIÓN:
      --gui               Instalar el plugin de compartición del escritorio.
      --no-gui            No instalar el plugin del escritorio.
      --wsdd              Instalar/activar wsdd (descubrimiento en Windows).
      --no-wsdd           No instalar wsdd.

EJEMPLOS:
  sudo ./$SCRIPT_NAME
  sudo ./$SCRIPT_NAME --check
  sudo ./$SCRIPT_NAME --yes --printer --folder /srv/compartido --read-only
  sudo ./$SCRIPT_NAME --folder "\$HOME/Compartida" --guest --read-only
  sudo ./$SCRIPT_NAME --check --no-root

NOTAS:
  * Los recursos se crean en /etc/samba/samba-share-setup.d y se aplican
    dentro de un bloque gestionado al final de /etc/samba/smb.conf.
  * Se guarda una copia de seguridad de smb.conf antes de modificarlo.
  * Para usar recursos autenticados, el usuario debe tener contraseña Samba:
        sudo smbpasswd -a USUARIO
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      -c|--check) CHECK_ONLY=1 ;;
      --dry-run) DRY_RUN=1 ;;
      -y|--yes) ASSUME_YES=1 ;;
      -f|--force) FORCE=1 ;;
      --no-root) NO_ROOT=1 ;;
      -v|--verbose) VERBOSE=1 ;;
      --no-apt-update) APT_UPDATE=0 ;;
      --log)
        [[ $# -ge 2 ]] || die "--log requiere un archivo"
        LOG_FILE_OPT="$2"; shift
        ;;
      --printer) SHARE_PRINTER=1 ;;
      --no-printer) SHARE_PRINTER=0 ;;
      --printer-guest) SHARE_PRINTER=1; PRINTER_GUEST=1 ;;
      --folder)
        SHARE_FOLDER=1
        if [[ $# -ge 2 && "${2:0:1}" != "-" ]]; then
          FOLDER_PATH="$2"; shift
        fi
        ;;
      --folder=*)
        SHARE_FOLDER=1
        FOLDER_PATH="${1#*=}"
        ;;
      --no-folder) SHARE_FOLDER=0 ;;
      --share-name)
        [[ $# -ge 2 ]] || die "--share-name requiere un nombre"
        SHARE_NAME="$2"; shift
        ;;
      --comment)
        [[ $# -ge 2 ]] || die "--comment requiere un texto"
        SHARE_COMMENT="$2"; shift
        ;;
      --read-only) READ_ONLY=1 ;;
      --guest) GUEST_OK=1 ;;
      --all-users) ALL_USERS=1 ;;
      --usershare) USE_USERSHARE=1 ;;
      --menu) MENU_FORCE=1 ;;
      --no-menu) NO_MENU=1 ;;
      --gui) INSTALL_GUI=1 ;;
      --no-gui) INSTALL_GUI=0 ;;
      --wsdd) INSTALL_WSDD=1 ;;
      --no-wsdd) INSTALL_WSDD=0 ;;
      -h|--help) usage; exit 0 ;;
      --version) printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
      --) shift; break ;;
      *) die "Opción desconocida: $1 (use --help)" ;;
    esac
    shift
  done
}

# =============================================================================
#  Identidad, root y registro
# =============================================================================

setup_identity_pre() {
  local pre_user pre_home
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    pre_user="$SUDO_USER"
  else
    pre_user="$(id -un 2>/dev/null || printf 'root')"
  fi
  pre_home="$(getent passwd "$pre_user" 2>/dev/null | cut -d: -f6)"
  [[ -n "$pre_home" ]] || pre_home="${HOME:-/root}"

  SC_REAL_USER="${SC_REAL_USER:-$pre_user}"
  SC_REAL_HOME="${SC_REAL_HOME:-$pre_home}"
  SC_DESKTOP="${SC_DESKTOP:-${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}}"
  SC_SESSION="${SC_SESSION:-${DESKTOP_SESSION:-}}"
  export SC_REAL_USER SC_REAL_HOME SC_DESKTOP SC_SESSION
}

require_root() {
  if [[ $EUID -eq 0 ]]; then
    return 0
  fi
  if [[ $CHECK_ONLY -eq 1 && $NO_ROOT -eq 1 ]]; then
    return 0
  fi
  if [[ $CHECK_ONLY -eq 1 && $NO_ROOT -eq 0 ]]; then
    # Para una auditoría completa se necesitan privilegios.
    :
  fi
  command -v sudo >/dev/null 2>&1 || die "Este script necesita root. Ejecútelo con sudo."
  info "Se necesitan privilegios de administrador. Solicitando sudo..."
  exec sudo -- env \
    SC_REAL_USER="$SC_REAL_USER" \
    SC_REAL_HOME="$SC_REAL_HOME" \
    SC_DESKTOP="$SC_DESKTOP" \
    SC_SESSION="$SC_SESSION" \
    bash "$SCRIPT_PATH" "$@"
}

setup_identity_post() {
  local u="${SC_REAL_USER:-${SUDO_USER:-}}"
  if [[ -z "$u" || "$u" == "root" ]]; then
    u="$(id -un 2>/dev/null || printf 'root')"
  fi
  REAL_USER="$u"
  REAL_HOME="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)"
  [[ -n "$REAL_HOME" ]] || REAL_HOME="${SC_REAL_HOME:-/root}"
  REAL_GROUP="$(id -gn "$REAL_USER" 2>/dev/null || printf 'root')"
  DESKTOP_RAW="${SC_DESKTOP:-${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}}"
}

setup_logging() {
  if [[ -n "$LOG_FILE_OPT" ]]; then
    LOG_FILE="$LOG_FILE_OPT"
  elif [[ $EUID -eq 0 ]]; then
    LOG_FILE="/var/log/samba-share-setup.log"
  else
    LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/samba-share-setup.log"
  fi
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  if ! : >>"$LOG_FILE" 2>/dev/null; then
    LOG_FILE="/tmp/samba-share-setup.log"
    : >>"$LOG_FILE" 2>/dev/null || LOG_FILE=""
  fi
  if [[ -n "$LOG_FILE" ]]; then
    printf '\n===== %s v%s — %s =====\n' "$SCRIPT_NAME" "$SCRIPT_VERSION" "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG_FILE"
  fi
}

banner() {
  printf '%s' "$CYAN"
  cat <<'EOF'
  ____                      _         ____  _                _
 / ___|  __ _ _ __ ___   __ _| |__   / ___|| |__   __ _ _ __| | ___
 \___ \ / _` | '_ ` _ \ / _` | '_ \  \___ \| '_ \ / _` | '__| |/ _ \
  ___) | (_| | | | | | | (_| | |_) |  ___) | | | | (_| | |  | |  __/
 |____/ \__,_|_| |_| |_|\__,_|_.__/  |____/|_| |_|\__,_|_|  |_|\___|
EOF
  printf '%s' "$NC"
  printf '  Compartición Linux ↔ Windows — Ubuntu / Debian — v%s\n' "$SCRIPT_VERSION"
  printf '  Usuario: %s   Escritorio: %s\n' "${REAL_USER:-?}" "${DESKTOP_RAW:-desconocido}"
}

# =============================================================================
#  Detección del sistema
# =============================================================================

detect_environment() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
    OS_PRETTY="${PRETTY_NAME:-$OS_ID}"
    OS_VERSION="${VERSION_ID:-}"
  fi

  local idlike=" ${OS_ID,,} ${OS_LIKE,,} "
  if [[ "$idlike" == *" ubuntu "* || "$idlike" == *" debian "* || "$idlike" == *" linuxmint "* || "$idlike" == *" pop "* || "$idlike" == *" kali "* ]]; then
    DISTRO_SUPPORTED=1
  fi

  local d="${DESKTOP_RAW,,}"
  case "$d" in
    *gnome*|*unity*|*budgie*|*pantheon*) DESKTOP_NAME="GNOME/Unity"; GUI_PLUGIN="nautilus-share" ;;
    *kde*|*plasma*)                       DESKTOP_NAME="KDE Plasma";  GUI_PLUGIN="kdenetwork-filesharing" ;;
    *xfce*)                               DESKTOP_NAME="XFCE";        GUI_PLUGIN="thunar-shares-plugin" ;;
    *mate*)                               DESKTOP_NAME="MATE";        GUI_PLUGIN="caja-share" ;;
    *cinnamon*)                           DESKTOP_NAME="Cinnamon";    GUI_PLUGIN="nemo-share" ;;
    *lxqt*)                               DESKTOP_NAME="LXQt";        GUI_PLUGIN="" ;;
    *lxde*)                               DESKTOP_NAME="LXDE";        GUI_PLUGIN="" ;;
    *deepin*)                             DESKTOP_NAME="Deepin";      GUI_PLUGIN="" ;;
    "")                                   DESKTOP_NAME="sin escritorio / CLI"; GUI_PLUGIN="" ;;
    *)                                    DESKTOP_NAME="$DESKTOP_RAW"; GUI_PLUGIN="" ;;
  esac
}

# =============================================================================
#  Paquetes
# =============================================================================

pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

pkg_available() {
  apt-cache show "$1" >/dev/null 2>&1
}

apt_update_once() {
  [[ $APT_UPDATE -eq 1 ]] || return 0
  [[ $APT_UPDATED -eq 0 ]] || return 0
  info "Actualizando la lista de paquetes (apt-get update)..."
  if run_visible env DEBIAN_FRONTEND=noninteractive apt-get update -qq; then
    APT_UPDATED=1
  else
    warn "No se pudo actualizar la lista de paquetes. Se intentará instalar igualmente."
    APT_UPDATED=1
  fi
}

apt_install() {
  local pkgs=("$@")
  ((${#pkgs[@]})) || return 0
  if [[ $DRY_RUN -eq 1 ]]; then
    info "[dry-run] Instalaría: ${pkgs[*]}"
    return 0
  fi
  apt_update_once
  info "Instalando: ${pkgs[*]}"
  if run_visible env DEBIAN_FRONTEND=noninteractive \
      apt-get install -y \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold \
      "${pkgs[@]}"; then
    ok "Paquetes instalados correctamente."
    return 0
  fi
  warn "La instalación de paquetes falló o quedó incompleta: ${pkgs[*]}"
  return 1
}

install_packages_needed() {
  local -a wanted=() missing=()
  local p
  declare -A seen=()

  wanted=(samba samba-common-bin smbclient cifs-utils avahi-daemon libnss-mdns)
  if [[ $PRINTER_ENABLED -eq 1 || $SHARE_PRINTER == "1" ]]; then
    wanted+=(cups cups-client)
  fi

  for p in "${wanted[@]}"; do
    [[ -n "${seen[$p]:-}" ]] && continue
    seen[$p]=1
    pkg_installed "$p" || missing+=("$p")
  done

  if ((${#missing[@]})); then
    info "Faltan paquetes: ${missing[*]}"
    if ask_yn "¿Desea instalarlos ahora?" s; then
      apt_install "${missing[@]}"
    else
      warn "No se instalarán los paquetes faltantes."
    fi
  else
    ok "Los paquetes principales ya están instalados."
  fi

  install_wsdd_package
  install_gui_plugin
}

# =============================================================================
#  Descubrimiento Windows (wsdd)
# =============================================================================

wsdd_pkg_installed() {
  pkg_installed wsdd || pkg_installed wsdd-server || pkg_installed wsdd2
}

wsdd_unit() {
  local u
  for u in wsdd-server.service wsdd.service wsdd2.service; do
    if systemctl is-active --quiet "$u" 2>/dev/null; then
      printf '%s' "$u"; return 0
    fi
  done
  for u in wsdd-server.service wsdd.service wsdd2.service; do
    if systemctl list-unit-files "$u" --no-legend 2>/dev/null | grep -q "^$u"; then
      printf '%s' "$u"; return 0
    fi
  done
  return 1
}

ensure_wsdd_service() {
  local unit
  unit="$(wsdd_unit || true)"
  if [[ -z "$unit" ]]; then
    if command -v wsdd >/dev/null 2>&1; then
      if [[ $DRY_RUN -eq 1 ]]; then
        info "[dry-run] Crearía y activaría wsdd.service"
        return 0
      fi
      warn "El binario wsdd existe pero no hay unidad systemd. Creando wsdd.service..."
      cat >/etc/systemd/system/wsdd.service <<'EOF'
[Unit]
Description=Web Services Dynamic Discovery host daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/wsdd --shortlog
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
      run systemctl daemon-reload
      unit="wsdd.service"
    else
      return 1
    fi
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    info "[dry-run] Activaría $unit"
    return 0
  fi
  if run systemctl enable --now "$unit"; then
    ok "Servicio de descubrimiento activo: $unit"
  else
    warn "No se pudo activar $unit. Revise: systemctl status $unit"
  fi
}

install_wsdd_package() {
  if [[ $INSTALL_WSDD -eq 0 ]]; then
    info "wsdd no se instalará ni modificará (--no-wsdd)."
    return 0
  fi

  if wsdd_pkg_installed; then
    ensure_wsdd_service || true
    return 0
  fi

  apt_update_once
  local pkg=""
  if pkg_available wsdd-server; then pkg="wsdd-server"
  elif pkg_available wsdd2; then pkg="wsdd2"
  elif pkg_available wsdd; then pkg="wsdd"
  fi

  if [[ -z "$pkg" ]]; then
    warn "No hay paquete wsdd/wsdd2 en los repositorios. Windows podría no descubrir el equipo en 'Red'."
    return 0
  fi

  if [[ $INSTALL_WSDD -eq -1 ]]; then
    if ! ask_yn "¿Instalar $pkg para que Windows descubra este equipo en la red?" s; then
      info "Puede instalar wsdd más tarde para mejorar el descubrimiento."
      return 0
    fi
  fi

  apt_install "$pkg" || return 0
  ensure_wsdd_service || true
}

# =============================================================================
#  Integración con el escritorio
# =============================================================================

install_gui_plugin() {
  [[ -n "$GUI_PLUGIN" ]] || return 0
  if pkg_installed "$GUI_PLUGIN"; then
    ok "Plugin de escritorio instalado: $GUI_PLUGIN"
    return 0
  fi
  if [[ $INSTALL_GUI -eq 0 ]]; then
    info "Plugin de escritorio no instalado (--no-gui)."
    return 0
  fi
  if ! pkg_available "$GUI_PLUGIN"; then
    apt_update_once
  fi
  if ! pkg_available "$GUI_PLUGIN"; then
    info "El plugin '$GUI_PLUGIN' no está disponible en los repositorios de esta versión."
    info "Podrá compartir igualmente con este script o con 'net usershare'."
    return 0
  fi
  if [[ $INSTALL_GUI -eq -1 ]]; then
    if ! ask_yn "¿Instalar '$GUI_PLUGIN' para compartir desde $DESKTOP_NAME?" n; then
      return 0
    fi
  fi
  apt_install "$GUI_PLUGIN" || return 0
  info "Cierre y vuelva a abrir el gestor de archivos para ver la opción de compartir."
}

# =============================================================================
#  Lectura de smb.conf
# =============================================================================

tp_param() {
  LC_ALL=C testparm -s "$SMB_CONF" --parameter-name="$1" 2>/dev/null | tail -n 1
}

tp_section_param() {
  LC_ALL=C testparm -s "$SMB_CONF" --section-name="$1" --parameter-name="$2" 2>/dev/null | tail -n 1
}

tp_sections() {
  LC_ALL=C testparm -s "$SMB_CONF" 2>/dev/null | sed -n 's/^\[\(.*\)\]$/\1/p'
}

smb_section_exists() {
  local section="$1"
  [[ -r "$SMB_CONF" ]] || return 1
  awk -v s="$section" '
    /^[[:space:]]*\[/ {
      name=$0
      sub(/^[[:space:]]*\[[[:space:]]*/, "", name)
      sub(/[[:space:]]*\].*$/, "", name)
      if (tolower(name) == tolower(s)) found=1
    }
    END { exit(found ? 0 : 1) }
  ' "$SMB_CONF"
}

smbconf_valid() {
  LC_ALL=C testparm -s "$SMB_CONF" >/dev/null 2>&1
}

# =============================================================================
#  Auditoría
# =============================================================================

record_check() {
  local key="$1" label="$2" status="$3" detail="${4:-}"
  if [[ -z "${CHECK_LABEL[$key]+x}" ]]; then
    CHECK_ORDER+=("$key")
  fi
  CHECK_LABEL["$key"]="$label"
  CHECK_STATUS["$key"]="$status"
  CHECK_DETAIL["$key"]="$detail"
}

reset_audit() {
  CHECK_ORDER=()
  unset CHECK_LABEL CHECK_STATUS CHECK_DETAIL
  declare -gA CHECK_LABEL=()
  declare -gA CHECK_STATUS=()
  declare -gA CHECK_DETAIL=()
  COUNT_OK=0; COUNT_WARN=0; COUNT_FAIL=0; COUNT_INFO=0; COUNT_SKIP=0
  PRINTER_SHARING_DETECTED=0
}

audit_distro() {
  if [[ $DISTRO_SUPPORTED -eq 1 ]]; then
    record_check distro "Distribución" OK "$OS_PRETTY ${OS_VERSION:+($OS_VERSION)}"
  else
    record_check distro "Distribución" WARN "$OS_PRETTY — este script está pensado para Ubuntu/Debian"
  fi
}

audit_desktop() {
  local detail="$DESKTOP_NAME"
  [[ -n "$GUI_PLUGIN" ]] && detail="$detail (plugin: $GUI_PLUGIN)"
  record_check desktop "Escritorio" INFO "$detail"
}

audit_packages() {
  local -a core=(samba samba-common-bin)
  local -a client=(smbclient cifs-utils)
  local -a discovery=(avahi-daemon libnss-mdns)
  local -a printing=(cups cups-client)
  local p missing

  missing=""
  for p in "${core[@]}"; do pkg_installed "$p" || missing+="$p "; done
  if [[ -z "$missing" ]]; then
    record_check pkg_core "Paquetes Samba" OK "samba, samba-common-bin"
  else
    record_check pkg_core "Paquetes Samba" FAIL "Faltan: $missing"
  fi

  missing=""
  for p in "${client[@]}"; do pkg_installed "$p" || missing+="$p "; done
  if [[ -z "$missing" ]]; then
    record_check pkg_client "Cliente SMB/CIFS" OK "smbclient, cifs-utils"
  else
    record_check pkg_client "Cliente SMB/CIFS" WARN "Faltan: $missing (para acceder a recursos Windows)"
  fi

  missing=""
  for p in "${discovery[@]}"; do pkg_installed "$p" || missing+="$p "; done
  if [[ -z "$missing" ]]; then
    record_check pkg_discovery "Descubrimiento mDNS (Avahi)" OK "avahi-daemon, libnss-mdns"
  else
    record_check pkg_discovery "Descubrimiento mDNS (Avahi)" WARN "Faltan: $missing"
  fi

  if [[ $PRINTER_ENABLED -eq 1 || $SHARE_PRINTER == "1" || $PRINTER_SHARING_DETECTED -eq 1 ]]; then
    missing=""
    for p in "${printing[@]}"; do pkg_installed "$p" || missing+="$p "; done
    if [[ -z "$missing" ]]; then
      record_check pkg_print "Servidor de impresión (CUPS)" OK "cups, cups-client"
    else
      record_check pkg_print "Servidor de impresión (CUPS)" FAIL "Faltan: $missing"
    fi
  else
    record_check pkg_print "Servidor de impresión (CUPS)" INFO "No se comprobará (no se compartirán impresoras)"
  fi

  if wsdd_pkg_installed; then
    record_check pkg_wsdd "Descubrimiento Windows (wsdd)" OK "paquete instalado"
  else
    record_check pkg_wsdd "Descubrimiento Windows (wsdd)" WARN "No instalado; Windows 10/11 podría no mostrar el equipo en 'Red'"
  fi

  if [[ -n "$GUI_PLUGIN" ]]; then
    if pkg_installed "$GUI_PLUGIN"; then
      record_check pkg_gui "Integración con $DESKTOP_NAME" OK "$GUI_PLUGIN"
    else
      record_check pkg_gui "Integración con $DESKTOP_NAME" INFO "$GUI_PLUGIN no instalado (opcional)"
    fi
  else
    record_check pkg_gui "Integración con $DESKTOP_NAME" INFO "Sin plugin específico; se usa la CLI"
  fi
}

svc_active() { systemctl is-active --quiet "$1" 2>/dev/null; }
svc_enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }

audit_services() {
  if ! command -v systemctl >/dev/null 2>&1; then
    record_check svc_smbd "Servicio smbd" SKIP "systemd no disponible"
    return 0
  fi

  if svc_active smbd; then
    if svc_enabled smbd; then
      record_check svc_smbd "Servicio smbd" OK "activo y habilitado"
    else
      record_check svc_smbd "Servicio smbd" WARN "activo pero no habilitado al arrancar"
    fi
  else
    record_check svc_smbd "Servicio smbd" FAIL "no está activo"
  fi

  local nb
  nb="$(tp_param 'disable netbios')"
  if [[ "${nb,,}" == "yes" ]]; then
    record_check svc_nmbd "Servicio nmbd" INFO "no necesario (NetBIOS deshabilitado)"
  else
    if svc_active nmbd; then
      record_check svc_nmbd "Servicio nmbd" OK "activo"
    else
      record_check svc_nmbd "Servicio nmbd" FAIL "no está activo y NetBIOS está habilitado"
    fi
  fi

  if pkg_installed avahi-daemon; then
    if svc_active avahi-daemon; then
      record_check svc_avahi "Servicio Avahi" OK "activo"
    else
      record_check svc_avahi "Servicio Avahi" WARN "no está activo"
    fi
  else
    record_check svc_avahi "Servicio Avahi" WARN "no instalado"
  fi

  if pkg_installed cups; then
    if svc_active cups; then
      record_check svc_cups "Servicio CUPS" OK "activo"
    else
      record_check svc_cups "Servicio CUPS" WARN "no está activo"
    fi
  else
    record_check svc_cups "Servicio CUPS" INFO "CUPS no instalado"
  fi

  local unit
  unit="$(wsdd_unit || true)"
  if [[ -n "$unit" ]]; then
    if svc_active "$unit"; then
      record_check svc_wsdd "Servicio wsdd" OK "$unit activo"
    else
      record_check svc_wsdd "Servicio wsdd" WARN "$unit no está activo"
    fi
  elif wsdd_pkg_installed; then
    record_check svc_wsdd "Servicio wsdd" WARN "paquete instalado pero sin servicio systemd"
  else
    record_check svc_wsdd "Servicio wsdd" WARN "no instalado"
  fi
}

audit_smbconf() {
  if [[ ! -f "$SMB_CONF" ]]; then
    record_check smb_file "Configuración smb.conf" FAIL "No existe $SMB_CONF"
    return 0
  fi

  if smbconf_valid; then
    record_check smb_file "Configuración smb.conf" OK "testparm no detecta errores"
  else
    record_check smb_file "Configuración smb.conf" FAIL "testparm detecta errores"
    return 0
  fi

  local perms
  perms="$(stat -c '%a' "$SMB_CONF" 2>/dev/null || printf '?')"
  if [[ ! "$perms" =~ ^[0-7]{3,4}$ ]]; then
    record_check smb_perms "Permisos de smb.conf" SKIP "no se pudieron leer los permisos"
  elif (( (8#$perms & 0022) != 0 )); then
    record_check smb_perms "Permisos de smb.conf" WARN "permisos $perms (debería ser 0644)"
  else
    record_check smb_perms "Permisos de smb.conf" OK "$perms"
  fi

  local workgroup role security minproto mapguest
  workgroup="$(tp_param workgroup)"
  role="$(tp_param 'server role')"
  security="$(tp_param security)"
  minproto="$(tp_param 'server min protocol')"
  mapguest="$(tp_param 'map to guest')"

  if [[ -n "$workgroup" ]]; then
    record_check smb_workgroup "Grupo de trabajo" OK "$workgroup"
  else
    record_check smb_workgroup "Grupo de trabajo" WARN "sin workgroup definido"
  fi

  if [[ "${role,,}" == *standalone* ]]; then
    record_check smb_role "Rol del servidor" OK "$role"
  else
    record_check smb_role "Rol del servidor" WARN "$role — este script asume servidor independiente"
  fi

  if [[ "${security,,}" == "user" || "${security,,}" == "auto" ]]; then
    record_check smb_security "Modo de seguridad" OK "$security"
  else
    record_check smb_security "Modo de seguridad" WARN "$security — revise la autenticación"
  fi

  if [[ -z "$minproto" ]]; then
    record_check smb_minproto "Protocolo mínimo SMB" INFO "valor predeterminado de Samba"
  elif [[ "${minproto,,}" == "nt1" || "${minproto,,}" == "lanman1" || "${minproto,,}" == "lanman2" ]]; then
    record_check smb_minproto "Protocolo mínimo SMB" WARN "$minproto — inseguro; se recomienda SMB2 o superior"
  else
    record_check smb_minproto "Protocolo mínimo SMB" OK "$minproto"
  fi

  if [[ "${mapguest,,}" == "never" ]]; then
    record_check smb_guest "Acceso de invitados" WARN "map to guest = Never (los recursos para invitados no funcionarán)"
  else
    record_check smb_guest "Acceso de invitados" OK "${mapguest:-predeterminado}"
  fi

  if smb_section_exists printers && [[ "$(tp_section_param printers printable)" =~ ^[Yy] ]]; then
    PRINTER_SHARING_DETECTED=1
    record_check smb_printers "Sección [printers]" OK "impresoras compartidas por SMB"
  else
    record_check smb_printers "Sección [printers]" INFO "no configurada para compartir impresoras"
  fi

  if smb_section_exists 'print$'; then
    record_check smb_printd "Sección [print$]" OK "repositorio de controladores"
  else
    record_check smb_printd "Sección [print$]" WARN "no existe [print$] (necesaria para controladores Windows)"
  fi

  local nb
  nb="$(tp_param 'disable netbios')"
  if [[ "${nb,,}" == "yes" ]]; then
    record_check smb_netbios "NetBIOS" INFO "deshabilitado"
  elif [[ "${nb,,}" == "no" ]]; then
    record_check smb_netbios "NetBIOS" INFO "habilitado"
  else
    record_check smb_netbios "NetBIOS" INFO "predeterminado"
  fi
}

audit_usershares() {
  local max path owner group mode guests owneronly
  max="$(tp_param 'usershare max shares')"
  [[ -n "$max" ]] || max=0
  path="$(tp_param 'usershare path')"
  [[ -n "$path" ]] || path="$USHARE_DIR"
  guests="$(tp_param 'usershare allow guests')"
  owneronly="$(tp_param 'usershare owner only')"

  if [[ "$max" =~ ^[0-9]+$ ]] && (( max > 0 )); then
    record_check ushare_max "Usershares (compartir sin root)" OK "máximo $max"
  else
    record_check ushare_max "Usershares (compartir sin root)" FAIL "deshabilitados (usershare max shares = 0)"
  fi

  if [[ -d "$path" ]]; then
    read -r owner group mode < <(stat -c '%U %G %a' "$path" 2>/dev/null || printf '? ? ?')
    if [[ "$group" == "sambashare" ]]; then
      if [[ "$mode" =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0002) == 0 )) && (( (8#$mode & 0020) != 0 )); then
        record_check ushare_dir "Directorio de usershares" OK "$path ($owner:$group $mode)"
      else
        record_check ushare_dir "Directorio de usershares" WARN "$path ($owner:$group $mode) — se recomienda 1770"
      fi
    else
      record_check ushare_dir "Directorio de usershares" FAIL "$path pertenece a $owner:$group (se espera root:sambashare)"
    fi
  else
    record_check ushare_dir "Directorio de usershares" FAIL "no existe $path"
  fi

  if getent group sambashare >/dev/null 2>&1; then
    if id -nG "$REAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx sambashare; then
      record_check ushare_group "Grupo sambashare" OK "$REAL_USER pertenece al grupo"
    else
      record_check ushare_group "Grupo sambashare" WARN "$REAL_USER no pertenece al grupo (cierre sesión tras añadirlo)"
    fi
  else
    record_check ushare_group "Grupo sambashare" FAIL "el grupo sambashare no existe"
  fi

  if [[ "${guests,,}" == "yes" ]]; then
    record_check ushare_guest "Invitados en usershares" OK "permitidos"
  else
    record_check ushare_guest "Invitados en usershares" INFO "no permitidos"
  fi
  record_check ushare_owner "usershare owner only" INFO "${owneronly:-predeterminado}"
}

audit_samba_user() {
  if [[ $EUID -ne 0 ]]; then
    record_check smb_user "Cuenta Samba" SKIP "requiere root para consultar pdbedit"
    return 0
  fi
  if ! command -v pdbedit >/dev/null 2>&1; then
    record_check smb_user "Cuenta Samba" SKIP "pdbedit no disponible"
    return 0
  fi
  local users
  users="$(pdbedit -L 2>/dev/null | cut -d: -f1)"
  if printf '%s\n' "$users" | grep -Fxq "$REAL_USER"; then
    local flags
    flags="$(pdbedit -Lv "$REAL_USER" 2>/dev/null | grep -i '^Account Flags' || true)"
    if [[ "$flags" == *D* ]]; then
      record_check smb_user "Cuenta Samba" WARN "$REAL_USER existe pero está deshabilitada"
    else
      record_check smb_user "Cuenta Samba" OK "$REAL_USER tiene cuenta Samba"
    fi
  else
    record_check smb_user "Cuenta Samba" WARN "no existe cuenta Samba para $REAL_USER"
  fi
}

port_tcp() { ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1$"; }
port_udp() { ss -lunH 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1$"; }

audit_network() {
  if ! command -v ss >/dev/null 2>&1; then
    record_check net_tools "Herramientas de red" SKIP "ss/iproute2 no disponible"
    return 0
  fi
  local ips
  ips="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | paste -sd ',' - | sed 's/,/, /g')"
  if [[ -n "$ips" ]]; then
    record_check net_ip "Direcciones IPv4" OK "$ips"
  else
    record_check net_ip "Direcciones IPv4" WARN "no se detectaron direcciones de red"
  fi

  if svc_active smbd; then
    if port_tcp 445; then
      record_check net_445 "Puerto 445 (SMB)" OK "escuchando"
    else
      record_check net_445 "Puerto 445 (SMB)" FAIL "smbd activo pero el puerto 445 no escucha"
    fi
  else
    record_check net_445 "Puerto 445 (SMB)" FAIL "smbd no está activo"
  fi

  local detail=""
  port_tcp 139 && detail+="139/tcp "
  port_udp 137 && detail+="137/udp "
  port_udp 138 && detail+="138/udp "
  if [[ -n "$detail" ]]; then
    record_check net_netbios "Puertos NetBIOS" OK "$detail"
  else
    record_check net_netbios "Puertos NetBIOS" INFO "no escuchan (normal si NetBIOS está deshabilitado)"
  fi

  local wsunit
  wsunit="$(wsdd_unit || true)"
  if [[ -n "$wsunit" ]] && svc_active "$wsunit"; then
    if port_udp 3702 && port_tcp 5357; then
      record_check net_wsdd "Puertos WS-Discovery" OK "3702/udp y 5357/tcp"
    else
      record_check net_wsdd "Puertos WS-Discovery" WARN "wsdd activo pero faltan puertos 3702/udp o 5357/tcp"
    fi
  else
    record_check net_wsdd "Puertos WS-Discovery" INFO "wsdd no activo"
  fi
}

audit_firewall() {
  if [[ $EUID -ne 0 ]]; then
    record_check fw "Cortafuegos" SKIP "requiere root para consultar ufw/firewalld"
    return 0
  fi

  if command -v ufw >/dev/null 2>&1 && LC_ALL=C ufw status 2>/dev/null | head -n 1 | grep -qi active; then
    local rules missing=""
    rules="$(LC_ALL=C ufw status 2>/dev/null)"
    grep -qiE 'Samba|445/tcp|139/tcp|137/udp|138/udp' <<<"$rules" || missing+="Samba(137-139,445) "
    if [[ $PRINTER_ENABLED -eq 1 || $SHARE_PRINTER == "1" || $PRINTER_SHARING_DETECTED -eq 1 ]]; then
      grep -qiE 'CUPS|631/tcp' <<<"$rules" || missing+="CUPS(631) "
    fi
    grep -qiE 'mDNS|5353/udp' <<<"$rules" || missing+="mDNS(5353) "
    if wsdd_pkg_installed; then
      grep -qiE 'wsdd|3702/udp|5357/tcp' <<<"$rules" || missing+="wsdd(3702,5357) "
    fi
    if [[ -n "$missing" ]]; then
      record_check fw "Cortafuegos (ufw)" FAIL "faltan reglas: $missing"
    else
      record_check fw "Cortafuegos (ufw)" OK "reglas de Samba y servicios presentes"
    fi
    return 0
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    local svcs missing=""
    svcs="$(firewall-cmd --list-services 2>/dev/null)"
    grep -qw samba <<<"$svcs" || missing+="samba "
    if [[ $PRINTER_ENABLED -eq 1 || $SHARE_PRINTER == "1" || $PRINTER_SHARING_DETECTED -eq 1 ]]; then
      grep -qw cups <<<"$svcs" || missing+="cups "
    fi
    grep -qw mdns <<<"$svcs" || missing+="mdns "
    if [[ -n "$missing" ]]; then
      record_check fw "Cortafuegos (firewalld)" FAIL "faltan servicios: $missing"
    else
      record_check fw "Cortafuegos (firewalld)" OK "servicios samba/cups/mdns permitidos"
    fi
    return 0
  fi

  record_check fw "Cortafuegos" INFO "no se detecta ufw/firewalld activo"
}

audit_printers() {
  if ! command -v cupsctl >/dev/null 2>&1; then
    record_check cups_share "Compartición CUPS" SKIP "cupsctl no disponible"
    return 0
  fi
  local out share remote
  out="$(cupsctl 2>/dev/null || true)"
  share="$(awk -F= '$1=="_share_printers"{print $2}' <<<"$out")"
  remote="$(awk -F= '$1=="_remote_any"{print $2}' <<<"$out")"

  if [[ "$share" == "1" ]]; then
    record_check cups_share "Compartición CUPS" OK "CUPS comparte impresoras"
  else
    record_check cups_share "Compartición CUPS" WARN "CUPS no comparte impresoras"
  fi
  if [[ "$remote" == "1" ]]; then
    record_check cups_remote "Acceso remoto a CUPS" OK "permite conexiones remotas"
  else
    record_check cups_remote "Acceso remoto a CUPS" WARN "solo escucha en local (IPP remoto deshabilitado)"
  fi

  local count
  count="$(timeout 5 lpstat -p 2>/dev/null | grep -c '^printer' || true)"
  if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )); then
    record_check cups_printers "Impresoras en CUPS" OK "$count impresora(s) configurada(s)"
  else
    record_check cups_printers "Impresoras en CUPS" INFO "no hay impresoras configuradas"
  fi
}

audit_discovery() {
  local nss
  nss="$(grep -E '^hosts:' /etc/nsswitch.conf 2>/dev/null || true)"
  if [[ "$nss" == *mdns* ]]; then
    record_check disc_mdns "Resolución .local (mDNS)" OK "nsswitch.conf incluye mdns"
  else
    record_check disc_mdns "Resolución .local (mDNS)" WARN "nsswitch.conf no incluye mdns"
  fi

  local unit
  unit="$(wsdd_unit || true)"
  if [[ -n "$unit" ]] && svc_active "$unit"; then
    record_check disc_wsdd "Descubrimiento WS-Discovery" OK "$unit activo"
  elif wsdd_pkg_installed; then
    record_check disc_wsdd "Descubrimiento WS-Discovery" WARN "instalado pero inactivo"
  else
    record_check disc_wsdd "Descubrimiento WS-Discovery" WARN "no instalado"
  fi
}

run_audit() {
  reset_audit
  detect_environment
  audit_distro
  audit_desktop
  audit_smbconf
  audit_packages
  audit_services
  audit_usershares
  audit_samba_user
  audit_network
  audit_firewall
  audit_printers
  audit_discovery

  local key
  for key in "${CHECK_ORDER[@]}"; do
    case "${CHECK_STATUS[$key]}" in
      OK) ((COUNT_OK++)) ;;
      WARN) ((COUNT_WARN++)) ;;
      FAIL) ((COUNT_FAIL++)) ;;
      INFO) ((COUNT_INFO++)) ;;
      SKIP) ((COUNT_SKIP++)) ;;
    esac
  done
}

print_audit() {
  local key status label detail color tag
  section "Auditoría del sistema"
  for key in "${CHECK_ORDER[@]}"; do
    status="${CHECK_STATUS[$key]}"
    label="${CHECK_LABEL[$key]}"
    detail="${CHECK_DETAIL[$key]:-}"
    case "$status" in
      OK)    color="$GREEN";  tag=" OK " ;;
      WARN)  color="$YELLOW"; tag="AVISO" ;;
      FAIL)  color="$RED";    tag="FALLO" ;;
      INFO)  color="$BLUE";   tag="INFO" ;;
      SKIP)  color="$YELLOW"; tag="OMIT" ;;
      *)     color="$NC";     tag="$status" ;;
    esac
    printf '  %s[%s]%s %-34s %s\n' "$color" "$tag" "$NC" "$label" "$detail"
  done
  printf '\n  Resumen: %s%d OK%s, %s%d avisos%s, %s%d fallos%s, %d informativos, %d omitidos\n' \
    "$GREEN" "$COUNT_OK" "$NC" "$YELLOW" "$COUNT_WARN" "$NC" "$RED" "$COUNT_FAIL" "$NC" \
    "$COUNT_INFO" "$COUNT_SKIP"
}

# =============================================================================
#  Escritura segura de smb.conf
# =============================================================================

backup_smb_conf() {
  [[ -n "$SMB_BACKUP" ]] && return 0
  [[ -f "$SMB_CONF" ]] || return 0
  SMB_BACKUP="${SMB_CONF}.bak.$(date '+%Y%m%d-%H%M%S').$$"
  if cp -a "$SMB_CONF" "$SMB_BACKUP" 2>/dev/null; then
    info "Copia de seguridad: $SMB_BACKUP"
  else
    warn "No se pudo crear copia de seguridad de $SMB_CONF"
    SMB_BACKUP=""
  fi
}

show_testparm_error() {
  local file="$1"
  printf '%s--- testparm ---%s\n' "$YELLOW" "$NC" >&2
  LC_ALL=C testparm -s "$file" 2>&1 | sed -n '1,35p' >&2
  printf '%s----------------%s\n' "$YELLOW" "$NC" >&2
}

install_validated_smbconf() {
  local tmp="$1"
  if ! LC_ALL=C testparm -s "$tmp" >/dev/null 2>&1; then
    show_testparm_error "$tmp"
    return 1
  fi
  backup_smb_conf
  cat "$tmp" >"$SMB_CONF" || return 1
  return 0
}

# Añade o reemplaza una clave dentro de una sección existente.
smb_set_param() {
  local section="$1" key="$2" value="$3"
  local tmp rc
  [[ -f "$SMB_CONF" ]] || return 1
  tmp="$(mktemp "${SMB_CONF}.tmp.XXXXXX")" || return 1
  TMP_FILES+=("$tmp")

  awk -v section="$section" -v key="$key" -v value="$value" '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    BEGIN { in_sec=0; found_sec=0; found_key=0 }
    /^[[:space:]]*\[/ {
      if (in_sec && !found_key) { print "   " key " = " value; found_key=1 }
      header=$0
      name=header
      sub(/^[[:space:]]*\[[[:space:]]*/, "", name)
      sub(/[[:space:]]*\].*$/, "", name)
      if (tolower(name) == tolower(section)) { in_sec=1; found_sec=1 } else { in_sec=0 }
      print
      next
    }
    {
      if (in_sec) {
        t=$0
        sub(/^[[:space:]]*/, "", t)
        if (t !~ /^[;#]/) {
          k=t
          sub(/[[:space:]]*=.*/, "", k)
          if (tolower(trim(k)) == tolower(key)) {
            current=t
            sub(/^[^=]*=[[:space:]]*/, "", current)
            if (trim(current) == trim(value)) { found_key=1; print; next }
            print "   " key " = " value
            found_key=1
            next
          }
        }
      }
      print
    }
    END {
      if (in_sec && !found_key) { print "   " key " = " value; found_key=1 }
      if (!found_sec) exit 42
    }
  ' "$SMB_CONF" >"$tmp"
  rc=$?

  if [[ $rc -eq 42 ]]; then
    rm -f "$tmp"
    return 2
  fi
  if [[ $rc -ne 0 ]]; then
    rm -f "$tmp"
    return 1
  fi
  if cmp -s "$SMB_CONF" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  if install_validated_smbconf "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

ensure_smb_section() {
  local section="$1" params="$2"
  smb_section_exists "$section" && return 0
  local tmp
  tmp="$(mktemp "${SMB_CONF}.tmp.XXXXXX")" || return 1
  TMP_FILES+=("$tmp")
  {
    cat "$SMB_CONF"
    printf '\n[%s]\n%s\n' "$section" "$params"
  } >"$tmp"
  if install_validated_smbconf "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

ensure_printer_sections() {
  local guest="No"
  [[ $PRINTER_GUEST -eq 1 ]] && guest="Yes"

  ensure_smb_section "printers" "   comment = All Printers
   path = /var/tmp
   printable = Yes
   browseable = Yes
   guest ok = No
   read only = Yes
   create mask = 0700" || true
  ensure_smb_section 'print$' "   comment = Printer Drivers
   path = /var/lib/samba/printers
   browseable = Yes
   read only = Yes
   guest ok = No" || true

  smb_set_param printers browseable Yes || true
  smb_set_param printers printable Yes || true
  smb_set_param printers "guest ok" "$guest" || true
  smb_set_param printers "use client driver" Yes || true
  smb_set_param printers "read only" Yes || true
  smb_set_param 'print$' browseable Yes || true
  smb_set_param 'print$' "read only" Yes || true
  smb_set_param 'print$' "guest ok" "$guest" || true
  smb_set_param 'print$' "write list" "@lpadmin" || true
}

# =============================================================================
#  Bloque gestionado dentro de smb.conf
# =============================================================================

write_managed_file() {
  local path="$1" content="$2"
  if [[ -f "$path" ]] && [[ "$(cat "$path" 2>/dev/null)" == "$content" ]]; then
    return 0
  fi
  if [[ -f "$path" ]]; then
    cp -a "$path" "${path}.bak.$(date '+%Y%m%d-%H%M%S')" 2>/dev/null || true
  fi
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" >"$path"
  chmod 0644 "$path" 2>/dev/null || true
  chown root:root "$path" 2>/dev/null || true
}

write_global_conf() {
  mkdir -p "$STATE_DIR" "$STATE_SHARES"
  local content
  content="[global]
   # Gestionado por samba-share-setup.sh. No edite este bloque a mano.
   usershare allow guests = Yes
   usershare max shares = 100
   usershare path = $USHARE_DIR
   usershare owner only = Yes
   map to guest = Bad User
   server min protocol = SMB2"

  if [[ $PRINTER_ENABLED -eq 1 ]]; then
    content+="
   load printers = Yes
   printing = cups
   printcap name = cups
   cups options = raw"
  fi

  write_managed_file "$STATE_DIR/global.conf" "$content"
}

apply_managed_block() {
  [[ -f "$SMB_CONF" ]] || return 1
  mkdir -p "$STATE_DIR" "$STATE_SHARES"
  write_global_conf

  local block tmp
  block="$(mktemp "${SMB_CONF}.block.XXXXXX")" || return 1
  tmp="$(mktemp "${SMB_CONF}.tmp.XXXXXX")" || { rm -f "$block"; return 1; }
  TMP_FILES+=("$block" "$tmp")

  {
    printf '%s\n' "$BEGIN_MARKER"
    printf '# Bloque gestionado por samba-share-setup.sh — no editar a mano.\n'
    cat "$STATE_DIR/global.conf"
    local f
    for f in "$STATE_SHARES"/*.conf; do
      [[ -e "$f" ]] || continue
      printf '\n'
      cat "$f"
    done
    printf '%s\n' "$END_MARKER"
  } >"$block"

  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { skip=1; next }
    $0 == end   { skip=0; next }
    !skip { print }
  ' "$SMB_CONF" >"$tmp"

  # Asegura salto de línea antes del bloque.
  if [[ -s "$tmp" ]] && [[ "$(tail -c 1 "$tmp" | wc -l)" -eq 0 ]]; then
    printf '\n' >>"$tmp"
  fi
  cat "$block" >>"$tmp"

  if install_validated_smbconf "$tmp"; then
    rm -f "$block" "$tmp"
    ok "Configuración de Samba actualizada."
    return 0
  fi
  rm -f "$block" "$tmp"
  warn "La nueva configuración no es válida; no se aplicó ningún cambio."
  return 1
}

# =============================================================================
#  Usershares
# =============================================================================

ensure_usershares() {
  if ! getent group sambashare >/dev/null 2>&1; then
    if [[ $DRY_RUN -eq 1 ]]; then
      info "[dry-run] Crearía el grupo sambashare"
    else
      run groupadd --system sambashare || warn "No se pudo crear el grupo sambashare"
    fi
  fi

  if [[ ! -d "$USHARE_DIR" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      info "[dry-run] Crearía $USHARE_DIR (root:sambashare 1770)"
    else
      install -d -m 1770 -o root -g sambashare "$USHARE_DIR" || warn "No se pudo crear $USHARE_DIR"
    fi
  else
    if [[ $DRY_RUN -eq 0 ]]; then
      chown root:sambashare "$USHARE_DIR" 2>/dev/null || true
      chmod 1770 "$USHARE_DIR" 2>/dev/null || true
    fi
  fi

  if getent group sambashare >/dev/null 2>&1; then
    if ! id -nG "$REAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx sambashare; then
      if [[ $DRY_RUN -eq 1 ]]; then
        info "[dry-run] Añadiría $REAL_USER al grupo sambashare"
      else
        run usermod -aG sambashare "$REAL_USER" && \
          info "Añadido $REAL_USER a sambashare. Cierre sesión y vuelva a entrar para que se aplique."
      fi
    fi
  fi
}

# =============================================================================
#  Cuenta Samba
# =============================================================================

ensure_samba_user() {
  command -v pdbedit >/dev/null 2>&1 || return 0
  [[ $EUID -eq 0 ]] || return 0

  local users exists=0
  users="$(pdbedit -L 2>/dev/null | cut -d: -f1)"
  if printf '%s\n' "$users" | grep -Fxq "$REAL_USER"; then
    exists=1
  fi

  if [[ $exists -eq 0 ]]; then
    if [[ $ASSUME_YES -eq 1 ]]; then
      warn "No hay cuenta Samba para $REAL_USER. Créela manualmente: sudo smbpasswd -a $REAL_USER"
      return 0
    fi
    if ask_yn "¿Crear ahora la contraseña de Samba para $REAL_USER?" s; then
      if run_visible smbpasswd -a "$REAL_USER"; then
        ok "Cuenta Samba creada para $REAL_USER."
      else
        warn "No se pudo crear la cuenta Samba. Ejecute: sudo smbpasswd -a $REAL_USER"
      fi
    else
      warn "Sin cuenta Samba, los recursos autenticados no serán accesibles."
    fi
    return 0
  fi

  local flags
  flags="$(pdbedit -Lv "$REAL_USER" 2>/dev/null | grep -i '^Account Flags' || true)"
  if [[ "$flags" == *D* ]]; then
    if [[ $ASSUME_YES -eq 1 ]]; then
      warn "La cuenta Samba de $REAL_USER está deshabilitada. Ejecute: sudo smbpasswd -e $REAL_USER"
    elif ask_yn "La cuenta Samba de $REAL_USER está deshabilitada. ¿Habilitarla?" s; then
      run smbpasswd -e "$REAL_USER" && ok "Cuenta Samba habilitada."
    fi
  fi
}

# =============================================================================
#  Impresoras
# =============================================================================

configure_printer_sharing() {
  section "Compartición de impresoras"
  PRINTER_ENABLED=1
  mkdir -p "$STATE_DIR"
  printf '1\n' >"$PRINTER_STATE"

  if [[ $PRINTER_GUEST -eq -1 ]]; then PRINTER_GUEST=0; fi
  if [[ $PRINTER_GUEST -eq 0 && $ASSUME_YES -eq 0 ]]; then
    if ask_yn "¿Permitir imprimir a invitados sin contraseña?" n; then
      PRINTER_GUEST=1
    fi
  fi

  write_global_conf
  apply_managed_block || return 1
  ensure_printer_sections

  if [[ $DRY_RUN -eq 1 ]]; then
    info "[dry-run] Ejecutaría: cupsctl --share-printers --remote-any"
    return 0
  fi

  if systemctl is-active --quiet cups 2>/dev/null || run systemctl enable --now cups 2>/dev/null; then
    if run cupsctl --share-printers --remote-any; then
      ok "CUPS configurado para compartir impresoras y aceptar conexiones remotas."
    else
      warn "No se pudo configurar CUPS. Revise: sudo cupsctl --share-printers --remote-any"
    fi
  else
    warn "CUPS no está activo. Inícielo con: sudo systemctl enable --now cups"
  fi

  if getent group lpadmin >/dev/null 2>&1; then
    if ! id -nG "$REAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx lpadmin; then
      run usermod -aG lpadmin "$REAL_USER" && \
        info "Añadido $REAL_USER a lpadmin. Cierre sesión y vuelva a entrar."
    fi
  fi

  local count
  count="$(timeout 5 lpstat -p 2>/dev/null | grep -c '^printer' || true)"
  if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )); then
    ok "Impresoras disponibles: $count. Se compartirán por SMB."
  else
    warn "No hay impresoras configuradas en CUPS. Añada una desde Configuración → Impresoras."
  fi
  return 0
}

# =============================================================================
#  Cortafuegos
# =============================================================================

configure_firewall() {
  if [[ $EUID -ne 0 ]]; then
    return 0
  fi

  if command -v ufw >/dev/null 2>&1 && LC_ALL=C ufw status 2>/dev/null | head -n 1 | grep -qi active; then
    section "Cortafuegos (ufw)"
    if ufw app info Samba >/dev/null 2>&1; then
      run ufw allow Samba || true
    else
      run ufw allow 137,138/udp || true
      run ufw allow 139,445/tcp || true
    fi
    run ufw allow 5353/udp || true
    if [[ $PRINTER_ENABLED -eq 1 || $SHARE_PRINTER == "1" ]]; then
      run ufw allow 631/tcp || true
    fi
    if wsdd_pkg_installed; then
      run ufw allow 3702/udp || true
      run ufw allow 5357/tcp || true
    fi
    ok "Reglas de ufw aplicadas (si ya existían, no se duplican)."
    return 0
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    section "Cortafuegos (firewalld)"
    run firewall-cmd --permanent --add-service=samba || true
    run firewall-cmd --permanent --add-service=mdns || true
    if [[ $PRINTER_ENABLED -eq 1 || $SHARE_PRINTER == "1" ]]; then
      run firewall-cmd --permanent --add-service=cups || true
    fi
    if wsdd_pkg_installed; then
      run firewall-cmd --permanent --add-service=wsdd || true
    fi
    run firewall-cmd --reload || true
    ok "Reglas de firewalld aplicadas."
    return 0
  fi

  info "No hay ufw/firewalld activo; no se modifican reglas de cortafuegos."
}

# =============================================================================
#  Servicios
# =============================================================================

reload_services() {
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemd no disponible; reinicie Samba manualmente."
    return 0
  fi
  section "Reiniciando servicios"
  run systemctl enable smbd 2>/dev/null || true
  if run systemctl restart smbd; then
    ok "smbd reiniciado."
  else
    warn "No se pudo reiniciar smbd. Revise: systemctl status smbd"
  fi

  if [[ "$(tp_param 'disable netbios')" =~ ^[Nn] ]]; then
    run systemctl enable --now nmbd 2>/dev/null || true
  fi

  if pkg_installed avahi-daemon; then
    run systemctl enable --now avahi-daemon 2>/dev/null || true
  fi

  if pkg_installed cups; then
    run systemctl enable --now cups 2>/dev/null || true
  fi

  local unit
  unit="$(wsdd_unit || true)"
  if [[ -n "$unit" ]]; then
    run systemctl enable --now "$unit" 2>/dev/null || true
  fi

  run smbcontrol smbd reload-config 2>/dev/null || true
}

# =============================================================================
#  Carpetas compartidas
# =============================================================================

sanitize_share_name() {
  local raw="$1" name
  name="$(printf '%s' "$raw" | tr -d '\n\r' | sed 's/[][\\/:;|=,+*?<>"%]/_/g' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "$name" ]] || name="Compartida"
  name="${name:0:80}"
  case "${name,,}" in
    global|printers|print\$|homes|ipc\$) name="${name}_share" ;;
  esac
  printf '%s' "$name"
}

share_name_exists() {
  local name="$1" n
  while IFS= read -r n; do
    [[ "${n,,}" == "${name,,}" ]] && return 0
  done < <(tp_sections)
  if [[ $EUID -eq 0 ]]; then
    while IFS= read -r n; do
      [[ "${n,,}" == "${name,,}" ]] && return 0
    done < <(runuser -u "$REAL_USER" -- net usershare list 2>/dev/null || true)
  fi
  return 1
}

unique_share_name() {
  local base="$1"
  local candidate="$base"
  local n=2
  while share_name_exists "$candidate"; do
    candidate="${base}-${n}"
    ((n++))
    ((n > 99)) && break
  done
  printf '%s' "$candidate"
}

expand_user_path() {
  local p="$1"
  # shellcheck disable=SC2088  # "~/"* es un patrón literal intencional
  case "$p" in
    "~") p="$REAL_HOME" ;;
    "~/"*) p="$REAL_HOME/${p:2}" ;;
    /*) ;;
    *) p="$REAL_HOME/$p" ;;
  esac
  realpath -m -- "$p" 2>/dev/null || printf '%s' "$p"
}

validate_folder_path() {
  local p="$1"
  case "$p" in
    /|/etc|/etc/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/lib|/lib/*|/lib64|/lib64/*|/boot|/boot/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/root|/root/*|/home)
      if [[ $FORCE -eq 0 ]]; then
        warn "Por seguridad no se comparte la ruta del sistema: $p"
        return 1
      fi
      ;;
  esac
  if [[ "$p" == *$'\n'* ]]; then
    warn "La ruta contiene saltos de línea; no es válida."
    return 1
  fi
  return 0
}

ensure_folder_exists() {
  local p="$1"
  if [[ -d "$p" ]]; then
    return 0
  fi
  if [[ -e "$p" ]]; then
    warn "$p existe pero no es un directorio."
    return 1
  fi
  if [[ $ASSUME_YES -eq 1 ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      info "[dry-run] Crearía la carpeta $p"
      return 0
    fi
    mkdir -p "$p" && chown "$REAL_USER:$REAL_GROUP" "$p" 2>/dev/null || true
    chmod 0775 "$p" 2>/dev/null || true
    ok "Carpeta creada: $p"
    return 0
  fi
  if ask_yn "La carpeta $p no existe. ¿Crearla?" s; then
    if [[ $DRY_RUN -eq 1 ]]; then
      info "[dry-run] Crearía la carpeta $p"
      return 0
    fi
    mkdir -p "$p" && chown "$REAL_USER:$REAL_GROUP" "$p" 2>/dev/null || true
    chmod 0775 "$p" 2>/dev/null || true
    ok "Carpeta creada: $p"
    return 0
  fi
  return 1
}

create_system_share() {
  local path="$1" name="$2" comment="$3" ro="$4" guest="$5" all_users="$6"
  local slug fragment content
  slug="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_' | sed 's/^[._-]*//; s/[._-]*$//')"
  [[ -n "$slug" ]] || slug="share"
  fragment="$STATE_SHARES/${slug}.conf"

  content="[$name]
   comment = $comment
   path = $path
   browseable = Yes
   available = Yes
   read only = $([[ "$ro" -eq 1 ]] && printf 'Yes' || printf 'No')
   guest ok = $([[ "$guest" -eq 1 ]] && printf 'Yes' || printf 'No')"

  if [[ "$guest" -eq 0 && "$all_users" -eq 0 ]]; then
    content+="
   valid users = $REAL_USER"
  fi
  if [[ "$guest" -eq 1 && "$ro" -eq 0 ]]; then
    content+="
   force user = $REAL_USER
   force group = $REAL_GROUP"
  fi
  content+="
   create mask = 0664
   directory mask = 0775"

  write_managed_file "$fragment" "$content"
  if apply_managed_block; then
    ok "Recurso compartido creado: [$name] → $path"
    return 0
  fi
  rm -f "$fragment"
  warn "No se pudo crear el recurso [$name]. Se ha revertido el cambio."
  return 1
}

create_usershare() {
  local path="$1" name="$2" comment="$3" ro="$4" guest="$5"
  local acl guestflag
  if [[ "$ro" -eq 1 ]]; then acl="Everyone:R"; else acl="Everyone:F"; fi
  if [[ "$guest" -eq 1 ]]; then guestflag="y"; else guestflag="n"; fi

  if [[ $DRY_RUN -eq 1 ]]; then
    info "[dry-run] net usershare add '$name' '$path' '$comment' '$acl' 'guest_ok=$guestflag'"
    return 0
  fi
  if run_as_user "$REAL_USER" net usershare add "$name" "$path" "$comment" "$acl" "guest_ok=$guestflag"; then
    ok "Usershare creado: [$name] → $path"
    return 0
  fi
  warn "No se pudo crear el usershare (¿la carpeta es propiedad de $REAL_USER?)."
  return 1
}

create_folder_share() {
  section "Compartir una carpeta"

  local path="${FOLDER_PATH:-}" name="${SHARE_NAME:-}" comment="${SHARE_COMMENT:-}"
  local ro="$READ_ONLY" guest="$GUEST_OK" all_users="$ALL_USERS"

  if [[ -z "$path" ]]; then
    path="$(ask_text "Ruta de la carpeta a compartir" "$REAL_HOME/Compartida")"
  fi
  path="$(expand_user_path "$path")"
  validate_folder_path "$path" || return 1
  ensure_folder_exists "$path" || return 1

  if [[ -z "$name" ]]; then
    name="$(basename "$path")"
    name="$(ask_text "Nombre del recurso compartido" "$name")"
  fi
  name="$(sanitize_share_name "$name")"
  if share_name_exists "$name"; then
    local newname
    newname="$(unique_share_name "$name")"
    warn "El nombre '$name' ya existe. Se usará '$newname'."
    name="$newname"
  fi

  if [[ -z "$comment" ]]; then
    comment="Carpeta compartida de $REAL_USER"
    comment="$(ask_text "Comentario del recurso" "$comment")"
  fi
  comment="$(printf '%s' "$comment" | tr '\n\r' '  ')"

  if [[ $ASSUME_YES -eq 0 ]]; then
    if [[ $READ_ONLY -eq 0 ]] && ask_yn "¿Compartir en solo lectura?" n; then
      ro=1
    fi
    if [[ $GUEST_OK -eq 0 ]] && ask_yn "¿Permitir acceso sin contraseña (invitados)?" n; then
      guest=1
    fi
    if [[ $ALL_USERS -eq 0 ]] && [[ $guest -eq 0 ]] && ask_yn "¿Permitir a todos los usuarios de Samba (no solo a $REAL_USER)?" n; then
      all_users=1
    fi
  fi

  if [[ $guest -eq 1 && $ro -eq 0 ]]; then
    warn "Un recurso para invitados con escritura es peligroso. Los invitados escribirán como $REAL_USER."
    if [[ $ASSUME_YES -eq 0 ]] && ! ask_yn "¿Continuar de todos modos?" n; then
      return 1
    fi
  fi

  if [[ $guest -eq 1 && $ro -eq 1 ]]; then
    if ! run_as_user "$REAL_USER" test -r "$path" 2>/dev/null; then
      warn "Compruebe que los invitados puedan leer $path (permisos del sistema)."
    fi
  fi

  if [[ "$USE_USERSHARE" -eq 1 ]]; then
    create_usershare "$path" "$name" "$comment" "$ro" "$guest" || return 1
  else
    create_system_share "$path" "$name" "$comment" "$ro" "$guest" "$all_users" || return 1
  fi

  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -n "$ip" ]] || ip="IP_DEL_EQUIPO"
  info "Acceso desde Windows: \\\\$ip\\$name"
  info "Acceso desde Linux:   smb://$ip/$name"
  if [[ $guest -eq 0 ]]; then
    info "Credenciales: usuario '$REAL_USER' y su contraseña Samba."
  fi
  return 0
}

# =============================================================================
#  Listar / eliminar / contraseña
# =============================================================================

list_shares() {
  section "Recursos compartidos"
  local -a sections=()
  local s path comment ro guest found=0

  while IFS= read -r s; do
    case "${s,,}" in
      global|printers|print\$|homes|ipc\$) continue ;;
    esac
    sections+=("$s")
  done < <(tp_sections)

  if ((${#sections[@]})); then
    for s in "${sections[@]}"; do
      path="$(tp_section_param "$s" path)"
      comment="$(tp_section_param "$s" comment)"
      ro="$(tp_section_param "$s" 'read only')"
      guest="$(tp_section_param "$s" 'guest ok')"
      printf '  %s[%s]%s %s\n' "$GREEN" "$s" "$NC" "$comment"
      printf '      Ruta: %s | Solo lectura: %s | Invitados: %s\n' "${path:-?}" "${ro:-?}" "${guest:-?}"
      found=1
    done
  fi

  if [[ $EUID -eq 0 ]]; then
    local us
    us="$(runuser -u "$REAL_USER" -- net usershare list 2>/dev/null || true)"
    if [[ -n "$us" ]]; then
      printf '  %sUsershares de %s:%s\n' "$CYAN" "$REAL_USER" "$NC"
      while IFS= read -r s; do
        [[ -n "$s" ]] && printf '      %s\n' "$s"
      done <<<"$us"
      found=1
    fi
  fi

  if [[ $found -eq 0 ]]; then
    info "No hay recursos compartidos configurados."
  fi

  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -n "$ip" ]] || ip="IP_DEL_EQUIPO"
  printf '\n  Equipo: %s   IP: %s\n' "$(hostname 2>/dev/null || printf '?')" "$ip"
}

remove_share() {
  section "Eliminar un recurso compartido"
  local f n name
  local -a managed=()
  for f in "$STATE_SHARES"/*.conf; do
    [[ -e "$f" ]] || continue
    n="$(sed -n 's/^\[\(.*\)\]$/\1/p' "$f" | head -n 1)"
    [[ -n "$n" ]] && managed+=("$n")
  done

  if ((${#managed[@]})); then
    printf '  Recursos gestionados por este script:\n'
    for n in "${managed[@]}"; do printf '    - %s\n' "$n"; done
  else
    info "No hay recursos gestionados por este script."
  fi

  local us=""
  if [[ $EUID -eq 0 ]]; then
    us="$(runuser -u "$REAL_USER" -- net usershare list 2>/dev/null || true)"
    if [[ -n "$us" ]]; then
      printf '  Usershares de %s:\n' "$REAL_USER"
      while IFS= read -r n; do [[ -n "$n" ]] && printf '    - %s\n' "$n"; done <<<"$us"
    fi
  fi

  name="$(ask_text "Nombre del recurso a eliminar" "")"
  [[ -n "$name" ]] || return 1

  for f in "$STATE_SHARES"/*.conf; do
    [[ -e "$f" ]] || continue
    n="$(sed -n 's/^\[\(.*\)\]$/\1/p' "$f" | head -n 1)"
    if [[ "${n,,}" == "${name,,}" ]]; then
      if ! ask_yn "¿Eliminar el recurso [$n]?" n; then return 1; fi
      local removed="${f}.removed.$$"
      mv "$f" "$removed"
      if apply_managed_block; then
        rm -f "$removed"
        ok "Recurso [$n] eliminado."
        reload_services >/dev/null 2>&1 || true
        return 0
      fi
      mv "$removed" "$f"
      warn "No se pudo eliminar; se ha restaurado la configuración."
      return 1
    fi
  done

  if [[ -n "$us" ]] && printf '%s\n' "$us" | grep -Fxiq "$name"; then
    if ! ask_yn "¿Eliminar el usershare [$name]?" n; then return 1; fi
    if run_as_user "$REAL_USER" net usershare delete "$name"; then
      ok "Usershare [$name] eliminado."
      return 0
    fi
    warn "No se pudo eliminar el usershare."
    return 1
  fi

  warn "No se encontró un recurso gestionado llamado '$name'."
  info "Si lo creó manualmente, edite $SMB_CONF."
  return 1
}

change_samba_password() {
  section "Contraseña de Samba"
  if [[ $ASSUME_YES -eq 1 ]]; then
    warn "No se puede cambiar la contraseña en modo --yes."
    return 0
  fi
  if ! command -v smbpasswd >/dev/null 2>&1; then
    warn "smbpasswd no está instalado."
    return 0
  fi
  if pdbedit -L 2>/dev/null | cut -d: -f1 | grep -Fxq "$REAL_USER"; then
    run_visible smbpasswd "$REAL_USER" && ok "Contraseña actualizada."
  else
    run_visible smbpasswd -a "$REAL_USER" && ok "Cuenta Samba creada."
  fi
}

# =============================================================================
#  Menú de gestión
# =============================================================================

menu() {
  local opt
  while true; do
    section "Menú de recursos compartidos"
    cat <<EOF
  1) Compartir una carpeta
  2) Compartir impresoras
  3) Listar recursos compartidos
  4) Eliminar un recurso compartido
  5) Cambiar la contraseña de Samba
  6) Volver a ejecutar la auditoría
  0) Salir
EOF
    read -r -p "Opción: " opt || break
    case "$opt" in
      1)
        FOLDER_PATH=""; SHARE_NAME=""; SHARE_COMMENT=""
        READ_ONLY=0; GUEST_OK=0; ALL_USERS=0
        create_folder_share || true
        pause
        ;;
      2)
        configure_printer_sharing || true
        reload_services || true
        pause
        ;;
      3) list_shares; pause ;;
      4) remove_share || true; pause ;;
      5) change_samba_password || true; pause ;;
      6) run_audit; print_audit; pause ;;
      0|"") break ;;
      *) warn "Opción no válida." ;;
    esac
  done
}

# =============================================================================
#  Preferencias y aplicación
# =============================================================================

ask_preferences() {
  section "¿Qué desea compartir?"

  if [[ -f "$PRINTER_STATE" || $PRINTER_SHARING_DETECTED -eq 1 ]]; then
    PRINTER_ENABLED=1
  fi

  if [[ -z "$SHARE_PRINTER" ]]; then
    if [[ $PRINTER_ENABLED -eq 1 ]]; then
      if ask_yn "¿Mantener y configurar la compartición de impresoras?" s; then
        SHARE_PRINTER=1
      else
        SHARE_PRINTER=0
      fi
    else
      if ask_yn "¿Desea compartir las impresoras de este equipo?" n; then
        SHARE_PRINTER=1
        PRINTER_ENABLED=1
      else
        SHARE_PRINTER=0
      fi
    fi
  fi
  [[ "$SHARE_PRINTER" == "1" ]] && PRINTER_ENABLED=1

  if [[ -z "$SHARE_FOLDER" ]]; then
    if ask_yn "¿Desea compartir una carpeta?" n; then
      SHARE_FOLDER=1
    else
      SHARE_FOLDER=0
    fi
  fi

  if [[ "$SHARE_FOLDER" == "1" ]]; then
    if [[ -z "$FOLDER_PATH" ]]; then
      FOLDER_PATH="$(ask_text "Ruta de la carpeta a compartir" "$REAL_HOME/Compartida")"
    fi
    FOLDER_PATH="$(expand_user_path "$FOLDER_PATH")"
    if [[ -z "$SHARE_NAME" ]]; then
      SHARE_NAME="$(basename "$FOLDER_PATH")"
      SHARE_NAME="$(ask_text "Nombre del recurso compartido" "$SHARE_NAME")"
    fi
    SHARE_NAME="$(sanitize_share_name "$SHARE_NAME")"
    if [[ -z "$SHARE_COMMENT" ]]; then
      SHARE_COMMENT="$(ask_text "Comentario del recurso" "Carpeta compartida de $REAL_USER")"
    fi
  fi
}

apply_fixes() {
  section "Aplicando configuración"
  install_packages_needed
  ensure_samba_config
  ensure_usershares
  ensure_samba_user
  configure_firewall

  if [[ "$SHARE_PRINTER" == "1" ]]; then
    configure_printer_sharing || warn "La configuración de impresoras quedó incompleta."
  fi
  if [[ "$SHARE_FOLDER" == "1" ]]; then
    create_folder_share || warn "La carpeta no se pudo compartir."
  fi

  reload_services
}

ensure_samba_config() {
  if [[ ! -f "$SMB_CONF" ]]; then
    warn "No existe $SMB_CONF. Creando configuración mínima..."
    mkdir -p /etc/samba
    cat >"$SMB_CONF" <<'EOF'
[global]
   workgroup = WORKGROUP
   server role = standalone server
   map to guest = Bad User

[printers]
   comment = All Printers
   path = /var/tmp
   printable = yes
   browseable = yes
   guest ok = no
   read only = yes

[print$]
   comment = Printer Drivers
   path = /var/lib/samba/printers
   browseable = yes
   read only = yes
   guest ok = no
EOF
    chmod 0644 "$SMB_CONF"
  fi

  mkdir -p "$STATE_DIR" "$STATE_SHARES"
  write_global_conf
  if ! apply_managed_block; then
    die "No se pudo aplicar la configuración gestionada en $SMB_CONF"
  fi
  if [[ $PRINTER_ENABLED -eq 1 ]]; then
    ensure_printer_sections || warn "No se pudieron ajustar las secciones de impresoras."
  fi
}

# =============================================================================
#  Plan (dry-run) y resumen
# =============================================================================

print_plan() {
  section "Plan de acciones (simulación)"
  local -a core=(samba samba-common-bin smbclient cifs-utils avahi-daemon libnss-mdns)
  local p
  for p in "${core[@]}"; do
    pkg_installed "$p" || printf '  - Instalar %s\n' "$p"
  done
  if [[ $PRINTER_ENABLED -eq 1 || $SHARE_PRINTER == "1" ]]; then
    for p in cups cups-client; do
      pkg_installed "$p" || printf '  - Instalar %s\n' "$p"
    done
  fi
  wsdd_pkg_installed || printf '  - Instalar wsdd (si está disponible)\n'
  printf '  - Escribir configuración gestionada en %s\n' "$STATE_DIR"
  printf '  - Aplicar bloque gestionado en %s\n' "$SMB_CONF"
  [[ "$SHARE_PRINTER" == "1" ]] && printf '  - Configurar CUPS y Samba para compartir impresoras\n'
  if [[ "$SHARE_FOLDER" == "1" ]]; then
    printf '  - Compartir la carpeta %s como [%s]\n' "${FOLDER_PATH:-?}" "${SHARE_NAME:-?}"
  fi
  printf '  - Abrir puertos en ufw/firewalld si están activos\n'
  printf '  - Reiniciar smbd y servicios relacionados\n'
  info "No se ha modificado nada (--dry-run)."
}

print_summary() {
  section "Resumen final"
  if [[ $COUNT_FAIL -eq 0 ]]; then
    ok "No se detectan fallos críticos."
  else
    warn "Quedan $COUNT_FAIL fallo(s). Revise la auditoría anterior."
  fi

  printf '  Usuario:        %s\n' "$REAL_USER"
  printf '  Distribución:   %s\n' "$OS_PRETTY"
  printf '  Escritorio:     %s\n' "$DESKTOP_NAME"
  printf '  Log:            %s\n' "${LOG_FILE:-no disponible}"
  [[ -n "$SMB_BACKUP" ]] && printf '  Backup smb.conf: %s\n' "$SMB_BACKUP"

  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -n "$ip" ]] || ip="IP_DEL_EQUIPO"
  printf '\n  Desde Windows:  \\\\%s\\NOMBRE_DEL_RECURSO\n' "$ip"
  printf '  Desde Linux:    smb://%s/NOMBRE_DEL_RECURSO\n' "$ip"
  printf '  Contraseña:     sudo smbpasswd -a %s\n' "$REAL_USER"

  if [[ $PRINTER_ENABLED -eq 1 ]]; then
    printf '\n  Impresoras:     SMB + CUPS (puerto 631)\n'
  fi
  if [[ $COUNT_WARN -gt 0 ]]; then
    printf '\n  Hay %d aviso(s). No siempre impiden compartir, pero conviene revisarlos.\n' "$COUNT_WARN"
  fi
  printf '\n  Si acaba de añadirse a sambashare/lpadmin, cierre sesión y vuelva a entrar.\n'
}

# =============================================================================
#  Principal
# =============================================================================

main() {
  parse_args "$@"
  setup_identity_pre
  require_root "$@"
  setup_identity_post
  setup_logging
  detect_environment
  banner

  if [[ $DISTRO_SUPPORTED -eq 0 && $FORCE -eq 0 ]]; then
    die "Distribución no soportada ($OS_PRETTY). Use --force para continuar bajo su responsabilidad."
  fi

  run_audit
  print_audit

  if [[ $CHECK_ONLY -eq 1 ]]; then
    if [[ $COUNT_FAIL -gt 0 ]]; then
      exit 1
    fi
    exit 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    # Se necesitan las preferencias para mostrar el plan, pero sin tocar nada.
    ask_preferences
    print_plan
    exit 0
  fi

  if [[ ! -t 0 && $ASSUME_YES -eq 0 ]]; then
    die "No hay terminal interactiva. Use --yes para el modo desatendido."
  fi

  ask_preferences

  local do_fix=0
  if [[ $COUNT_FAIL -gt 0 || $COUNT_WARN -gt 0 ]]; then
    if ask_yn "¿Desea aplicar las correcciones y la configuración necesaria?" s; then
      do_fix=1
    else
      warn "No se aplicarán cambios. Algunos recursos podrían no funcionar."
    fi
  elif [[ "$SHARE_PRINTER" == "1" || "$SHARE_FOLDER" == "1" ]]; then
    do_fix=1
  fi

  if [[ $do_fix -eq 1 ]]; then
    apply_fixes
    run_audit
    print_audit
  fi

  if [[ $NO_MENU -eq 0 ]]; then
    if [[ $MENU_FORCE -eq 1 ]]; then
      menu
    elif [[ -t 0 ]]; then
      if ask_yn "¿Desea abrir el menú para añadir o gestionar más recursos?" n; then
        menu
      fi
    fi
  fi

  print_summary
  cleanup_tmp

  if [[ $COUNT_FAIL -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

trap 'cleanup_tmp' EXIT
main "$@"
