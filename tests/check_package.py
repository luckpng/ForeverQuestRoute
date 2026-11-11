"""Validate the distributable, optionally creating a reproducible install ZIP.

Usage: python tests/check_package.py [--build]
"""
from pathlib import Path
import hashlib
import re
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
addon = root / "ForeverQuestRoute"
manifest = (addon / "ForeverQuestRoute.toc").read_text(encoding="utf-8-sig")
version = re.search(r"^## Version: (\d+\.\d+\.\d+)$", manifest, re.M).group(1)
runtime = [line.strip() for line in manifest.splitlines() if line.strip() and not line.startswith("#")]
assert len(runtime) == len(set(runtime)), "Duplicate manifest entry"
expected = set(runtime) | {"ForeverQuestRoute.toc", "LEIA-ME.txt", "AjustarInterface.ps1"}
assert {p.name for p in addon.iterdir()} == expected, "Unexpected or missing install files"
assert runtime.index("Tracker.lua") < runtime.index("TrackerUI.lua") < runtime.index("UI.lua") < runtime.index("Core.lua")
assert f'A.version = "{version}"' in (addon / "Core.lua").read_text(encoding="utf-8-sig")

patterns = {
    "local absolute path": r"(?i)\b[A-Z]:[\\/]|/(?:Users|home)/|\\\\(?:DESKTOP-|LAPTOP-)",
    "email": r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}",
    "private key": r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    "service credential": r"gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}",
    "private network address": r"\b(?:192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|127\.0\.0\.1)\b",
}
for path in addon.iterdir():
    text = path.read_text(encoding="utf-8-sig")
    assert path.is_file() and path.suffix in {".lua", ".toc", ".txt", ".ps1"}
    for label, pattern in patterns.items():
        assert not re.search(pattern, text), f"Review {label} in {path.name}"
    if path.suffix == ".lua":
        assert not re.search(r"SendAddonMessage|SendChatMessage|https?://|os\.execute|io\.open", text), f"Review external transport in {path.name}"
for name in runtime:
    assert "/" not in name and "\\" not in name and (addon / name).is_file()
print(f"PASS package: {version}, {len(expected)} install files, manifest order and privacy patterns")

if "--build" in sys.argv:
    destination = root / "dist"
    destination.mkdir(exist_ok=True)
    archive = destination / f"ForeverQuestRoute-{version}.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as output:
        for name in sorted(expected):
            info = zipfile.ZipInfo(f"ForeverQuestRoute/{name}", (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            data = (addon / name).read_bytes().replace(b"\r\n", b"\n")
            output.writestr(info, data)
    with zipfile.ZipFile(archive) as output:
        assert output.testzip() is None and len(output.namelist()) == len(expected)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    (destination / "SHA256SUMS.txt").write_text(f"{checksum}  {archive.name}\n", encoding="utf-8")
    print(f"Built {archive.name}: SHA-256 {checksum}")
