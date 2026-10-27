#!/bin/bash
#
# verify-config.sh —— 在 make defconfig 之后执行（工作目录 = openwrt 源码根）
#
# 为什么需要它：kconfig 对"不存在的包名 / 依赖不满足的包"是**静默丢弃**，
# 构建照样成功，但你拿到手的固件少功能，而且看不出来。
# 这里把九项能力对应的符号逐一硬校验，缺一个就直接失败。
#
set -u

FAIL=0
check() {
    if grep -qx "$1" .config; then
        printf '  [ OK ] %s\n' "$2"
    else
        printf '  [MISS] %s  (%s)\n' "$2" "$1"
        FAIL=1
    fi
}

echo "==> 校验设备与无线驱动"
check "CONFIG_TARGET_mediatek_filogic_DEVICE_cmcc_xr30-nand-mtkuboot=y" "设备 cmcc_xr30-nand-mtkuboot"
check "CONFIG_PACKAGE_kmod-mt_wifi=y"                    "MTK 闭源无线驱动 mt_wifi"
check "CONFIG_MTK_MT_WIFI_DRIVER_VERSION_7673=y"         "驱动版本 7673（PMF 补丁按此版本编写）"
check "CONFIG_MTK_APCLI_SUPPORT=y"                       "apcli（中继站模式）"
check "CONFIG_MTK_DOT11W_PMF_SUPPORT=y"                  "PMF 编译开关（补丁生效前提）"
check "CONFIG_PACKAGE_luci-app-mtwifi-cfg=y"             "REQ-02 无线中继面板"

echo "==> 校验九项能力"
check "CONFIG_PACKAGE_luci-app-store=y"                  "REQ-01 iStore"
check "CONFIG_PACKAGE_luci-app-qmodem-next=y"            "REQ-04 QModem"
check "CONFIG_PACKAGE_luci-app-openclash=y"              "REQ-05 OpenClash"
check "CONFIG_PACKAGE_kmod-mediatek_hnat=y"              "REQ-06 HNAT 硬件加速"
check "CONFIG_PACKAGE_luci-app-turboacc-mtk=y"           "REQ-06 加速面板"
check "CONFIG_PACKAGE_luci-app-autoreboot=y"             "REQ-07 定时重启"
check "CONFIG_PACKAGE_luci-app-nlbwmon=y"                "REQ-08 流量统计"
check "CONFIG_PACKAGE_luci-app-ttyd=y"                   "REQ-09 网页终端"
check "CONFIG_PACKAGE_dropbear=y"                        "REQ-10 SSH"
check "CONFIG_PACKAGE_openssh-sftp-server=y"             "REQ-10 SFTP"

echo "==> 校验 USB 上网所需驱动"
# USB 网卡框架与基础（缺 kmod-usb-net 则 rndis/ncm/mbim 全部挂不上）
for k in kmod-usb-net kmod-mii kmod-usb-net-cdc-ether kmod-usb-net-rndis \
         kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim; do
    check "CONFIG_PACKAGE_${k}=y" "$k"
done
# 模组拨号与 AT 口
for k in kmod-usb-net-qmi-wwan kmod-usb-wdm kmod-usb-acm \
         kmod-usb-serial kmod-usb-serial-option kmod-usb-serial-wwan \
         usb-modeswitch uqmi umbim comgt comgt-ncm; do
    check "CONFIG_PACKAGE_${k}=y" "$k"
done
# USB 存储（ZeroCD 模组 eject + U 盘扩 overlay 都靠它）
for k in kmod-scsi-core kmod-usb-storage kmod-fs-ext4 kmod-fs-vfat \
         kmod-fs-exfat kmod-fs-ntfs3 block-mount; do
    check "CONFIG_PACKAGE_${k}=y" "$k"
done

echo "==> 校验 PMF 补丁是否就位"
for p in 042-pmf-skip-saquery-on-not-robust-unicast.patch \
         043-pmf-keep-wcid-on-saquery-timeout.patch; do
    if [ -f "package/mtk/drivers/mt_wifi/patches-7673/$p" ]; then
        printf '  [ OK ] %s\n' "$p"
    else
        printf '  [MISS] %s\n' "$p"
        FAIL=1
    fi
done

echo "==> 校验 perl 测试套件是否关闭"
# perl 5.40 把 Math-BigRat 挪到了 dist/，而 perlbase-math 的测试用例安装
# 仍指向 cpan/Math-BigRat/t，一旦打开就会在打包阶段 Error 23。
if grep -qx 'CONFIG_PERL_TESTS=y' .config; then
    printf '  [WARN] CONFIG_PERL_TESTS=y —— perlbase-math 会去拷已搬迁的 cpan/Math-BigRat/t\n'
    printf '         （已由 perlmod.mk 的 --ignore-missing-args 兜住，但会白白多编一堆测试包）\n'
else
    printf '  [ OK ] perl 测试套件已关闭\n'
fi

if [ "$FAIL" -ne 0 ]; then
    echo
    echo "!! 有配置项没被 defconfig 保留，构建继续下去也会得到缺功能的固件，先修。"
    echo "!! 常见原因：包名写错 / 依赖未满足 / feed 没拉下来。"
    exit 1
fi

echo
echo "==> 全部校验通过"
