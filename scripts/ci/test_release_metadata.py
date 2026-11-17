"""Validate built bundle versions and describe a deliberately unnotarized package."""

import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path


DEVICE_ARTWORK = {"G502Top", "G502Side", "G502RenderTop", "G502RenderSide", "G7", "GenericMouse"}


def validate_artwork(entries):
    names = {entry.get("Name") for entry in entries}
    missing = DEVICE_ARTWORK - names
    if missing:
        raise ValueError("Missing bundled device artwork: " + ", ".join(sorted(missing)))
    return sorted(DEVICE_ARTWORK)


def validate(app, widget, tag):
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("Expected vMAJOR.MINOR.PATCH")
    version = tag[1:]
    build = app.get("CFBundleVersion", "")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", build):
        raise ValueError("Missing or invalid build number")
    for info, bundle_id in [(app, "moe.khan.MouseControl"), (widget, "moe.khan.MouseControl.BatteryWidget")]:
        if info.get("CFBundleIdentifier") != bundle_id:
            raise ValueError("Unexpected bundle identifier")
        if info.get("CFBundleShortVersionString") != version or info.get("CFBundleVersion") != build:
            raise ValueError("Tag, app and widget versions must match")
    if app.get("SUFeedURL"):
        raise ValueError("Test packages must not opt into an update feed")
    return {"version": version, "build": build, "tag": tag, "architectures": ["arm64"],
            "signing": "ad-hoc", "notarized": False, "hardened_runtime": False,
            "widget_runtime_validated": False}


def main():
    app_path, tag, commit, output_path = sys.argv[1:]
    app_path, output_path = Path(app_path), Path(output_path)
    with (app_path / "Contents/Info.plist").open("rb") as stream:
        app = plistlib.load(stream)
    with (app_path / "Contents/PlugIns/ChuuWidget.appex/Contents/Info.plist").open("rb") as stream:
        widget = plistlib.load(stream)
    metadata = validate(app, widget, tag)
    catalog = subprocess.run(["xcrun", "assetutil", "--info", str(app_path / "Contents/Resources/Assets.car")],
                             check=True, capture_output=True, text=True)
    metadata["bundled_device_artwork"] = validate_artwork(json.loads(catalog.stdout))
    metadata["distribution"] = "unnotarized-test-artifact"
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Invalid source commit")
    metadata["source_commit"] = commit
    output_path.mkdir(parents=True, exist_ok=True)
    (output_path / "build-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
    source = Path.cwd()
    changelog = (source / "CHANGELOG.md").read_text(encoding="utf-8")
    heading = f"## {metadata['version']} - "
    sections = changelog.split(heading, 1)
    if len(sections) != 2:
        raise ValueError("Missing release changelog section")
    changes = sections[1].split("\n", 1)[1].split("\n## ", 1)[0].strip()
    notes = f"""# Chuu {tag}: Unnotarized Test Build

## Changes / 更新内容

{changes}

## Installation

For testing only. Ad-hoc signed, not Developer ID signed or notarized. This is not a stable release and is not delivered through Sparkle.

This test package does not enable Hardened Runtime, so its ad-hoc-signed embedded frameworks can load. Normally signed local builds retain Hardened Runtime.

- Apple Silicon (arm64) macOS app, for M-series Macs only. Intel Macs are not supported by this package. Minimum system: macOS {app['LSMinimumSystemVersion']}.
- macOS may block first launch. Review this build's source and origin before approving it through System Settings > Privacy & Security. Do not disable Gatekeeper globally.
- Complete Accessibility and Input Monitoring setup on first launch. If Chuu is already enabled but access is denied, quit Chuu, remove the old permission entry, add the currently installed app, enable it and reopen Chuu.
- The WidgetKit extension is bundled, but ad-hoc signing does not authenticate membership in the shared App Group. Use a normally signed build with a matching App Group when the widget is essential.
- This test package includes G502 X PLUS and MCHOSE G7 artwork; other mice use an original generic illustration. Vendor artwork is not covered by the code license; see NOTICES.md for sources.
- Back up your settings before replacing an existing installation. Quit other running copies of Chuu before opening this one.
- Verify the download using the attached SHA256SUMS file. Build number: {metadata['build']}.

Source: https://github.com/Imyukehan/Chuu/tree/{commit}

Changes: https://github.com/Imyukehan/Chuu/blob/{commit}/CHANGELOG.md

## 中文说明

这是未公证测试包，不是稳定版，也不会通过应用内更新分发。仅适用于 M 系列芯片的 Mac（Apple Silicon / arm64），不支持 Intel Mac。首次启动可能被 macOS 拦截，请核对来源后自行决定是否允许打开，不要关闭系统的全局安全保护。

此测试包不启用加固运行时，以便加载临时签名的内嵌组件；正常签名的本机构建保持启用。

首次启动请完成辅助功能和输入监控授权。若已开启却仍提示拒绝访问，请先退出 Chuu，移除旧授权条目，再添加当前安装的 App、开启权限并重新打开。临时签名无法认证共享 App Group 的成员身份；需要小组件时请使用 App Group 匹配的正常签名版本。

此测试包内置 G502 X PLUS 和迈从 G7 图片，素材来源及权利说明见 NOTICES.md。替换旧版前请备份设置，并退出正在运行的其他 Chuu 副本。
"""
    (output_path / "release-notes.md").write_text(notes, encoding="utf-8")


if __name__ == "__main__":
    main()
