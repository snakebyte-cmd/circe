# BUILD.md — Compiler Circé 5 (IGNF/circe) sur macOS et RedHat/RHEL

Document rédigé lors d'un build de test effectué sur macOS 26 arm64 (Apple Silicon),
avec extension prévue pour RedHat/RHEL 9. Toutes les commandes ci-dessous ont été
exécutées et validées sur le Mac.

- Dépôt upstream : https://github.com/IGNF/circe (branche `main`, dernière version V5.5.0)
- Licence : GPL-3.0
- Système de build : **qmake** (fichiers `.pro`), pas de CMake

## 1. Structure du dépôt et dépendances

```
circe/
├── circelib/            bibliothèque C++ cœur (dépend de QtCore pour QDebug)
│   ├── gdal/            wrapper OGR (circe_ogr.cpp) — compilé seulement avec GDAL
│   └── tinyxml2/        embarqué, aucune dépendance externe
├── interfaces/
│   ├── qt_cmd/          CLI console  (circe.pro  → cible circeFR,  QT += core, QT -= gui)
│   └── qt_gui/          GUI Qt       (circeWidget.pro → cible circeWidget, QT += core gui widgets)
├── assets/              données géodésiques par territoire (8 zones, fichiers potentiellement gros)
└── html/                documentation du code
```

Dépendances :

| Composant | Requis pour | Notes |
|---|---|---|
| Compilateur C++ | tout | clang (macOS) ou gcc-c++ (RHEL) |
| Qt 5 (Core) | CLI | Qt 5.15 testé ; le code est Qt5 (QDesktopWidget...), éviter Qt6 |
| Qt 5 (Core+Gui+Widgets) | GUI | idem |
| GDAL (headers + lib) | formats vectoriels OGR (SHP, GeoJSON, KML, CSV...) | **optionnel** : activé par `CONFIG+=WITH_COMPLEX_FORMATS` ; nécessite GDAL 3.x patché (voir §4) |
| tinyxml2 | — | embarqué dans `circelib/tinyxml2/` |

Le bloc GDAL dans les `.pro` d'origine vise Linux (`/usr/include/gdal`, `/usr/lib/libgdal.so`).

## 2. Clone local (léger)

Le dossier `assets/` contient de grosses grilles ; on fait un clone sparse sans `assets`,
puis on ne récupère que le territoire utile :

```sh
git clone --depth 1 --filter=blob:none --sparse https://github.com/IGNF/circe.git circe
cd circe
git sparse-checkout set --no-cone '/*' '!/assets/' '!/circe12qua.png'
git sparse-checkout add assets/CirceFR      # données France métropolitaine (~14 Mo) pour les tests
# tous les territoires : git sparse-checkout disable
```

## 3. Patchs locaux (branche `local-macos-gdal`)

4 commits sur la branche `local-macos-gdal` (par rapport à `main`) :

1. `circelib/circe.cpp` : `#include "../dependances/gdal/circe_ogr.h"` → `#include "gdal/circe_ogr.h"`
   (le chemin d'origine n'existe pas dans le dépôt)
2. `interfaces/qt_cmd/circe.pro` et `interfaces/qt_gui/circeWidget.pro` : le bloc unix
   `QMAKE_WITH_GDAL` utilise désormais `gdal-config --prefix` quand disponible
   (INCLUDEPATH += `$prefix/include`, LIBS += `-L$prefix/lib -lgdal`,
   et sur macOS `QMAKE_LFLAGS += -Wl,-rpath,$prefix/lib`) ; sinon retombe sur les
   chemins Linux d'origine. **Portable macOS + RedHat.**
3. `circelib/gdal/circe_ogr.cpp` : compatibilité **GDAL 3.x** (obligatoire sur RHEL9
   où gdal-devel fournit GDAL 3.x) :
   - `OGRSFDriverRegistrar::Open(f, FALSE)` → `(OGRDataSource*) GDALOpenEx(f, GDAL_OF_VECTOR | GDAL_OF_READONLY, NULL, NULL, NULL)`
   - `OGRSFDriver` / `OGRSFDriverRegistrar::GetRegistrar()` → `GDALDriver` / `GetGDALDriverManager()`
   - `GetName()` → `GetDescription()`
   - `poDriver->CreateDataSource(f, NULL)` → `(OGRDataSource*) poDriver->Create(f, 0, 0, 0, GDT_Unknown, NULL)`

## 4. macOS (testé : macOS 26.6.2 arm64)

### 4.1 Installer Qt5 et GDAL

```sh
brew install qt@5                       # Qt 5.15.19 ; qmake = /opt/homebrew/opt/qt@5/bin/qmake
# GDAL : brew install gdal est très lourd (llvm, aws-sdk-cpp, ~2 Go). Préférer conda :
brew install miniforge                   # conda = /opt/homebrew/bin/conda
/opt/homebrew/bin/conda create -y -n gdal -c conda-forge gdal   # GDAL 3.13.3
# env GDAL : /opt/homebrew/Caskroom/miniforge/base/envs/gdal (avec bin/gdal-config)
```

### 4.2 Compiler (depuis la racine du clone)

