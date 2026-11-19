// 安心加速器 · iOS 壳(Linux 交叉编译版)
// 结构:UITabBarController
//   ① 节点页 —— 登录 / 拉节点 / 导出 sing-box 配置(账号与节点管理)
//   ② 导航页 —— 原 APK 的热门站点 + 内置浏览器
// 依赖:UIKit / WebKit / Foundation / Security,零第三方库
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <Security/Security.h>

#pragma mark - 全局

static NSArray *BootstrapBases(void) {
    return @[
        @"https://zz1.qjfifnbotx.top:14215",
        @"https://zz2.qjfifnbotx.top:14215",
        @"https://zz3.qjfifnbotx.top:14215",
        @"https://hwjdybyaop.top:33441",
        @"https://jgmqsypqvo.top:33441"
    ];
}

static NSString * const kPEM =
@"-----BEGIN PUBLIC KEY-----\n"
@"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAul63dy7ITAg12bwk4mqL\n"
@"o4jk4PuQVMdEDb5KRXTYdcf/LqCEMpv7KzUCGPODwES+jgSO703s2XtxsXKfPYw7\n"
@"MRzLG7Mvk2FKSJ+zNI80fdW6zRNI+Iguihr3JQcb8FKEbHQ3yfijC4ScmoRxjggv\n"
@"J7ReuHkl0+Fgpgh4hBrX7cAA1kCutTN+WbbnmxmVLUhCNFG7bmXUD/eOjLVpnndk\n"
@"y2F8oL6kHID21STHnBpyl6zOKf+uWty4Jwz9sE7XRZeytv+Jxjn/dzNlPDaPyen1\n"
@"ekiN/+dPhV6LJhpmrk+8SLKxmdDMKZKwMBmZEiu4agQsh083IibPDiE0mGIghjYv\n"
@"iwIDAQAB\n"
@"-----END PUBLIC KEY-----";

#pragma mark - 日志

static NSMutableArray *gLog = nil;
static void Log(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    if (!gLog) { gLog = [NSMutableArray array]; }
    [gLog addObject:line];
    NSLog(@"[AntiAccel] %@", line);
}

#pragma mark - RSA / PKCS1

