# 安心加速器 APK -> iPhone 可装 IPA(交付包)

> 目标:用你手上的 p12 证书,把 `安心加速器 4 / 1.0.5`(包名 `com.at.arknet.app`)做成一个
> **能装上、能打开、不闪退** 的 iOS 安装包。
> 结论先给:APK 的二进制搬不到 iOS(ELF vs Mach-O),能搬的是 **界面 + 导航数据 + 桥接协议**;
> 本包把这部分做成了一个零依赖的 Swift 工程,配一条 `编译 -> p12 重签 -> 出 IPA` 的流水线。

---

## 一、三条落地路线(先对号入座)

| 路线 | 你要的东西 | 产物 | 能翻墙吗 |
|---|---|---|---|
| **A. 自建 iOS 壳(本包)** | p12 + 描述文件 + 一次云构建 | 你自己的 `.ipa`,可直装 | 否(界面/导航/浏览器) |
| **B. 同账号 + sing-box 客户端** | 一个能登录的账号 | 无(用 App Store 客户端) | 是 |
| **C. 官方 iOS 包改签** | 一份官方 iOS ipa | 改签后的 `.ipa` | 是(原功能) |

"不闪退"这三个字归 A 管;"能上网"这三个字归 B/C 管。两条腿一起走,才是完整答案。

---

## 二、交付物清单

| 路径 | 内容 |
|---|---|
| `ios/AntiAccel.xcodeproj` | 完整 Xcode 工程(已生成,双击即开) |
| `ios/AntiAccel/Sources` | 9 个 Swift 源文件(纯 UIKit,零三方依赖) |
| `ios/AntiAccel/Resources` | 从 APK 原样搬来的 `nav_default_home.json`(38 KB)、`NativeObject.js`、BFF 公钥、内嵌导航页 |
| `ios/AntiAccel/Assets.xcassets` | 1024 图标(从 APK 的 480x480 母版放大,已去 alpha) |
| `ios/scripts/build_signed_ipa.sh` | macOS:一条命令 `编译 + 重签 + 出 IPA` |
| `ios/scripts/build_unsigned_ipa.sh` | macOS:只出未签名 IPA(给 Windows 端本地重签用) |
| `ios/project.yml` | XcodeGen 描述文件(想重新生成工程时用) |
| `ios/manifest-example.plist` | 企业证书 OTA 分发的清单模板 |
| `.github/workflows/ios-build.yml` | GitHub Actions:Windows 上推一次就能拿到签好的 IPA |
| `resign/inspect_signing.ps1` | p12 + 描述文件体检器(纯 Windows,.NET 实现) |
| `resign/resign.ps1` | Windows 端 IPA 重签(zsign 驱动,自动对齐 Bundle ID) |
| `resign/resign_ipa.sh` | macOS 端 IPA 重签(codesign 驱动) |
| `nodes/arknet_probe.py` | 从服务端拉节点并转 sing-box 配置(纯标准库,自带 RSA 实现) |
| `docs/01-APK取证报告.md` | 包结构、内核、64 条接口、加密方式、隐藏 Activity 全记录 |
| `docs/02-从APK到IPA的工程真相.md` | 为什么不能翻译、三条路线对比、10 条不闪退要点 |
| `docs/03-签名与装机手册.md` | 证书类型、四道坎、9 个闪退真凶、11 条验收清单 |
| `docs/04-拿p12三步出包.md` | **手上已有 p12**:先验证书、再出未签名 IPA、最后 ESign 签 |
| `docs/05-一条命令出包.md` | **不装 git**:一行命令推仓 + 云端编译 + 自动拉回 IPA |

---

## 三、你要做的事(按顺序)

### 第 0 步:体检(30 秒,能挡掉 90% 的返工)

    cd resign
    .\inspect_signing.ps1 -P12 D:\你的\cert.p12 -P12Password 你的口令 -Profile D:\你的\profile.mobileprovision

看三行就够:**含私钥**、**未过期**、**签名时必须把包名改成 xxx**。

### 第 1 步:出 IPA(二选一)

**方式一 · 云构建(没有 Mac 就走这条)**

想省事直接跑一键脚本(见 `docs/05`):

    cd tools
    .\push-and-build.ps1 -Token ghp_你的令牌

手动版:

