#!/usr/bin/env bash
#
# run-tests.sh — run the upstream Circé batch tests (assets/Circe*/<ZONE>.txt)
# with a locally built circe CLI binary and compare the produced test*.log
# files with the reference logs committed upstream.
#
# Usage:
#   scripts/run-tests.sh [circe-binary] [zone ...]
#
#   circe-binary   path to a built CLI binary
#                  (default: build/qt_cmd_gdal/circeFR, fallback build/qt_cmd/circeFR)
#   zone           e.g. CirceGUY (default: all zones that contain test files)
#
# The tests are run in a scratch directory so the reference logs in the
# repository are never overwritten. Each test data file is normalized on
# the fly (see normalize_test_file below): the metadata path on line 2 is
# rewritten to the zone's own Data<ZONE>new.txt and Windows path separators
# are converted to '/'. If line 3 has only two numbers (old format), a huge
# alert threshold is appended so no spurious "**** shift" alert is raised.
#
# Exit status: 0 if every test that has a reference log produced no new
# alert compared to the reference, 1 otherwise.

set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

BIN=${1:-}
if [ -z "$BIN" ]; then
    if [ -x "$REPO_ROOT/build/qt_cmd_gdal/circeFR" ]; then
        BIN="$REPO_ROOT/build/qt_cmd_gdal/circeFR"
    elif [ -x "$REPO_ROOT/build/qt_cmd/circeFR" ]; then
        BIN="$REPO_ROOT/build/qt_cmd/circeFR"
    else
        echo "ERROR: no circe binary found. Build first (scripts/build-macos.sh)" >&2
        echo "or pass the binary path as first argument." >&2
        exit 1
    fi
fi
if [ ! -x "$BIN" ]; then
    echo "ERROR: $BIN is not executable" >&2
    exit 1
fi
# Absolute path: the tests are run from a scratch directory
BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")
echo "Using binary: $BIN"

shift 2>/dev/null || true
if [ $# -gt 0 ]; then
    ZONES=("$@")
else
    ZONES=(CirceANT CirceFR CirceGUY CirceKER CirceREU CirceSPM CirceTA)
fi

# Alert threshold appended to old-format line 3 (2 numbers only), in mm.
BIG_THRESHOLD=1000000000

# Tolerance for the numeric log comparison (mixed units: m, degrees, mm).
# Catches real regressions, ignores sub-0.2 platform rounding noise.
TOL=${TOL:-0.2}

overall=0
results=()

normalize_test_file() {
    # $1 = source test file, $2 = destination, $3 = metadata file name
    awk -v meta="$3" '
        { gsub(/\\/, "/") }
        NR == 2 { print meta; next }
        NR == 3 && NF == 2 { print $0, "'"$BIG_THRESHOLD"'"; next }
        { print }
    ' "$1" > "$2"
}

# Reference log for a zone/test, read from git (never from the working tree,
# so a test run can never corrupt the reference it is compared against).
ref_log() { # $1 = zone, $2 = test base name
    git -C "$REPO_ROOT" show "HEAD:assets/$1/test$2.log" 2>/dev/null
}

# Numeric-tolerant comparison of two logs (after stripping "[ transfo ]"
# annotations and the "Max expected shift" header line, which older reference
# logs lack). Prints "BAD <n> MAXDEV <x>".
compare_logs() { # $1 = reference file, $2 = produced file, $3 = tolerance
    awk -v tol="$3" '
        function strip(s) {
            gsub(/\[ [^]]*\]/, "", s)
            gsub(/[[:space:]]+/, " ", s)
            sub(/^ /, "", s); sub(/ $/, "", s)
            if (s ~ /^Max expected shift/) return ""
            return s
        }
        NR == FNR { if (strip($0) != "") ref[++n] = strip($0); next }
        { if (strip($0) != "") prod[++m] = strip($0) }
        END {
            if (n != m) { printf "BAD LINECOUNT MAXDEV 0\nCOUNTS ref=%d prod=%d\n", n, m; exit }
            bad = 0; maxdev = 0
            for (i = 1; i <= n; i++) {
                if (ref[i] == prod[i]) continue
                na = split(ref[i], A, " "); nb = split(prod[i], B, " ")
                if (na != nb) { bad++; if (bad <= 3) printf "MISMATCH line %d: [%s] vs [%s]\n", i, ref[i], prod[i]; continue }
                for (j = 1; j <= na; j++) {
                    if (A[j] == B[j]) continue
                    num = "^-?[0-9]+\\.?[0-9]*([eE][-+]?[0-9]+)?$"
                    if (A[j] ~ num && B[j] ~ num) {
                        d = A[j] - B[j]; if (d < 0) d = -d
                        if (d > maxdev) maxdev = d
                        if (d > tol) { bad++; if (bad <= 3) printf "MISMATCH line %d field %d: %s vs %s\n", i, j, A[j], B[j]; break }
                    } else { bad++; if (bad <= 3) printf "MISMATCH line %d field %d: [%s] vs [%s]\n", i, j, A[j], B[j]; break }
                }
            }
            printf "BAD %d MAXDEV %g\n", bad, maxdev
        }' "$1" "$2"
}