static NSData *DataFromPEM(NSString *pem) {
    NSMutableString *b64 = [NSMutableString string];
    for (NSString *line in [pem componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if ([line hasPrefix:@"-----"]) { continue; }
        [b64 appendString:line];
    }
    return [[NSData alloc] initWithBase64EncodedString:b64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

/// 从 DER 里读一个 TLV,返回内容长度并把 cursor 推进到内容起点
static NSInteger ReadTLV(const uint8_t *p, NSInteger len, NSInteger *cursor, uint8_t *tagOut, NSInteger *bodyLen) {
    if (*cursor + 2 > len) { return -1; }
    uint8_t tag = p[*cursor];
    NSInteger pos = *cursor + 1;
    uint8_t l = p[pos]; pos++;
    NSInteger body = l;
    if (l & 0x80) {
        NSInteger n = l & 0x7F;
        if (n <= 0 || n > 4 || pos + n > len) { return -1; }
        body = 0;
        for (NSInteger i = 0; i < n; i++) { body = (body << 8) | p[pos + i]; }
        pos += n;
    }
    if (pos + body > len) { return -1; }
    if (tagOut) { *tagOut = tag; }
    if (bodyLen) { *bodyLen = body; }
    *cursor = pos;
    return body;
}

static NSData *PKCS1FromPEM(NSString *pem, NSData **spkiOut) {
    NSData *der = DataFromPEM(pem);
    if (!der) { return nil; }
    if (spkiOut) { *spkiOut = der; }
    const uint8_t *p = der.bytes;
    NSInteger len = (NSInteger)der.length, pos = 0;
    if (ReadTLV(p, len, &pos, NULL, NULL) < 0) { return nil; }          // SPKI SEQUENCE
    NSInteger algLen = ReadTLV(p, len, &pos, NULL, NULL);               // AlgorithmIdentifier
    if (algLen < 0) { return nil; }
    pos += algLen;                                                       // 关键:跳过算法内容
    uint8_t tag = 0; NSInteger bitLen = 0;
    if (ReadTLV(p, len, &pos, &tag, &bitLen) < 0 || tag != 0x03 || bitLen < 2) { return nil; }
    const uint8_t *body = p + pos;                                       // 首字节 unused bits
    return [NSData dataWithBytes:(body + 1) length:(NSUInteger)(bitLen - 1)];
}

static SecKeyRef PublicKeyFromPEM(NSString *pem) {
    NSData *spki = nil;
    NSData *pkcs1 = PKCS1FromPEM(pem, &spki);
    NSDictionary *attrs = @{
        (id)kSecAttrKeyType: (id)kSecAttrKeyTypeRSA,
        (id)kSecAttrKeyClass: (id)kSecAttrKeyClassPublic
    };
    CFErrorRef err = NULL;
    SecKeyRef key = NULL;
    if (pkcs1) {
        key = SecKeyCreateWithData((__bridge CFDataRef)pkcs1, (__bridge CFDictionaryRef)attrs, &err);
        if (!key) { Log(@"PKCS1 建键失败 err=%ld", err ? (long)CFErrorGetCode(err) : -1); }
        if (err) { CFRelease(err); err = NULL; }
    }
    if (!key && spki) {
        key = SecKeyCreateWithData((__bridge CFDataRef)spki, (__bridge CFDictionaryRef)attrs, &err);
        if (!key) { Log(@"SPKI 建键失败 err=%ld", err ? (long)CFErrorGetCode(err) : -1); }
        if (err) { CFRelease(err); err = NULL; }
    }
    return key;
}

static NSString *RSAEncryptBase64(NSString *plain) {
    SecKeyRef key = PublicKeyFromPEM(kPEM);
    if (!key) { Log(@"RSA 公钥解析失败"); return nil; }
    NSData *in = [plain dataUsingEncoding:NSUTF8StringEncoding];
    CFErrorRef err = NULL;
    NSData *out = (__bridge_transfer NSData *)SecKeyCreateEncryptedData(key, kSecKeyAlgorithmRSAEncryptionPKCS1, (__bridge CFDataRef)in, &err);
    CFRelease(key);
    if (err) { CFRelease(err); }
    if (!out) { Log(@"RSA 加密失败"); return nil; }
    return [out base64EncodedStringWithOptions:0];
}

#pragma mark - HTTP

typedef void (^ApiCallback)(NSInteger status, id json, NSString *raw);

static void ApiRequest(NSString *base, NSString *path, NSString *method, NSDictionary *body,
                       NSString *token, ApiCallback done) {
    NSString *urlStr = [base stringByAppendingString:path];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) { if (done) { done(-1, nil, @"bad url"); } return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method ?: @"GET";
    req.timeoutInterval = 20;
    [req setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"okhttp/4.12.0" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    // BFF 网关要的一批上下文头,缺了就回 9009 header参数错误
    NSString *ts = [NSString stringWithFormat:@"%lld", (long long)([[NSDate date] timeIntervalSince1970] * 1000)];
    NSString *dev = [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: @"unknown";
    NSDictionary *extra = @{
        @"x-platform": @"android",
        @"x-os": @"android",
        @"x-client-platform": @"android",
        @"x-app-version": @"1.0.5",
        @"x-version": @"1.0.5",
        @"x-app-version-code": @"4",
        @"x-channel": @"official",
        @"x-lang": @"zh-CN",
        @"x-timestamp": ts,
        @"x-nonce": [NSString stringWithFormat:@"%08x", (unsigned)arc4random()],
        @"x-device-id": dev,
        @"x-device-model": [[UIDevice currentDevice] model] ?: @"iPhone",
        @"x-request-id": [[NSUUID UUID] UUIDString],
        @"x-sign": @"0"
    };
    for (NSString *k in extra) { [req setValue:extra[k] forHTTPHeaderField:k]; }
    if (token.length) {
        [req setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
        [req setValue:token forHTTPHeaderField:@"token"];
    }
    if (body) {
        NSData *d = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
        req.HTTPBody = d;
    }

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
        NSString *raw = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        id json = nil;
        if (data.length) { json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]; }
        NSLog(@"[AntiAccel] %@ -> %ld %@", urlStr, (long)status, [raw substringToIndex:MIN((NSUInteger)200, raw.length)] ?: @"");
        if (done) { done(status, json, raw); }
    }];
    [task resume];
}

static NSString *ExtractToken(id json) {
    if (![json isKindOfClass:[NSDictionary class]]) { return nil; }
    NSDictionary *d = json;
    for (NSString *k in @[@"token", @"accessToken", @"access_token"]) {
        id v = d[k];
        if ([v isKindOfClass:[NSString class]] && [v length] > 0) { return v; }
    }
    id data = d[@"data"];
    if ([data isKindOfClass:[NSDictionary class]]) {
        for (NSString *k in @[@"token", @"accessToken", @"access_token"]) {
            id v = data[k];
            if ([v isKindOfClass:[NSString class]] && [v length] > 0) { return v; }
        }
    }
    return nil;
}

static void CollectNodes(id obj, NSMutableArray *acc) {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = obj;
        BOOL hasPort = (d[@"port"] != nil) || (d[@"server_port"] != nil);
        BOOL hasServer = (d[@"host"] || d[@"server"] || d[@"address"] || d[@"domain"]);
        if (hasPort && hasServer) { [acc addObject:d]; }
        for (id v in [d allValues]) { CollectNodes(v, acc); }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        for (id v in (NSArray *)obj) { CollectNodes(v, acc); }
    }
}


#pragma mark - 节点 -> sing-box 配置

static NSString *S(id v) { return [v isKindOfClass:[NSString class]] ? (NSString *)v : nil; }

static NSDictionary *NodeToOutbound(NSDictionary *n) {
    NSString *type = S(n[@"type"]) ?: S(n[@"protocol"]) ?: S(n[@"nodeType"]) ?: @"shadowsocks";
    type = [type lowercaseString];
    NSString *tag = S(n[@"name"]) ?: S(n[@"remark"]) ?: S(n[@"nodeName"]) ?: S(n[@"id"]) ?: @"node";
    NSString *server = S(n[@"host"]) ?: S(n[@"server"]) ?: S(n[@"address"]) ?: S(n[@"domain"]);
    id port = n[@"port"] ?: n[@"server_port"];
    NSString *pwd = S(n[@"password"]) ?: S(n[@"passwd"]) ?: S(n[@"pwd"]) ?: S(n[@"auth"]);
    NSString *sni = S(n[@"sni"]) ?: S(n[@"host"]) ?: server;

    NSMutableDictionary *o = [NSMutableDictionary dictionary];
    o[@"tag"] = tag;
    o[@"server"] = server ?: @"0.0.0.0";
    o[@"server_port"] = port ?: @443;

    if ([type containsString:@"shadowsocks"] || [type isEqualToString:@"ss"]) {
        o[@"type"] = @"shadowsocks";
        o[@"method"] = S(n[@"method"]) ?: S(n[@"cipher"]) ?: @"aes-256-gcm";
        if (pwd) { o[@"password"] = pwd; }
    } else if ([type containsString:@"vmess"]) {
        o[@"type"] = @"vmess";
        o[@"uuid"] = S(n[@"uuid"]) ?: S(n[@"id"]) ?: @"";
        o[@"security"] = S(n[@"security"]) ?: S(n[@"scy"]) ?: @"auto";
        o[@"alter_id"] = n[@"alterId"] ?: n[@"aid"] ?: @0;
        if (S(n[@"tls"]) || S(n[@"security"]) ) { o[@"tls"] = @{@"enabled": @YES, @"server_name": sni ?: @""}; }
    } else if ([type containsString:@"trojan"]) {
        o[@"type"] = @"trojan";
        if (pwd) { o[@"password"] = pwd; }
        o[@"tls"] = @{@"enabled": @YES, @"server_name": sni ?: @""};
    } else if ([type containsString:@"hysteria2"] || [type isEqualToString:@"hy2"] || [type containsString:@"hysteria"]) {
        o[@"type"] = @"hysteria2";
        if (pwd) { o[@"password"] = pwd; }
        o[@"tls"] = @{@"enabled": @YES, @"server_name": sni ?: @""};
    } else if ([type containsString:@"tuic"]) {
        o[@"type"] = @"tuic";
        o[@"uuid"] = S(n[@"uuid"]) ?: S(n[@"id"]) ?: @"";
        if (pwd) { o[@"password"] = pwd; }
        o[@"tls"] = @{@"enabled": @YES, @"server_name": sni ?: @""};
    } else if ([type containsString:@"vless"]) {
        o[@"type"] = @"vless";
        o[@"uuid"] = S(n[@"uuid"]) ?: S(n[@"id"]) ?: @"";
        o[@"tls"] = @{@"enabled": @YES, @"server_name": sni ?: @""};
    } else if ([type containsString:@"wireguard"]) {
        o[@"type"] = @"wireguard";
        o[@"private_key"] = S(n[@"privateKey"]) ?: S(n[@"password"]) ?: @"";
        o[@"peer_public_key"] = S(n[@"publicKey"]) ?: @"";
    } else {
        o[@"type"] = @"shadowsocks";
        o[@"method"] = @"aes-256-gcm";
        if (pwd) { o[@"password"] = pwd; }
    }
    return o;
}

static NSString *BuildSingBoxJSON(NSArray *nodes) {
    NSMutableArray *outbounds = [NSMutableArray array];
    for (NSDictionary *n in nodes) {
        [outbounds addObject:NodeToOutbound(n)];
    }
    NSDictionary *config = @{
        @"log": @{@"level": @"info", @"timestamp": @YES},
        @"dns": @{@"servers": @[ @{@"tag": @"google", @"address": @"tls://8.8.8.8"},
                                  @{@"tag": @"local", @"address": @"223.5.5.5", @"detour": @"direct"} ]},
        @"inbounds": @[ @{@"type": @"tun", @"tag": @"tun-in", @"address": @[@"172.19.0.1/30"],
                          @"auto_route": @YES, @"strict_route": @YES} ],
        @"outbounds": outbounds,
        @"route": @{@"auto_detect_interface": @YES}
    };
    NSData *d = [NSJSONSerialization dataWithJSONObject:config
                                                options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                  error:NULL];
    if (!d) { return nil; }
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

#pragma mark - 节点页

@interface NodesViewController : UITableViewController
@property (nonatomic, copy) NSString *token;
@property (nonatomic, strong) NSMutableArray *nodes;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, copy) NSString *currentBase;
@end

@implementation NodesViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _nodes = [NSMutableArray array];
        _statusText = @"未登录";
        _currentBase = BootstrapBases().firstObject;
        self.title = @"节点";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"日志"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(showLog)];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52;
}

