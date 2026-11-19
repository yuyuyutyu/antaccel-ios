// 安心加速器 · iOS 壳(Linux 交叉编译版)
// 纯 UIKit + WebKit,零第三方依赖,不申请任何特殊 entitlement
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface RootViewController : UIViewController <WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *web;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"安心加速器";

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
        NSURL *dir = [url URLByDeletingLastPathComponent];
        [web loadFileURL:url allowingReadAccessToURL:dir];
    } else {
        [web loadHTMLString:@"<h1 style=\"font-family:-apple-system;padding:30px\">资源缺失</h1>" baseURL:nil];
    }
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:[NSString class]]) { return; }
    NSData *data = [(NSString *)message.body dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) { return; }
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![dict isKindOfClass:[NSDictionary class]]) { return; }

    NSString *command = dict[@"command"];
    NSString *callback = dict[@"callback"];
    id args = dict[@"args"];

    if ([command isEqualToString:@"toast"]) {
        NSString *text = [args isKindOfClass:[NSString class]] ? args : @"原生已收到调用";
        if ([args isKindOfClass:[NSDictionary class]]) {
            id t = args[@"text"];
            if ([t isKindOfClass:[NSString class]]) { text = t; }
        }
        [self toast:text];
        [self reply:callback payload:@{@"result": @"ok"}];
    } else if ([command isEqualToString:@"getAppInfo"] || [command isEqualToString:@"getVersion"]) {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        [self reply:callback payload:@{
            @"name": info[@"CFBundleDisplayName"] ?: @"安心加速器",
            @"version": info[@"CFBundleShortVersionString"] ?: @"1.0.5",
            @"build": info[@"CFBundleVersion"] ?: @"4",
            @"bundleId": info[@"CFBundleIdentifier"] ?: @"",
            @"platform": @"ios"
        }];
    } else if ([command isEqualToString:@"openUrl"] && [args isKindOfClass:[NSDictionary class]]) {
        id u = args[@"url"];
        if ([u isKindOfClass:[NSString class]] && [u length] > 0) {
            NSURL *url = [NSURL URLWithString:u];
            if (url) { [self.web loadRequest:[NSURLRequest requestWithURL:url]]; }
        }
        [self reply:callback payload:@{@"result": @"ok"}];
    } else {
        [self reply:callback payload:@{@"error": @"unknown command"}];
    }
}

- (void)reply:(NSString *)callback payload:(NSDictionary *)payload {
    if (callback.length == 0) { return; }
    NSDictionary *body = @{@"callback": callback, @"args": payload ?: @{}};
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    if (!data) { return; }
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!json) { return; }
    NSString *js = [NSString stringWithFormat:@"if(window.nativeObjectJs&&nativeObjectJs.callback){nativeObjectJs.callback(%@);}", json];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.web evaluateJavaScript:js completionHandler:nil];
    });
}

- (void)toast:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:text preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - WKUIDelegate(网页弹窗,不实现会把 JS 卡住)

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { completionHandler(); }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) { completionHandler(NO); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { completionHandler(YES); }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    if (navigationAction.request.URL) { [webView loadRequest:navigationAction.request]; }
    return nil;
}

#pragma mark - WKNavigationDelegate

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [webView reload];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (webView.title.length > 0) { self.title = webView.title; }
}

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) RootViewController *root;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.root = [[RootViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:self.root];
    nav.navigationBar.translucent = YES;
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
