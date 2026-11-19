import Foundation

struct NavSite: Codable {
    let id: String?
    let name: String?
    let url: String?
    let iconUrl: String?
    let categoryId: String?
    let description: String?
    let recommended: Bool?
}

struct NavCategory: Codable {
    let id: String?
    let name: String?
}

struct NavData: Codable {
    let banners: [NavSite]?
    let categories: [NavCategory]?
    let hotSites: [NavSite]?
}

enum AppConfig {

    static let displayName = "安心加速器"
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.5"
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.arknet.shell"

    /// 从 APK 的 classes.dex 字符串表中提取出来的引导域名(仅作展示,真实节点需登录后由服务端下发)
    static let bootstrapDomains: [String] = [
        "https://hwjdybyaop.top:33441",
        "https://jgmqsypqvo.top:33441",
        "https://zz1.qjfifnbotx.top:14215",
        "https://zz2.qjfifnbotx.top:14215",
        "https://zz3.qjfifnbotx.top:14215"
    ]

    static let apiHint: String = """
    账号体系: POST /api/v1/auth/login
    节点下发: GET  /api/v1/nodes
    路由规则: GET  /api/v1/routing-rules
    请求体使用 assets/security/client-bff-rsa-prod2.public.pem 做 RSA/ECB/PKCS1Padding 加密
    """

    static func navData() -> NavData {
        let empty = NavData(banners: nil, categories: nil, hotSites: nil)
        guard let url = Bundle.main.url(forResource: "nav_default_home", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return empty
        }
        do {
            return try JSONDecoder().decode(NavData.self, from: data)
        } catch {
            NSLog("nav_default_home 解析失败: %@", String(describing: error))
            return empty
        }
    }

    static func navJSONString() -> String {
        guard let url = Bundle.main.url(forResource: "nav_default_home", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"hotSites\":[]}"
        }
        return text
    }

    static func openExternal(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
