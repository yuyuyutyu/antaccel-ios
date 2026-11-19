import UIKit
import WebKit

/// 复刻 APK 内 assets/js/NativeObject.js 的原生桥接协议:
/// JS 侧 -> window.webkit.messageHandlers.nativeObject.postWithCallback(JSON)
/// 原生侧 -> nativeObjectJs.callback({callback: key, args: payload})
final class Bridge: NSObject, WKScriptMessageHandler, WKUIDelegate {

    weak var webView: WKWebView?
    weak var presenter: UIViewController?

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? String, let data = body.data(using: .utf8) else { return }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any] else { return }
        let command = dictionary["command"] as? String ?? ""
        let callback = dictionary["callback"] as? String
        let args = dictionary["args"] ?? [:]
        handle(command: command, args: args, callback: callback)
    }

    // MARK: - 命令分发

    private func handle(command: String, args: Any, callback: String?) {
        switch command {
        case "toast", "showToast":
            let text = flatten(args, fallback: "原生已收到调用")
            showAlert(text)
            reply(callback, ["result": "ok"])

        case "getAppInfo", "getVersion":
            reply(callback, [
                "name": AppConfig.displayName,
                "version": AppConfig.version,
                "build": AppConfig.build,
                "bundleId": AppConfig.bundleID,
                "platform": "ios"
            ])

        case "getDeviceInfo":
            let device = UIDevice.current
            reply(callback, [
                "model": device.model,
                "systemName": device.systemName,
                "systemVersion": device.systemVersion,
                "name": device.name,
                "platform": "ios"
            ])

        case "getNavData":
            reply(callback, ["nav": AppConfig.navJSONString()])

        case "copy", "copyText":
            let text = flatten(args, fallback: "")
            if !text.isEmpty {
                UIPasteboard.general.string = text
                showAlert("已复制到剪贴板")
            }
            reply(callback, ["result": "ok"])

        case "openUrl", "open", "openSafari":
            let text = flatten(args, fallback: "")
            if let url = URL(string: text) {
                if let presenter = presenter {
                    let browser = BrowserViewController(url: url)
                    presenter.navigationController?.pushViewController(browser, animated: true)
                } else {
                    AppConfig.openExternal(url)
                }
            }
            reply(callback, ["result": "ok"])

        case "close":
            DispatchQueue.main.async { [weak self] in
                self?.presenter?.dismiss(animated: true, completion: nil)
            }
            reply(callback, ["result": "ok"])

        case "setTitle":
            let text = flatten(args, fallback: AppConfig.displayName)
            DispatchQueue.main.async { [weak self] in
                self?.presenter?.title = text
            }
            reply(callback, ["result": "ok"])

        case "vibrate":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            reply(callback, ["result": "ok"])

        default:
            reply(callback, ["error": "unknown command: " + command])
        }
    }

    private func flatten(_ args: Any, fallback: String) -> String {
        if let text = args as? String, !text.isEmpty { return text }
        if let dictionary = args as? [String: Any] {
            for key in ["text", "message", "msg", "content", "title", "url"] {
                if let value = dictionary[key] as? String, !value.isEmpty { return value }
            }
            if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        if let array = args as? [Any], !array.isEmpty {
            return array.map { String(describing: $0) }.joined(separator: " ")
        }
        return fallback
    }

    private func reply(_ callback: String?, _ payload: [String: Any]) {
        guard let callback = callback, !callback.isEmpty else { return }
        let body: [String: Any] = ["callback": callback, "args": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = "if(window.nativeObjectJs&&window.nativeObjectJs.callback){window.nativeObjectJs.callback(" + json + ");}"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    // MARK: - 交互

    private func topViewController() -> UIViewController? {
        var top = presenter
        var depth = 0
        while let presented = top?.presentedViewController, depth < 8 {
            top = presented
            depth += 1
        }
        return top
    }

    private func showAlert(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let host = self.topViewController() else { return }
            let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default, handler: nil))
            host.present(alert, animated: true, completion: nil)
        }
    }

    // MARK: - WKUIDelegate (网页弹窗,不处理会让 JS 卡死)

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let host = self?.topViewController() else {
                completionHandler()
                return
            }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default, handler: { _ in completionHandler() }))
            host.present(alert, animated: true, completion: nil)
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let host = self?.topViewController() else {
                completionHandler(false)
                return
            }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: { _ in completionHandler(false) }))
            alert.addAction(UIAlertAction(title: "确定", style: .default, handler: { _ in completionHandler(true) }))
            host.present(alert, animated: true, completion: nil)
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let host = self?.topViewController() else {
                completionHandler(defaultText)
                return
            }
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { field in field.text = defaultText }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: { _ in completionHandler(nil) }))
            alert.addAction(UIAlertAction(title: "确定", style: .default, handler: { _ in
                completionHandler(alert.textFields?.first?.text)
            }))
            host.present(alert, animated: true, completion: nil)
        }
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