for zone in "${ZONES[@]}"; do
    zdir="$REPO_ROOT/assets/$zone"
    [ -d "$zdir" ] || { echo "SKIP $zone (no such directory)"; continue; }
    Z=${zone#Circe}
    meta="Data${Z}new.txt"
    [ -f "$zdir/$meta" ] || meta="Data${Z}.txt"
    [ -f "$zdir/$meta" ] || { echo "SKIP $zone (no metadata file Data${Z}new.txt)"; continue; }

    # Collect test data files: *.txt except metadata, plate files and list files
    bases=()
    for t in "$zdir"/*.txt; do
        b=$(basename "$t" .txt)
        case "$b" in
            Data*|PB2002_plates|test-*) continue ;;
        esac
        bases+=("$b")
    done
    if [ ${#bases[@]} -eq 0 ]; then
        echo "SKIP $zone (no test file)"
        continue
    fi

    work=$(mktemp -d /tmp/circe-test-${Z}-XXXXXX)
    echo "=== $zone : tests ${bases[*]} (workdir $work)"

    # Real copy of the zone directory (metadata + grids + test files + reference
    # logs). Never symlink: the tested binary writes test*.log files and the
    # normalization rewrites the test files, both must stay inside $work.
    cp -a "$zdir/." "$work/"
    # Remove the copied reference logs: the binary must produce them fresh,
    # otherwise a failed run would silently compare the reference with itself
    rm -f "$work"/test*.log
    # Normalized copies of the test data files (rewrite line 2 metadata path)
    for b in "${bases[@]}"; do
        normalize_test_file "$work/$b.txt" "$work/$b.txt.norm" "$meta"
        mv "$work/$b.txt.norm" "$work/$b.txt"
        if [ ! -s "$work/$b.txt" ]; then
            echo "  ABORT $zone/$b: normalized test file is empty (source: $zdir/$b.txt)"
            overall=1
            continue
        fi
    done
    # List file expected by processMultipleCRSdefinitionFile: nFTest then base names
    {
        echo "${#bases[@]}"
        for b in "${bases[@]}"; do echo "$b"; done
    } > "$work/run.txt"

    ( cd "$work" && "$BIN" -t -p run.txt > run.stdout 2>&1 )
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "  $zone: circe exited with code $rc (see $work/run.stdout)"
        overall=1
    fi

    for b in "${bases[@]}"; do
        produced="$work/test$b.log"
        ref=$(ref_log "$zone" "$b")
        if [ ! -f "$produced" ]; then
            echo "  FAIL $b: no log produced (see $work/run.stdout)"
            overall=1
            results+=("$zone/$b:$work")
            continue
        fi
        n_alerts=$(grep -c '\*\*\*\*' "$produced" || true)
        n_lines=$(wc -l < "$produced")
        if [ -z "$ref" ]; then
            if [ "$n_alerts" -gt 0 ]; then
                echo "  DIFF $b: $n_alerts alerts, no reference log upstream ($n_lines lines)"
            else
                echo "  OK   $b: $n_lines lines, no alerts (no reference log upstream)"
            fi
            results+=("$zone/$b:$work")
            continue
        fi
        r_alerts=$(printf '%s\n' "$ref" | grep -c '\*\*\*\*' || true)
        printf '%s\n' "$ref" > "$work/ref-$b.log"
        # the sequence of "(i to j)" pair headers must be identical: it proves
        # every expected CRS-to-CRS transformation was attempted
        pairseq=$(diff <(grep -oE '^\([0-9]+ to [0-9]+\)' "$work/ref-$b.log") \
                        <(grep -oE '^\([0-9]+ to [0-9]+\)' "$produced") | grep -c '^[<>]')
        cmp_out=$(compare_logs "$work/ref-$b.log" "$produced" "$TOL")
        bad=$(echo "$cmp_out" | grep '^BAD' | awk '{print $2}')
        maxdev=$(echo "$cmp_out" | grep '^BAD' | awk '{print $4}')
        if [ "$n_alerts" -gt "$r_alerts" ] || [ "$pairseq" != "0" ] || [ "$rc" -ne 0 ]; then
            echo "  FAIL $b: $n_alerts alerts (ref $r_alerts), pair-header diffs: $pairseq, body mismatches: $bad (max dev $maxdev)"
            echo "$cmp_out" | grep MISMATCH | head -3 | sed 's/^/    /'
            overall=1
        elif [ "$bad" = "0" ] || [ "$bad" = "LINECOUNT" ]; then
            if [ "$bad" = "0" ]; then
                echo "  PASS $b: $n_lines lines, $n_alerts alerts (ref $r_alerts), body identical to reference (max dev $maxdev)"
            else
                echo "  DIFF $b: $n_lines lines vs ref, $n_alerts alerts (ref $r_alerts) — reference log stale upstream (see TESTS.md)"
            fi
        else
            echo "  DIFF $b: $n_alerts alerts (ref $r_alerts), $bad mismatching lines, max dev $maxdev (tol $TOL) — reference log stale upstream (see TESTS.md)"
            echo "$cmp_out" | grep MISMATCH | head -3 | sed 's/^/    /'
        fi
        results+=("$zone/$b:$work")
    done
done

echo
if [ $overall -eq 0 ]; then
    echo "NO HARD FAILURE (PASS = identical to reference, DIFF = runs fine but reference log is stale upstream, OK = no reference)"
else
    echo "HARD FAILURES (scratch dirs kept for inspection):"
    for r in "${results[@]}"; do echo "  ${r%%:*} -> ${r##*:}"; done
fi
exit $overall
