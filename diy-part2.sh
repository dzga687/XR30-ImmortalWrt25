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

echo "==> [3/5] 清理 passwall / weechat，并修正 istore 的依赖声明"
# luci-app-passwall 不在任何构建期 feed 里（原脚本写的是 apk 运行时源，
# 而且路径写错到了 package/system/opkg/files/），make defconfig 会把它静默丢弃。
# 这里直接删掉相关行，避免"配置里写着有、固件里其实没有"的错觉。
sed -i '/passwall/d' .config

# weechat 的 Kconfig 有循环依赖（luci-app-weechat → weechat-full → weechat-minimal
# → 又被 luci-app-weechat select），kconfig 会报
#   "error: recursive dependency detected!"
# 然后中途退出，留下一个不一致的 .config —— 表现为若干个毫不相关的包被静默丢掉。
# 路由器上没人要用 weechat，直接把这两个包摘掉，让 defconfig 干净退出。
#
# 注意两处都要删：feeds install 在 package/feeds/<feed>/ 下建的是软链接，
# 只删 feed 源目录会留下悬空链接，后续扫描 package/ 时会报错。
for d in feeds/*/*/luci-app-weechat feeds/*/*/weechat \
         package/feeds/*/luci-app-weechat package/feeds/*/weechat; do
    if [ -L "$d" ] || [ -e "$d" ]; then
        rm -rf "$d"
        echo "  移除 $d（消除 kconfig 循环依赖）"
    fi
done

# luci-app-store 的 Makefile 里有两处会让 kconfig 直接把它隐藏掉：
#   1) LUCI_EXTRA_DEPENDS:=luci-lib-taskd (>=1.0.19) —— 带版本号的依赖，
#      kconfig 不认版本约束，生成的 depends on 永远不成立，符号被隐藏，
#      .config 里连 "# ... is not set" 都不会出现（最难查的一种丢包方式）；
#   2) LUCI_DEPENDS 里的 +tar —— 本树 tar 是 MENU 包，符号在某些配置下不可见。
# 两者都去掉：luci-lib-taskd 已在 LUCI_DEPENDS 里硬依赖，版本约束多余；
# tar 用 busybox 自带的即可，iStore 解包没有问题。
STORE_MK="feeds/istore/luci/luci-app-store/Makefile"
if [ -f "$STORE_MK" ]; then
    sed -i -E '/^LUCI_EXTRA_DEPENDS:=/d' "$STORE_MK"
    sed -i -E '/^LUCI_DEPENDS:=/ s/[[:space:]]*\+tar//' "$STORE_MK"
    echo "  已修正 $STORE_MK"
    grep -nE '^LUCI_(DEPENDS|EXTRA_DEPENDS)' "$STORE_MK" || true
else
    echo "!! 找不到 $STORE_MK（istore feed 没拉下来？）"
    exit 1
fi

# perl 的测试用例安装是"整体拷贝目录"，源目录在 perl 5.40 里被搬迁过
# （Math-BigRat 从 cpan/ 挪到 dist/），rsync 找不到就直接 code 23，
# 整个 perlbase-math 打包失败 —— 固件里根本用不到测试用例，却卡住整条流水线。
# config.add 已经把 CONFIG_PERL_TESTS 关掉，这里再给 rsync 上一层保险：
# 源参数缺失时跳过而不是报错（ubuntu-22.04 自带 rsync 3.2.7，支持该选项）。
PERLMOD_MK="feeds/packages/lang/perl/perlmod.mk"
if [ -f "$PERLMOD_MK" ]; then
    sed -i 's/rsync --relative -rlHp --itemize-changes/rsync --ignore-missing-args --relative -rlHp --itemize-changes/g' "$PERLMOD_MK"
    echo "  已为 $PERLMOD_MK 的 rsync 加上 --ignore-missing-args"
    grep -n -- '--ignore-missing-args' "$PERLMOD_MK" || true
else
    echo "  (没有 $PERLMOD_MK，跳过 perl 兜底)"
fi

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