1. 新建 GitHub 仓库,把**本目录整体**推上去(README / ios / .github / resign / nodes / docs,已是仓库根结构);
2. 确认 `.github/workflows/ios-build.yml` 就在仓库根目录(本目录已是仓库根结构);
3. 仓库 Settings -> Secrets 加三条:

       P12_BASE64            Base64 后的 p12(Windows 下: [Convert]::ToBase64String([IO.File]::ReadAllBytes("cert.p12")) | Set-Clipboard)
       P12_PASSWORD          p12 口令
       PROFILE_BASE64        Base64 后的 mobileprovision(同上办法)

4. Actions -> `build-signed-ipa` -> Run workflow;
5. 跑完在 Artifacts 里下 `AntiAccel-signed-ipa`,那就是可直接装的包。

不配 secrets 也能跑:只会产出 `AntiAccel-unsigned-ipa`,拿回 Windows 本地重签。

**方式二 · 本地 Mac**

    cd ios/scripts
    P12_PASSWORD=你的口令 ./build_signed_ipa.sh -k ~/cert.p12 -m ~/profile.mobileprovision -o AntiAccel.ipa

脚本会自己从描述文件里读出正确 Bundle ID 并写进 Info.plist,不需要你手动对齐。

### 第 2 步:本地重签(拿到的是未签名 IPA 时)

    cd resign
    .\resign.ps1 -Ipa .\AntiAccel-unsigned.ipa -P12 .\cert.p12 -P12Password 口令 -Profile .\profile.mobileprovision -Zsign .\zsign.exe

### 第 3 步:装到手机

- 数据线:爱思助手 -> 应用 -> 安装本地 IPA;或 Sideloadly 拖入。
- OTA(企业证书):按 `ios/manifest-example.plist` 改好域名,一起放 HTTPS 目录,用 `itms-services://` 链接分发。
- 首次打开若提示未受信任:设置 -> 通用 -> VPN与设备管理 -> 信任你的公司名。

---

## 四、这个壳里到底有什么

| 页面 | 实现 | 数据来源 |
|---|---|---|
| 首页 | `UITableView` 站点列表 + 搜索,推荐项置顶 | APK 的 `nav_default_home.json`(12 分类 / 40+ 站点) |
| 内置浏览器 | `WKWebView`,带进度条、前进后退、刷新、分享 | 用户点击的任意站点 |
| 导航页 | 内嵌 HTML + `WKScriptMessageHandler` 桥接 | 原包 `NativeObject.js` 协议 1:1 复刻 |
| 我的 | 版本信息、服务端情报复制、节点获取指引 | 取证结果 |

桥接命令已实现:`toast`、`getAppInfo`、`getVersion`、`getDeviceInfo`、`getNavData`、`copy`、`openUrl`、`close`、`setTitle`、`vibrate`,未知命令回 `unknown command` 不崩。

代码里没有 `!` 强解包、没有 `try!`、没有 `fatalError`、JSON 全 optional、WebView 白屏自动 reload、JS 弹窗三件套齐全 —— 这就是"不闪退"的实现方式,不是运气。

---

## 五、验收清单

    [ ] inspect_signing.ps1:TeamID 一致 / 未过期 / 含私钥 / 包名已读出
    [ ] IPA 里三件套齐全:Info.plist、_CodeSignature/CodeResources、embedded.mobileprovision
    [ ] 主二进制是 arm64
    [ ] 手机上装完图标正常,3 秒内进首页
    [ ] 首页列出热门站点,点进去网页能开
    [ ] 导航页能开,点"调用原生 toast"能弹窗
    [ ] 我的页显示版本 1.0.5(4) 与 Bundle ID

---

## 六、边界与预期管理

1. 本壳不含隧道内核。iOS 的 VPN 必须走 `NetworkExtension` + entitlement,普通 p12 补不出这个资质;带 NE 的包还需要 Apple 单独批准。
2. 想真上网:走路线 B(同账号 + sing-box 客户端)或路线 C(官方包改签)。
3. 证书一年一换,描述文件过期就重签;企业证书掉签是常态,建议留一套自动化(本包的工作流就是为这个准备的)。
4. `docs/01` 里的接口与域名是静态取证结果,服务端改版后可能失效,以抓包为准。
