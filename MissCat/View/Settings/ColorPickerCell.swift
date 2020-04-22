//
//  ColorPickerCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/22.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Eureka
import UIKit

public class ColorPickerCell: Cell<Bool>, CellType {
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var colorIndicator: UIView!
    
    private var currentColor: UIColor = .systemBlue
    
    public override func setup() {
        super.setup()
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
    }
}

public final class ColorPickerRow: Row<ColorPickerCell>, RowType {
    public var currentColor: UIColor = .systemBlue {
        didSet {
            cell.setColor(currentColor)
        }
    }
    
    public required init(tag: String?) {
        super.init(tag: tag)
        cellProvider = CellProvider<ColorPickerCell>(nibName: "ColorPickerCell")
    }
}