- (void)showLog {
    NSString *text = gLog.count ? [gLog componentsJoinedByString:@"\n"] : @"(空)";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"运行日志" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        UIPasteboard.generalPasteboard.string = text;
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)setStatus:(NSString *)s {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusText = s;
        [self.tableView reloadData];
    });
}

#pragma mark 登录

- (void)showLogin {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"登录" message:@"用你安卓端那个账号" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"账号 / 邮箱 / 手机号";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"密码";
        tf.secureTextEntry = YES;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"登录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *user = a.textFields.firstObject.text ?: @"";
        NSString *pwd = a.textFields.lastObject.text ?: @"";
        if (user.length == 0 || pwd.length == 0) { return; }
        [self doLogin:user password:pwd];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)tryBases:(NSArray *)bases index:(NSUInteger)i user:(NSString *)user password:(NSString *)pwd {
    if (i >= bases.count) {
        [self setStatus:@"所有引导域名都没连上,点『日志』看细节"];
        return;
    }
    NSString *base = bases[i];
    self.currentBase = base;
    [self setStatus:[NSString stringWithFormat:@"登录中… %@", base]];

    NSDictionary *plain = @{@"account": user, @"password": pwd,
                            @"loginType": @"password", @"deviceType": @1, @"platform": @"android"};

    [self postLogin:base body:plain user:user password:pwd attempt:0 bases:bases index:i];
}

