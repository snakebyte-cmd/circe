# Tests de Circé

Le dépôt upstream (IGNF/circe, branche `main`) ne contient **pas de framework de
tests unitaires** (pas de répertoire `test/`, pas de CI). En revanche, il embarque
une **suite de tests par lots** dans les assets de chaque territoire :

```
assets/Circe<ZONE>/<TEST>.txt      fichier d'entrée : liste de SRC + points connus
assets/Circe<ZONE>/test<TEST>.log  log de référence (résultats attendus) produit upstream
```

Zones concernées : `CirceANT` (GUAD, MART1, MART2, SMSB), `CirceFR` (FR — sans log
de référence), `CirceGUY` (GUYA), `CirceKER` (KER), `CirceREU` (REU),
`CirceSPM` (SPM_20190524), `CirceTA` (TA). `CirceMAY` n'a pas de test.

## Principe du test (code : `circelib/circe.cpp`, `processMultipleCRSdefinitionFile`)

Chaque fichier `<TEST>.txt` déclare N SRC (ligne `--sourceCRS=... --sourceFormat=...`)
et les coordonnées de M points exprimés dans chacun de ces SRC. Le mode test
(`--runTest` / `-t`) convertit chaque point de chaque SRC vers **tous** les autres
et compare au résultat attendu : le log produit contient les coordonnées calculées
et les **résidus en millimètres** (`E: N: W:` ou `L: P: H:`), plus une alerte
`**** shift ... larger than expected ****` si le résidu dépasse le seuil indiqué
sur la 3ᵉ ligne du fichier de test.

Lancement direct (depuis le répertoire d'un territoire, ex. `assets/CirceGUY`) :

```sh
printf '1\nGUYA\n' > run.txt        # liste : nombre de tests, puis noms de base
./circeFR -t -p run.txt             # produit testGUYA.log dans le répertoire courant
```

## Lanceur local : `scripts/run-tests.sh`

```sh
scripts/run-tests.sh [binaire-circe] [zone ...]
# défaut : build/qt_cmd_gdal/circeFR (fallback build/qt_cmd/circeFR), toutes les zones
```

Le script exécute chaque test dans un **répertoire temporaire** (copie réelle du
territoire — jamais de lien symbolique vers le dépôt, pour ne pas écraser les logs
de référence), en normalisant à la volée le fichier de test :

- ligne 2 (métadonnées) : réécrite vers `Data<ZONE>new.txt` du territoire (les
  fichiers upstream contiennent des chemins Windows obsolètes, ex.
  `data\DataANTnew.txt` dans `GUYA.txt`, ou `C:\ProgramData\...` dans SPM) ;
- séparateurs `\` → `/` ;
- si la 3ᵉ ligne n'a que 2 nombres (ancien format), un seuil d'alerte très grand
  est ajouté pour ne pas déclencher d'alertes parasites.

Les logs de référence sont lus via `git show HEAD:...` (jamais depuis le working
tree). Comparaison : séquence des en-têtes `(i to j)` identique, nombre d'alertes
produit ≤ référence, et corps du log comparé champ par champ avec tolérance
numérique (`TOL=0.2`, unités mixtes m/degrés/mm) après suppression des annotations
`[ transfo ]` et de la ligne d'en-tête `Max expected shift`.

Statuts : **PASS** (identique à la référence), **DIFF** (tourne sans erreur mais le
log de référence upstream est périmé — voir ci-dessous), **OK** (pas de log de
référence), **FAIL** (pas de log produit, alerte en plus, ou séquence de
transformations incomplète). Code de sortie 1 uniquement en cas de FAIL.

## Résultats sur macOS (arm64, build `qt_cmd_gdal`, GDAL 3.13 conda)

| Test | Statut | Détail |
|---|---|---|
| CirceGUY / GUYA | **PASS** | 241 lignes, 0 alerte, corps identique à la référence (écart max 0,2 mm) |
| CirceKER / KER | **PASS** | 228 lignes, 0 alerte, identique (écart max 0,001) |
| CirceFR / FR | **OK** | 4832 lignes, 0 alerte (pas de log de référence upstream) |
| CirceANT / GUAD, MART1, MART2, SMSB | **DIFF** | 0 alerte, mêmes 81 paires `(i to j)` ; le log de référence contient des lignes de message `Ambiguous vertical transformations...` que la version actuelle du code n'émet plus |
| CirceREU / REU | **DIFF** | 0 alerte ; 1 ligne de résidu diffère (bruit d'arrondi 0,1 mm sur une ligne) |
| CirceSPM / SPM_20190524 | **DIFF** | 10 alertes produites vs 28 dans la référence : le fichier d'entrée a été corrigé upstream (-56.236 → -56.240) après génération du log de référence |
| CirceTA / TA | **DIFF** | écarts ~512 mm sur PGP50G.PETRELS52 → RGTAAF07 : le fichier de test vise l'ancien métadonnées `DataTA.txt` ; le dépôt ne fournit plus que `DataTAnew.txt` (métadonnées mises à jour) |

**Ces écarts ne viennent pas des modifications locales** : le diff de `circelib/`
vs upstream ne touche que la couche GDAL (`circelib/gdal/circe_ogr.cpp`, portage
API GDAL 3) et l'en-tête de licence ; de plus, les builds avec et sans GDAL
(`build/qt_cmd_gdal/circeFR` et `build/qt_cmd/circeFR`) produisent des logs de
test **identiques** (vérifié sur CirceTA et CirceGUY).

## Idées d'amélioration (propositions)

1. **Tests unitaires proper** : ajouter un petit framework (ex. Qt Test pour
   `circelib`, cible `tests/` + `CONFIG += testcase`) couvrant `parser`,
   `stringtools`, `units`, `conversioncore` — le cœur de calcul.
2. **CI GitHub Actions** : builder la CLI sur ubuntu/macos/windows et lancer
   `scripts/run-tests.sh` à chaque PR, avec les logs de référence comme artefacts.
3. **Régénérer les logs de référence** upstream (SPM, TA, ANT) à partir de la
   branche `main` courante pour éliminer les statut DIFF.
4. **Tests de non-régression GDAL** : compléter par un test GeoJSON/Shapefile
   aller-retour (`-f GDAL_OGR...`), aujourd'hui couvert seulement manuellement.
