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

Tout en une commande (rebuild complet + préparation des `.app`) :

```sh
./scripts/build-macos.sh
```

Ce script compile les 4 cibles (CLI/GUI × avec/sans GDAL) dans `build/`, puis copie
les plugins Qt dans chaque `.app` et re-signe le bundle (voir §4.4). Équivalent manuel :

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

### 4.3 Commande `circe` accessible de partout (macOS)

Au lieu d'un alias dans `.zshrc`, on installe un **wrapper** dans `/opt/homebrew/bin`
(déjà dans le PATH) — plus propre et découvrable :

```sh
./scripts/install-cli-macos.sh
# installe :
#   circe        -> CLI avec GDAL    (build/qt_cmd_gdal/circeFR)
#   circe-plain  -> CLI sans GDAL    (build/qt_cmd/circeFR)
```

Le wrapper se place automatiquement dans le dossier des données du territoire
(`assets/$CIRCE_ZONE`, défaut `CirceFR`) et injecte `-m DataFRnew.txt` si absent.

Exemples, depuis n'importe quel répertoire :

```sh
circe -l                                                          # liste des CRS (zone France)
CIRCE_ZONE=CirceANT circe -l                                      # autre zone (si assets téléchargés)
circe -s RGF93v2bG. -f LP.METERS.DEGREES -S NTFLAMB2E. -F EN.METERS. 2.337229 48.856614
# -> 600051.756  2428697.028   < 5 cm
circe -h                                                          # aide complète
```

### 4.3b Autres territoires (zones)

Chaque territoire a son dossier `assets/CirceXXX` et son fichier de métadonnées
`DataXXXnew.txt`. Le wrapper choisit automatiquement le bon fichier d'après la zone.
Pour utiliser une zone, télécharge d'abord ses données puis lance avec `CIRCE_ZONE` :

```sh
git sparse-checkout add assets/CirceGUY          # ex. Guyane
CIRCE_ZONE=CirceGUY circe -l                     # liste les CRS de la zone
# Guyane : RGFG95 / RGFG95G (géodésique), RGFG95UTM22 (projection),
#          GUYA77 = NGG 1977 Guyane (vertical)
CIRCE_ZONE=CirceGUY circe -s RGFG95G.GUYA77 -f LP.METERS.DEGREES -S RGFG95UTM22.GUYA77 -F EN.METERS. -52.3333 4.9333
# Cayenne -> UTM22 : 352169.812  545439.325
```

Zones disponibles : CirceANT, CirceFR, CirceGUY, CirceKER, CirceMAY, CirceREU, CirceSPM, CirceTA.
Note : la précision verticale en Guyane est de 5/10 cm (grille ggguy15), contre < 5 cm en métropole.

### 4.4 Tests (depuis `assets/CirceFR`)

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

### 4.5 Lancer la GUI sur macOS (Gatekeeper + plugins Qt)

`make` ne déploie pas les plugins Qt dans le `.app` et laisse une signature ad-hoc
incomplète → macOS affiche « impossible d'ouvrir ». `scripts/build-macos.sh` corrige
ça automatiquement (copie des plugins + `codesign --force --deep -s -`). En manuel :

```sh
export PATH=/opt/homebrew/opt/qt@5/bin:$PATH
for APP in build/qt_gui/circeWidget.app build/qt_gui_gdal/circeWidget.app; do
  cd "$APP/Contents"
  mkdir -p PlugIns/platforms PlugIns/imageformats PlugIns/styles
  cp /opt/homebrew/opt/qt@5/plugins/platforms/libqcocoa.dylib PlugIns/platforms/
  cp /opt/homebrew/opt/qt@5/plugins/imageformats/*.dylib PlugIns/imageformats/
  cp /opt/homebrew/opt/qt@5/plugins/styles/*.dylib PlugIns/styles/
  codesign --force --deep -s - "$OLDPWD/$APP"
  cd - >/dev/null
done
```

(Alternative à la copie manuelle : `macdeployqt circeWidget.app`, mais il embarque aussi
toutes les dépendances conda de GDAL — lourd. La copie des seuls plugins Qt suffit,
libgdal reste résolue via le rpath conda.)

