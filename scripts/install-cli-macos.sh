#!/bin/sh
# install-cli-macos.sh — installe les commandes `circe` et `circe-plain` dans /opt/homebrew/bin
# Ce fichier fait partie du fork local de IGNF/circe, distribué sous GPL-3.0 (voir LICENSE).
# (déjà dans le PATH sur macOS Apple Silicon). Aucun sudo requis.
#
# `circe`       -> CLI compilé AVEC GDAL   (build/qt_cmd_gdal/circeFR)
# `circe-plain` -> CLI compilé SANS GDAL   (build/qt_cmd/circeFR)
#
# Le wrapper se place dans le dossier des données du territoire choisi
# (variable d'env CIRCE_ZONE, défaut CirceFR) et injecte -m DataFRnew.txt
# si l'utilisateur ne l'a pas fourni.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINDIR=/opt/homebrew/bin

write_wrapper() {
    name="$1"; bin="$2"
    cat > "$BINDIR/$name" <<EOF
#!/bin/sh
# $name — lance le CLI Circé depuis n'importe quel répertoire.
# Zone par défaut : CirceFR (surcharger avec CIRCE_ZONE=CirceANT etc.)
CIRCE_HOME="\${CIRCE_HOME:-$ROOT}"
ZONE="\${CIRCE_ZONE:-CirceFR}"
BIN="$bin"
DATA="\$CIRCE_HOME/assets/\$ZONE"
[ -x "\$BIN" ] || { echo "binaire introuvable : \$BIN (lancer scripts/build-macos.sh)" >&2; exit 1; }
[ -d "\$DATA" ] || { echo "données de la zone \$ZONE introuvables : \$DATA" >&2; echo "  -> git sparse-checkout add assets/\$ZONE" >&2; exit 1; }
cd "\$DATA" || exit 1
has_m=0
for a in "\$@"; do case "\$a" in -m|--metadataFile|--metadataFile=*|-m*) has_m=1;; esac; done
# fichier de métadonnées de la zone : Data<ZONE sans 'Circe'>new.txt (ex. DataFRnew.txt, DataGUYnew.txt)
[ "\$has_m" = 0 ] && set -- -m "Data\${ZONE#Circe}new.txt" "\$@"
exec "\$BIN" "\$@"
EOF
    chmod +x "$BINDIR/$name"
    echo "installé : $BINDIR/$name -> $bin"
}

mkdir -p "$BINDIR"
write_wrapper circe       "$ROOT/build/qt_cmd_gdal/circeFR"
write_wrapper circe-plain "$ROOT/build/qt_cmd/circeFR"
echo "OK. Teste depuis n'importe où :  circe -l | head"
