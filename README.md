# XR30 ImmortalWrt 25.12 自编译固件

CMCC XR30（NAND 版，MTK / H大 U-Boot 固定分区）专用固件源码仓库，用 GitHub Actions 云端编译。

## 基线

| 项 | 值 |
| --- | --- |
| 源码 | `chasey-dev/immortalwrt-mt798x-rebase` |
| 分支 | `25.12` |
| 设备 | `cmcc_xr30-nand-mtkuboot` |
| 分区布局 | NAND + MTK/H大 U-Boot 固定分区（`UBINIZE_OPTS -E 5`、`IMAGE_SIZE 116736k`、`KERNEL_IN_UBI`、`factory.bin = append-ubi`） |
| 无线驱动 | MTK 闭源 `mt_wifi` 7.6.7.3（7673）+ WARP v2 |
| 包管理器 | apk（沿用基线默认，未改 opkg） |

> 设备定义在 `target/linux/mediatek/image/filogic-ext.mk`，本仓库没有自己移植设备树——上游已带。
> `-ubootmod`（OpenWrt U-Boot）那套与本机 U-Boot 不匹配，刷了会变砖。

## 内置功能

| 需求 | 实现 | 配置开关 |
| --- | --- | --- |
| iStore 软件中心 | `luci-app-store` + `taskd` | `config.add` REQ-01 |
| 无线中继面板 | `luci-app-mtwifi-cfg` + 驱动 `APCLI_SUPPORT` | REQ-02 |
| USB 4G 上网 | `kmod-usb-net-rndis / cdc-ncm / cdc-mbim / qmi-wwan`、`usb-modeswitch`、`uqmi` | REQ-03 |
| 模组管理 | `luci-app-qmodem-next`（QModem，纯 JS 前端） | REQ-04 |
| 科学上网 | `luci-app-openclash`（不再带 passwall） | REQ-05 |
| 硬件加速 | `kmod-mediatek_hnat` + `luci-app-turboacc-mtk` + WARP | REQ-06 |
| 定时重启 | `luci-app-autoreboot` | REQ-07 |
| 流量统计 | `luci-app-nlbwmon` | REQ-08 |
| 网页终端 | `luci-app-ttyd` | REQ-09 |
| SSH / SFTP | `dropbear` + `openssh-sftp-server` | REQ-10 |

## 驱动补丁（本仓库重点）

`patches/` 下的两个补丁会被 `diy-part2.sh` 拷进
`package/mtk/drivers/mt_wifi/patches-7673/`，由 quilt 自动应用：

- `042-pmf-skip-saquery-on-not-robust-unicast.patch`
  命中 `NOT_ROBUST_UNICAST_FRAME` 时不再调用 `PMF_MlmeSAQueryReq()`，只保持原来的
  `return FALSE`（= 丢弃该管理帧）。不发起 SA Query，就没有后续的超时踢人。
- `043-pmf-keep-wcid-on-saquery-timeout.patch`
  SA Query 定时器超时后不再 `cntl_disconnect_request()` / `mac_entry_delete()`，
  不再踢除 wcid。

> 这两个是 **mt_wifi 闭源 SDK 驱动补丁**，不是主线 OpenWrt 补丁，上游仓库不带。
> 补丁上下文基于 `mt79xx_20250408-705eb4.tar.xz`（7673 版本的源码包），换驱动版本要重做。
> 若上游以后占用了 042/043 编号，`diy-part2.sh` 会直接报错中止。

## 构建

推送到 `main` 会自动触发；也可在 Actions 页手动 `Run workflow`。

本地想跑的话：把本仓库当成 `$GITHUB_WORKSPACE`，先 `git clone` 基线到 `openwrt/`，
然后依次执行 `diy-part1.sh`（在 feeds update 前）、`feeds update -a && feeds install -a`、
`diy-part2.sh`、`make defconfig`、`verify-config.sh`、`make -j$(nproc)`。

## 刷机前

1. 确认是 **NAND 版**，U-Boot 是 **H大 fixed-parts**；
2. 备份 Factory / Bdata / u-boot-env / BL2 / FIP；
3. 首刷用 `factory.bin`（U-Boot 网页恢复），升级用 `sysupgrade.bin`；
4. 默认 LAN：`192.168.3.254`，无密码。

## 已知取舍

- **HNAT 与代理互斥**：OpenClash 走 tproxy 会打断 netfilter 快路径，HNAT 面板显示"已开启"但实际失效。
  跑代理时把 `turboacc` 的 HNAT/BBR 关掉，或只用 BBR。
- **iStore 只装轻量包**：128MB NAND 下 squashfs 约 32MB，UBI 卷约 114MB，overlay 余量看产物大小。
  大插件让 iStore 装到 U 盘更稳。
- **nlbwmon 写 NAND**：统计库在 `/etc/nlbwmon`，长期累计会磨损闪存，建议保留天数 ≤ 30。
- **passwall 已移除**：原仓库的 passwall 源写错了位置（apk 地址写进 opkg 目录），实际从未编进固件。

## Credits

- [chasey-dev/immortalwrt-mt798x-rebase](https://github.com/chasey-dev/immortalwrt-mt798x-rebase)
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [vernesong/OpenClash](https://github.com/vernesong/OpenClash) · [istoreos/istore](https://github.com/istoreos/istore) · [FUjr/QModem](https://github.com/FUjr/QModem)
