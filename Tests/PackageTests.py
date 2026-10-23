"""Validate the release allowlist without extracting private/local files."""
from pathlib import Path
import plistlib
import hashlib
import stat
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
version = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
archive = Path(sys.argv[1])
prefix = f"CodexRealtimeStatusbar-v{version}/"
shared = {"安装或升级.command", "PayloadSHA256.txt", "安装交接技能.command", "使用说明.md", "README.en.md", "skills/handoff/SKILL.md",
          "skills/handoff/agents/openai.yaml", "skills/handoff/references/handoff.md"}
app = {"Contents/Info.plist", "Contents/MacOS/CCUsage", "Contents/_CodeSignature/CodeResources",
       "Contents/Resources/AppIcon.icns", "Contents/Resources/Localization/en.json",
       "Contents/Resources/en.lproj/InfoPlist.strings", "Contents/Resources/zh-Hans.lproj/InfoPlist.strings"}
with zipfile.ZipFile(archive) as package:
    assert package.testzip() is None, "Damaged zip entry"
    # macOS ditto stores UTF-8 names without the ZIP UTF-8 flag; Finder handles them.
    entries = {item.filename if item.flag_bits & 0x800 else item.filename.encode("cp437").decode("utf-8"): item
               for item in package.infolist()}
    expected = {prefix + name for name in shared} | {prefix + "Codex实时状态栏.app/" + name for name in app}
    actual = {name for name in entries if not name.endswith("/")}
    assert actual == expected, f"Unexpected/missing release files: {actual ^ expected}"
    assert entries[prefix + "安装交接技能.command"].external_attr >> 16 & stat.S_IXUSR
    assert entries[prefix + "安装或升级.command"].external_attr >> 16 & stat.S_IXUSR
    for name in actual:
        assert not stat.S_ISLNK(entries[name].external_attr >> 16), name
        assert Path.home().as_posix().encode() not in package.read(entries[name]), f"Home path leaked: {name}"
    manifest = package.read(entries[prefix + "PayloadSHA256.txt"]).decode("utf-8")
    checksums = dict(line.split("  ", 1)[::-1] for line in manifest.splitlines())
    assert set(checksums) == {"./" + name.removeprefix(prefix) for name in actual if name != prefix + "PayloadSHA256.txt"}
    for path, digest in checksums.items():
        assert hashlib.sha256(package.read(entries[prefix + path.removeprefix("./")])).hexdigest() == digest, path
    info = plistlib.loads(package.read(entries[prefix + "Codex实时状态栏.app/Contents/Info.plist"]))
    assert info["CFBundleShortVersionString"] == version
print("Passed: release allowlist, archive integrity, version, executable installer and home-path exclusion.")
