//
//  SettingsViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/12.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxSwift
import UIKit

class SettingsViewController: UITableViewController {
    // MARK: LifeCycle
    
    @IBOutlet weak var accountIcon: UILabel!
    @IBOutlet weak var designIcon: UILabel!
    @IBOutlet weak var muteIcon: UILabel!
    @IBOutlet weak var reactionIcon: UILabel!
    @IBOutlet weak var fontIcon: UILabel!
    @IBOutlet weak var catIcon: UILabel!
    @IBOutlet weak var licenseIcon: UILabel!
    
    @IBOutlet weak var accountLabel: UILabel!
    @IBOutlet weak var designLabel: UILabel!
    @IBOutlet weak var reactionLabel: UILabel!
    @IBOutlet weak var aboutLabel: UILabel!
    @IBOutlet weak var licenseLabel: UILabel!
    
    var homeViewController: HomeViewController?
    private var disposeBag: DisposeBag = .init()
    private lazy var iconLabels = [accountIcon, designIcon, muteIcon, reactionIcon, fontIcon, catIcon, licenseIcon]
    private lazy var labels = [accountLabel, designLabel, reactionLabel, aboutLabel, licenseLabel]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.delegate = self
        setFont()
        bindTheme()
        setTheme()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = .clear
    }
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { $0.colorPattern.ui }.subscribe(onNext: { colorPattern in
            self.view.backgroundColor = colorPattern.base
            self.iconLabels.forEach { $0?.textColor = colorPattern.text }
            self.labels.forEach { $0?.textColor = colorPattern.text }
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            view.backgroundColor = colorPattern.base
            iconLabels.forEach { $0?.textColor = colorPattern.text }
            labels.forEach { $0?.textColor = colorPattern.text }
        }
    }
    
    /// ステータスバーの文字色
    override var preferredStatusBarStyle: UIStatusBarStyle {
        let currentColorMode = Theme.shared.currentModel?.colorMode ?? .light
        return currentColorMode == .light ? UIStatusBarStyle.default : UIStatusBarStyle.lightContent
    }
    
    // MARK: Privates
    
    private func setFont() {
        for iconLabel in iconLabels {
            iconLabel?.font = .awesomeSolid(fontSize: 23)
        }
    }
    
    // MARK: TableViewDelegate
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 60
    }
    
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        view.tintColor = .clear
        
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.text = "MissCat"
        header.textLabel?.textColor = Theme.shared.currentModel?.colorPattern.ui.text ?? .black
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let index = indexPath.row
        if index == 0 {
            guard let accountSettings = getViewController(name: "accounts-settings") as? AccountViewController else { return }
            
            accountSettings.homeViewController = homeViewController
            navigationController?.pushViewController(accountSettings, animated: true)
        } else if index == 1 {
            let designSettings = DesignSettingsViewController()
            
            designSettings.homeViewController = homeViewController
            navigationController?.pushViewController(designSettings, animated: true)
        } else if index == 3 {
            let licenseTable = LicenseTableViewController()
            navigationController?.pushViewController(licenseTable, animated: true)
        }
    }
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
}
