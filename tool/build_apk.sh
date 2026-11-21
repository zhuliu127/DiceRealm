#!/usr/bin/env bash
# ============================================================
# tool/build_apk.sh — 骰境 release APK 出包脚本（带 AOT 产物校验）
#
# 为什么需要这个脚本（2026-11-09 实测踩坑）：
#   1. 本机 `flutter config` 的 enable-native-assets 必须是 **true**，
#      否则 `flutter test` 直接拒绝运行（objective_c 传递依赖强制要求）。
#   2. 但 native assets 开启时，`flutter build apk` 会因为增量缓存的
#      失效判断（build 是 junction → D 盘，工具按 C 盘路径判时间戳）
#      而**跳过 AOT 编译**，最后仍打印 "√ Built app-release.apk"，
#      产出一个**不含 libapp.so 的坏包**（装上白屏，体积只有 ~33MB）。
#   3. 正常包体积 ~57MB（三 ABI 各带 libapp.so）。
#
# 因此：出包临时关 native assets，出完立刻恢复，并**强制校验 libapp.so**。
#
# ★ 2026-11-13 修订（R-1 依赖漂移）：`flutter build apk` 默认会**隐式跑
#   `flutter pub get`**（默认 `--pub`）。本机 `PUB_HOSTED_URL` 指向
#   `https://pub.flutter-io.cn` 镜像，于是 pub 会按镜像索引重新解析，
#   把 `android_file_picker` 从 lock 冻结的 **2.1.5(pub.dev)** 升到
#   **2.1.6(pub.flutter-io.cn)**：结果是**出货包里的依赖与仓库 lock 不一致**，
#   构建不可复现，而且事后把 lock 还原也补不回产物（包已经生成了）。
#   处置：① 构建加 `--no-pub`，让 pub 解析完全不参与出包；
#        ② 出包前后各校验一次 `pubspec.lock` 与 `pubspec.lock.t7bak` 逐字节一致；
#        ③ 若 `.dart_tool/package_config.json` 不存在则直接拒绝——
#           `--no-pub` 不会自己生成它，必须先手工 `flutter pub get --offline`。
# ============================================================
set -euo pipefail

source /d/dev/env.sh
cd "$(dirname "$0")/.."
export NO_PROXY=127.0.0.1,localhost,::1

APK="build/app/outputs/flutter-apk/app-release.apk"

# ★ 2026-11-10 修订：**不再**临时关闭 native-assets。
#   踩坑记录：`flutter pub get` 拉入新依赖后，`objective_c` 的 build_hooks
#   在 native-assets 关闭时直接报错退出：
#     Target build_hooks failed: Package(s) objective_c require the dart
#     assets feature to be enabled.
#   结果是 `:app:compileFlutterBuildRelease` 必然失败，脚本还会因为 trap
#   没跑完而把全局配置留在「关闭」状态，导致随后的 `flutter test` 也一起崩。
#   实测：**保持 native-assets 开启也能正常产出三 ABI 的 libapp.so**
#   （见下面 [2/3] 的强制校验），所以改为「保持开启 + 强校验」。
flutter config --enable-native-assets >/dev/null 2>&1 || true

echo "[1/4] 出包前校验依赖锁（防镜像漂移）"
if [ ! -f .dart_tool/package_config.json ]; then
  echo "✗ 缺少 .dart_tool/package_config.json —— 本脚本用 --no-pub 出包，" >&2
  echo "  必须先执行：unset PUB_HOSTED_URL && flutter pub get --offline" >&2
  exit 1
fi
if [ -f pubspec.lock.t7bak ]; then
  if ! cmp -s pubspec.lock pubspec.lock.t7bak; then
    echo "✗ pubspec.lock 与 pubspec.lock.t7bak 不一致 —— 依赖已漂移，拒绝出包。" >&2
    echo "  先 diff 两处差异；确认要升级就把 t7bak 一起更新，别只改锁文件。" >&2
    exit 1
  fi
  echo "  lock 与基准一致：$(sha256sum pubspec.lock | cut -c1-16)…"
else
  echo "  ⚠ 没有 pubspec.lock.t7bak，跳过基准比对（仅本次）"
fi

echo "[2/4] 构建 release APK（native-assets 保持开启；--no-pub 不重解析依赖）"
rm -f "$APK"
flutter build apk --release --no-pub

echo "[3/4] 校验 AOT 产物"
if [ ! -f "$APK" ]; then
  echo "✗ 没有产出 APK" >&2
  exit 1
fi
# ★ 必须重试：`flutter build` 刚返回时，Windows 上这个文件可能还被
#   Gradle / 杀毒软件锁着，`unzip -l` 会直接失败 —— 那样会把**好包**
#   误判成坏包（本机真踩过：57.5MB 的好包被判「缺 libapp.so」）。
ok=0
for i in 1 2 3 4 5; do
  if unzip -l "$APK" 2>/dev/null | grep -q "libapp\.so"; then
    ok=1
    break
  fi
  sleep 1
done
if [ "$ok" -ne 1 ]; then
  echo "✗ APK 缺 libapp.so —— 构建静默失败（增量缓存不一致）。" >&2
  echo "  修复：删掉 .dart_tool/flutter_build 与 build/app/intermediates/flutter 后重跑本脚本。" >&2
  exit 1
fi
unzip -l "$APK" | grep "libapp\.so"

echo "[4/4] 出包后复核依赖锁（--no-pub 下不应有任何改写）"
if [ -f pubspec.lock.t7bak ]; then
  if ! cmp -s pubspec.lock pubspec.lock.t7bak; then
    echo "✗ 构建过程改写了 pubspec.lock —— 依赖漂移，本包不可复现，请勿交付。" >&2
    exit 1
  fi
  echo "  lock 仍与基准逐字节一致；pub.dev 源计数：$(grep -c 'url: \"https://pub.dev\"' pubspec.lock)"
fi

echo ""
echo "===== 出包成功 ====="
ls -la --time-style=long-iso "$APK"
sha256sum "$APK"
echo "签名：debug（signingConfigs.getByName(\"debug\")，可侧载安装、不可上架）"
