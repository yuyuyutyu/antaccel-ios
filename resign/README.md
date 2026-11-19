# resign · 签名工具链

## 目录

    inspect_signing.ps1     p12 + 描述文件体检(纯 Windows,.NET 实现,不上传任何文件)
    resign.ps1              Windows 端 IPA 重签(zsign 驱动,自动对齐 Bundle ID)
    resign_ipa.sh           macOS 端 IPA 重签(codesign 驱动)
    README.md               本文件

## 一、先体检

    .\inspect_signing.ps1 -P12 .\cert.p12 -P12Password 123456 -Profile .\profile.mobileprovision

输出会告诉你:证书类型、是否含私钥、TeamID、到期时间、描述文件包名、是否企业 In-House、以及**签名时必须用的 Bundle ID**。

## 二、Windows 重签(需要 zsign.exe)

zsign 是 C++ 写的跨平台签名器(zhlynn/zsign),Windows 构建放脚本同目录即可。

    .\resign.ps1 -Ipa .\AntiAccel-unsigned.ipa -P12 .\cert.p12 -P12Password 123456 -Profile .\profile.mobileprovision -Zsign .\zsign.exe

脚本自动做的事:

1. 从描述文件里解出 `application-identifier`,取后半段作为目标 Bundle ID;
2. 调 `zsign -k p12 -p 口令 -m 描述文件 -b 包名 -o out.ipa -z 9` 完成重签;
3. 解包自检 `Payload/Info.plist`、`_CodeSignature/CodeResources`、`embedded.mobileprovision` 三件套是否齐;
4. 打不通时直接告诉你哪一环缺。

没有 zsign 也能干:用 ESign(手机上自签)、Sideloadly、爱思助手"IPA 签名"功能,喂同样的三个文件。

## 三、macOS 重签

    chmod +x resign_ipa.sh
    ./resign_ipa.sh -i in.ipa -k cert.p12 -m profile.mobileprovision -p 口令 -o out.ipa

内部流程:解包 -> `security cms -D` 解描述文件 -> `plutil` 改 CFBundleIdentifier -> 逐层 `codesign`(appex/framework/dylib)-> `--verify --deep --strict` -> 重新 zip。

## 四、常见报错对照

| 报错 | 含义 | 处理 |
|---|---|---|
| `failed to parse p12` | 口令错或证书链不全 | 用 `inspect_signing.ps1` 复查,补 WWDR 中间证书 |
| `bundle id mismatch` | 包名与描述文件不一致 | 让脚本自动 `-b` 对齐,别手改 |
| `no identity found` | p12 里没私钥 | 换一份带私钥的 p12 |
| `ApplicationVerificationFailed` | 描述文件不认这张证书 | 证书与描述文件必须同一 TeamID |
| 装完点开闪退 | 描述文件过期 / 掉签 | 重取描述文件,重签 |
