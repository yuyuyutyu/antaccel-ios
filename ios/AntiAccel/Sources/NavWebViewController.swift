import UIKit
import WebKit

final class NavWebViewController: UIViewController {

    private var webView: WKWebView?
    private let bridge = Bridge()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private var progressObservation: NSKeyValueObservation?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "导航"
        view.backgroundColor = .systemBackground

        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        configuration.userContentController.add(bridge, name: "nativeObject")

        let navJSON = AppConfig.navJSONString()
        let source = "window.__NAV_JSON__ = " + navJSON + ";"
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(script)

        let web = WKWebView(frame: .zero, configuration: configuration)
        web.uiDelegate = bridge
        web.translatesAutoresizingMaskIntoConstraints = false
        bridge.webView = web
        bridge.presenter = self
        webView = web
        view.addSubview(web)

        progressView.progressTintColor = .systemBlue
        progressView.trackTintColor = .clear
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])

        progressObservation = web.observe(\.estimatedProgress, options: [.new]) { [weak self] webViewValue, _ in
            let value = Float(webViewValue.estimatedProgress)
            self?.progressView.setProgress(value, animated: true)
            self?.progressView.isHidden = value >= 1.0
        }

        if let fileURL = Bundle.main.url(forResource: "index", withExtension: "html") {
            web.loadFileURL(fileURL, allowingReadAccessTo: Bundle.main.bundleURL)
        } else {
            web.loadHTMLString("<h1 style=\"font-family:-apple-system;padding:24px\">导航页资源缺失</h1>", baseURL: nil)
        }
    }

    deinit {
        progressObservation?.invalidate()
        progressObservation = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "nativeObject")
        webView?.uiDelegate = nil
        webView?.navigationDelegate = nil
    }
}
