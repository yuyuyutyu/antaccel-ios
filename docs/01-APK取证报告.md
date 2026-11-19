# 01 · 目标包取证报告

> 样本:安心加速器_4_1.0.5.apk
> 大小:74,830,684 字节(71.4 MB)
> SHA256:04DCDAA29A4EF97B3110BD1A317C27399782B4DD41EE3D8520906132E7F91919
> MD5:132860D51378ACAFCADEF6715654E7B2
> 取证环境:Windows,静态分析(zip 结构 / 自写 AXML 字符串抽取 / dex 字符串表 / ELF 符号)

---

## 1. 应用身份

| 项 | 值 |
|---|---|
| 包名 | `com.at.arknet.app` |
| Application 类 | `com.at.arknet.app.ArkApplication` |
| versionName | `1.0.5` |
| 资源前缀 | `com.at.arknetprod2` |
| 入口 | `SplashActivity` -> `MainHomeActivity` |
| 结构 | 1692 个 zip entry:res 1298、assets 274、META-INF 94、lib 12、kotlin 8 |

## 2. 它到底是个什么东西

一句话:**原生 UI + WebView 模块 + sing-box 内核的机场客户端**。既不是网页套壳,也不是单纯浏览器。

### 2.1 内核层(决定它能不能被"翻译")

| 产物 | 大小 | 说明 |
|---|---|---|
| `lib/arm64-v8a/libarknet.so` | 41.2 MB | Go 1.26.3 编译的 sing-box(libbox)全量内核 |
| `lib/armeabi-v7a/libarknet.so` | 38.6 MB | 同上,32 位 |
| `lib/x86/libarknet.so` | 39.4 MB | 模拟器 |
| `lib/x86_64/libarknet.so` | 43.9 MB | 模拟器 64 位 |
| `libsqlcipher.so` | 4.1~7.3 MB | SQLCipher,配置/账号本地加密库 |
| `libmmkv.so` | 0.36~0.59 MB | 腾讯 MMKV,键值存储 |

内核里能直接数出来的特征字符串:

- `sing-box` × 9393、`libbox` × 4042、`gvisor` × 7175
- `github.com/sagernet/*`(bbolt 等)、`github.com/Dreamacro/clash`(规则/配置解析)
- 协议全家桶:`shadowsocks` 920、`wireguard` 930、`hysteria` 817、`tuic` 346、`v2ray(utls)` 375、`trojan` 165、`quic-go`
- 编译信息:`go1.26.3`

规则集(assets/rule-set):

    geoip-cn.srs                    40,851 B
    geosite-cn.srs                  34,110 B
    geosite-geolocation-!cn.srs    146,471 B

这是 sing-box 的二进制 rule-set 格式 `.srs`,不是 Clash 的 yaml。

### 2.2 隧道层(Android 专用)

| 组件 | 作用 |
|---|---|
| `com.melancholy.arknetcore.VPNService` | VpnService,建 tun、接管全局路由 |
| `com.melancholy.arknetcore.ProxyService` | 前台服务,保活 |
| `com.melancholy.arknetcore.TileService` | 下拉快捷开关 |
| `TunnelKeepaliveReceiver` / `KeepaliveEditionInitProvider` | 各家 ROM 的保活对抗 |
| `MessengerService` | 独立进程推送 |

权限里 `BIND_VPN_SERVICE`、`FOREGROUND_SERVICE_SPECIAL_USE`、`FOREGROUND_SERVICE_SYSTEM_EXEMPTED`、`QUERY_ALL_PACKAGES`、`REQUEST_INSTALL_PACKAGES`、`SCHEDULE_EXACT_ALARM`、`WAKE_LOCK` 全都具备。

### 2.3 前端层(可以直接搬去 iOS)

- `assets/js/NativeObject.js`(3014 B):桥接协议,且**自带 iOS 分支**:

      window.webkit.messageHandlers.nativeObject.postWithCallback(JSON.stringify(request))

  回调侧:`nativeObjectJs.callback({callback: key, args: payload})`。

- `assets/nav_default_home.json`(38 KB):服务端下发的导航页默认数据,12 个分类(AI/视频/动漫/小说/新闻/社交/游戏/币圈/购物/商务/生活/其他)+ hotSites 列表(TikTok、YouTube、X、Instagram、ChatGPT、Netflix、币安…… 每项带 name/url/description/recommended)。
- `com.melancholy.webview`:自研 WebView 容器(MainProcessCommandService / WebViewActivity),说明"内置浏览器 + 导航站"是原生模块,不是纯 H5。

结论:**UI 与桥接协议可以 1:1 搬到 iOS,隧道内核搬不过去**。

