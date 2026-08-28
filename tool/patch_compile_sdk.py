#!/usr/bin/env python3
"""
يرقّع compileSdk في حزم Android إلى 36 قبل بناء Gradle.
يقرأ المسارات الحقيقية من .dart_tool/package_config.json (لا يخمن pub-cache).
يُشغَّل بعد flutter pub get وقبل flutter build apk --no-pub.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

TARGET_SDK = 36
REPORT: list[str] = []


def patch_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8", errors="replace")
    original = text

    # 1) Symbolic: compileSdk flutter.compileSdkVersion (and variants)
    text = re.sub(
        r"compileSdk(?:Version)?\s*(?:=\s*)?(?:project\.)?flutter\.compileSdkVersion",
        f"compileSdk {TARGET_SDK}",
        text,
    )
    text = re.sub(
        r"compileSdkVersion\s*\(\s*(?:project\.)?flutter\.compileSdkVersion\s*\)",
        f"compileSdk {TARGET_SDK}",
        text,
    )

    # 2) Numeric: raise any compileSdk N where N < 36
    def raise_numeric(m: re.Match[str]) -> str:
        num = int(m.group(2))
        if num < TARGET_SDK:
            return f"{m.group(1)}{TARGET_SDK}"
        return m.group(0)

    text = re.sub(
        r"(compileSdk(?:Version)?\s*(?:=\s*)?)(\d+)",
        raise_numeric,
        text,
    )

    if text != original:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def main() -> int:
    root = Path.cwd()
    config_path = root / ".dart_tool" / "package_config.json"
    if not config_path.is_file():
        print("ERROR: .dart_tool/package_config.json not found. Run flutter pub get first.", file=sys.stderr)
        return 1

    data = json.loads(config_path.read_text(encoding="utf-8"))
    packages = data.get("packages", [])

    patched = 0
    for pkg in packages:
        name = pkg.get("name", "?")
        root_uri = pkg.get("rootUri", "")
        if not root_uri.startswith("file://"):
            continue
        # file:///path or file://path
        pkg_root = Path(root_uri.replace("file://", ""))
        for rel in ("android/build.gradle", "android/build.gradle.kts"):
            gradle = pkg_root / rel
            if gradle.is_file():
                if patch_file(gradle):
                    msg = f"patched: {name} -> {gradle}"
                    print(msg)
                    REPORT.append(msg)
                    patched += 1

    # Also patch app-level android if present
    for rel in ("android/app/build.gradle", "android/app/build.gradle.kts", "android/build.gradle", "android/build.gradle.kts"):
        p = root / rel
        if p.is_file() and patch_file(p):
            msg = f"patched (app): {p}"
            print(msg)
            REPORT.append(msg)
            patched += 1

    report_path = root / "compile_sdk_patch_report.txt"
    report_path.write_text(
        f"Patched {patched} file(s) to compileSdk {TARGET_SDK}\n\n" + "\n".join(REPORT) + "\n",
        encoding="utf-8",
    )
    print(f"Done. Patched {patched} file(s). Report: {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
