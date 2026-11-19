
// 安心加速器 iOS 壳 v10 —— 完整协议版
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <netinet/in.h>
#import <netdb.h>
#import <unistd.h>

static NSString * const kPEM = @"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAul63dy7ITAg12bwk4mqLo4jk4PuQVMdEDb5KRXTYdcf/LqCEMpv7KzUCGPODwES+jgSO703s2XtxsXKfPYw7MRzLG7Mvk2FKSJ+zNI80fdW6zRNI+Iguihr3JQcb8FKEbHQ3yfijC4ScmoRxjggvJ7ReuHkl0+Fgpgh4hBrX7cAA1kCutTN+WbbnmxmVLUhCNFG7bmXUD/eOjLVpnndky2F8oL6kHID21STHnBpyl6zOKf+uWty4Jwz9sE7XRZeytv+Jxjn/dzNlPDaPyen1ekiN/+dPhV6LJhpmrk+8SLKxmdDMKZKwMBmZEiu4agQsh083IibPDiE0mGIghjYviwIDAQAB";

static NSString * const kDefaultBase = @"https://zz1.qjfifnbotx.top:14215";
static NSString * const kKeyId       = @"client-rsa-prod2-v1";
static NSString * const kChannelCode = @"2d21bee8";
static NSString * const kDistChannel = @"free";
static NSString * const kEmptyHash   = @"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

static NSMutableArray *gLog = nil;
static void Log(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[ArkNet] %@", s);
    if (!gLog) gLog = [NSMutableArray array];
    [gLog addObject:s];
}
static NSString *LogText(void) { return gLog ? [gLog componentsJoinedByString:@"\n"] : @""; }

#pragma mark - 基础编码

static NSString *B64(NSData *d) { return d ? [d base64EncodedStringWithOptions:0] : @""; }
static NSData *UB64(NSString *s) {
    if (!s) return nil;
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    return [[NSData alloc] initWithBase64EncodedString:s options:NSDataBase64DecodingIgnoreUnknownCharacters];
}
static NSData *SHA256(NSData *d) {
    unsigned char out[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(d.bytes, (CC_LONG)d.length, out);
    return [NSData dataWithBytes:out length:CC_SHA256_DIGEST_LENGTH];
}
static NSString *SHA256Hex(NSData *d) {
    NSData *h = SHA256(d);
    const unsigned char *p = h.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:64];
    for (int i = 0; i < 32; i++) [s appendFormat:@"%02x", p[i]];
    return s;
}
static NSData *HMACSHA256(NSData *key, NSData *data) {
    unsigned char out[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, out);
    return [NSData dataWithBytes:out length:CC_SHA256_DIGEST_LENGTH];
}
static NSData *AESECB(NSData *data, NSData *key, BOOL encrypt) {
    size_t outLen = data.length + kCCBlockSizeAES128;
    void *buf = malloc(outLen);
    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(encrypt ? kCCEncrypt : kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding | kCCOptionECBMode,
                                 key.bytes, key.length, NULL, data.bytes, data.length, buf, outLen, &moved);
    if (st != kCCSuccess) { free(buf); return nil; }
    return [NSData dataWithBytesNoCopy:buf length:moved freeWhenDone:YES];
}

#pragma mark - RSA

