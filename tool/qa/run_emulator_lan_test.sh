#!/usr/bin/env bash
# ============================================================
# tool/qa/run_emulator_lan_test.sh — 双模拟器局域网联调（尽力而为）
#
# 目的：在一台机器上用两个 Android 模拟器验证
#   「A 建房 → B 加入 → 互发消息」这条链路在真实 Android 运行时能跑。
#
# 为什么不能指望 UDP 广播：
#   两个模拟器各自在 10.0.2.15 的 NAT 里，广播包出不去。
#   所以本脚本用 **adb forward + 手输地址** 绕过发现环节，
#   只验真正的传输与同步（发现单独在真机上验）。
#
# 前置：
#   sdkmanager "emulator" "system-images;android-35;google_apis;x86_64"
#   bash tool/build_apk.sh   （先产出 app-release.apk）
# ============================================================
set -uo pipefail

SDK=/d/dev/android-sdk
ADB="$SDK/platform-tools/adb.exe"
EMU="$SDK/emulator/emulator.exe"
AVDM="$SDK/cmdline-tools/latest/bin/avdmanager.bat"
IMG="system-images;android-35;google_apis;x86_64"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"

if [ ! -x "$EMU" ]; then
  echo "✗ 没有 emulator，先跑：sdkmanager \"emulator\" \"$IMG\"" >&2
  exit 1
fi
if [ ! -f "$APK" ]; then
  echo "✗ 没有 APK，先跑：bash tool/build_apk.sh" >&2
  exit 1
fi

echo "[1/5] 建两个 AVD（已存在则跳过）"
for n in diceA diceB; do
  if ! "$AVDM" list avd 2>/dev/null | grep -q "Name: $n"; then
    echo no | "$AVDM" create avd -n "$n" -k "$IMG" -d pixel_6 --force >/dev/null
    echo "  created $n"
  else
    echo "  exists $n"
  fi
done

echo "[2/5] 启动两个模拟器（无窗口，省内存）"
"$EMU" -avd diceA -no-window -no-audio -no-snapshot -gpu swiftshader_indirect -port 5554 &
"$EMU" -avd diceB -no-window -no-audio -no-snapshot -gpu swiftshader_indirect -port 5556 &

echo "[3/5] 等两个设备上线（最多 5 分钟）"
for i in $(seq 1 100); do
  ready=$("$ADB" devices | grep -c "emulator-555[46][[:space:]]*device")
  [ "$ready" -ge 2 ] && break
  sleep 3
done
"$ADB" devices

echo "[4/5] 安装 APK 到两台"
"$ADB" -s emulator-5554 install -r "$APK"
"$ADB" -s emulator-5556 install -r "$APK"

echo "[5/5] 建立端口转发（B 通过宿主机访问 A 的 4211）"
# B 里的 10.0.2.2 是宿主机；把宿主机 14211 转到 A 的 4211
"$ADB" -s emulator-5554 forward tcp:14211 tcp:4211
echo "  A 的服务 → 宿主 127.0.0.1:14211 → B 可用 http://10.0.2.2:14211 访问"

cat <<'EOF'

================ 手动验收步骤 ================
1) A（emulator-5554）打开 App → 骰境 → 创建房间，记下 6 位房号
2) B（emulator-5556）打开 App → 骰境 → 加入
   ⚠️ 当前「加入」只按房号走 UDP 发现，模拟器间收不到广播
      所以这一步会回退「本机预览」—— 属预期。
   真正的跨设备验证请在真机上做（同 WiFi）。
3) 若要在模拟器上强验传输：
   - 用 `adb -s emulator-5556 shell am start ...` 带注入地址启动
     （需要 App 暴露一个调试用的 base 参数，当前没有）
   - 或临时把 emulator A 的 4211 通过 `adb forward` 暴露后，
     在 B 里手输 http://10.0.2.2:14211（需 UI 支持手输地址，当前也没有）

结论：模拟器能验「安装 + 启动 + 不崩」，
      跨设备联调的完整验收仍需两台真机同 WiFi。
==============================================
EOF

echo ""
echo "清理："
echo "  $ADB -s emulator-5554 emu kill"
echo "  $ADB -s emulator-5556 emu kill"
