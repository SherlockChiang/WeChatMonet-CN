#!/usr/bin/env python3
"""Build a versioned Mainland WeChat overlay from the delivered APKs.

This is the short path for a WeChat update when the upstream Play overlay is
not available.  It only applies mappings that have been checked against the
specified target APK and writes version-suffixed APKs, so the legacy payload
remains usable by older WeChat versions.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

try:
    from loguru import logger as _loguru_logger
    _loguru_logger.remove()
except Exception:
    pass

from androguard.core.apk import APK

ROOT = Path(__file__).resolve().parent
OVERLAYS = (
    "MonetWeChat",
    "MonetWeChatBadge",
    "MonetWeChatChatBubble",
    "MonetWeChatMultiSceneCorners",
    "MonetWeChatSolidTab",
    "MonetWeChatBlurTab",
)


def path(value: str | Path) -> Path:
    return Path(value).expanduser().resolve()


def resource_names(apk_path: Path) -> set[str]:
    apk = APK(str(apk_path))
    resources = apk.get_android_resources()
    if resources is None:
        raise RuntimeError(f"{apk_path} 没有 resources.arsc")
    resources._analyse()
    package = apk.get_package()
    return {
        f"{resource_type}/{name}"
        for resource_type, names in resources.resource_keys.get(package, {}).items()
        for name in names
    }


def sha256(filename: Path) -> str:
    with filename.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def private_name(name: str) -> str:
    kind, _ = name.split('/', 1)
    return f"{kind}/compat_private_{hashlib.sha256(name.encode()).hexdigest()[:16]}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wx-apk", required=True, help="与映射中版本号、SHA256 一致的微信基础 APK")
    parser.add_argument(
        "--mapping",
        default=str(ROOT / "compat" / "3182.json"),
        help="版本映射 JSON（默认 compat/3182.json）",
    )
    parser.add_argument(
        "--module-dir", default=str(ROOT), help="模块目录（默认当前项目）"
    )
    parser.add_argument(
        "--output-dir",
        default=str(ROOT / "Workspace" / "adapt-3182"),
        help="构建输出目录",
    )
    parser.add_argument(
        "--signer",
        default=str(ROOT.parent / "tools" / "uber-apk-signer.jar"),
        help="uber-apk-signer.jar；--apply 要求签名器存在",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="把版本化 APK 复制到 files/，保留旧版 files/*.apk",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    wx_apk = path(args.wx_apk)
    mapping_path = path(args.mapping)
    module_dir = path(args.module_dir)
    output_dir = path(args.output_dir)
    signer = path(args.signer)

    if not wx_apk.is_file():
        raise SystemExit(f"新版 APK 不存在: {wx_apk}")
    if not mapping_path.is_file():
        raise SystemExit(f"映射文件不存在: {mapping_path}")

    target_apk = APK(str(wx_apk))
    version_code = int(target_apk.get_androidversion_code())
    spec = json.loads(mapping_path.read_text(encoding="utf-8"))
    expected = int(spec["versionCode"])
    if version_code != expected:
        raise SystemExit(
            f"版本不匹配：输入 APK versionCode={version_code}，映射要求 {expected}"
        )
    if target_apk.get_package() != 'com.tencent.mm':
        raise SystemExit('目标 APK 包名必须是 com.tencent.mm')
    if spec.get('targetSha256') and sha256(wx_apk) != spec['targetSha256']:
        raise SystemExit('目标 APK 与已审核的资源映射不一致')
    if spec.get('schemaVersion') != 2:
        raise SystemExit('需要完整审核的 schemaVersion=2 映射，拒绝沿用未分类的同名资源')
    if args.apply and not signer.is_file():
        raise SystemExit(f'签名器不存在，不能应用未签名 APK: {signer}')

    # Include split resources when they sit next to the base APK.  The base
    # APK is enough for the current 3182 mappings, while this also handles a
    # future name moved into the language split without changing the script.
    target_names = resource_names(wx_apk)
    for split in wx_apk.parent.glob("split_*.apk"):
        try:
            target_names |= resource_names(split)
        except Exception:
            continue

    from wx_patch import patch_apk

    output_dir.mkdir(parents=True, exist_ok=True)
    overlays = spec.get("overlays", {})
    built: list[Path] = []
    for overlay in OVERLAYS:
        source = module_dir / "files" / f"{overlay}.apk"
        if not source.is_file():
            raise SystemExit(f"模块 APK 不存在: {source}")
        rename = overlays[overlay]
        source_names = resource_names(source)
        expected_hash = spec.get('sourceSha256', {}).get(overlay)
        if not expected_hash or sha256(source) != expected_hash:
            raise SystemExit(f'{overlay} 源 APK 与映射审核时不一致')
        missing_source = sorted(set(rename) - source_names)
        missing_target = sorted(set(rename.values()) - target_names)
        private = set(spec.get('privateResources', {}).get(overlay, []))
        if private & set(rename):
            raise SystemExit(f'{overlay} 条目同时被分类为目标资源和内部资源')
        unclassified = source_names - set(rename) - private
        if missing_source or missing_target or unclassified or private - source_names:
            raise SystemExit(
                f"{overlay} 映射校验失败："
                f"源资源缺失={missing_source} 目标资源缺失={missing_target} "
                f"未分类资源={sorted(unclassified)}"
            )
        rename = {**rename, **{name: private_name(name) for name in private}}
        if len(set(rename.values())) != len(rename):
            raise SystemExit(f'{overlay} 存在重名目标资源')
        destination = output_dir / f"{overlay}-{version_code}.apk"
        if rename:
            patch_apk(
                str(source),
                str(destination),
                {APK(str(source)).get_package(): rename},
                typed=True,
            )
        else:
            shutil.copy2(source, destination)
        built.append(destination)
        if resource_names(destination) != set(rename.values()):
            raise SystemExit(f'{overlay} 输出资源表不符合完整映射')
        print(f"built {destination.name}: {len(rename) - len(private)} targets, {len(private)} private entries")

    if signer.is_file():
        for apk in built:
            subprocess.run(
                ["java", "-jar", str(signer), "-a", str(apk), "--overwrite"],
                check=True,
            )
        print(f"signed {len(built)} APKs")
    else:
        print(f"warning: signer not found, APKs are not signed: {signer}", file=sys.stderr)

    if args.apply:
        files_dir = module_dir / "files"
        for apk in built:
            destination = files_dir / apk.name
            shutil.copy2(apk, destination)
            print(f"applied {destination}")
        print(
            f"已生成版本化 APK；安装器会按 versionCode 选择 *-{version_code}.apk。"
        )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