static NSData *DataFromPEM(NSString *pem) {
    NSMutableString *b = [NSMutableString string];
    for (NSString *line in [pem componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"-----"]) continue;
        [b appendString:[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    }
    return UB64(b);
}

static NSInteger ReadTLV(const uint8_t *p, NSInteger len, NSInteger *cursor, uint8_t *tagOut, NSInteger *bodyLen) {
    NSInteger c = *cursor;
    if (c + 2 > len) return -1;
    uint8_t tag = p[c++];
    uint8_t l = p[c++];
    NSInteger blen = l;
    if (l & 0x80) {
        NSInteger n = l & 0x7f;
        if (c + n > len) return -1;
        blen = 0;
        for (NSInteger i = 0; i < n; i++) blen = (blen << 8) | p[c++];
    }
    if (tagOut) *tagOut = tag;
    if (bodyLen) *bodyLen = blen;
    *cursor = c;
    return 0;
}

static SecKeyRef PublicKeyFromPEM(NSString *pem) {
    NSData *der = DataFromPEM(pem);
    if (!der) return NULL;
    NSInteger cursor = 0, outer = 0;
    uint8_t tag = 0;
    if (ReadTLV(der.bytes, der.length, &cursor, &tag, &outer) != 0 || tag != 0x30) return NULL;
    NSInteger inner = cursor, algLen = 0;
    if (ReadTLV(der.bytes, der.length, &inner, &tag, &algLen) != 0 || tag != 0x30) return NULL;
    inner += algLen;
    uint8_t bitTag = 0; NSInteger bitLen = 0;
    if (ReadTLV(der.bytes, der.length, &inner, &bitTag, &bitLen) != 0 || bitTag != 0x03) return NULL;
    if (inner + bitLen > der.length || bitLen < 2) return NULL;
    const uint8_t *bits = der.bytes + inner;
    if (bits[0] != 0) return NULL;
    NSData *pkcs1 = [NSData dataWithBytes:bits + 1 length:bitLen - 1];
    NSDictionary *attrs = @{ (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
                             (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic };
    CFErrorRef err = NULL;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)pkcs1, (__bridge CFDictionaryRef)attrs, &err);
    if (err) CFRelease(err);
    return key;
}

static SecKeyRef gPub = NULL;
static SecKeyRef GetPub(void) {
    if (!gPub) gPub = PublicKeyFromPEM(kPEM);
    if (!gPub) Log(@"公钥解析失败");
    return gPub;
}

static NSString *RSAEncryptB64(NSData *plain) {
    SecKeyRef key = GetPub();
    if (!key) return nil;
    CFErrorRef err = NULL;
    CFDataRef out = SecKeyCreateEncryptedData(key, kSecKeyAlgorithmRSAEncryptionPKCS1, (__bridge CFDataRef)plain, &err);
    if (err) { Log(@"RSA 失败: %@", err); CFRelease(err); return nil; }
    NSData *d = (__bridge_transfer NSData *)out;
    return B64(d);
}

#pragma mark - 会话

static NSString *gToken = nil;
static NSString *gDeviceId = nil;
static NSString *gBaseUrl = nil;
static NSString *gConfig = nil;
static NSDictionary *gMe = nil;

static NSString *TokenPath(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"arktoken.txt"];
}
static void SaveToken(NSString *t) { gToken = t; [t writeToFile:TokenPath() atomically:YES encoding:NSUTF8StringEncoding error:NULL]; }
static void LoadToken(void) { gToken = [NSString stringWithContentsOfFile:TokenPath() encoding:NSUTF8StringEncoding error:NULL]; }

