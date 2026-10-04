#!/usr/bin/env bash
#
# 眼中名片（EyeCard）iOS 安装包打包脚本
# =====================================
#
# 这个脚本只在 macOS 上运行。iOS 的编译和签名工具链（xcodebuild / codesign）
# 是苹果独有的，Windows 和 Linux 上没有替代品。
#
# 四种模式：
#
#   ./build_ipa.sh unsigned               不打签名的 ipa，给 Sideloadly / AltStore 用（不需要开发者账号）
#   ./build_ipa.sh development --team XX   带开发签名的 ipa，装到已登记的设备
#   ./build_ipa.sh adhoc --team XX         带 Ad Hoc 签名的 ipa，分发给已登记 UDID 的设备
#   ./build_ipa.sh appstore --team XX      用于上传 App Store Connect（产物用 Transporter 上传）
#
# `--team` 后面填你的 Apple Developer Team ID（10 位，例如 A1B2C3D4E5）。
# 也可以在环境变量里给：TEAM_ID=A1B2C3D4E5 ./build_ipa.sh development
#
# 没有付费开发者账号时用 unsigned 模式：产物是未签名的 ipa，
# 回到 Windows 或 Mac 上用 Sideloadly 配合免费 Apple ID 重新签名后安装。
#
# 产物统一放在 ios/dist/ 目录（iOS 相关的东西都收在 ios/ 里）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$SCRIPT_DIR"
# iOS 的东西全部收在 ios/ 目录里，产物也放在 ios/dist/，不在仓库根另开目录
OUT_DIR="$IOS_DIR/dist"
BUILD_DIR="$IOS_DIR/build"
DERIVED="$BUILD_DIR/DerivedData"
PROJECT="$IOS_DIR/EyeCard.xcodeproj"
SCHEME="EyeCard"
APP_NAME="EyeCard"

MODE="unsigned"
TEAM_ID="${TEAM_ID:-}"

usage() {
    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
    echo "" >&2
    echo "错误：$*" >&2
    exit 1
}

step() {
    echo ""
    echo "==> $*"
}

# ---------------------------------------------------------------- 参数解析

while [[ $# -gt 0 ]]; do
    case "$1" in
        unsigned|development|adhoc|appstore)
            MODE="$1"
            shift
            ;;
        --team)
            TEAM_ID="${2:-}"
            shift 2
            ;;
        --team=*)
            TEAM_ID="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知参数：$1" >&2
            usage
            exit 2
            ;;
    esac
done

# ---------------------------------------------------------------- 环境自检

step "检查构建环境"

[[ "$(uname -s)" == "Darwin" ]] || die "这个脚本只能在 macOS 上运行（当前系统：$(uname -s)）。
iOS 的编译工具链只存在于 macOS，Windows 上无法编译 ipa。
如果在 Windows 上，请改用 GitHub Actions 的 macOS 机器打包，
方法见《导出iOS安装包.md》第四节的路线 B。"

command -v xcodebuild >/dev/null 2>&1 || die "未找到 xcodebuild。请先安装 Xcode（App Store 里搜 Xcode），
安装完成后在终端执行一次：sudo xcode-select --switch /Applications/Xcode.app"

DEVELOPER_DIR_PATH="$(xcode-select -p 2>/dev/null || true)"
case "$DEVELOPER_DIR_PATH" in
    */Xcode*.app/Contents/Developer) ;;
    *)
        die "xcode-select 当前指向的不是完整的 Xcode：${DEVELOPER_DIR_PATH:-<空>}
请执行：sudo xcode-select --switch /Applications/Xcode.app"
        ;;
esac

XCODE_VERSION="$(xcodebuild -version | head -1 | awk '{print $2}')"
XCODE_MAJOR="${XCODE_VERSION%%.*}"
XCODE_MAJOR="${XCODE_MAJOR:-0}"
if ! [[ "$XCODE_MAJOR" =~ ^[0-9]+$ ]]; then
    XCODE_MAJOR=0
fi
echo "Xcode 版本：$XCODE_VERSION"
echo "构建模式：$MODE"

if [[ "$XCODE_MAJOR" -lt 16 ]]; then
    if command -v xcodegen >/dev/null 2>&1; then
        echo "Xcode 低于 16，改用 XcodeGen 重新生成工程（自带工程文件是新格式，旧版 Xcode 打不开）"
        (cd "$IOS_DIR" && xcodegen generate)
    else
        die "自带的 EyeCard.xcodeproj 使用了 Xcode 16 的工程格式，当前 Xcode $XCODE_VERSION 打不开。
两个办法：
  1) 升级到 Xcode 16 或更高；
  2) 安装 XcodeGen 后用备用描述文件重新生成工程：
       brew install xcodegen
       cd \"$IOS_DIR\" && xcodegen generate"
    fi
