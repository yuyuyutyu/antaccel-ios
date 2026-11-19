# nodes · 服务端取证与节点导出

## 为什么要有这一步

APK 里没有节点。节点是登录后 `/api/v1/nodes` 实时下发的。所以"把 APK 变成能上网的 iOS App"这件事,数据层必须自己走一遍。

## 三种拿法(按成功率排序)

### 1. App 内置导出(最省事)

安卓端连上节点后:我的 -> 日志 -> 代理配置查看(`ProxyConfigViewerActivity`)。它会把当前 sing-box 配置打出来,直接复制,粘到 iPhone 的 sing-box(SFA)/Shadowrocket 里。

### 2. 脚本直连服务端(本目录)

    python arknet_probe.py --probe https://hwjdybyaop.top:33441
    python arknet_probe.py --base https://hwjdybyaop.top:33441 --user 账号 --password 密码 --mode rsa --out nodes.json
    python arknet_probe.py --base ... --token <抓包得到的 token> --out nodes.json

产出 `nodes.json` 就是一份 sing-box 配置(inbounds tun + outbounds 节点),iPhone 上可直接导入。

脚本特性:

- 零第三方依赖(pure stdlib),自带 PEM->RSA 解析与 `RSA/ECB/PKCS1Padding` 实现,已自检:2048 bit / 256 字节块 / base64 344 字符。
- `--mode plain` 走明文 JSON(部分版本接口兼容),`--mode rsa` 走 `{"data": "<base64(RSA 明文)>"}` 外层。
- 多域名自动探活,失败自动换 `zz1/zz2/zz3/zz11/zz22/zz33`。
- 响应里递归找带 `port` 的对象转成 outbound,字段名做了别名兜底(`host/server/address`、`password/passwd/auth`、`uuid/id`)。

### 3. 抓包(接口结构变了才用)

mitmproxy/Charles + 安卓机装证书,过滤 `/api/v1/`。若遇到 SSL Pinning,先 hook(本机 `libarknet.so` 是 Go 静态编译,证书固定一般在 Java 层 OkHttp,`objection`/Frida 可以绕)。

## 接口要点

    POST /api/v1/auth/login      body 明文或 RSA 包裹;返回 token(也可能在 data.token)
    GET  /api/v1/nodes           需要 Authorization: Bearer <token>(或 token / X-Token)
    POST /api/v1/nodes/connect   选节点,服务端登记占用
    GET  /api/v1/routing-rules   分流规则(与 assets/rule-set/*.srs 配合)

## 边界

这份脚本是给你"自己的账号"用的取证工具。节点是你买的服务的凭据,别外传。
