"""Validate built bundle versions and describe a deliberately unnotarized package."""

import json
import plistlib
import re
import sys
from pathlib import Path


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
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Invalid source commit")
    metadata["source_commit"] = commit
    output_path.mkdir(parents=True, exist_ok=True)
    (output_path / "build-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
    notes = f"""# Chuu {tag}: Unnotarized Test Build

For testing only. Ad-hoc signed, not Developer ID signed or notarized. This is not a stable release and is not delivered through Sparkle.

This test package does not enable Hardened Runtime, so its ad-hoc-signed embedded frameworks can load. Normally signed local builds retain Hardened Runtime.

- Apple Silicon (arm64) macOS app, for M-series Macs only. Intel Macs are not supported by this package. Minimum system: macOS {app['LSMinimumSystemVersion']}.
- macOS may block first launch. Review this build's source and origin before approving it through System Settings > Privacy & Security. Do not disable Gatekeeper globally.
- Scrolling and button shortcuts require Accessibility permission. Changing from a signed development app may require granting permission again.
- The WidgetKit extension is bundled, but App Group sharing and widget operation are NOT validated with ad-hoc signing. Use a normally signed local build when the widget is essential.
- Optional device artwork is not bundled. Generic mouse artwork is used where an asset is unavailable.
- Back up your settings before replacing an existing installation. Quit other running copies of Chuu before opening this one.
- Verify the download using the attached SHA256SUMS file. Build number: {metadata['build']}.

Source: https://github.com/Imyukehan/Chuu/tree/{commit}

Changes: https://github.com/Imyukehan/Chuu/blob/{commit}/CHANGELOG.md

## 中文说明

这是未公证测试包，不是稳定版，也不会通过应用内更新分发。仅适用于 M 系列芯片的 Mac（Apple Silicon / arm64），不支持 Intel Mac。首次启动可能被 macOS 拦截，请核对来源后自行决定是否允许打开，不要关闭系统的全局安全保护。

此测试包不启用加固运行时，以便加载临时签名的内嵌组件；正常签名的本机构建保持启用。

滚动和快捷操作需要辅助功能权限，更换签名后可能需要重新授权。包内包含 WidgetKit 扩展，但临时签名下的 App Group 共享和小组件功能未经验证；依赖小组件时请继续使用正常签名的本机构建。测试包不包含本机专用鼠标外观素材。替换旧版前请备份设置，并退出正在运行的其他 Chuu 副本。
"""
    (output_path / "release-notes.md").write_text(notes, encoding="utf-8")


if __name__ == "__main__":
    main()
