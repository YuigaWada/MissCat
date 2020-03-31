//
//  AccountViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/19.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import UIKit

class AccountViewController: UITableViewController {
    @IBOutlet weak var logoutButton: UIButton!
    
    private var disposeBag = DisposeBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        
        logoutButton.rx.tap.subscribe(onNext: { _ in
            self.showLogoutAlert()
        }).disposed(by: disposeBag)
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath as IndexPath, animated: true) // タップ解除
        showLogoutAlert()
    }
    
    private func showLogoutAlert() {
        let alert = UIAlertController(title: "ログアウト", message: "本当にログアウトしますか？", preferredStyle: UIAlertController.Style.alert)
        
        let defaultAction: UIAlertAction = UIAlertAction(title: "ログアウト", style: UIAlertAction.Style.destructive, handler: {
            (_: UIAlertAction!) -> Void in
            self.logout()
        })
        let cancelAction: UIAlertAction = UIAlertAction(title: "閉じる", style: UIAlertAction.Style.cancel, handler: nil)
        
        alert.addAction(cancelAction)
        alert.addAction(defaultAction)
        
        present(alert, animated: true, completion: nil)
    }
    
    private func logout() {
        let viewController = getViewController(name: "start")
        
        Cache.UserDefaults.shared.setCurrentLoginedApiKey("")
        Cache.UserDefaults.shared.setCurrentLoginedInstance("")
        Cache.UserDefaults.shared.setCurrentLoginedUserId("")
        
        navigationController?.pushViewController(viewController, animated: true)
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
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 70
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
}
