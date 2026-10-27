#!/bin/bash
#
# diy-part1.sh —— 在 ./scripts/feeds update 之前执行（工作目录 = openwrt 源码根）
# 只做一件事：声明第三方 feed 源。
#
# 基线：chasey-dev/immortalwrt-mt798x-rebase  分支 25.12
# 设备：cmcc_xr30-nand-mtkuboot（NAND + MTK/H大 U-Boot 固定分区，定义在
#       target/linux/mediatek/image/filogic-ext.mk，无需自行移植）
#
set -e

FEEDS_FILE="feeds.conf.default"

add_feed() {
    local name="$1" url="$2"
    if grep -q "^src-git ${name} " "$FEEDS_FILE"; then
        sed -i "s|^src-git ${name} .*|src-git ${name} ${url}|" "$FEEDS_FILE"
    else
        echo "src-git ${name} ${url}" >>"$FEEDS_FILE"
    fi
    echo "  feed: ${name} -> ${url}"
}

echo "==> 追加第三方 feed"
# iStore 官方推荐的 feed 形式（官方同时支持 apk / opkg 固件）
add_feed istore "https://github.com/linkease/istore;main"
# OpenClash
add_feed openclash "https://github.com/vernesong/OpenClash;master"
# QModem：4G/5G 模组管理（推荐 UI 为纯 JS 的 luci-app-qmodem-next）
add_feed qmodem "https://github.com/FUjr/QModem;main"

echo "==> 已移除原脚本里的 passwall .adb 源"
# 原脚本把 apk 仓库地址写进了 package/system/opkg/files/customfeeds.conf：
# 路径和格式都不对，实际从未生效（luci-app-passwall 不在任何构建期 feed 里，
# 所以 make defconfig 会把它连同依赖一起静默丢掉）。
# 本固件的代理方案统一用 OpenClash，不再保留 passwall。
