#!/bin/sh
# install-cli-linux.sh — installe les commandes `circe` et `circe-plain` dans /usr/local/bin
# Ce fichier fait partie du fork local de IGNF/circe, distribué sous GPL-3.0 (voir LICENSE).
# (RedHat/RHEL, Debian, etc. — /usr/local/bin est dans le PATH par défaut).
# Nécessite les droits root (sudo) pour écrire dans /usr/local/bin.
#
#   circe       -> CLI compilé AVEC GDAL   (build/qt_cmd_gdal/circeFR)
#   circe-plain -> CLI compilé SANS GDAL   (build/qt_cmd/circeFR)
#
# Le wrapper se place dans le dossier des données du territoire choisi
# (CIRCE_ZONE, défaut CirceFR) et injecte le fichier de métadonnées de la zone
# (DataXXXnew.txt) si l'utilisateur ne l'a pas fourni.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINDIR="${CIRCE_BINDIR:-/usr/local/bin}"

sudo mkdir -p "$BINDIR"

write_wrapper() {
    name="$1"; bin="$2"
    sudo tee "$BINDIR/$name" > /dev/null <<EOF
#!/bin/sh
# $name — lance le CLI Circé depuis n'importe quel répertoire.
CIRCE_HOME="\${CIRCE_HOME:-$ROOT}"
ZONE="\${CIRCE_ZONE:-CirceFR}"
BIN="$bin"
DATA="\$CIRCE_HOME/assets/\$ZONE"
[ -x "\$BIN" ] || { echo "binaire introuvable : \$BIN (voir BUILD.md §5)" >&2; exit 1; }
[ -d "\$DATA" ] || { echo "données de la zone \$ZONE introuvables : \$DATA" >&2; exit 1; }
cd "\$DATA" || exit 1
has_m=0
for a in "\$@"; do case "\$a" in -m|--metadataFile|--metadataFile=*|-m*) has_m=1;; esac; done
[ "\$has_m" = 0 ] && set -- -m "Data\${ZONE#Circe}new.txt" "\$@"
exec "\$BIN" "\$@"
EOF
    sudo chmod +x "$BINDIR/$name"
    echo "installé : $BINDIR/$name -> $bin"
}

write_wrapper circe       "$ROOT/build/qt_cmd_gdal/circeFR"
write_wrapper circe-plain "$ROOT/build/qt_cmd/circeFR"
echo "OK. Test : circe -l | head"
