#!/usr/bin/env python3
"""
يرقّع compileSdk في build.gradle(.kts) الخاص بكل حزمة في pub-cache، ليكون
36 على الأقل — الحل الموثَّق في القسم 3 من دليل مشاكل بناء Flutter (تعارض
compileSdk بين flutter_plugin_android_lifecycle وما يعتمد عليها من حزم مثل
file_picker/image_picker مع القيمة الافتراضية الأقل التي يستخدمها Flutter).

لماذا بهذه الطريقة تحديدًا (وليس عبر build.gradle الجذري):
- محاولات subprojects{...}/afterEvaluate{...} فشلت جميعها كما هو موثّق —
  إما لأن ملف الحزمة نفسه يعيد ضبط القيمة لاحقًا فيطغى على أي تعديل مبكر،
  أو لأن AGP الحديث "يقفل" compileSdk فور أول قراءة له (AgpDslLockedException).
- الحل الوحيد الموثوق: تعديل نص ملف build.gradle الأصلي لكل حزمة على القرص
  مباشرة، قبل أن يبدأ Gradle أي تقييم — فتصبح compileSdk=36 جزءًا طبيعيًا
  من كود الحزمة نفسه.

الاستخدام (من جذر المشروع، بعد flutter pub get):
    flutter pub get
    python3 tool/patch_compile_sdk.py
    flutter build apk --release --no-pub   # --no-pub ضروري! راجع أدناه

⚠️ ضروري: استخدم --no-pub في أمر flutter build بعد هذا السكربت. بدونها،
يشغّل flutter build تحققًا داخليًا من نوع pub get يقارن بصمة (hash) كل حزمة
مع pubspec.lock؛ وبما أننا عدّلنا الملفات يدويًا فستتغيّر البصمة، فيعيد pub
تحميل النسخة الأصلية غير المعدَّلة من الإنترنت بصمت، فيُلغي هذا الترقيع
بالكامل قبل أن يبدأ Gradle.
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.parse
import urllib.request

MIN_COMPILE_SDK = 36
PACKAGE_CONFIG_PATH = os.path.join(".dart_tool", "package_config.json")
LOG_PATH = "compile_sdk_patch_log.txt"

# النمط الرمزي: compileSdk(Version) يشير لـ flutter.compileSdkVersion (أو
# project.flutter...)، بأي صيغة Groovy أو Kotlin DSL
_SYMBOLIC_PATTERN = re.compile(
    r"compileSdk(?:Version)?\s*(?:=)?\s*\(?\s*(?:project\.)?flutter\.compileSdkVersion\s*\)?"
)

# النمط العددي: compileSdk(Version) = <رقم>. نرفع الرقم فقط إن كان أقل من الحد الأدنى.
_NUMERIC_PATTERN = re.compile(
    r"(compileSdk(?:Version)?\s*(?:=)?\s*\(?\s*)(\d+)(\s*\)?)"
)


def uri_to_path(uri: str) -> str:
    parsed = urllib.parse.urlparse(uri)
    return urllib.request.url2pathname(parsed.path)


def patch_file(path: str, is_kts: bool) -> bool:
    with open(path, "r", encoding="utf-8") as f:
        original = f.read()
    content = original

    replacement = f"compileSdk = {MIN_COMPILE_SDK}" if is_kts else f"compileSdk {MIN_COMPILE_SDK}"
    content = _SYMBOLIC_PATTERN.sub(replacement, content)

    def _numeric_replacer(match: re.Match) -> str:
        prefix, num_str, suffix = match.group(1), match.group(2), match.group(3)
        if int(num_str) < MIN_COMPILE_SDK:
            return f"{prefix}{MIN_COMPILE_SDK}{suffix}"
        return match.group(0)

    content = _NUMERIC_PATTERN.sub(_numeric_replacer, content)

    if content != original:
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        return True
    return False


def main() -> None:
    if not os.path.exists(PACKAGE_CONFIG_PATH):
        print(
            f"لم أجد {PACKAGE_CONFIG_PATH} — شغّل flutter pub get أولًا قبل هذا السكربت.",
            file=sys.stderr,
        )
        sys.exit(1)

    with open(PACKAGE_CONFIG_PATH, "r", encoding="utf-8") as f:
        config = json.load(f)

    patched: list[str] = []

    for pkg in config.get("packages", []):
        name = pkg.get("name", "?")
        root_uri = pkg.get("rootUri")
        if not root_uri:
            continue

        # rootUri قد يكون مطلقًا (file://...) أو نسبيًا لمجلد .dart_tool نفسه
        if root_uri.startswith("file://"):
            root_path = uri_to_path(root_uri)
        else:
            root_path = os.path.normpath(os.path.join(".dart_tool", root_uri))

        for filename, is_kts in (("build.gradle", False), ("build.gradle.kts", True)):
            gradle_path = os.path.join(root_path, "android", filename)
            if os.path.exists(gradle_path):
                try:
                    if patch_file(gradle_path, is_kts):
                        patched.append(f"{name} -> {gradle_path}")
                except Exception as e:  # لا نوقف بقية الحزم بسبب فشل حزمة واحدة
                    patched.append(f"{name} -> فشل الترقيع ({gradle_path}): {e}")

    with open(LOG_PATH, "w", encoding="utf-8") as f:
        if patched:
            f.write("تم ترقيع compileSdk في الحزم التالية:\n")
            f.write("\n".join(patched))
        else:
            f.write("لم يُرقَّع أي حزمة (كل شيء مطابق للحد الأدنى بالفعل، أو لا حزم Android في المشروع).")

    with open(LOG_PATH, "r", encoding="utf-8") as f:
        print(f.read())


if __name__ == "__main__":
    main()