- (void)postLogin:(NSString *)base body:(NSDictionary *)body user:(NSString *)user password:(NSString *)pwd
          attempt:(NSUInteger)attempt bases:(NSArray *)bases index:(NSUInteger)i {
    Log(@"登录尝试 #%lu -> %@/api/v1/auth/login", (unsigned long)attempt, base);
    ApiCallback done = ^(NSInteger status, id json, NSString *raw) {
        NSString *token = ExtractToken(json);
        if (token.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.token = token;
                Log(@"拿到 token: %@…", [token substringToIndex:MIN((NSUInteger)12, token.length)]);
            });
            [self fetchNodes];
            return;
        }
        // 明文不行就换 RSA 包裹再试一次
        if (attempt == 0) {
            NSString *jsonStr = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:body options:0 error:NULL]
                                                      encoding:NSUTF8StringEncoding];
            NSString *enc = RSAEncryptBase64(jsonStr);
            if (enc.length) {
                [self postLogin:base body:@{@"data": enc} user:user password:pwd attempt:1 bases:bases index:i];
                return;
            }
        }
        NSString *snippet = raw.length > 160 ? [raw substringToIndex:160] : raw;
        Log(@"登录失败 status=%ld body=%@", (long)status, snippet ?: @"(空)");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self tryBases:bases index:i + 1 user:user password:pwd];
        });
    };
    ApiRequest(base, @"/api/v1/auth/login", @"POST", body, nil, done);
}