fi

if [[ ! -d "$PROJECT" ]]; then
    command -v xcodegen >/dev/null 2>&1 || die "缺少 $PROJECT，且未安装 XcodeGen。
请执行：brew install xcodegen && cd \"$IOS_DIR\" && xcodegen generate"
    (cd "$IOS_DIR" && xcodegen generate)
fi

mkdir -p "$OUT_DIR" "$BUILD_DIR"

echo "产物目录：$OUT_DIR"

# ---------------------------------------------------------------- 未签名打包

build_unsigned() {
    local app_path="$DERIVED/Build/Products/Release-iphoneos/$APP_NAME.app"
    local pkg_dir="$BUILD_DIR/unsigned-pkg"
    local ipa="$OUT_DIR/$APP_NAME-unsigned.ipa"

    step "编译 Release 版（关闭代码签名）"
    rm -rf "$DERIVED"
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -sdk iphoneos \
        -destination 'generic/platform=iOS' \
        -derivedDataPath "$DERIVED" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        ENABLE_USER_SCRIPT_SANDBOXING=NO \
        build

    [[ -d "$app_path" ]] || die "编译结束但没找到产物：$app_path"

    step "打包成 ipa"
    # 清掉可能残留的签名痕迹，未签名 ipa 交给 Sideloadly 重新签名
    rm -rf "$app_path/_CodeSignature" "$app_path/embedded.mobileprovision"

    # 保险起见，确认 Info.plist 里有 MinimumOSVersion，Sideloadly 会读这一项
    if ! /usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$app_path/Info.plist" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string 16.0" "$app_path/Info.plist"
    fi

    rm -rf "$pkg_dir"
    mkdir -p "$pkg_dir/Payload"
    cp -R "$app_path" "$pkg_dir/Payload/"

    rm -f "$ipa"
    (cd "$pkg_dir" && zip -qryX "$ipa" Payload)

    echo "已生成：$ipa"
    echo ""
    echo "这个包未签名，装不进 iPhone。下一步任选一种："
    echo "  - Windows：用 Sideloadly 载入它，填一个 Apple ID，点 Start 即可签名并安装"
    echo "    （详细步骤见《导出iOS安装包.md》第五节）"
    echo "  - macOS：用 AltStore 或 Sideloadly，同样需要一个 Apple ID"
}

# ---------------------------------------------------------------- 签名打包

build_signed() {
    [[ -n "$TEAM_ID" ]] || die "$MODE 模式需要指定 Team ID。
用法：./build_ipa.sh $MODE --team <10位TeamID>
Team ID 在 https://developer.apple.com/account 的 Membership 页面可以查到，
用 Xcode 打开工程时也会显示在 Signing & Capabilities 里。"

    local archive="$BUILD_DIR/$APP_NAME.xcarchive"
    local export_dir="$BUILD_DIR/export-$MODE"
    local options_src="$IOS_DIR/ExportOptions-$MODE.plist"
    local options_tmp="$BUILD_DIR/ExportOptions-$MODE.generated.plist"
    local ipa_out="$OUT_DIR/$APP_NAME-$MODE.ipa"

    [[ -f "$options_src" ]] || die "缺少导出配置文件：$options_src"

    step "归档（Archive）"
    rm -rf "$archive" "$export_dir"
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -archivePath "$archive" \
        -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_STYLE=Automatic \
        archive

    step "导出 ipa（$MODE）"
    sed "s/__TEAM_ID__/$TEAM_ID/g" "$options_src" > "$options_tmp"
    xcodebuild \
        -exportArchive \
        -archivePath "$archive" \
        -exportPath "$export_dir" \
        -exportOptionsPlist "$options_tmp" \
        -allowProvisioningUpdates

    local produced
    produced="$(find "$export_dir" -maxdepth 1 -name '*.ipa' | head -1)"
    [[ -n "$produced" ]] || die "导出结束但没找到 ipa，请检查上面的导出日志"

    cp "$produced" "$ipa_out"
    echo "已生成：$ipa_out"
}

# ---------------------------------------------------------------- 主流程

case "$MODE" in
    unsigned)
        if [[ -n "$TEAM_ID" ]]; then
            echo "提示：unsigned 模式不需要 Team ID，已忽略 --team"
        fi
        build_unsigned
        ;;
    development|adhoc|appstore)
        build_signed
        ;;
esac

step "完成"
shasum -a 256 "$OUT_DIR"/*.ipa 2>/dev/null || true
echo ""
echo "提示：免费 Apple ID 签名的应用有效期只有 7 天，到期需要重新签名安装；
要用 TestFlight 或长期分发，需要付费的 Apple Developer 账号（99 美元/年）。"
