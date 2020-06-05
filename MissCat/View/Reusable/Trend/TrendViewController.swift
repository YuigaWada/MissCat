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
    private var disposeBag: DisposeBag = .init()
    
    
    private lazy var misskey: MisskeyKit? =  {
        guard let owner = owner else { return nil }
        let misskey = MisskeyKit(from: owner)
        return misskey
    }()
    private lazy var owner: SecureUser? = Cache.UserDefaults.shared.getCurrentUser()
    private var instance: String {
        guard let instance = owner?.instance,
            instance.count > 0 else { return "このインスタンス" }
        
        return instance.prefix(1).uppercased() + instance.suffix(instance.count - 1)
    }
    
    var tappedTable: PublishRelay<String> = .init()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabe.text = "\(instance)でのトレンド"
        setTheme()
        bindTheme()
        setupTables()
    }
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { $0.colorPattern.ui }.subscribe(onNext: { colorPattern in
            self.view.backgroundColor = colorPattern.base
            self.mainTableView.backgroundColor = colorPattern.base
            self.titleLabe.textColor = colorPattern.text
            self.mainTableView.reloadData()
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            view.backgroundColor = colorPattern.base
            mainTableView.backgroundColor = colorPattern.base
            titleLabe.textColor = colorPattern.text
        }
    }
    
    private func setupTables() {
        mainTableView.delegate = self
        mainTableView.dataSource = self
        
        
        misskey?.search.trendHashtags { trends, error in
            guard let trends = trends, error == nil else { return }
            self.tables = trends.compactMap { $0.tag }.map { "#\($0)" }
            DispatchQueue.main.async {
                self.reloadTableView(diff: self.tables)
                self.mainTableView.stopSpinner()
            }
        }
    }
    
    private func reloadTableView(diff: [String]) {
        mainTableView.beginUpdates()
        for i in 0 ..< diff.count {
            mainTableView.insertRows(at: [IndexPath(row: i, section: 0)],
                                     with: .automatic)
        }
        mainTableView.endUpdates()
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let index = indexPath.row
        tableView.deselectRow(at: indexPath, animated: true)
        tappedTable.accept(tables[index])
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        
        cell.textLabel?.text = tables[indexPath.row]
        cell.textLabel?.textColor = Theme.shared.currentModel?.colorPattern.ui.text ?? .black
        cell.backgroundColor = Theme.shared.currentModel?.colorPattern.ui.base ?? .white
        
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
        view.tintColor = Theme.shared.currentModel?.colorPattern.ui.base ?? .white
    }
}