Lancement (toujours depuis le dossier des données) :

```sh
cd /Users/snakebyte/Python/circe/assets/CirceFR
open ../../build/qt_gui_gdal/circeWidget.app
```

Si macOS affiche encore un avertissement : clic droit sur l'app > « Ouvrir », ou
Réglages système > Confidentialité et sécurité > « Ouvrir quand même ».
Vérification sans écran : `QT_QPA_PLATFORM=offscreen timeout 8 <app>/Contents/MacOS/circeWidget`
doit afficher un warning Qt puis tourner (tué par le timeout).

### 4.6 Utilisation avancée du CLI

```sh
circe -h                                   # aide complète (toutes les options)

# transformation d'un FICHIER de points (un point par ligne, séparateur espace) :
circe -s RGF93v2bG. -f LP.METERS.DEGREES -S RGF93LAMB93. -F EN.METERS. \
      -p points_in.txt -P points_out.txt

# fichier vectoriel via GDAL (SHP, GeoJSON, KML, CSV...) — format GDAL_OGR :
circe -s RGF93v2bG. -f GDAL_OGR.METERS.DEGREES -S NTFLAMB2E. -F GDAL_OGR.METERS. \
      -p in.geojson -P out.geojson

# sortie JSON + fichier de log :
circe -O JSON -o circe.log -s RGF93v2bG. -f LP.METERS.DEGREES -S NTFLAMB2E. -F EN.METERS. 2.337229 48.856614

# coordonnées 4D (avec époques) : -e époque source, -E époque cible (années décimales)
circe -s ITRF2014G. -e 2010.0 -S RGF93v2bG. -E 2019.0 -f LP.METERS.DEGREES -F LP.METERS.DEGREES 2.337229 48.856614 100

# listes utiles : -l CRS, -x/-X frames, -w/-W transformations, -U unités, -v/-V formats
```

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

## 6. RedHat : commande `circe` dans le PATH (Linux)

```sh
sudo ./scripts/install-cli-linux.sh     # installe circe et circe-plain dans /usr/local/bin
circe -l
CIRCE_ZONE=CirceGUY circe -l            # autres zones, idem macOS
```

## 7. Publier ce fork sur GitHub (SSH + commits signés GPG)

### 7.1 Clé SSH dédiée (générée localement — GitHub ne voit jamais la clé privée)

```sh
ssh-keygen -t ed25519 -C "github" -N "" -f ~/.ssh/id_ed25519_github
# ~/.ssh/config :
#   Host github.com
#     IdentityFile ~/.ssh/id_ed25519_github
#     IdentitiesOnly yes
cat ~/.ssh/id_ed25519_github.pub     # copier dans GitHub > Settings > SSH and GPG keys > New SSH key
ssh -T git@github.com                # -> "Hi <user>! You've successfully authenticated..."
# Méthode la plus fiable (évite les erreurs de copier-coller) : GitHub CLI
#   brew install gh && gh auth login
#   gh ssh-key add ~/.ssh/id_ed25519_github.pub -t "MacBook circe"
#   gh gpg-key add ~/.ssh/cle-gpg-pub.asc
```

### 7.2 Clé GPG pour signer les commits (badge « Verified » sur GitHub)

```sh
brew install gnupg
export PATH=/opt/homebrew/bin:$PATH
gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-gen-key 'Snake Byte <trinbash@proton.me>' rsa4096 sign never
KEYID=$(gpg --list-secret-keys --with-colons | awk -F: '/^sec/{print $5; exit}')
git config --global user.signingkey "$KEYID"
git config --global commit.gpgsign true
git config --global gpg.program /opt/homebrew/bin/gpg
gpg --armor --export "$KEYID" > ~/.ssh/cle-gpg-pub.asc   # fichier propre pour upload
# NE PAS recopier le bloc à la main depuis le terminal (risque de tronquer/altérer l'armor → HTTP 422).
# Upload recommandé via CLI :  gh auth login  puis  gh gpg-key add ~/.ssh/cle-gpg-pub.asc
# Notes :
# - la clé doit avoir la capacité certify+sign ([SC]) ; un 'sign' seul est rejeté par GitHub ;
# - l'email de la clé doit être un email vérifié du compte GitHub pour le badge « Verified » ;
# - en cas d'erreur HTTP 422 « not a valid GPG key », régénérer le fichier avec la commande ci-dessus
#   (export direct, pas de copier-coller) et réessayer.
# re-signer tout l'historique du fork :  git rebase --exec 'git commit --amend --no-edit' 0bc8772..HEAD
```

