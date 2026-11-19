import UIKit

final class ProfileViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private struct Row {
        let title: String
        let detail: String
        let action: (() -> Void)?
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var sections: [(String, [Row])] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "我的"
        view.backgroundColor = .systemGroupedBackground

        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        buildSections()
    }

    private func buildSections() {
        let appInfo = Row(title: AppConfig.displayName,
                          detail: "版本 " + AppConfig.version + " (" + AppConfig.build + ") · " + AppConfig.bundleID,
                          action: nil)

        let signed = Row(title: "签名状态",
                         detail: "已通过 p12 重签,可直装(详见交付文档)",
                         action: nil)

        let domainRow = Row(title: "复制引导域名",
                            detail: AppConfig.bootstrapDomains.joined(separator: "\n"),
                            action: { [weak self] in
                                UIPasteboard.general.string = AppConfig.bootstrapDomains.joined(separator: "\n")
                                self?.feedback("引导域名已复制")
                            })

        let apiRow = Row(title: "复制接口清单",
                         detail: "登录 / 节点 / 路由规则",
                         action: { [weak self] in
                             UIPasteboard.general.string = AppConfig.apiHint
                             self?.feedback("接口清单已复制")
                         })

        let pemRow = Row(title: "复制 BFF RSA 公钥",
                         detail: "client-bff-rsa-prod2.public.pem",
                         action: { [weak self] in
                             guard let url = Bundle.main.url(forResource: "client-bff-rsa-prod2.public", withExtension: "pem"),
                                   let text = try? String(contentsOf: url, encoding: .utf8) else {
                                 self?.feedback("公钥资源缺失")
                                 return
                             }
                             UIPasteboard.general.string = text
                             self?.feedback("RSA 公钥已复制")
                         })

        let guideRow = Row(title: "如何在 iPhone 上真正上网",
                           detail: "用同账号节点 + sing-box / SFA 客户端",
                           action: { [weak self] in self?.showGuide() })

        let aboutRow = Row(title: "关于",
                           detail: "本壳 App 用于 iOS 端界面复刻,不含隧道内核",
                           action: { [weak self] in self?.showAbout() })

        sections = [
            ("应用", [appInfo, signed]),
            ("服务端情报", [domainRow, apiRow, pemRow]),
            ("使用指引", [guideRow, aboutRow])
        ]
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section < sections.count else { return 0 }
        return sections[section].1.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section < sections.count else { return nil }
        return sections[section].0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "profile-cell"
        var cell = tableView.dequeueReusableCell(withIdentifier: identifier)
        if cell == nil {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        }
        guard let cell = cell,
              indexPath.section < sections.count,
              indexPath.row < sections[indexPath.section].1.count else {
            return UITableViewCell()
        }
        let row = sections[indexPath.section].1[indexPath.row]
        cell.textLabel?.text = row.title
        cell.textLabel?.textColor = row.action == nil ? .label : .systemBlue
        cell.detailTextLabel?.text = row.detail
        cell.detailTextLabel?.numberOfLines = 3
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = row.action == nil ? .none : .disclosureIndicator
        cell.selectionStyle = row.action == nil ? .none : .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section < sections.count,
              indexPath.row < sections[indexPath.section].1.count else { return }
        sections[indexPath.section].1[indexPath.row].action?()
    }

    // MARK: - 交互

    private func feedback(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func showGuide() {
        let text = """
        1. 安卓端登录同一账号并连接任意节点;
        2. 打开 我的 → 日志 → 代理配置查看,导出 sing-box 配置;
        3. iPhone 安装 sing-box(SFA)/Shadowrocket,导入该配置;
        4. 隧道由系统扩展承载,壳 App 只负责界面与导航。
        """
        let alert = UIAlertController(title: "节点获取路径", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "复制", style: .default, handler: { _ in
            UIPasteboard.general.string = text
        }))
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func showAbout() {
        let text = "包名 " + AppConfig.bundleID + "\n版本 " + AppConfig.version
            + "\n\n界面数据来自原 APK 的 assets/nav_default_home.json,桥接协议复刻 assets/js/NativeObject.js。"
        let alert = UIAlertController(title: "关于", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