static NSDictionary *JWTClaims(NSString *jwt) {
    NSArray *parts = [jwt componentsSeparatedByString:@"."];
    if (parts.count < 2) return nil;
    NSData *d = UB64(parts[1]);
    if (!d) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static NSString *DeviceIdForToken(void) {
    if (gDeviceId) return gDeviceId;
    if (gToken) {
        NSDictionary *c = JWTClaims(gToken);
        NSString *d = c[@"device_id"];
        if ([d isKindOfClass:[NSString class]] && d.length) { gDeviceId = d; return d; }
    }
    NSString *uuid = [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: @"unknown";
    gDeviceId = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
    return gDeviceId;
}

#pragma mark - API

static void ArkCallAsync(NSString *method, NSString *path, NSString *query, NSDictionary *bodyObj, void (^done)(NSInteger status, id json)) {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSData *K = nil;
        {
            uint8_t kb[32];
            if (SecRandomCopyBytes(kSecRandomDefault, 32, kb) != errSecSuccess) { done(-1, nil); return; }
            K = [NSData dataWithBytes:kb length:32];
        }
        NSString *ts = [NSString stringWithFormat:@"%lld", (long long)[[NSDate date] timeIntervalSince1970]];
        NSString *prefix = [NSString stringWithFormat:@"version=v1; type=1; key=%@; time=%@", B64(K), ts];
        NSString *secret = RSAEncryptB64([prefix dataUsingEncoding:NSUTF8StringEncoding]);
        if (!secret) { done(-1, nil); return; }

        NSString *bodyStr = @"";
        NSData *bodyData = nil;
        if (bodyObj) {
            NSData *plain = [NSJSONSerialization dataWithJSONObject:bodyObj options:0 error:NULL];
            NSData *enc = AESECB(plain, K, YES);
            bodyStr = B64(enc);
            bodyData = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];
        }
        NSString *bodyHash = bodyStr.length ? SHA256Hex(bodyData) : kEmptyHash;
        NSString *payload = [NSString stringWithFormat:@"%@\n%@\n%@\n%@\n%@", ts, method, path, query ?: @"", bodyHash];
        NSString *sig = B64(HMACSHA256(K, [payload dataUsingEncoding:NSUTF8StringEncoding]));

        NSString *base = gBaseUrl ?: kDefaultBase;
        NSString *urlStr = [base stringByAppendingString:path];
        if (query.length) urlStr = [urlStr stringByAppendingFormat:@"?%@", query];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
        req.HTTPMethod = method;
        req.timeoutInterval = 25;
        [req setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
        [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        [req setValue:@"okhttp/4.12.0" forHTTPHeaderField:@"user-agent"];
        [req setValue:kChannelCode forHTTPHeaderField:@"channel-code"];
        [req setValue:kDistChannel forHTTPHeaderField:@"distribution-channel"];
        [req setValue:@"android" forHTTPHeaderField:@"platform"];
        [req setValue:DeviceIdForToken() forHTTPHeaderField:@"device-id"];
        [req setValue:@"2206123SC" forHTTPHeaderField:@"model"];
        [req setValue:@"zh-CN" forHTTPHeaderField:@"locale"];
        [req setValue:@"Asia/Shanghai" forHTTPHeaderField:@"timezone"];
        [req setValue:[NSString stringWithFormat:@"key=%@; secret=%@; signature=%@", kKeyId, secret, sig] forHTTPHeaderField:@"X-Content-Security"];
        if (gToken.length) [req setValue:[@"Bearer " stringByAppendingString:gToken] forHTTPHeaderField:@"Authorization"];
        if (bodyData) req.HTTPBody = bodyData;

        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        NSURLSession *sess = [NSURLSession sessionWithConfiguration:cfg];
        __block BOOL finished = NO;
        __block NSInteger code = -1;
        __block id result = nil;
        NSURLSessionDataTask *task = [sess dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            code = [(NSHTTPURLResponse *)resp statusCode];
            if (err) Log(@"网络错误: %@", err.localizedDescription);
            result = data;
            finished = YES;
        }];
        [task resume];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
        while (!finished && [deadline timeIntervalSinceNow] > 0) { [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
        [sess finishTasksAndInvalidate];

        if (!result) { done(code, nil); return; }
        NSString *text = [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding];
        text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSData *raw = UB64(text);
        id json = nil;
        if (raw) {
            NSData *dec = AESECB(raw, K, NO);
            if (dec) json = [NSJSONSerialization JSONObjectWithData:dec options:0 error:NULL];
        }
        if (!json) json = [NSJSONSerialization JSONObjectWithData:result options:0 error:NULL];
        done(code, json);
    });
}

#pragma mark - 配置生成

static NSString *BuildSingBox(NSDictionary *node, NSDictionary *conn) {
    NSString *tag = node[@"name"] ?: @"美国节点";
    NSString *serverName = conn[@"tlsServerName"] ?: conn[@"ingress"] ?: node[@"ingress"];
    NSDictionary *out = @{
        @"type": @"anytls",
        @"tag": tag,
        @"server": conn[@"ingress"] ?: node[@"ingress"],
        @"server_port": @([conn[@"listenPort"] intValue] ?: 10020),
        @"password": conn[@"password"] ?: @"",
        @"idle_session_check_interval": @"30s",
        @"idle_session_timeout": @"60s",
        @"min_idle_session": @5,
        @"tls": @{ @"enabled": @YES, @"server_name": serverName, @"alpn": @[@"h2"] }
    };
    NSDictionary *cfg = @{
        @"log": @{ @"level": @"warn", @"timestamp": @YES },
        @"inbounds": @[ @{ @"type": @"tun", @"tag": @"tun-in", @"address": @[@"172.19.0.1/30"], @"mtu": @9000,
                           @"auto_route": @YES, @"strict_route": @NO, @"stack": @"gvisor" } ],
        @"outbounds": @[ out, @{ @"type": @"direct", @"tag": @"direct" }, @{ @"type": @"block", @"tag": @"block" } ],
        @"route": @{ @"rules": @[ @{ @"action": @"sniff" }, @{ @"protocol": @"dns", @"action": @"hijack-dns" },
                                  @{ @"ip_is_private": @YES, @"outbound": @"direct" } ],
                     @"final": tag, @"auto_detect_interface": @YES },
        @"experimental": @{ @"cache_file": @{ @"enabled": @YES } }
    };
    NSData *d = [NSJSONSerialization dataWithJSONObject:cfg options:NSJSONWritingPrettyPrinted error:NULL];
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

#pragma mark - 节点页

@interface NodesViewController : UITableViewController <UIAlertViewDelegate>
@property (nonatomic, strong) NSMutableArray *nodes;
@property (nonatomic, strong) NSDictionary *connected;
@property (nonatomic, strong) NSMutableDictionary *latency;
@property (nonatomic, copy) NSString *status;
@end

@implementation NodesViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    _nodes = [NSMutableArray array];
    _latency = [NSMutableDictionary dictionary];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"安心加速器";
    LoadToken();
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"日志" style:UIBarButtonItemStylePlain target:self action:@selector(showLog)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];
    if (gToken.length) [self loadMe];
}

- (void)alert:(NSString *)t {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:t preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showLog {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"日志" message:LogText() preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)loadMe {
    ArkCallAsync(@"GET", @"/api/v1/users/me", [NSString stringWithFormat:@"channelCode=%@", kChannelCode], nil, ^(NSInteger status, id json) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([json isKindOfClass:[NSDictionary class]] && [json[@"code"] intValue] == 0) {
                gMe = json[@"data"][@"user"];
                Log(@"用户: %@", gMe[@"username"]);
                [self refresh];
            } else {
                Log(@"token 无效: %@", json);
                [self.tableView reloadData];
            }
        });
    });
}