## 3. 服务端情报(从 dex 字符串表挖出)

### 3.1 引导域名

    https://hwjdybyaop.top:33441
    https://jgmqsypqvo.top:33441
    https://zz1.qjfifnbotx.top:14215   (zz2 / zz3 同端口)
    https://zz11.qjfifnbotx.top:14215  (zz22 / zz33 同端口)
    app-test.arknet.dev                (测试环境)

dex 里还有一段逗号拼接的多域名列表,典型的多活 failover 写法:

    https://zz1.qjfifnbotx.top:14215,https://zz2...,https://zz3...,https://jgmqsypqvo.top:33441,

### 3.2 接口清单(56 条,摘主干)

    认证   /api/v1/auth/login  /api/v1/auth/register  /api/v1/auth/captcha
           /api/v1/auth/email/verify  /api/v1/auth/password/reset
           /api/v1/auth/verification-codes  /api/v1/auth/account/delete
    节点   /api/v1/nodes  /api/v1/nodes/check  /api/v1/nodes/connect  /api/v1/nodes/disconnect
    策略   /api/v1/routing-rules
    导航   /api/v1/navigation/carousels  /api/v1/navigation/categories  /api/v1/navigation/items
    账号   /api/v1/users/me  /api/v1/users/me/devices  /api/v1/users/me/rewards
           /api/v1/users/me/billing-policy  /api/v1/users/me/invite-code
    运营   /api/v1/announcements  /api/v1/notifications  /api/v1/faqs  /api/v1/legal-documents
           /api/v1/ads/delivery  /api/v1/ads/events  /api/v1/ads/reward-claims
    运维   /api/v1/app/version  /api/v1/app/initialization  /api/v1/communication-domains
           /api/v1/client-log-upload-grant  /api/v1/client-log-uploads
    工单   /api/v1/tickets  /api/v1/ticket-types

### 3.3 加密与签名

| 项 | 值 |
|---|---|
| BFF 公钥 | `assets/security/client-bff-rsa-prod2.public.pem`(RSA 2048,e=65537) |
| 混入算法 | `RSA/ECB/PKCS1Padding`、`AES/ECB/PKCS5Padding`、`AES-CTR` |
| 关键 header | `X-Renewed-Token`(续签),其余为动态混淆名(`x-T8w-T7v-q`、`x-Ysy-Yxz-Yu` 一类) |
| 签名字段 | `timestamp`、`nonce`、`signature`、`deviceId`、`encrypted` |

RSA 公钥已经完整取到,`nodes/arknet_probe.py` 里内置并跑通加密自检:2048 bit / 256 字节块 / base64 344 字符。

### 3.4 节点在哪

**APK 里没有硬编码节点,也没有订阅链接。** 节点必须 `/api/v1/auth/login` 拿 token,再 `/api/v1/nodes` 才下发。这一点决定了后面所有方案的走向。

## 4. 反调试 / 加固

- 未见主流商业加固壳(无 `libjiagu`、`libDexHelper`、`libmegjb` 一类),主要是 R8 混淆 + 字符串混淆。
- 混淆手段:类名短化、资源名短化(`res/kF.9.png`、`res/aQ.png`)、header 名动态拼接。
- 大量 ROM 适配代码(miui / coloros / originos / oneui / harmony),国内机场客户端标配。

## 5. 顺手挖到的彩蛋

Manifest 里挂了 20+ 个伪装 Activity:

    LauncherCamera / LauncherSms / LauncherPhone / LauncherSettings / LauncherWeather
    LauncherMemo / LauncherMusic / LauncherPhoto / LauncherEmail / LauncherFolder
    IconSwitchPing / IconMaskActivity

作用是换图标伪装(把 VPN 图标换成"相机""天气"骗过桌面检查)。iOS 上没有对应能力(除企业签名包的 `UIPrerenderedIcon` 换图以外,系统不允许动态变脸),想保留这个体验只能在壳里做"图标套餐"静态切换页。

## 6. 对"转 IPA"这件事的直接结论

1. 内核是 Linux/Android 的 ELF(sing-box Go 产物),iOS 只认 Mach-O arm64 —— 二进制层面没有翻译通道。
2. 隧道能力在 iOS 上必须走 NetworkExtension(`NEPacketTunnelProvider`),这个东西要联网 + 专门的 App ID + entitlement,普通 p12 补不出来。
3. 界面、导航数据、桥接协议这三块是可以整包搬走的,搬完就是一个能装能开、功能等价于"内置浏览器 + 站点导航"的 App。
4. 真上网的最短路径:同一账号在 iPhone 的 sing-box 类客户端导入节点,隧道交给系统扩展。