- (void)doLogin:(NSString *)user password:(NSString *)pwd {
    [self tryBases:BootstrapBases() index:0 user:user password:pwd];
}

#pragma mark 探活(未授权接口,能反推网关要什么头)

- (void)probeApis {
    NSArray *paths = @[@"/api/v1/app/version", @"/api/v1/app/initialization", @"/api/v1/communication-domains"];
    NSString *base = BootstrapBases().firstObject;
    [self setStatus:[NSString stringWithFormat:@"探活 %@", base]];
    __block NSInteger left = (NSInteger)paths.count;
    for (NSString *path in paths) {
        ApiRequest(base, path, @"GET", nil, nil, ^(NSInteger status, id json, NSString *raw) {
            NSString *snippet = raw.length > 300 ? [raw substringToIndex:300] : raw;
            Log(@"探活 %@ -> %ld %@", path, (long)status, snippet ? snippet : @"(空)");
            left--;
            if (left <= 0) { [self setStatus:@"探活结束,点『日志』看返回"]; }
        });
    }
}

#pragma mark 节点

- (void)fetchNodes {
    if (self.token.length == 0) { [self showLogin]; return; }
    NSString *base = self.currentBase ?: BootstrapBases().firstObject;
    [self setStatus:@"拉取节点…"];
    ApiCallback done = ^(NSInteger status, id json, NSString *raw) {
        NSMutableArray *found = [NSMutableArray array];
        if (json) { CollectNodes(json, found); }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.nodes removeAllObjects];
            [self.nodes addObjectsFromArray:found];
            Log(@"节点接口 %ld,解析到 %lu 个节点", (long)status, (unsigned long)found.count);
            self.statusText = found.count
                ? [NSString stringWithFormat:@"已登录 · %lu 个节点", (unsigned long)found.count]
                : [NSString stringWithFormat:@"接口 %ld 未解析出节点,点『日志』看原始返回", (long)status];
            [self.tableView reloadData];
        });
    };
    ApiRequest(base, @"/api/v1/nodes", @"GET", nil, self.token, done);
}

