import UIKit

final class HomeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchBar = UISearchBar()
    private let emptyLabel = UILabel()
    private var allSites: [NavSite] = []
    private var filteredSites: [NavSite] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = AppConfig.displayName
        view.backgroundColor = .systemGroupedBackground

        searchBar.placeholder = "搜索站点"
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.sizeToFit()
        tableView.tableHeaderView = searchBar

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        emptyLabel.text = "没有匹配的站点"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "刷新", style: .plain, target: self, action: #selector(reloadSites))

        loadSites()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = tableView.tableHeaderView, abs(header.frame.width - tableView.bounds.width) > 0.5 {
            var frame = header.frame
            frame.size.width = tableView.bounds.width
            header.frame = frame
            tableView.tableHeaderView = header
        }
    }

    @objc private func reloadSites() {
        loadSites()
        tableView.reloadData()
    }

    private func loadSites() {
        let data = AppConfig.navData()
        let sites = data.hotSites ?? []
        allSites = sites.sorted { left, right in
            let l = left.recommended ?? false
            let r = right.recommended ?? false
            if l != r { return l }
            return (left.id ?? "") < (right.id ?? "")
        }
        applyFilter(searchBar.text ?? "")
    }

    private func applyFilter(_ keyword: String) {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            filteredSites = allSites
        } else {
            filteredSites = allSites.filter { site in
                let name = site.name ?? ""
                let desc = site.description ?? ""
                let url = site.url ?? ""
                return name.localizedCaseInsensitiveContains(key)
                    || desc.localizedCaseInsensitiveContains(key)
                    || url.localizedCaseInsensitiveContains(key)
            }
        }
        emptyLabel.isHidden = !filteredSites.isEmpty
        tableView.reloadData()
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredSites.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "site-cell"
        var cell = tableView.dequeueReusableCell(withIdentifier: identifier)
        if cell == nil {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
            cell?.accessoryType = .disclosureIndicator
        }
        guard let cell = cell, indexPath.row < filteredSites.count else { return UITableViewCell() }
        let site = filteredSites[indexPath.row]
        cell.textLabel?.text = site.name ?? "未命名"
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        cell.detailTextLabel?.text = site.description ?? (site.url ?? "")
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.textColor = .secondaryLabel
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < filteredSites.count else { return }
        let site = filteredSites[indexPath.row]
        guard let raw = site.url, let url = URL(string: raw) else {
            presentMessage("该站点没有可用地址")
            return
        }
        let browser = BrowserViewController(url: url)
        browser.title = site.name
        navigationController?.pushViewController(browser, animated: true)
    }

    // MARK: - UISearchBarDelegate

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applyFilter(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    private func presentMessage(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
