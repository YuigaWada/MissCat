//
//  AccountViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/19.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift
import UIKit

class AccountViewController: UITableViewController {
    @IBOutlet weak var logoutButton: UIButton!
    
    var homeViewController: HomeViewController?
    private var disposeBag = DisposeBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setTheme()
        bindTheme()
        
        tableView.delegate = self
        
        logoutButton.rx.tap.subscribe(onNext: { _ in
            self.showLogoutAlert()
        }).disposed(by: disposeBag)
    }
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { $0.colorPattern.ui }.subscribe(onNext: { colorPattern in
            self.view.backgroundColor = colorPattern.base
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            view.backgroundColor = colorPattern.base
        }
    }
    
    /// ステータスバーの文字色
    override var preferredStatusBarStyle: UIStatusBarStyle {
        let currentColorMode = Theme.shared.currentModel?.colorMode ?? .light
        return currentColorMode == .light ? UIStatusBarStyle.default : UIStatusBarStyle.lightContent
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true) // タップ解除
        showLogoutAlert()
    }
    
    private func showLogoutAlert() {
        let alert = UIAlertController(title: "ログアウト", message: "本当にログアウトしますか？", preferredStyle: UIAlertController.Style.alert)
        
        let defaultAction = UIAlertAction(title: "ログアウト", style: UIAlertAction.Style.destructive, handler: {
            (_: UIAlertAction!) -> Void in
            self.logout()
        })
        let cancelAction = UIAlertAction(title: "閉じる", style: UIAlertAction.Style.cancel, handler: nil)
        
        alert.addAction(cancelAction)
        alert.addAction(defaultAction)
        
        present(alert, animated: true, completion: nil)
    }
    
    private func logout() {
        guard let startViewController = getViewController(name: "start") as? StartViewController,
              let currentUserId = Cache.UserDefaults.shared.getCurrentUserId() else { return }
        
        Cache.UserDefaults.shared.removeUser(userId: currentUserId)
        Cache.shared.resetMyCache()
        
//        startViewController.setup(afterLogout: true)
        presentOnFullScreen(startViewController, animated: true, completion: nil)
    }
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
    
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        view.tintColor = .clear
        
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.text = "アカウント管理"
        header.textLabel?.textColor = Theme.shared.currentModel?.colorPattern.ui.text ?? .black
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = .clear
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 70
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
}