#pragma mark 导出

- (void)copyConfig {
    NSString *conf = BuildSingBoxJSON(self.nodes);
    if (!conf.length) { [self alert:@"还没有节点,先登录"]; return; }
    UIPasteboard.generalPasteboard.string = conf;
    [self alert:[NSString stringWithFormat:@"已复制 sing-box 配置(%lu 字节),去 sing-box 里导入", (unsigned long)conf.length]];
}

- (void)shareConfig {
    NSString *conf = BuildSingBoxJSON(self.nodes);
    if (!conf.length) { [self alert:@"还没有节点,先登录"]; return; }
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"antiaccel-singbox.json"];
    [conf writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]]
                                                                    applicationActivities:nil];
    vc.popoverPresentationController.sourceView = self.view;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)openClient {
    NSURL *u = [NSURL URLWithString:@"sing-box://"];
    if (!u) { [self alert:@"scheme 构造失败"]; return; }
    [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:^(BOOL ok) {
        if (!ok) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self alert:@"没检测到 sing-box。先装一个(TestFlight 版 SFA 或 Shadowrocket),再回来点『分享配置文件』导入。"];
            });
        }
    }];
}

- (void)alert:(NSString *)t {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:t preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"账号", @"节点", @"导出到 sing-box"][section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) { return 3; }
    if (section == 1) { return MAX((NSInteger)self.nodes.count, 1); }
    return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) { cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid]; }
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = self.token.length ? @"已登录" : @"登录账号";
            cell.detailTextLabel.text = self.statusText;
            cell.textLabel.textColor = [UIColor systemBlueColor];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"探活网关(诊断)";
            cell.detailTextLabel.text = @"打 app/version 等公开接口,反推缺哪个头";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            return cell;
        } else {
            cell.textLabel.text = @"拉取 / 刷新节点";
            cell.detailTextLabel.text = self.currentBase ?: @"";
            cell.textLabel.textColor = [UIColor systemBlueColor];
        }
        return cell;
    }
    if (indexPath.section == 1) {
        if (self.nodes.count == 0) {
            cell.textLabel.text = @"(还没有节点)";
            cell.detailTextLabel.text = @"登录后自动拉取";
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            return cell;
        }
        NSDictionary *n = self.nodes[indexPath.row];
        cell.textLabel.text = S(n[@"name"]) ?: S(n[@"remark"]) ?: S(n[@"nodeName"]) ?: [NSString stringWithFormat:@"节点 %ld", (long)indexPath.row + 1];
        NSString *proto = S(n[@"type"]) ?: S(n[@"protocol"]) ?: @"?";
        NSString *host = S(n[@"host"]) ?: S(n[@"server"]) ?: S(n[@"address"]) ?: @"?";
        id port = n[@"port"] ?: n[@"server_port"] ?: @"?";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@:%@", proto, host, port];
        return cell;
    }
    NSArray *titles = @[@"复制 sing-box 配置", @"分享配置文件(存到『文件』)", @"打开 sing-box"];
    NSArray *subs = @[@"粘到客户端里直接导入", @"sing-box -> 配置 -> 从文件导入", @"没装就先装,再回来分享"];
    cell.textLabel.text = titles[indexPath.row];
    cell.detailTextLabel.text = subs[indexPath.row];
    cell.textLabel.textColor = [UIColor systemBlueColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) { [self showLogin]; }
        else if (indexPath.row == 2) { [self probeApis]; }
        else { [self fetchNodes]; }
        return;
    }
    if (indexPath.section == 2) {
        if (indexPath.row == 0) { [self copyConfig]; }
        else if (indexPath.row == 1) { [self shareConfig]; }
        else { [self openClient]; }
    }
}

