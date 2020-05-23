//
//  DropdownMenuViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/05/23.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import UIKit

struct DropdownMenu {
    let awesomeIcon: String?
    let title: String
    
    func getAttributed(iconColor: UIColor, textColorHex: String) -> NSAttributedString {
        let helvetica = UIFont(name: "Helvetica", size: 11.0)
        let titleAttributed = MFMEngine.generatePlaneString(string: title, font: helvetica, textHex: textColorHex)
        
        guard let awesomeIcon = awesomeIcon else { return titleAttributed }
        
        let awesomeString = NSAttributedString(string: awesomeIcon, attributes: [
            .foregroundColor: iconColor,
            .font: UIFont.awesomeSolid(fontSize: 13.0)!
        ])
        
        let space = NSAttributedString(string: "  ")
        return awesomeString + space + titleAttributed
    }
}

class DropdownMenuViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    var cellHeight: CGFloat = 50
    var selected: PublishRelay<Int> = .init()
    
    private var textColorHex: String = "ffffff"
    private var iconColor: UIColor = .systemBlue
    
    private var menus: [DropdownMenu] = []
    private lazy var attributedMenus: [NSAttributedString] = menus.map {
        $0.getAttributed(iconColor: iconColor, textColorHex: textColorHex)
    }
    
    // MARK: LifeCycle
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    convenience init(with menus: [DropdownMenu], size: CGSize) {
        self.init()
        
        self.menus = menus
        cellHeight = size.height / CGFloat(menus.count)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setTheme()
        setupTableView()
    }
    
    // MARK: Design
    
    private func setTheme() {
        guard let theme = Theme.shared.currentModel else { return }
        
        let mainColorHex = theme.mainColorHex
        let colorPattern = theme.colorPattern.ui
        let backgroundColor = theme.colorMode == .light ? colorPattern.base : colorPattern.sub3
        
        iconColor = UIColor(hex: mainColorHex)
        textColorHex = theme.colorPattern.hex.text
        view.backgroundColor = backgroundColor
        popoverPresentationController?.backgroundColor = backgroundColor
    }
    
    // MARK: Setup
    
    func setupTableView() {
        let tableView = UITableView(frame: view.frame)
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        tableView.bounces = false
        tableView.showsVerticalScrollIndicator = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        
        tableView.delegate = self
        tableView.dataSource = self
        
        view.addSubview(tableView)
    }
    
    // MARK: Delegate
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return cellHeight
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selected.accept(indexPath.row)
        dismiss(animated: true, completion: nil)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return menus.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.attributedText = attributedMenus[indexPath.row]
        cell.backgroundColor = .clear
        
        return cell
    }
}
