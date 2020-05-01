//
//  ColorPicker.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/24.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import ChromaColorPicker
import RxCocoa
import RxSwift

class ColorPicker: UIView, ChromaColorPickerDelegate {
    var selectedColor: PublishRelay<UIColor> = .init()
    private var currentColor: UIColor?
    
    private lazy var colorPicker = ChromaColorPicker(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
    private lazy var brightnessSlider = ChromaBrightnessSlider(frame: CGRect(x: 0, y: 0, width: 280, height: 32))
    
    init(frame: CGRect, initialColor: UIColor) {
        super.init(frame: frame)
        setup(with: initialColor)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if !colorPicker.frame.contains(point), !brightnessSlider.frame.contains(point) {
            dismiss()
        }
        
        return super.point(inside: point, with: event)
    }
    
    private func setup(with initialColor: UIColor = .systemBlue) {
        setupBlur()
        setupColorPicker(with: initialColor)
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    private func setupBlur() {
        let blurView = getBlurView()
        blurView.frame = frame
        addSubview(blurView)
    }
    
    private func getBlurView() -> UIVisualEffectView {
        let colorMode = Theme.shared.currentModel?.colorMode ?? .light
        let style: UIBlurEffect.Style = colorMode == .light ? .light : .dark
        
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    private func setupColorPicker(with initialColor: UIColor) {
        colorPicker.delegate = self
        addSubview(colorPicker)
        addSubview(brightnessSlider)
        
        colorPicker.connect(brightnessSlider)
        _ = colorPicker.addHandle(at: initialColor)
        
        colorPicker.layoutIfNeeded()
        colorPicker.center = .init(x: center.x, y: center.y * 0.8)
        brightnessSlider.center = .init(x: center.x, y: center.y * 1.2)
    }
    
    private func dismiss() {
        if let currentColor = currentColor {
            selectedColor.accept(currentColor)
        }
        
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseInOut, animations: {
            self.alpha = 0
        }, completion: { fin in
            guard fin else { return }
            self.removeFromSuperview()
        })
    }
    
    // MARK: ChromaColorPickerDelegate
    
    func colorPickerHandleDidChange(_ colorPicker: ChromaColorPicker, handle: ChromaColorHandle, to color: UIColor) {
        currentColor = color
    }
}
