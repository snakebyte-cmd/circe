#!/bin/sh
# build-macos.sh — compile Circé 5 (CLI + GUI, avec et sans GDAL) sur macOS (Apple Silicon)
# et prépare les bundles .app (plugins Qt copiés + re-signature ad-hoc pour Gatekeeper).
#
# Prérequis :
#   brew install qt@5
#   brew install miniforge && /opt/homebrew/bin/conda create -y -n gdal -c conda-forge gdal
#
# Usage :  ./scripts/build-macos.sh

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QT_BIN=/opt/homebrew/opt/qt@5/bin
GDAL_ENV=/opt/homebrew/Caskroom/miniforge/base/envs/gdal
export PATH="$QT_BIN:$GDAL_ENV/bin:$PATH"

cd "$ROOT"

echo "== qmake/make : CLI sans GDAL =="
rm -rf build/qt_cmd && mkdir -p build/qt_cmd && cd build/qt_cmd
qmake ../../interfaces/qt_cmd/circe.pro && make -j8
cd "$ROOT"

echo "== qmake/make : CLI avec GDAL =="
rm -rf build/qt_cmd_gdal && mkdir -p build/qt_cmd_gdal && cd build/qt_cmd_gdal
qmake ../../interfaces/qt_cmd/circe.pro "CONFIG+=WITH_COMPLEX_FORMATS" && make -j8
cd "$ROOT"

echo "== qmake/make : GUI sans GDAL =="
rm -rf build/qt_gui && mkdir -p build/qt_gui && cd build/qt_gui
qmake ../../interfaces/qt_gui/circeWidget.pro "CONFIG+=sdk_no_version_check" && make -j8
cd "$ROOT"

echo "== qmake/make : GUI avec GDAL =="
rm -rf build/qt_gui_gdal && mkdir -p build/qt_gui_gdal && cd build/qt_gui_gdal
qmake ../../interfaces/qt_gui/circeWidget.pro "CONFIG+=WITH_COMPLEX_FORMATS" "CONFIG+=sdk_no_version_check" && make -j8
cd "$ROOT"

echo "== préparation des bundles .app (plugins Qt + signature) =="
for APP in build/qt_gui/circeWidget.app build/qt_gui_gdal/circeWidget.app; do
    [ -d "$APP" ] || continue
    cd "$ROOT/$APP/Contents"
    mkdir -p PlugIns/platforms PlugIns/imageformats PlugIns/styles
    cp -f "$QT_BIN/../plugins/platforms/libqcocoa.dylib" PlugIns/platforms/ 2>/dev/null || true
    cp -f "$QT_BIN/../plugins/imageformats/"*.dylib PlugIns/imageformats/ 2>/dev/null || true
    cp -f "$QT_BIN/../plugins/styles/"*.dylib PlugIns/styles/ 2>/dev/null || true
    codesign --force --deep -s - "$ROOT/$APP"
    cd "$ROOT"
    echo "   OK: $APP"
done

echo "== terminé =="
echo "CLI : build/qt_cmd/circeFR  et  build/qt_cmd_gdal/circeFR"
echo "GUI : build/qt_gui/circeWidget.app  et  build/qt_gui_gdal/circeWidget.app"
echo "Lancement GUI : cd assets/CirceFR && open ../../build/qt_gui_gdal/circeWidget.app"
