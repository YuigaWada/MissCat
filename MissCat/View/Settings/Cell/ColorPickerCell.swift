//
//  ColorPickerCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/22.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import ChromaColorPicker
import Eureka
import RxCocoa
import RxSwift
import UIKit

public class ColorPickerCell: Cell<String>, CellType {
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var colorIndicator: UIView!
    
    private var currentColor: UIColor = .systemBlue
    private var disposeBag: DisposeBag = .init()
    
    var value: String { return currentColor.hex }
    
    override public func setup() {
        super.setup()
        setupTapGesture()
        setTheme()
        
        colorIndicator.layer.borderWidth = 1
        colorIndicator.layer.borderColor = UIColor.lightGray.cgColor
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        colorIndicator.layoutIfNeeded()
        colorIndicator.layer.cornerRadius = colorIndicator.frame.width / 2
    }
    
    // MARK: Publics
    
    public func setColor(_ color: UIColor) {
        currentColor = color
        colorIndicator.backgroundColor = color
        window?.tintColor = color
    }
    
    // MARK: Design
    
    private func setTheme() {
        guard let theme = Theme.shared.currentModel else { return }
        let colorPattern = theme.colorPattern.ui
        
        nameLabel.textColor = colorPattern.text
    }
    
    // MARK: Setup
    
    private func setupTapGesture() {
        setTapGesture(disposeBag, closure: {
            self.showMenu()
        })
    }
    
    private func showColorPicker() {
        let picker = prepareColorPicker()
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseInOut, animations: {
            picker?.alpha = 1
        })
    }
    
    private func prepareColorPicker() -> UIView? {
        guard let parent = parentViewController?.view else { return nil }
        let picker = ColorPicker(frame: parent.frame, initialColor: currentColor)
        
        picker.center = parent.center
        picker.alpha = 0
        parent.addSubview(picker)
        
        picker.selectedColor.subscribe(onNext: { color in
            self.setColor(color)
        }).disposed(by: disposeBag)
        
        return picker
    }
    
    private func showMenu() {
        guard let parent = parentViewController else { return }
        let panelMenu = PanelMenuViewController()
        let menuItems: [PanelMenuViewController.MenuItem] = [.init(title: "デフォルトに戻す", awesomeIcon: "", order: 0),
                                                             .init(title: "カスタムカラーを設定", awesomeIcon: "", order: 1)]
        
        panelMenu.setupMenu(items: menuItems)
        panelMenu.tapTrigger.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { order in // どのメニューがタップされたのか
            guard order >= 0 else { return }
            panelMenu.dismiss(animated: true, completion: nil)
            
            switch order {
            case 0: // Default
                self.setColor(.systemBlue)
            case 1: // Custom
                self.showColorPicker()
            default:
                break
            }
        }).disposed(by: disposeBag)
        
        parent.present(panelMenu, animated: true, completion: nil)
    }
}

public final class ColorPickerRow: Row<ColorPickerCell>, RowType {
    public var currentColorHex: String {
        return cell.value
    }
    
    public required init(tag: String?) {
        super.init(tag: tag)
        cellProvider = CellProvider<ColorPickerCell>(nibName: "ColorPickerCell")
    }
}

extension UIColor {
    var hex: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "%02X%02X%02X",
            Int(r * 0xFF),
            Int(g * 0xFF),
            Int(b * 0xFF)
        )
    }
}
