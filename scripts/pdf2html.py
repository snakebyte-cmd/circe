#!/usr/bin/env python3
"""Convert the Circé user manual PDF into a single self-contained HTML page.

Usage:
    python3 scripts/pdf2html.py <input.pdf> <output.html> [--txt toc.txt]
                                  [--figdir doc/figures] [--addendum addendum.html]

Requires: pip install pymupdf

The TOC is recovered from the plain-text extraction (--txt, produced by
`pdftotext -layout <input.pdf> toc.txt`) because the PDF has no bookmarks.
Header/footer lines of the IGN template are dropped. Images are extracted to
--figdir and referenced relatively. If --addendum is given, its content is
injected right after the navigation (used for the "alignment with the latest
GitHub version" notes).
"""
import argparse
import html
import re
import sys
from pathlib import Path


def parse_toc(txt_path):
    """Return list of (level, number, title, page) from the pdftotext TOC pages."""
    entries = []
    if not txt_path:
        return entries
    text = Path(txt_path).read_text(encoding="utf-8", errors="replace")
    # TOC entries look like: "   1.2 Pour les utilisateurs avancés ...... 7"
    pat = re.compile(r"^\s*(\d+(?:\.\d+)*|Glossaire)\s+(.+?)\s*\.{3,}\s*(\d+)\s*$")
    for line in text.splitlines():
        m = pat.match(line)
        if m:
            num, title, page = m.group(1), m.group(2).strip(), int(m.group(3))
            level = num.count(".") + 1 if num != "Glossaire" else 1
            entries.append((level, num, title, page))
    return entries


SKIP_PATTERNS = [
    r"^\s*IGN\s*$",
    r"Service\s+de\s+géodésie",
    r"et de Métrologie",
    r"DT n°",
    r"Circé v[\d.]+ Manuel utilisateur",
    r"page \d+/\d+",
    r"73 avenue de Paris",
    r"geodesie@ign\.fr",
]
SKIP_RE = re.compile("|".join(SKIP_PATTERNS))

HEAD_RE = re.compile(r"^(\d+(?:\.\d+)*)\s+(\S.*)$")


def norm(s):
    return re.sub(r"\s+", " ", s).strip().lower()