Note : pour le badge « Verified », l'email de la clé GPG doit être un email **vérifié** du compte GitHub.

### 7.3 Forker et pousser

```sh
# sur github.com/IGNF/circe : bouton "Fork" -> compte snakebyte-cmd
#   => crée github.com/snakebyte-cmd/circe (historique upstream conservé)
git remote add github git@github.com:snakebyte-cmd/circe.git   # déjà fait ici
git ls-remote github                                          # vérifier que le fork répond (SSH OK)
git push -u github local-macos-gdal    # branche de travail (patchs + doc + scripts, signés GPG)
# main n'a pas besoin d'être poussée : le fork l'a déjà (même commit que upstream)
```

Alternative sans SSH : remote HTTPS + Personal Access Token (Settings > Developer settings).
Ancienne procédure CodeBerg (remplacée) : remote `https://codeberg.org/<user>/circe.git`.

## 8. Mettre à jour le fork (nouvelles versions upstream)

```sh
git remote add upstream https://github.com/IGNF/circe.git    # une seule fois
git fetch upstream
git checkout local-macos-gdal
git rebase upstream/main      # ou merge ; résoudre les conflits si upstream touche les mêmes lignes
./scripts/build-macos.sh      # rebuilder et re-tester (macOS)
```

## 9. FAQ / dépannage

- `dyld: Library not loaded: @rpath/libgdal...` → le rpath a sauté : relancer `./scripts/build-macos.sh`
- `Cannot open` / `Bad Metadata filename` → lancer via le wrapper `circe` (il fait le `cd` dans `assets/<zone>`)
- GUI « impossible d'ouvrir » → voir §4.5 (plugins Qt + `codesign`)
- `qmake: command not found` → `export PATH=/opt/homebrew/opt/qt@5/bin:$PATH` (macOS) ou `qmake-qt5` (RHEL)
- après un changement de flags qmake : supprimer `Makefile`, `.qmake.stash` **et la cible** avant `make`
- `make ... | tail; echo $?` renvoie le code de `tail` → rediriger la sortie dans un fichier

## 10. Licence et modifications (GPL-3.0)

- Le projet upstream est distribué sous **GPL-3.0** (`LICENSE`, inchangé dans ce fork).
- Ce fork ajoute des modifications sur la branche `local-macos-gdal` (voir §3 et
  `git log 0bc8772..HEAD`) : patchs de build (qmake `.pro`), compatibilité GDAL 3.x,
  correction d'un `#include`, scripts `scripts/*.sh`, documentation (`BUILD.md`,
  section added to `README.md`). **L'ensemble reste distribué sous GPL-3.0** :
  - `LICENSE` conservé tel quel ;
  - les notices de copyright des fichiers modifiés sont conservées (aucune supprimée) ;
  - les nouveaux fichiers portent une mention GPL-3.0 en en-tête ;
  - l'historique git conserve la trace de chaque modification (GPLv3 §4/§5 : distribuer
    les sources des versions modifiées sous la même licence, en indiquant les changements).
- Dépendances : **compatibles GPL-3.0** — GDAL (licence MIT/X11, lien dynamique uniquement,
  non redistribué), Qt 5 (LGPL-3.0, lien dynamique), tinyxml2 embarqué (zlib). Aucune
  bibliothèque tierce n'est embarquée dans ce dépôt.
- Aucune clause additionnelle ("additional terms", GPLv3 §7) n'est ajoutée.

## 11. Références

- Dépôt upstream : https://github.com/IGNF/circe
- Site IGN (installateurs officiels, manuel) : https://geodesie.ign.fr (page Circé v5)
- Doc du code : `html/index.html` dans le dépôt
- CodeBerg : https://codeberg.org