- (void)refresh {
    [self.tableView reloadData];
}

- (void)pasteToken {
    NSString *s = [UIPasteboard generalPasteboard].string;
    if (!s.length) { [self alert:@"剪贴板是空的"]; return; }
    NSArray *comps = [s componentsSeparatedByString:@"."];
    if (comps.count < 3) { [self alert:@"这不是一个 JWT。\n从安卓的 mmkv.default 里抓 token 再复制过来。"]; return; }
    SaveToken([[s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""]);
    gDeviceId = nil;
    [self loadMe];
}

- (void)doLogin {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"登录" message:@"输入安心加速器账号密码" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"账号"; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"密码"; tf.secureTextEntry = YES; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"登录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *u = a.textFields[0].text;
        NSString *p = a.textFields[1].text;
        if (!u.length || !p.length) return;
        NSDictionary *body = @{ @"account": u, @"password": p };
        ArkCallAsync(@"POST", @"/api/v1/auth/login", @"", body, ^(NSInteger status, id json) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *tok = nil;
                if ([json isKindOfClass:[NSDictionary class]]) {
                    id data = json[@"data"];
                    if ([data isKindOfClass:[NSDictionary class]]) tok = data[@"token"] ?: data[@"accessToken"];
                    if ([tok isKindOfClass:[NSString class]] && [tok length]) {
                        SaveToken(tok); gDeviceId = nil;
                        Log(@"登录成功");
                        [self loadMe];
                        return;
                    }
                }
                Log(@"登录返回: %@", json);
                [self alert:[NSString stringWithFormat:@"登录未成功(%ld)。\n可用「粘贴 Token」方式。", (long)status]];
            });
        });
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)fetchNodes {
    if (!gToken.length) { [self alert:@"先登录或粘贴 token"]; return; }
    [self alert:@"正在拉取节点…"];
    ArkCallAsync(@"GET", @"/api/v1/nodes", [NSString stringWithFormat:@"nodeType=free&channelCode=%@", kChannelCode], nil, ^(NSInteger status, id json) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableArray *list = [NSMutableArray array];
            if ([json isKindOfClass:[NSDictionary class]] && json[@"data"]) {
                NSArray *groups = json[@"data"][@"groups"];
                for (NSDictionary *g in groups) {
                    NSArray *ns = g[@"nodes"];
                    if ([ns isKindOfClass:[NSArray class]]) [list addObjectsFromArray:ns];
                }
            }
            self.nodes = list;
            Log(@"节点数: %lu", (unsigned long)list.count);
            [self.tableView reloadData];
            [self measureAll];
        });
    });
}

- (void)measureAll {
    for (NSDictionary *n in self.nodes) {
        NSString *ingress = n[@"ingress"]; int port = [n[@"testPort"] intValue];
        if (!ingress.length || !port) continue;
        id key = n[@"nodeId"];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSTimeInterval t0 = [NSDate date].timeIntervalSince1970;
            int fd = socket(AF_INET, SOCK_STREAM, 0);
            struct timeval tv; tv.tv_sec = 3; tv.tv_usec = 0;
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
            struct sockaddr_in addr; memset(&addr, 0, sizeof(addr));
            addr.sin_family = AF_INET; addr.sin_port = htons(port);
            struct hostent *he = gethostbyname([ingress UTF8String]);
            BOOL ok = NO;
            if (he) {
                memcpy(&addr.sin_addr, he->h_addr_list[0], he->h_length);
                ok = (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0);
            }
            close(fd);
            NSTimeInterval ms = ok ? ([NSDate date].timeIntervalSince1970 - t0) * 1000 : 9999;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.latency[key] = @(ms);
                [self.tableView reloadData];
            });
        });
    }
}

