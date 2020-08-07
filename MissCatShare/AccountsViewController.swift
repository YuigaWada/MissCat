//
//  AccountsViewController.swift
//  MissCatShare
//
//  Created by Yuiga Wada on 2020/08/08.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import UIKit

protocol AccountsProtocol {
    func switchAccount(userId: String)
}

class AccountsViewController: UITableViewController {
    private var accounts: [SecureUser] = []
    var delegate: AccountsProtocol?
    
    convenience init(with accounts: [SecureUser]) {
        self.init()
        self.accounts = accounts
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        clearsSelectionOnViewWillAppear = false
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return accounts.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let user = accounts[indexPath.row]
        let cell = UITableViewCell()
        
        cell.textLabel?.text = "\(user.username)@\(user.instance)"
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let user = accounts[indexPath.row]
        delegate?.switchAccount(userId: user.userId)
        navigationController?.popViewController(animated: true)
    }
}
