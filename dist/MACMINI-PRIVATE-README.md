# HyperVibe Mac mini 私人迁移包

此安装包用于把当前 MacBook 已验证的 Siri Remote 控制映射和真实遥控器麦克风组件迁移到 Apple 芯片 Mac mini。

## 安装

1. 解压 `HyperVibe-Full-Setup-1.1.0-macmini-arm64.zip`。
2. 右键 `HyperVibe Setup.app`，选择“打开”，输入一次管理员密码。
3. 按安装器提示开启辅助功能、输入监控和麦克风权限，然后在蓝牙设置中配对 Siri Remote。

安装器会自动：

- 安装 HyperVibe App；
- 备份 Mac mini 原有映射并安装当前已验证映射；
- 安装 Siri Remote Mic 虚拟麦克风、router 和后台采集服务；
- 安装包内附带的 PacketLogger；
- 生成 `下载/HyperVibe-安装检查.txt`。

## 不能自动完成的项目

macOS 不允许安装器代替用户开启隐私权限，也不能替用户确认蓝牙配对。因此以下操作仍需手动点击：

- 辅助功能；
- 输入监控；
- 麦克风；
- Siri Remote 蓝牙配对。

Codex 或输入法的语音快捷键也属于目标应用自身设置，需与当前映射保持一致。

## 回退

安装前原配置会保存为：

`~/.config/siriremote/config.jsonc.backup.时间戳`

系统组件可通过 `/Applications/HyperVibe Uninstall.app` 卸载。卸载器会保留用户配置和 PacketLogger。

## 使用范围

- 仅支持 Apple 芯片 Mac。
- 这是包含个人映射和 Apple PacketLogger 的私人迁移包，不要上传到公开 GitHub。
