#!/usr/bin/env python3
"""Subset the OFL fonts to the glyphs the game actually uses (strings.csv + UI source) and emit WOFF2.
Noto Sans SC (OFL 1.1) for CJK/body, Orbitron (OFL 1.1) for Latin display numerals."""
import pathlib, re, sys, shutil
from fontTools import subset
from fontTools.ttLib import TTFont
root = pathlib.Path(__file__).resolve().parent.parent
src = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/fonts")
out = root / "src/assets/fonts"; out.mkdir(parents=True, exist_ok=True)
text = set(chr(c) for c in range(0x20, 0x7F))
text |= set("·—–…‹›«»←→↑↓✓✕⚡°×％：，。！？（）【】「」、；“”‘’")
for f in list((root / "src").rglob("*.ts")) + [root / "src/data/strings.csv", root / "index.html"] + list((root / "src/data").rglob("*.json")):
    text |= set(f.read_text(encoding="utf-8"))
chars = "".join(sorted(c for c in text if ord(c) >= 0x20))
def run(inp, name, extra):
    opts = subset.Options(); opts.flavor = "woff2"; opts.layout_features = ["*"]; opts.name_IDs = ["*"]; opts.notdef_outline = True
    for k, v in extra.items(): setattr(opts, k, v)
    f = TTFont(str(inp)); s = subset.Subsetter(opts); s.populate(text=chars); s.subset(f)
    dst = out / name; f.flavor = "woff2"; f.save(str(dst)); print(f"[FONT] {name}: {dst.stat().st_size/1024:.1f} KB, {len(chars)} chars requested")
run(src / "NotoSansSC.ttf", "NotoSansSC-VS.woff2", {})
run(src / "Orbitron.ttf", "Orbitron-VS.woff2", {})
shutil.copy(src / "OFL_noto.txt", out / "LICENSE-NotoSansSC-OFL.txt"); shutil.copy(src / "OFL_orbitron.txt", out / "LICENSE-Orbitron-OFL.txt")
