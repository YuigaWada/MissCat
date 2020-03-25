//
//  SettingsViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/12.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

public class SettingsViewController: UITableViewController {
    // MARK: LifeCycle
    
    @IBOutlet weak var accountIcon: UILabel!
    @IBOutlet weak var muteIcon: UILabel!
    @IBOutlet weak var reactionIcon: UILabel!
    @IBOutlet weak var fontIcon: UILabel!
    @IBOutlet weak var catIcon: UILabel!
    @IBOutlet weak var licenseIcon: UILabel!
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.delegate = self
        setFont()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    // MARK: Privates
    
    private func setFont() {
        for iconLabel in [accountIcon, muteIcon, reactionIcon, fontIcon, catIcon, licenseIcon] {
            iconLabel?.font = .awesomeSolid(fontSize: 23)
        }
    }
    
    // MARK: TableViewDelegate
    
    public override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 60
    }
    
    public override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        view.tintColor = .clear
        
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.text = "MissCat"
    }
    
    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let index = indexPath.row
        
        if index == 1 || index == 2 {
            let viewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "under-development")
            
            navigationController?.pushViewController(viewController, animated: true)
        }
    }
}
