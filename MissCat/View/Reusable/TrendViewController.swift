//
//  TrendViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/13.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit
import RxCocoa
import RxSwift
import UIKit

class TrendViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    @IBOutlet weak var titleLabe: UILabel!
    @IBOutlet weak var mainTableView: MissCatTableView!
    
    private var tables: [String] = []
    private var instance: String {
        guard let instance = Cache.UserDefaults.shared.getCurrentLoginedInstance(),
            instance.count > 0 else { return "このインスタンス" }
        
        return instance.prefix(1).uppercased() + instance.suffix(instance.count - 1)
    }
    
    var tappedTable: PublishRelay<String> = .init()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabe.text = "\(instance)でのトレンド"
        setupTables()
    }
    
    private func setupTables() {
        mainTableView.delegate = self
        mainTableView.dataSource = self
        
        MisskeyKit.search.trendHashtags { trends, error in
            guard let trends = trends, error == nil else { return }
            self.tables = trends.compactMap { $0.tag }.map { "#\($0)" }
            DispatchQueue.main.async {
                self.mainTableView.reloadData()
            }
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let index = indexPath.row
        tableView.deselectRow(at: indexPath, animated: true)
        tappedTable.accept(tables[index])
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = tables[indexPath.row]
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tables.count
    }
    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        view.tintColor = .white
    }
}
