#!/bin/sh
# Instalador de la herramienta tapadera para macOS y Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/marcosdeaza/tapadera/main/install.sh | sh
#
# Descarga el binario de la ultima version publicada y lo deja en
# /usr/local/bin (o en $PREFIX/bin si lo defines). No instala la app de macOS:
# esa se descarga de la pagina de versiones.

set -eu

REPO="marcosdeaza/tapadera"
PREFIX="${PREFIX:-/usr/local}"
DEST="$PREFIX/bin"

aviso() { printf '%s\n' "$*" >&2; }
abortar() { aviso "error: $*"; exit 1; }

case "$(uname -s)" in
    Darwin) ARCHIVO="tapadera-macos-universal.tar.gz" ;;
    Linux)
        case "$(uname -m)" in
            x86_64|amd64)  ARCHIVO="tapadera-linux-x86_64.tar.gz" ;;
            aarch64|arm64) ARCHIVO="tapadera-linux-aarch64.tar.gz" ;;
            *) abortar "arquitectura no soportada: $(uname -m)" ;;
        esac ;;
    *) abortar "sistema no soportado: $(uname -s). En Windows descarga el .zip de la pagina de versiones." ;;
esac

URL="https://github.com/$REPO/releases/latest/download/$ARCHIVO"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

aviso "· descargando $ARCHIVO"
curl -fsSL "$URL" -o "$TMP/t.tar.gz" || abortar "no se pudo descargar $URL"
tar -xzf "$TMP/t.tar.gz" -C "$TMP"
chmod +x "$TMP/tapadera"

if [ -w "$DEST" ] 2>/dev/null; then
    mv "$TMP/tapadera" "$DEST/tapadera"
else
    aviso "· $DEST necesita permisos de administrador"
    sudo mkdir -p "$DEST"
    sudo mv "$TMP/tapadera" "$DEST/tapadera"
fi

aviso "· instalado en $DEST/tapadera"
"$DEST/tapadera" version
aviso ""
aviso "  tapadera on       no dormir al cerrar la tapa"
aviso "  tapadera status   ver el estado"