@end


#pragma mark - 导航页

@interface NavViewController : UIViewController <WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *web;
@end

@implementation NavViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"导航";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    [config.userContentController addScriptMessageHandler:self name:@"nativeObject"];
    config.allowsInlineMediaPlayback = YES;

    WKWebView *web = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    web.UIDelegate = self;
    web.navigationDelegate = self;
    web.allowsBackForwardNavigationGestures = YES;
    [self.view addSubview:web];
    self.web = web;

    NSString *path = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    if (path) {
        NSURL *url = [NSURL fileURLWithPath:path];
        [web loadFileURL:url allowingReadAccessToURL:[url URLByDeletingLastPathComponent]];
    } else {
        [web loadHTMLString:@"<h1 style=\"font-family:-apple-system;padding:30px\">导航资源缺失</h1>" baseURL:nil];
    }
}

- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:[NSString class]]) { return; }
    NSData *data = [(NSString *)message.body dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) { return; }
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![dict isKindOfClass:[NSDictionary class]]) { return; }

    NSString *command = dict[@"command"];
    NSString *callback = dict[@"callback"];
    id args = dict[@"args"];

    if ([command isEqualToString:@"toast"]) {
        NSString *text = @"原生已收到调用";
        if ([args isKindOfClass:[NSDictionary class]] && [args[@"text"] isKindOfClass:[NSString class]]) {
            text = args[@"text"];
        } else if ([args isKindOfClass:[NSString class]]) {
            text = args;
        }
        UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:text preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        [self reply:callback payload:@{@"result": @"ok"}];
    } else if ([command isEqualToString:@"getAppInfo"]) {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        [self reply:callback payload:@{@"name": info[@"CFBundleDisplayName"] ?: @"安心加速器",
                                       @"version": info[@"CFBundleShortVersionString"] ?: @"1.0.5",
                                       @"bundleId": info[@"CFBundleIdentifier"] ?: @"",
                                       @"platform": @"ios"}];
    } else {
        [self reply:callback payload:@{@"error": @"unknown command"}];
    }
}

- (void)reply:(NSString *)callback payload:(NSDictionary *)payload {
    if (callback.length == 0) { return; }
    NSData *d = [NSJSONSerialization dataWithJSONObject:@{@"callback": callback, @"args": payload ?: @{}} options:0 error:NULL];
    if (!d) { return; }
    NSString *json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (!json) { return; }
    NSString *js = [NSString stringWithFormat:@"if(window.nativeObjectJs&&nativeObjectJs.callback){nativeObjectJs.callback(%@);}", json];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.web evaluateJavaScript:js completionHandler:nil];
    });
}

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { completionHandler(); }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    if (action.request.URL) { [webView loadRequest:action.request]; }
    return nil;
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView { [webView reload]; }

@end

#pragma mark - AppDelegate

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    UINavigationController *nodesNav = [[UINavigationController alloc] initWithRootViewController:[[NodesViewController alloc] init]];
    nodesNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"节点" image:[UIImage systemImageNamed:@"bolt.horizontal.circle"] tag:0];

    UINavigationController *navNav = [[UINavigationController alloc] initWithRootViewController:[[NavViewController alloc] init]];
    navNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"导航" image:[UIImage systemImageNamed:@"safari"] tag:1];

    UITabBarController *tab = [[UITabBarController alloc] init];
    tab.viewControllers = @[nodesNav, navNav];
    self.window.rootViewController = tab;
    [self.window makeKeyAndVisible];

    Log(@"启动完成,版本 %@", [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: @"?");
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
