#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
arknet_probe.py —— 安心加速器(com.at.arknet.app)服务端取证 / 节点导出工具

纯标准库实现,不装任何第三方包:
  * PEM -> RSA 公钥解析(手写 DER 解析)
  * RSA/ECB/PKCS1Padding 加密(对应 APK 里的 client-bff-rsa-prod2.public.pem)
  * 登录 /api/v1/auth/login -> 拉 /api/v1/nodes -> 转 sing-box outbounds

用法:
  python arknet_probe.py --base https://hwjdybyaop.top:33441 --user 账号 --password 密码 --out nodes.json
  python arknet_probe.py --base ... --token <抓包拿到的 token> --out nodes.json
  python arknet_probe.py --probe https://hwjdybyaop.top:33441        # 只探活,不发账号
"""

import argparse
import base64
import json
import os
import random
import ssl
import sys
import urllib.error
import urllib.request

PUB_PEM = """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAul63dy7ITAg12bwk4mqL
o4jk4PuQVMdEDb5KRXTYdcf/LqCEMpv7KzUCGPODwES+jgSO703s2XtxsXKfPYw7
MRzLG7Mvk2FKSJ+zNI80fdW6zRNI+Iguihr3JQcb8FKEbHQ3yfijC4ScmoRxjggv
J7ReuHkl0+Fgpgh4hBrX7cAA1kCutTN+WbbnmxmVLUhCNFG7bmXUD/eOjLVpnndk
y2F8oL6kHID21STHnBpyl6zOKf+uWty4Jwz9sE7XRZeytv+Jxjn/dzNlPDaPyen1
ekiN/+dPhV6LJhpmrk+8SLKxmdDMKZKwMBmZEiu4agQsh083IibPDiE0mGIghjYv
iwIDAQAB
-----END PUBLIC KEY-----"""

DEFAULT_BASES = [
    "https://hwjdybyaop.top:33441",
    "https://jgmqsypqvo.top:33441",
    "https://zz1.qjfifnbotx.top:14215",
]


# ---------------------------------------------------------------- DER / RSA

def _der_next(buf, pos):
    tag = buf[pos]
    pos += 1
    length = buf[pos]
    pos += 1
    if length & 0x80:
        n = length & 0x7F
        length = int.from_bytes(buf[pos:pos + n], "big")
        pos += n
    return tag, buf[pos:pos + length], pos + length


def parse_rsa_public_key(pem):
    """解析 SubjectPublicKeyInfo 形式的 PEM,返回 (n, e)"""
    b64 = "".join(line.strip() for line in pem.splitlines() if "-----" not in line)
    der = base64.b64decode(b64)
    _tag, spki, _end = _der_next(der, 0)
    _tag, _alg, pos = _der_next(spki, 0)
    _tag, bitstr, _pos = _der_next(spki, pos)
    rsa_der = bitstr[1:]
    _tag, seq, _end2 = _der_next(rsa_der, 0)
    _tag, n_bytes, p2 = _der_next(seq, 0)
    _tag, e_bytes, _p3 = _der_next(seq, p2)
    return int.from_bytes(n_bytes, "big"), int.from_bytes(e_bytes, "big")


def rsa_pkcs1_encrypt(message, n, e):
    """RSA/ECB/PKCS1Padding,返回 base64"""
    k = (n.bit_length() + 7) // 8
    if len(message) > k - 11:
        raise ValueError("明文太长,超出单块 RSA 上限")
    ps = bytes(random.randint(1, 255) for _ in range(k - len(message) - 3))
    block = b"\x00\x02" + ps + b"\x00" + message
    m = int.from_bytes(block, "big")
    c = pow(m, e, n)
    return base64.b64encode(c.to_bytes(k, "big")).decode()


# ---------------------------------------------------------------- HTTP

def http_request(url, method="GET", body=None, headers=None, timeout=20, insecure=True):
    ctx = ssl.create_default_context()
    if insecure:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    data = None
    hdrs = {
        "User-Agent": "okhttp/4.12.0",
        "Accept": "application/json",
        "Content-Type": "application/json; charset=utf-8",
    }
    if headers:
        hdrs.update(headers)
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            raw = resp.read()
            return resp.status, dict(resp.headers), raw
    except urllib.error.HTTPError as err:
        return err.code, dict(err.headers or {}), err.read()
    except Exception as err:  # 连不上就换域名
        return 0, {}, str(err).encode()


def parse_json(raw):
    try:
        return json.loads(raw.decode("utf-8", "ignore"))
    except Exception:
        return None


# ---------------------------------------------------------------- 业务

def probe(base):
    for path in ("/api/v1/app/version", "/api/v1/communication-domains", "/api/v1/app/initialization"):
        status, _h, raw = http_request(base.rstrip("/") + path, "GET")
        body = parse_json(raw)
        print("%-45s -> %s %s" % (path, status, (json.dumps(body, ensure_ascii=False)[:160] if body else raw[:120])))
        if status and status < 500:
            return True
    return False


def login(base, user, password, mode):
    n, e = parse_rsa_public_key(PUB_PEM)
    plain = {"account": user, "password": password, "loginType": "password", "deviceType": 1, "platform": "android"}
    payload = plain
    if mode == "rsa":
        payload = {"data": rsa_pkcs1_encrypt(json.dumps(plain, ensure_ascii=False).encode(), n, e)}
    for path in ("/api/v1/auth/login", "/api/v1/auth/login/", "/api/v1/auth/login?type=password"):
        status, _h, raw = http_request(base.rstrip("/") + path, "POST", payload)
        body = parse_json(raw)
        print("[login] %s -> %s" % (path, status))
        if body:
            print(json.dumps(body, ensure_ascii=False)[:600])
            token = None
            if isinstance(body, dict):
                for key in ("token", "accessToken", "access_token"):
                    value = body.get(key)
                    if isinstance(value, str):
                        token = value
                        break
                if token is None and isinstance(body.get("data"), dict):
                    for key in ("token", "accessToken", "access_token"):
                        value = body["data"].get(key)
                        if isinstance(value, str):
                            token = value
                            break
            if token:
                print("[login] token = " + token[:40] + "...")
                return token
    return None


def fetch_nodes(base, token):
    headers = {}
    if token:
        headers["Authorization"] = "Bearer " + token
        headers["token"] = token
        headers["X-Token"] = token
    for path in ("/api/v1/nodes", "/api/v1/nodes?page=1&size=200", "/api/v1/routing-rules"):
        status, _h, raw = http_request(base.rstrip("/") + path, "GET", None, headers)
        body = parse_json(raw)
        print("[nodes] %s -> %s" % (path, status))
        if body:
            text = json.dumps(body, ensure_ascii=False)
            print(text[:800])
            return body
    return None


def to_singbox(node):
    """把服务端节点 dict 转成 sing-box outbound,字段名做常见别名兜底"""
    get = lambda *keys: next((node[k] for k in keys if isinstance(node, dict) and node.get(k)), None)
    kind = (get("type", "protocol", "nodeType") or "shadowsocks").lower()
    tag = get("name", "remark", "nodeName", "id") or "node"
    server = get("host", "server", "address", "domain")
    port = get("port", "serverPort")
    base = {"type": kind, "tag": str(tag), "server": server, "server_port": port}
    password = get("password", "passwd", "pwd", "auth")
    if kind in ("shadowsocks", "ss"):
        base.update({"type": "shadowsocks", "method": get("method", "cipher") or "aes-256-gcm", "password": password})
    elif kind in ("vmess",):
        base.update({"uuid": get("uuid", "id"), "security": get("security", "scy") or "auto",
                     "alter_id": int(get("alterId", "aid") or 0)})
    elif kind in ("trojan",):
        base.update({"password": password, "tls": {"enabled": True, "server_name": get("sni", "host") or server}})
    elif kind in ("hysteria2", "hy2"):
        base.update({"type": "hysteria2", "password": password,
                     "tls": {"enabled": True, "server_name": get("sni") or server}})
    elif kind in ("tuic",):
        base.update({"uuid": get("uuid", "id"), "password": password,
                     "tls": {"enabled": True, "server_name": get("sni") or server}})
    elif kind in ("vless",):
        base.update({"uuid": get("uuid", "id"),
                     "tls": {"enabled": True, "server_name": get("sni") or server,
                             "reality": {"enabled": True, "public_key": get("pbk", "publicKey"),
                                         "short_id": get("sid", "shortId")}}})
    tls = get("tls", "security")
    if tls in (True, "tls", "reality") and "tls" not in base:
        base["tls"] = {"enabled": True, "server_name": get("sni", "host") or server}
    return base


def export_singbox(nodes_obj, out_path):
    def walk(obj, acc):
        if isinstance(obj, dict):
            if obj.get("port") or obj.get("server_port"):
                acc.append(obj)
            for value in obj.values():
                walk(value, acc)
        elif isinstance(obj, list):
            for item in obj:
                walk(item, acc)
    found = []
    walk(nodes_obj, found)
    outbounds = [to_singbox(node) for node in found]
    config = {
        "log": {"level": "info"},
        "inbounds": [{"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/30"], "auto_route": True, "strict_route": True}],
        "outbounds": outbounds + [{"type": "direct", "tag": "direct"}]
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(config, fh, ensure_ascii=False, indent=2)
    print("[+] 写出 %s,共 %d 个节点" % (out_path, len(outbounds)))
    print("[+] 这份 JSON 可直接给 iPhone 上的 sing-box(SFA)导入")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default=DEFAULT_BASES[0])
    parser.add_argument("--user", default="")
    parser.add_argument("--password", default="")
    parser.add_argument("--token", default="")
    parser.add_argument("--mode", default="plain", choices=["plain", "rsa"])
    parser.add_argument("--probe", default="")
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    if args.probe:
        for base in (args.probe, ) + tuple(b for b in DEFAULT_BASES if b != args.probe):
            print("== 探活 " + base)
            if probe(base):
                break
        return

    token = args.token
    if not token:
        if not args.user or not args.password:
            parser.error("要么给 --token,要么给 --user/--password")
        token = login(args.base, args.user, args.password, args.mode)
        if not token:
            print("[!] 没拿到 token。改用抓包:安卓端连上节点后从日志页导出配置,或代理抓 /api/v1/auth/login 的返回")
    nodes = fetch_nodes(args.base, token)
    if nodes and args.out:
        export_singbox(nodes, args.out)


if __name__ == "__main__":
    main()
