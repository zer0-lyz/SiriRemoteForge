#!/bin/bash
# Produce a compact reader-facing installation report without changing system state.
set -u

PAYLOAD="${1:?payload dir required}"
REPORT="${2:-$HOME/Downloads/HyperVibe-安装检查.txt}"
CONFIG="$HOME/.config/siriremote/config.jsonc"
APP="/Applications/HyperVibe.app"
SUPPORT="/Library/Application Support/SiriRemoteMic"
HAL="/Library/Audio/Plug-Ins/HAL/SiriRemoteMic.driver"
PLIST="/Library/LaunchDaemons/au.holodata.SiriRemoteMic.captured.plist"
LOG="/tmp/hypervibe.log"

status_line() {
    printf '%-20s %s\n' "$1" "$2"
}

APP_STATUS="未安装"
if [ -x "$APP/Contents/MacOS/HyperVibe" ]; then
    APP_STATUS="已安装"
fi

CONFIG_STATUS="缺失"
if [ -f "$CONFIG" ]; then
    if /usr/bin/cmp -s "$PAYLOAD/config.jsonc" "$CONFIG"; then
        CONFIG_STATUS="已同步当前映射"
    else
        CONFIG_STATUS="存在，但与安装包不同"
    fi
fi

MIC_STATUS="未安装"
if [ -d "$HAL" ]; then
    MIC_STATUS="驱动已安装"
    if /usr/sbin/system_profiler SPAudioDataType 2>/dev/null \
        | /usr/bin/grep -Fq "Siri Remote Mic"; then
        MIC_STATUS="设备已识别"
    fi
fi

DAEMON_STATUS="未运行"
if [ -f "$PLIST" ] && /bin/launchctl print \
    system/au.holodata.SiriRemoteMic.captured 2>/dev/null \
    | /usr/bin/grep -Fq "state = running"; then
    DAEMON_STATUS="运行中"
fi

PACKETLOGGER_STATUS="缺失，遥控器麦克风不可用"
if [ -x "/Applications/PacketLogger.app/Contents/Resources/packetlogger" ]; then
    PACKETLOGGER_STATUS="已安装"
fi

HID_STATUS="启动后待检查"
INPUT_STATUS="启动后待检查"
if [ -f "$LOG" ]; then
    if /usr/bin/grep -Fq "IOHIDManagerOpen success" "$LOG"; then
        HID_STATUS="正常"
    fi
    if /usr/bin/grep -Fq "Input Monitoring access: granted" "$LOG"; then
        INPUT_STATUS="已授权"
    elif /usr/bin/grep -Fq "Input Monitoring access: NOT granted" "$LOG"; then
        INPUT_STATUS="未授权"
    fi
fi

REMOTE_STATUS="尚未检测到"
if [ -f "$LOG" ] && /usr/bin/grep -Eq \
    'candidate vendor=0x4C product=0x(315|314)|Siri Remote connected' "$LOG"; then
    REMOTE_STATUS="已检测到"
fi

/bin/mkdir -p "$(/usr/bin/dirname "$REPORT")"
{
    echo "HyperVibe 安装检查"
    echo "生成时间：$(/bin/date '+%Y-%m-%d %H:%M:%S %Z')"
    echo
    status_line "Mac 架构" "$(/usr/bin/uname -m)"
    status_line "macOS" "$(/usr/bin/sw_vers -productVersion)"
    status_line "HyperVibe App" "$APP_STATUS"
    status_line "当前映射" "$CONFIG_STATUS"
    status_line "Siri Remote Mic" "$MIC_STATUS"
    status_line "后台采集服务" "$DAEMON_STATUS"
    status_line "PacketLogger" "$PACKETLOGGER_STATUS"
    status_line "输入监控" "$INPUT_STATUS"
    status_line "HID 读取" "$HID_STATUS"
    status_line "Siri Remote" "$REMOTE_STATUS"
    echo
    echo "仍需人工完成："
    echo "1. 在隐私与安全性中开启 HyperVibe 的辅助功能、输入监控和麦克风权限。"
    echo "2. 在蓝牙设置中将 Siri Remote 与当前 Mac 配对。"
    echo "3. Codex/输入法的语音快捷键需与配置中的按键组合一致。"
    echo
    echo "诊断日志：$LOG"
} > "$REPORT"

/bin/cat "$REPORT"