- (void)connectNode:(NSDictionary *)n {
    [self alert:[NSString stringWithFormat:@"正在连接 %@ ...", n[@"name"]]];
    NSDictionary *body = @{ @"nodeId": n[@"nodeId"] };
    __weak NodesViewController *weakSelf = self;
    ArkCallAsync(@"POST", @"/api/v1/nodes/connect", @"", body, ^(NSInteger status, id json) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleConnect:json node:n];
        });
    });
}

- (void)handleConnect:(id)json node:(NSDictionary *)n {
    if ([json isKindOfClass:[NSDictionary class]] && [json[@"code"] intValue] == 0) {
        self.connected = json[@"data"];
        gConfig = BuildSingBox(n, self.connected);
        Log(@"session password: %@", self.connected[@"password"]);
        [self.tableView reloadData];
        [self alert:[NSString stringWithFormat:@"已连接 %@,去「配置」分享", n[@"name"]]];
    } else {
        Log(@"connect failed: %@", json);
        [self alert:@"连接失败,看日志"];
    }
}

- (void)shareConfig {
    if (!gConfig.length) { [self alert:@"先选一个节点连接"]; return; }
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"AntiAccel-ios.json"];
    [gConfig writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    vc.popoverPresentationController.sourceView = self.view;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)copyConfig {
    if (!gConfig.length) { [self alert:@"先选一个节点连接"]; return; }
    [UIPasteboard generalPasteboard].string = gConfig;
    [self alert:@"配置已复制，粘到 sing-box 里导入"];
}

- (void)openSingBox {
    NSURL *u = [NSURL URLWithString:@"sing-box://"];
    [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:^(BOOL ok) {
        if (!ok) dispatch_async(dispatch_get_main_queue(), ^{ [self alert:@"没装 sing-box"]; });
    }];
}

#pragma mark 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"账号";
    if (section == 1) return [NSString stringWithFormat:@"节点 (%lu)", (unsigned long)self.nodes.count];
    return @"配置";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    if (section == 1) return MAX(self.nodes.count, 1);
    return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (indexPath.section == 0) {
        NSArray *t = @[@"登录", @"粘贴 Token", @"清除 Token"];
        NSArray *s = @[gMe[@"username"] ?: @"账号密码登录", gToken.length ? @"已保存 token" : @"从剪贴板导入 JWT", @"退出登录"];
        cell.textLabel.text = t[indexPath.row];
        cell.detailTextLabel.text = s[indexPath.row];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1) {
        if (!self.nodes.count) {
            cell.textLabel.text = gToken.length ? @"点右上角「刷新」拉取节点" : @"先登录/粘贴 token";
        } else {
            NSDictionary *n = self.nodes[indexPath.row];
            id key = n[@"nodeId"];
            NSNumber *ms = self.latency[key];
            cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", n[@"name"], ms ? (ms.intValue >= 9999 ? @"超时" : [NSString stringWithFormat:@"%dms", ms.intValue]) : @"…"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  出口 %@", n[@"ingress"], n[@"publicIp"]];
            if (self.connected && [self.connected[@"ingress"] isEqual:n[@"ingress"]]) cell.accessoryType = UITableViewCellAccessoryCheckmark;
        }
    } else {
        NSArray *t = @[@"生成并复制配置", @"分享配置文件", @"打开 sing-box"];
        cell.textLabel.text = t[indexPath.row];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) [self doLogin];
        else if (indexPath.row == 1) [self pasteToken];
        else { SaveToken(@""); gMe = nil; gToken = nil; self.nodes = [NSMutableArray array]; [self.tableView reloadData]; }
    } else if (indexPath.section == 1) {
        if (self.nodes.count) [self connectNode:self.nodes[indexPath.row]];
        else [self fetchNodes];
    } else {
        if (indexPath.row == 0) { if (!gConfig.length) [self connectNode:self.nodes.firstObject]; else [self copyConfig]; }
        else if (indexPath.row == 1) [self shareConfig];
        else [self openSingBox];
    }
}

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    NodesViewController *vc = [[NodesViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