def convert(pdf_path, out_path, txt_path, figdir, addendum_path):
    import pymupdf  # noqa: delayed import so --help works without the dep

    doc = pymupdf.open(pdf_path)
    toc = parse_toc(txt_path)
    toc_titles = {norm(t): (lvl, num, page) for lvl, num, t, page in toc}

    figdir = Path(figdir) if figdir else None
    if figdir:
        figdir.mkdir(parents=True, exist_ok=True)

    parts = []
    nav = []
    for lvl, num, title, page in toc:
        nav.append(
            f'<li class="lvl{lvl}"><a href="#p{page}">{html.escape(num)} '
            f"{html.escape(title)}</a></li>"
        )

    for pageno in range(1, doc.page_count + 1):
        page = doc[pageno - 1]
        lines = page.get_text("text").splitlines()
        body = []
        para = []

        def flush():
            if para:
                body.append("<p>" + " ".join(para) + "</p>")
                para.clear()

        for raw in lines:
            line = raw.strip()
            if not line or SKIP_RE.search(line):
                continue
            # heading: matches a TOC title (with or without its number)
            key = norm(re.sub(r"^\d+(?:\.\d+)*\s+", "", line))
            if key in toc_titles:
                flush()
                lvl, num, _ = toc_titles[key]
                slug = f"p{pageno}"
                body.append(
                    f'<h{min(lvl + 1, 6)} id="{slug}">{html.escape(line)}</h{min(lvl + 1, 6)}>'
                )
                continue
            m = HEAD_RE.match(line)
            if m and len(line) < 90 and m.group(1).count(".") <= 2:
                flush()
                lvl = m.group(1).count(".") + 1
                body.append(f"<h{min(lvl + 1, 6)}>{html.escape(line)}</h{min(lvl + 1, 6)}>")
                continue
            # command-line block
            if ("circeFR" in line or "circeWidget" in line) or re.match(r"^--?[A-Za-z]", line) or " --" in line:
                flush()
                body.append(f'<pre class="cmd">{html.escape(line)}</pre>')
                continue
            para.append(html.escape(line))
        flush()

        # images of the page
        imgs = []
        for img in page.get_images(full=True):
            xref = img[0]
            try:
                pix = pymupdf.Pixmap(doc, xref)
                if pix.n > 4:
                    pix = pymupdf.Pixmap(pymupdf.csRGB, pix)
                if figdir:
                    fn = f"fig-p{pageno}-{xref}.png"
                    pix.save(str(figdir / fn))
                    imgs.append(f'<figure><img src="{figdir.name}/{fn}" alt="figure page {pageno}">'
                                f"<figcaption>Figure — page {pageno}</figcaption></figure>")
                pix = None
            except Exception:
                continue

        parts.append(
            f'<section class="page" id="p{pageno}">\n<h2 class="pg">Page {pageno}</h2>\n'
            + "\n".join(body)
            + ("\n" + "\n".join(imgs) if imgs else "")
            + "\n</section>"
        )

    addendum = ""
    if addendum_path and Path(addendum_path).exists():
        addendum = Path(addendum_path).read_text(encoding="utf-8")

    css = """
:root { --fg:#1a1a1a; --accent:#0b5394; --bg:#fff; --code:#f4f4f4; }
* { box-sizing: border-box; }
body { font-family: "Segoe UI", "Helvetica Neue", Arial, sans-serif; color:var(--fg);
       background:var(--bg); margin:0; line-height:1.55; }
nav { position:sticky; top:0; background:#0b5394; padding:.6rem 1rem; max-height:100vh;
      overflow:auto; width:280px; float:left; }
nav a { color:#fff; text-decoration:none; font-size:.85rem; }
nav ul { list-style:none; padding-left:.6rem; margin:.2rem 0; }
nav li.lvl2 { padding-left:.8rem; } nav li.lvl3 { padding-left:1.6rem; }
main { margin-left:300px; padding:1rem 2rem 4rem; max-width:60rem; }
h1 { color:var(--accent); } h2 { border-bottom:2px solid var(--accent); padding-bottom:.2rem; }
h3, h4 { color:var(--accent); }
pre.cmd { background:var(--code); border-left:4px solid var(--accent); padding:.5rem .8rem;
          overflow-x:auto; font-size:.85rem; }
section.page { border-top:1px dashed #bbb; margin-top:2rem; padding-top:.5rem; }
h2.pg { color:#999; font-size:.9rem; border:none; text-transform:uppercase; letter-spacing:.1em; }
figure { margin:1rem 0; } figure img { max-width:100%; border:1px solid #ccc; }
figcaption { font-size:.8rem; color:#666; }
table { border-collapse:collapse; margin:1rem 0; }
th, td { border:1px solid #ccc; padding:.3rem .6rem; font-size:.9rem; text-align:left; }
th { background:var(--code); }
.addendum { background:#fff8e1; border:1px solid #e0c060; padding:1rem 1.5rem; margin:1rem 0; }
@media print { nav { display:none; } main { margin-left:0; } }
"""

    out = f"""<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>Manuel utilisateur de Circé (version HTML)</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>{css}</style>
</head>
<body>
<nav>
<h1 style="color:#fff;font-size:1.1rem;margin:.2rem 0 .6rem">Circé — Manuel utilisateur</h1>
<ul>{''.join(nav)}</ul>
</nav>
<main>
<h1>Manuel utilisateur de Circé</h1>
<p>Conversion HTML du manuel officiel <em>« Ciré v5.4 — Manuel utilisateur »</em>
(IGN, DT n° 60082 / 8648, septembre 2022, 46 pages, PDF distribué par
<a href="https://geodesie.ign.fr/files/geodesie/2024-11/CirceV5ManuelUtilisateur.pdf">geodesie.ign.fr</a>).
Générée par <code>scripts/pdf2html.py</code>.</p>
<div class="addendum">
{addendum}
</div>
{''.join(parts)}
</main>
</body>
</html>
"""
    Path(out_path).write_text(out, encoding="utf-8")
    print(f"wrote {out_path} ({len(out)} bytes, {doc.page_count} pages, {len(toc)} TOC entries)")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("pdf")
    ap.add_argument("out")
    ap.add_argument("--txt", help="pdftotext -layout output used to recover the TOC")
    ap.add_argument("--figdir", default=None)
    ap.add_argument("--addendum", default=None)
    a = ap.parse_args()
    convert(a.pdf, a.out, a.txt, a.figdir, a.addendum)


if __name__ == "__main__":
    sys.exit(main())
