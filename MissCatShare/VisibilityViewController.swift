//
//  VisibilityViewController.swift
//  MissCatShare
//
//  Created by Yuiga Wada on 2020/08/08.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import UIKit

protocol VisibilityProtocol {
    func switchVisibility(_ visibility: Visibility)
}

class VisibilityViewController: UITableViewController {
    private var visibilities: [Visibility] = [.public, .home, .followers]
    var delegate: VisibilityProtocol?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        clearsSelectionOnViewWillAppear = false
        view.backgroundColor = .clear
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return visibilities.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let visibility = visibilities[indexPath.row]
        let cell = UITableViewCell()
        
        cell.backgroundColor = .clear
        cell.textLabel?.text = visibility.rawValue
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let visibility = visibilities[indexPath.row]
        delegate?.switchVisibility(visibility)
        navigationController?.popViewController(animated: true)
    }
}
