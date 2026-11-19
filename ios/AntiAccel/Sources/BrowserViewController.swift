import UIKit
import WebKit

final class BrowserViewController: UIViewController, WKNavigationDelegate {

    private let initialURL: URL?
    private var webView: WKWebView?
    private let progressView = UIProgressView(progressViewStyle: .default)
    private var progressObservation: NSKeyValueObservation?
    private let bridge = Bridge()

    private var backItem: UIBarButtonItem?
    private var forwardItem: UIBarButtonItem?

    init(url: URL?) {
        self.initialURL = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.initialURL = nil
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        configuration.userContentController.add(bridge, name: "nativeObject")

        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        web.uiDelegate = bridge
        web.allowsBackForwardNavigationGestures = true
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
            web.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
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

        buildToolbar()

        if let url = initialURL {
            web.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
        } else {
            web.loadHTMLString("<h1 style=\"font-family:-apple-system;padding:24px\">空白页</h1>", baseURL: nil)
        }
        updateButtons()
    }

    deinit {
        progressObservation?.invalidate()
        progressObservation = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "nativeObject")
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
    }

    private func buildToolbar() {
        let back = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(goBack))
        let forward = UIBarButtonItem(image: UIImage(systemName: "chevron.right"), style: .plain, target: self, action: #selector(goForward))
        let reload = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(reloadPage))
        let home = UIBarButtonItem(image: UIImage(systemName: "house"), style: .plain, target: self, action: #selector(goHome))
        let share = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(sharePage))
        let spacer = { () -> UIBarButtonItem in UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil) }
        setToolbarItems([back, spacer(), forward, spacer(), home, spacer(), reload, spacer(), share], animated: false)
        backItem = back
        forwardItem = forward
        navigationController?.isToolbarHidden = false
    }

    private func updateButtons() {
        backItem?.isEnabled = webView?.canGoBack ?? false
        forwardItem?.isEnabled = webView?.canGoForward ?? false
    }

    @objc private func goBack() {
        guard let web = webView, web.canGoBack else { return }
        web.goBack()
    }

    @objc private func goForward() {
        guard let web = webView, web.canGoForward else { return }
        web.goForward()
    }

    @objc private func reloadPage() {
        webView?.reload()
    }

    @objc private func goHome() {
        guard let url = initialURL else { return }
        webView?.load(URLRequest(url: url))
    }

    @objc private func sharePage() {
        let target = webView?.url ?? initialURL
        guard let url = target else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activity, animated: true, completion: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        progressView.isHidden = false
        updateButtons()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let webTitle = webView.title, !webTitle.isEmpty {
            title = webTitle
        }
        updateButtons()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateButtons()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateButtons()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}