```sh
export PATH=/opt/homebrew/opt/qt@5/bin:/opt/homebrew/Caskroom/miniforge/base/envs/gdal/bin:$PATH

# CLI sans GDAL
mkdir -p build/qt_cmd && cd build/qt_cmd
qmake ../../interfaces/qt_cmd/circe.pro && make -j8          # -> ./circeFR

# CLI avec GDAL
cd ../.. && mkdir -p build/qt_cmd_gdal && cd build/qt_cmd_gdal
qmake ../../interfaces/qt_cmd/circe.pro "CONFIG+=WITH_COMPLEX_FORMATS"
make -j8                                                      # -> ./circeFR (linké libgdal)

# GUI sans GDAL
cd ../.. && mkdir -p build/qt_gui && cd build/qt_gui
qmake ../../interfaces/qt_gui/circeWidget.pro "CONFIG+=sdk_no_version_check"
make -j8                                                      # -> ./circeWidget.app

# GUI avec GDAL
cd ../.. && mkdir -p build/qt_gui_gdal && cd build/qt_gui_gdal
qmake ../../interfaces/qt_gui/circeWidget.pro "CONFIG+=WITH_COMPLEX_FORMATS" "CONFIG+=sdk_no_version_check"
make -j8                                                      # -> ./circeWidget.app
```

Pièges :
- après un changement de flags qmake, supprimer `Makefile .qmake.stash` **et la cible**
  (`rm -f circeFR`) avant `make`, sinon make ne relink pas avec les nouveaux flags ;
- `$$system(gdal-config --cflags)` produit `-I-I...` dans qmake → d'où l'usage de `--prefix` ;
- `QMAKE_RPATHDIR` est ignoré par qmake sur mac → utiliser `QMAKE_LFLAGS += -Wl,-rpath,...` ;
- `make ... | tail; echo $?` renvoie le code de `tail`, pas de `make` → rediriger la sortie
  dans un fichier et tester `$?` directement.

### 4.3 Tests (depuis `assets/CirceFR`)

```sh
C=../../build/qt_cmd/circeFR
$C -m DataFRnew.txt -l                                            # liste des CRS
$C -m DataFRnew.txt -s RGF93v2bG. -f LP.METERS.DEGREES -S NTFLAMB2E. -F EN.METERS. 2.337229 48.856614
# attendu : 600051.756  2428697.028   < 5 cm   (Notre-Dame, Lambert II étendu)

# Test OGR/GDAL (build qt_cmd_gdal) : GeoJSON -> GeoJSON
cat > /tmp/test.geojson <<'EOF'
{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[2.337229,48.856614]},"properties":{"nom":"Notre-Dame"}}]}
EOF
../../build/qt_cmd_gdal/circeFR -m DataFRnew.txt -s RGF93v2bG. -f GDAL_OGR.METERS.DEGREES \
  -S NTFLAMB2E. -F GDAL_OGR.METERS. -p /tmp/test.geojson -P /tmp/out.geojson
# /tmp/out.geojson doit contenir [600051.756, 2428697.028, 0.0]
```

Résultats obtenus : conformes (point et fichier GeoJSON, précision < 5 cm).

## 5. RedHat / RHEL / Rocky Linux 9

### 5.1 Paquets (root)

```sh
sudo dnf install -y gcc-c++ make qt5-qtbase-devel gdal-devel
# qmake s'appelle qmake-qt5 (ou /usr/lib64/qt5/bin/qmake)
# gdal-devel fournit GDAL 3.x + gdal-config  →  le patch GDAL 3.x (§3) est requis
```

### 5.2 Clone + patch

Idem §2, puis appliquer la branche `local-macos-gdal` (les 4 commits du §3).

### 5.3 Build

```sh
mkdir -p build/qt_cmd && cd build/qt_cmd
qmake-qt5 ../../interfaces/qt_cmd/circe.pro && make -j$(nproc)                 # CLI
cd ../.. && mkdir -p build/qt_cmd_gdal && cd build/qt_cmd_gdal
qmake-qt5 ../../interfaces/qt_cmd/circe.pro "CONFIG+=WITH_COMPLEX_FORMATS" && make -j$(nproc)   # CLI+GDAL
cd ../.. && mkdir -p build/qt_gui && cd build/qt_gui
qmake-qt5 ../../interfaces/qt_gui/circeWidget.pro && make -j$(nproc)           # GUI
# GUI+GDAL : ajouter "CONFIG+=WITH_COMPLEX_FORMATS"
# serveur sans écran : sudo dnf install xorg-x11-server-Xvfb ; lancer avec xvfb-run ./circeWidget
```

Avec le patch, `gdal-config` est utilisé automatiquement ; plus besoin de créer
`ln -s /usr/lib64/libgdal.so /usr/lib/libgdal.so` (contournement sans patch).

### 5.4 Tests

Idem §4.3 (chemins relatifs depuis `assets/CirceFR`, binaires dans `build/...`).

## 6. Références

- Dépôt : https://github.com/IGNF/circe
- Site IGN (installateurs officiels, manuel) : https://geodesie.ign.fr (page Circé v5)
- Doc du code : `html/index.html` dans le dépôt
