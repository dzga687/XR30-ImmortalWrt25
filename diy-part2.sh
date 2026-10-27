#!/bin/bash
#
# diy-part2.sh —— 在 ./scripts/feeds install -a 之后、make defconfig 之前执行
# 工作目录 = openwrt 源码根；脚本自身所在目录 = 本仓库根
#
# 做四件事：
#   1) 从新 feed 里安装插件包（iStore / OpenClash / QModem）
#   2) 把 mtwifi 的 PMF 补丁放进 package/mtk/drivers/mt_wifi/patches-7673/
#   3) 删掉无法构建的 passwall 残留配置
#   4) 按 config.add 覆盖写入 .config
#
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(pwd)"
DRV_PATCH_DIR="$SRC/package/mtk/drivers/mt_wifi/patches-7673"

echo "==> [1/5] 安装第三方插件包"
for spec in \
    "istore:luci-app-store" \
    "openclash:luci-app-openclash" \
    "qmodem:luci-app-qmodem-next"
do
    feed="${spec%%:*}"
    pkg="${spec##*:}"
    if ./scripts/feeds list -n 2>/dev/null | grep -qx "$pkg"; then
        echo "  (已随 feeds install -a 就位) $pkg"
        continue
    fi
    echo "  安装 $pkg (feed: $feed)"
    ./scripts/feeds install -d y -p "$feed" "$pkg"
done

echo "==> [2/5] 植入 mtwifi PMF 补丁"
if [ ! -d "$DRV_PATCH_DIR" ]; then
    echo "!! 找不到 $DRV_PATCH_DIR"
    echo "!! 说明基线的 mt_wifi 不是 7673（或仓库不是 chasey-dev/immortalwrt-mt798x-rebase）"
    exit 1
fi
shopt -s nullglob
patch_count=0
for p in "$ROOT"/patches/*.patch; do
    name="$(basename "$p")"
    if [ -e "$DRV_PATCH_DIR/$name" ]; then
        echo "!! 补丁编号冲突：$DRV_PATCH_DIR/$name 已存在"
        echo "!! 上游已占用该编号，请把 patches/ 里的文件改成更大的序号"
        exit 1
    fi
    cp -f "$p" "$DRV_PATCH_DIR/$name"
    echo "  + $name"
    patch_count=$((patch_count + 1))
done
shopt -u nullglob
if [ "$patch_count" -eq 0 ]; then
    echo "!! patches/ 目录为空，PMF 补丁没有被植入"
    exit 1
fi
echo "  共植入 $patch_count 个补丁"

echo "==> [3/5] 清理 passwall 残留配置"
# luci-app-passwall 不在任何构建期 feed 里（原脚本写的是 apk 运行时源，
# 而且路径写错到了 package/system/opkg/files/），make defconfig 会把它静默丢弃。
# 这里直接删掉相关行，避免"配置里写着有、固件里其实没有"的错觉。
sed -i '/passwall/d' .config

echo "==> [4/5] 按 config.add 写入开关"
set_cfg() {
    local key="$1" val="$2"
    sed -i "/^${key}=/d" .config
    sed -i "/^# ${key} is not set\$/d" .config
    if [ "$val" = "n" ]; then
        printf '# %s is not set\n' "$key" >>.config
    else
        printf '%s=%s\n' "$key" "$val" >>.config
    fi
}

while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        ''|'#'*) continue ;;
        *=*) set_cfg "${line%%=*}" "${line#*=}" ;;
    esac
done <"$ROOT/config.add"

echo "  已写入 $(grep -c '^CONFIG_' "$ROOT/config.add") 项"

echo "==> [5/5] 其它定制"
# 默认 LAN 地址（保留仓库原有设定，如需 192.168.1.1 改成对应值）
sed -i 's/192.168.1.1/192.168.3.254/g' package/base-files/files/bin/config_generate

echo "==> diy-part2.sh 完成"
