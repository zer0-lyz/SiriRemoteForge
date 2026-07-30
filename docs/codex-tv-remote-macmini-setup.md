# Mac mini 同步 Codex TV Remote 配置说明

本文用于把当前 Mac 上调好的 Siri Remote / HyperVibe 配置同步到另一台 Mac mini。

## 先说结论

配置没有自动同步到 Mac mini，最常见原因是：

1. GitHub 默认分支是 `main`，但当前可用配置在 `codex-siri-remote-ptt` 分支。
2. `examples/config.codex-tv-remote.jsonc` 只是配置文件，Mac mini 还需要安装或重新构建新版 `HyperVibe.app`。
3. 双击 TV 键的 `appSwitcher` 是新增动作，旧版 HyperVibe 不认识这个动作，光复制配置不够。
4. 遥控器蓝牙只能连当前主机。要在 Mac mini 使用，需要先从旧 Mac 断开/忽略设备，再在 Mac mini 重新配对。
5. macOS 的“辅助功能”和“输入监控”权限是每台 Mac 单独授权，不能通过 GitHub 同步。

## Mac mini 推荐安装步骤

### 1. 克隆正确分支

不要只克隆默认分支。请在 Mac mini 终端执行：

```sh
mkdir -p "$HOME/Projects/Apple TV 遥控器/work"
cd "$HOME/Projects/Apple TV 遥控器/work"
git clone -b codex-siri-remote-ptt https://github.com/zer0-lyz/SiriRemoteForge.git
cd SiriRemoteForge
```

如果已经克隆过，但不确定分支：

```sh
cd "$HOME/Projects/Apple TV 遥控器/work/SiriRemoteForge"
git fetch origin
git switch codex-siri-remote-ptt
git pull --ff-only
```

验证是否拿到当前配置：

```sh
grep -n 'appSwitcherStepInterval\\|com.google.Chrome\\|com.tencent.WeWorkMac\\|button.tv.double' examples/config.codex-tv-remote.jsonc
```

应该能看到：

- `com.google.Chrome : chrome`
- `com.tencent.WeWorkMac : wechat`
- `button.tv.double`
- `appSwitcherStepInterval : 0.8`

### 2. 构建并安装新版 HyperVibe

```sh
cd "$HOME/Projects/Apple TV 遥控器/work/SiriRemoteForge/app"
./build.sh
./create_app_bundle.sh
xattr -cr HyperVibe.app
ditto HyperVibe.app /Applications/HyperVibe.app
xattr -cr /Applications/HyperVibe.app
codesign --force --deep --sign - /Applications/HyperVibe.app
```

如果之前已经打开过 HyperVibe，先退出再重新打开：

```sh
osascript -e 'tell application "HyperVibe" to quit' 2>/dev/null || true
open -a /Applications/HyperVibe.app
```

### 3. 同步配置文件

```sh
cd "$HOME/Projects/Apple TV 遥控器/work/SiriRemoteForge"
scripts/install-codex-tv-config.sh
```

这个脚本会把：

```text
examples/config.codex-tv-remote.jsonc
```

复制到：

```text
~/.config/siriremote/config.jsonc
```

并自动备份旧配置。

验证配置一致：

```sh
jq -S . examples/config.codex-tv-remote.jsonc > /tmp/example.sorted.json
jq -S . ~/.config/siriremote/config.jsonc > /tmp/runtime.sorted.json
diff -u /tmp/example.sorted.json /tmp/runtime.sorted.json
```

没有输出就表示配置一致。

### 4. 授权 macOS 权限

Mac mini 上必须单独授权：

```sh
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent'
```

在系统设置里给 `/Applications/HyperVibe.app` 打开：

- 辅助功能
- 输入监控

如果开关本来就是开的，但遥控器没反应，先关闭再打开，然后重启 HyperVibe。

### 5. 配对 Siri Remote

遥控器不能同时稳定连接两台 Mac。切到 Mac mini 时建议：

1. 在当前 Mac 的蓝牙设置里断开或忽略 Siri Remote。
2. 在 Mac mini 蓝牙设置里搜索并连接 Siri Remote。
3. 遥控器靠近 Mac mini。
4. 如果一直搜不到，长按遥控器上的返回键和音量上键数秒，尝试进入配对状态。

### 6. 检查运行日志

```sh
tail -n 120 /tmp/hypervibe.log
```

比较理想的信号：

```text
Input Monitoring access: granted
IOHIDManagerOpen success
MediaKeyInterceptor: event tap installed and enabled
```

如果看到：

```text
Input Monitoring access: NOT granted
CGEvent.tapCreate FAILED
```

就是权限没授权好。

## Codex 语音输入快捷键

当前配置里 Siri 键是：

```jsonc
"button.siri" : {
  "action" : "pushToTalk",
  "keys" : "ropt+/"
}
```

所以 Mac mini 上也需要把 Codex / 微信输入法的语音快捷键设置成右 Option + `/`。否则 Siri 键会发出快捷键，但目标应用不会响应。

## 常见问题判断

### 配置文件不存在

大概率克隆的是 `main` 分支。切换到：

```sh
git switch codex-siri-remote-ptt
```

### 双击 TV 键没法 Cmd-Tab

大概率是 HyperVibe 还是旧版。需要重新构建并覆盖 `/Applications/HyperVibe.app`。

### 按键完全没反应

优先检查：

1. Siri Remote 是否已经连接 Mac mini 蓝牙。
2. HyperVibe 是否正在运行。
3. 辅助功能和输入监控是否授权。
4. 是否只有一个 HyperVibe 在运行。

检查命令：

```sh
pgrep -fl HyperVibe
tail -n 120 /tmp/hypervibe.log
```

### Chrome / WPS / 微信没有按应用切换

确认配置文件里有对应 bundle id：

```sh
grep -n 'com.google.Chrome\\|com.kingsoft.wpsoffice.mac\\|com.tencent.xinWeChat\\|com.tencent.WeWorkMac' ~/.config/siriremote/config.jsonc
```

如果没有，说明同步的不是当前配置。

## 当前 GitHub 版本

- 仓库：`https://github.com/zer0-lyz/SiriRemoteForge`
- 分支：`codex-siri-remote-ptt`
- 当前配置提交：`eaee1e1 Refine TV remote app controls`

