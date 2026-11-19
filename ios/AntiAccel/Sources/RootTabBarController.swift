import UIKit

final class RootTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let home = UINavigationController(rootViewController: HomeViewController())
        home.tabBarItem = UITabBarItem(title: "首页", image: UIImage(systemName: "house"), tag: 0)

        let nav = UINavigationController(rootViewController: NavWebViewController())
        nav.tabBarItem = UITabBarItem(title: "导航", image: UIImage(systemName: "safari"), tag: 1)

        let mine = UINavigationController(rootViewController: ProfileViewController())
        mine.tabBarItem = UITabBarItem(title: "我的", image: UIImage(systemName: "person.crop.circle"), tag: 2)

        viewControllers = [home, nav, mine]
        overrideUserInterfaceStyle = .light
    }
}
