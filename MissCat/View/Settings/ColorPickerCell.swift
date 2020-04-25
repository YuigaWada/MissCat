//
//  ColorPickerCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/22.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import ChromaColorPicker
import Eureka
import RxSwift
import UIKit

public class ColorPickerCell: Cell<String>, CellType {
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var colorIndicator: UIView!
    
    private var currentColor: UIColor = .systemBlue
    private var disposeBag: DisposeBag = .init()
    
    var value: String { return currentColor.hex }
    
    public override func setup() {
        super.setup()
        setupTapGesture()
        
        colorIndicator.layer.borderWidth = 1
        colorIndicator.layer.borderColor = UIColor.lightGray.cgColor
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        colorIndicator.layoutIfNeeded()
        colorIndicator.layer.cornerRadius = colorIndicator.frame.width / 2
    }
    
    public func setColor(_ color: UIColor) {
        currentColor = color
        colorIndicator.backgroundColor = color
        window?.tintColor = color
    }
    
    private func setupTapGesture() {
        setTapGesture(disposeBag, closure: {
            let picker = self.prepareColorPicker()
            UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseInOut, animations: {
                picker?.alpha = 1
            })
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
