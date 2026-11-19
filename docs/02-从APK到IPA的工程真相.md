# 02 · 从 APK 到 IPA:工程真相与三条落地路线

## 1. 为什么不存在"一键翻译"

| 维度 | Android(APK) | iOS(IPA) |
|---|---|---|
| 可执行代码 | DEX(ART 字节码)+ ELF `.so` | Mach-O arm64(LD_PIE)+ `.dylib`/`.framework` |
| UI 框架 | View/Compose + XML 布局 | UIKit/SwiftUI + storyboard/xib |
| 网络接管 | `VpnService`(用户在系统里点"允许"就给 tun) | `NetworkExtension` + `NEPacketTunnelProvider` + entitlement `packet-tunnel-provider` |
| 打包 | zip + `META-INF` 签名 | zip + `_CodeSignature/CodeResources` + `embedded.mobileprovision` + CMS 签名 |
| 系统调用 | Linux syscall + binder | Darwin syscall + launchd/XPC |

一个 `.so` 是 ELF 容器(`ELF magic 0x7F 'E' 'L' 'F'`),iOS 的 `dlopen` 只认 Mach-O(`0xFEEDFACF`)。这不是"格式转换",是换一套指令编码、符号表、重定位、加载器。你在 Android 上跑的通话栈,到 iOS 上连第一条指令都读不出来。

所以市面上所有"APK 转 IPA"的服务,本质只有三种做法:

1. **重新做一个 iOS 应用**(壳/复刻),再签名 —— 本交付包路线 A。
2. **拿 iOS 官方包改签名** —— 路线 C。
3. **只搬数据,不搬程序**:账号体系/节点搬去成熟的 iOS 客户端 —— 路线 B。

## 2. 三条路线对比

| | A. 自建 iOS 壳(本包) | B. 同账号 + sing-box 客户端 | C. 官方 iOS 包改签 |
|---|---|---|---|
| 交付物 | 你自己签名的 `.ipa` | 无(用 App Store 客户端) | 改签后的 `.ipa` |
| 需要 | p12 + mobileprovision + 云构建 | 一个能登录的账号 | 一份官方 iOS 包(ipa) |
| 界面 | 原包数据 1:1(导航/热门站点/内置浏览器/桥接协议) | 第三方界面 | 官方原界面 |
| 隧道 | 不含(除非你有 NetworkExtension 资质) | 系统扩展,sing-box 内核 | 官方内核 |
| 能不能真上网 | 不能,只做界面与导航 | 能 | 能 |
| 闪退风险 | 极低(纯 UIKit,零三方依赖) | 不适用 | 中(框架/插件签名链) |
| 适合谁 | 要"有个自己的 iOS 包" | 要"现在就能翻" | 手上有官方包 |

**"能装、能开、不闪退"和"能翻墙"是两件事。** 本包把第一件事做到位,第二件事走路线 B/C。

## 3. 路线 A:本包怎么变成 IPA

### 3.1 原理链

    Swift 源码
      -> xcodebuild archive(CODE_SIGNING_ALLOWED=NO,先出裸 .app)
      -> 塞入 embedded.mobileprovision + 改 CFBundleIdentifier 对齐描述文件
      -> codesign --entitlements <描述文件里的 Entitlements> --sign <p12 里的证书>
      -> zip -r Payload/xxx.app -> xxx.ipa

签名必须满足的等式(任何一项不等就装不上或装完闪退):

    Info.plist 的 CFBundleIdentifier  ==  描述文件 Entitlements.application-identifier 的后半段
    codesign 用的证书                 ==  描述文件里 ProvisionedDevices/Certificates 认可的那张
    codesign 注入的 entitlements      ⊂   描述文件允许的 entitlements
    目标设备                          ∈   ProvisionsAllDevices(企业包)或 ProvisionedDevices(Ad Hoc/开发包)

### 3.2 两种执行环境

- **GitHub Actions(Windows 上就能推)**:`.github/workflows/ios-build.yml`,把 p12/描述文件做成 base64 secret,macos 跑一次编译+签名,产物直接在 Artifacts 里下载。免费额度够用,不用买 Mac。
- **本地 Mac**:`ios/scripts/build_signed_ipa.sh`,一条命令出 `AntiAccel.ipa`。
- **纯 Windows 重签**:先用云构建拿"未签名 IPA",再用 `resign/resign.ps1`(zsign)本地重签,或者用爱思助手/ESign/Sideloadly 图形化重签。

### 3.3 本壳的工程要点(为什么它不闪退)

| 风险点 | 处理 |
|---|---|
| 三方依赖崩 | 零依赖,只有 UIKit / WebKit / Foundation |
| NetworkExtension entitlement 缺失导致秒退 | 根本不申请(不引 NE 框架) |
| 强制解包 | 全工程无 `!`、无 `fatalError`、无 `try!` |
| JSON 结构变更 | `Codable` 全字段 optional,解析失败回退空数组 |
| WebView 空白 | `didFailProvisionalNavigation` 兜底 + `WebContentProcessDidTerminate` 自动 reload |
| JS 弹窗卡死 | Bridge 实现 `WKUIDelegate` 的 alert/confirm/prompt 三件套 |
| 桥接崩溃 | 未识别命令回 `unknown command`,不抛异常 |
| 启动图缺失(letterbox) | 带 `LaunchScreen.storyboard` |
| 部署版本过高 | iOS 13.0 起,覆盖 iPhone 6s 以上全系 |
| 64 位缺失 | `ARCHS=arm64`、`ONLY_ACTIVE_ARCH=NO` |

## 4. 路线 B:让 iPhone 真正上网(最短路径)

1. 安卓端登录你的账号,连任意节点(证明账号可用)。
2. App 内:我的 -> 日志 -> **代理配置查看**(`com.at.arknet.mine.ui.log.ProxyConfigViewerActivity`),导出 sing-box 配置文本。
3. iPhone 装 sing-box(TestFlight 版 SFA)或 Shadowrocket,导入这份配置。
4. 之后隧道由 iOS 系统扩展承载,本壳 App 可共存。

如果拿不到配置文本,用 `nodes/arknet_probe.py` 直接打服务端接口拉节点再转 sing-box JSON。

## 5. 路线 C:官方 iOS 包改签

手上有 `安心加速器` 的 iOS 版本 ipa(从 App Store 下载并解密,或官方自签包)时:

    Windows:  resign/resign.ps1 -Ipa in.ipa -P12 cert.p12 -P12Password x -Profile p.mobileprovision -Zsign zsign.exe
    macOS  :  resign/resign_ipa.sh -i in.ipa -k cert.p12 -m p.mobileprovision -p x

脚本会自动:解描述文件 -> 读出正确的 Bundle ID -> 改 Info.plist -> 逐层签 Framework/AppEx -> 注入 entitlements -> 重新打包。

注意:若官方包带 `com.apple.developer.networking.networkextension` 而你的证书没有这个资质,签名会失败或装完隧道起不来。这种情况只能走"同一 TeamID 的证书"或路线 B。

## 6. 一句话决策树

    手上有没有官方 iOS 包? ── 有 ──> 路线 C(功能最全)
      │
      └ 没有 ── 想立刻能翻 ──> 路线 B(账号 + sing-box 客户端)
                   │
                   └ 想要一个"自己的 iOS App" ──> 路线 A(本包,能装能开)
