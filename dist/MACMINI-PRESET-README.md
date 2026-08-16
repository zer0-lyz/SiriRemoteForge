# HyperVibe Mac mini GitHub 安装包

此安装包用于将项目中公开保存的 Siri Remote 控制映射、HyperVibe 和 Siri Remote Mic 组件安装到 Apple 芯片 Mac。

## 安装

1. 解压 GitHub Release 中的 `HyperVibe-Macmini-Setup` ZIP。
2. 右键 `HyperVibe Setup.app`，选择“打开”。
3. 输入一次管理员密码。
4. 按安装器提示开启辅助功能、输入监控和麦克风权限。
5. 在蓝牙设置中将 Siri Remote 与当前 Mac 配对。

安装器会自动：

- 安装 HyperVibe App；
- 备份目标 Mac 原有映射并安装仓库内的 Codex TV Remote 预设；
- 安装 Siri Remote Mic、router 和后台采集服务；
- 生成 `下载/HyperVibe-安装检查.txt`；
- 安装卸载器到 `/Applications/HyperVibe Uninstall.app`。

## PacketLogger

GitHub 公开包不包含 Apple PacketLogger。遥控器真实麦克风需要从 Apple 的 `Additional Tools for Xcode` 中安装 PacketLogger。若目标 Mac 尚未安装，安装器会打开 Apple 官方下载页。

按键、触控和应用映射不依赖 PacketLogger。

## 仍需手动完成

macOS 不允许安装器代替用户授权隐私权限，也不能代替用户确认蓝牙配对：

- 辅助功能；
- 输入监控；
- 麦克风；
- Siri Remote 蓝牙配对。

Codex 或输入法自身的语音快捷键也需与预设中的按键组合一致。

## 回退

旧配置会备份为：

`~/.config/siriremote/config.jsonc.backup.时间戳`

系统组件可通过 `/Applications/HyperVibe Uninstall.app` 卸载。
