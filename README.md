# Chuu

一个正在开发中的 macOS 鼠标管理 App，基于 [Mos](https://github.com/Caldis/Mos)，把电量、板载按键、平滑滚动和应用设置放在一起。

**开发中，尚未发布稳定安装包。** 目前主要在个人使用的 G502 X PLUS 和 MCHOSE G7 上验证，不代表支持全部罗技或迈从鼠标。

![Chuu 首页：白色 G502 X PLUS、电量和按键设置](docs/images/home.png)

截图来自本机开发版；鼠标产品图归 Logitech 所有，公开源码不附带厂商原始图片，缺少图片时使用通用鼠标图标。

## 已有功能

- 原生半透明窗口、菜单栏入口和 Liquid Glass 图标。
- G502 X PLUS：2.4 GHz 电量、充电状态、板载按键映射、RGB 开关。
- MCHOSE G7：2.4 GHz 电量读取。
- WidgetKit 电量小组件；后台定时读取并请求更新。
- 保留 Mos 的平滑滚动、快捷操作和按应用设置。
- 鼠标页集中管理板载按键与全局快捷操作，普通鼠标使用通用外观。
- 连接电量浮窗；可在“通用”中预览或关闭。
- 可选的 20% 低电量通知，充至 25% 后重新启用下一次提醒。

电量读取需要 Chuu 在后台运行；WidgetKit 的实际刷新时间由系统安排。第三方 Qi 充电底座不一定会上报充电状态。板载写入会先备份，再读回校验。

关闭主窗口会隐藏 Dock 图标，但继续在后台运行。菜单里的“退出 Chuu”才会停止滚动、按键和电量读取；再次打开 App 可回到主窗口。

## 构建

运行需要 macOS 14+。当前开发环境为 Xcode 27.1，项目使用 XcodeGen；旧版 SDK 未验证。

1. 安装 Xcode 和 XcodeGen。
2. 按 [构建说明](docs/build.md) 配置自己的签名团队和 App Group。
3. 打开 `MouseControl.xcodeproj`，选择 `Debug` scheme，运行 Chuu。

也可以使用：

```sh
./script/build_and_run.sh --build    # 仅构建
./script/build_and_run.sh --install  # 安装到 ~/Applications/Chuu.app
```

滚动和快捷操作需要辅助功能权限。不要同时运行其他会接管相同鼠标按键的工具。

## 下一步

这版先验证页面合并和提醒体验。连接浮窗识别接收器热插拔、首次成功连接；接收器一直插着时，不把无线查询超时后的恢复当成重连，避免鼠标日常休眠反复弹窗。普通鼠标只显示可确认的连接信息，不代表已经支持其电量或板载协议。

低电量通知需要在“通用”中开启并允许通知。后续计划是配置导入导出、更多设备协议和手势操作，见 [交互方案与同类工具调研](docs/interaction-proposal.md)。

## 致谢与许可

Chuu 是 [Caldis/Mos](https://github.com/Caldis/Mos) 的非商业开发分支，保留上游历史和 [CC BY-NC 4.0](LICENSE) 许可，并非 MIT 项目，也不是 Mos 或硬件厂商的官方产品。第三方素材说明见 [NOTICES](NOTICES.md)。
