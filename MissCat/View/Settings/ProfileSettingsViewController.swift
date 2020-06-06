//
//  ProfileSettingsViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/05/14.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Eureka
import RxCocoa
import RxSwift
import UIKit

class ProfileSettingsViewController: FormViewController {
    var homeViewController: HomeViewController?
    var overrideInfoTrigger: PublishRelay<ChangedProfile> = .init()
    
    private var disposeBag: DisposeBag = .init()
    
    private lazy var bannerCover: UIView = .init()
    private lazy var bannerImage: MissCatImageView = .init()
    private lazy var iconImage: MissCatImageView = .init()
    
    private let saveButtonItem = UIBarButtonItem(title: "保存", style: .plain, target: nil, action: nil)
    private var headerHeight: CGFloat = 150
    
    private let selectedImage: PublishRelay<UIImage> = .init()
    private let resetImage: PublishRelay<Void> = .init()
    private var viewModel: ProfileSettingsViewModel?
    private var owner: SecureUser?
    
    // MARK: Row
    
    private lazy var catSwitch: SwitchRow = SwitchRow { row in
        row.tag = "cat-switch"
        row.title = "Catとして設定"
    }.cellUpdate { cell, _ in
        cell.backgroundColor = self.getCellBackgroundColor()
        cell.textLabel?.textColor = Theme.shared.currentModel?.colorPattern.ui.text ?? .black
    }
    
    private lazy var bioTextArea = TextAreaRow { row in
        row.tag = "bio-text-area"
        row.placeholder = "自分について..."
        row.textAreaHeight = .dynamic(initialTextViewHeight: 220)
    }.cellUpdate { cell, _ in
        cell.backgroundColor = self.getCellBackgroundColor()
        cell.textLabel?.textColor = Theme.shared.currentModel?.colorPattern.ui.text
        cell.placeholderLabel?.textColor = .lightGray
        cell.textView?.textColor = Theme.shared.currentModel?.colorPattern.ui.text
    }
    
    private lazy var nameTextArea = TextRow { row in
        row.tag = "name-text"
        row.title = "名前"
    }.cellUpdate { cell, _ in
        cell.backgroundColor = self.getCellBackgroundColor()
        cell.textLabel?.textColor = Theme.shared.currentModel?.colorPattern.ui.text
        cell.textField?.textColor = Theme.shared.currentModel?.colorPattern.ui.text
    }
    
    // MARK: LifeCycle
    
    func setup(owner: SecureUser, banner: UIImage? = nil, bannerUrl: String, icon: UIImage? = nil, iconUrl: String, name: String, description: String, isCat: Bool) {
        bannerImage.image = banner
        iconImage.image = icon
        
        let loadIcon = icon == nil
        let loadBanner = banner == nil
        
        nameTextArea.value = name
        bioTextArea.value = description
        catSwitch.value = isCat
        let viewModel = getViewModel(loadIcon: loadIcon,
                                     loadBanner: loadBanner,
                                     bannerUrl: bannerUrl,
                                     iconUrl: iconUrl,
                                     name: name,
                                     description: description,
                                     isCat: isCat)
        self.viewModel = viewModel
        self.owner = owner
    }
    
    private func getViewModel(loadIcon: Bool, loadBanner: Bool, bannerUrl: String?, iconUrl: String?, name: String, description: String, isCat: Bool) -> ProfileSettingsViewModel {
        let input: ProfileSettingsViewModel.Input = .init(owner: owner,
                                                          needLoadIcon: loadIcon,
                                                          needLoadBanner: loadBanner,
                                                          iconUrl: iconUrl,
                                                          bannerUrl: bannerUrl,
                                                          currentName: name,
                                                          currentDescription: description,
                                                          currentCatState: isCat,
                                                          rxName: nameTextArea.rx.value,
                                                          rxDesc: bioTextArea.rx.value,
                                                          rxCat: catSwitch.rx.value,
                                                          rightNavButtonTapped: saveButtonItem.rx.tap,
                                                          iconTapped: iconImage.rxTap,
                                                          bannerTapped: bannerImage.rxTap,
                                                          selectedImage: selectedImage.asObservable(),
                                                          resetImage: resetImage.asObservable(),
                                                          overrideInfoTrigger: overrideInfoTrigger)
        let viewModel = ProfileSettingsViewModel(with: input, and: disposeBag)
        binding(with: viewModel)
        
        return viewModel
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // ui
        setupComponent()
        setTable()
        setIconCover()
        setupNavBar()
        
        // theme
        setTheme()
        bindTheme()
        
        // viewModel
        viewModel?.transform()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    // MARK: Design
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { $0.colorPattern.ui }.subscribe(onNext: { colorPattern in
            self.view.backgroundColor = colorPattern.base
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        if let colorPattern = Theme.shared.currentModel?.colorPattern.ui {
            view.backgroundColor = colorPattern.base
            tableView.backgroundColor = colorPattern.base
        }
        
        if let mainColorHex = Theme.shared.currentModel?.mainColorHex {
            catSwitch.cell.switchControl.onTintColor = UIColor(hex: mainColorHex)
        }
    }
    
    /// ステータスバーの文字色
    override var preferredStatusBarStyle: UIStatusBarStyle {
        let currentColorMode = Theme.shared.currentModel?.colorMode ?? .light
        return currentColorMode == .light ? UIStatusBarStyle.default : UIStatusBarStyle.lightContent
    }
    
    private func getCellBackgroundColor() -> UIColor {
        guard let theme = Theme.shared.currentModel else { return .white }
        return theme.colorMode == .light ? theme.colorPattern.ui.base : theme.colorPattern.ui.sub2
    }
    
    private func changeSeparatorStyle() {
        let currentColorMode = Theme.shared.currentModel?.colorMode ?? .light
        tableView.separatorStyle = currentColorMode == .light ? .singleLine : .none
    }
    
    // MARK: Binding
    
    private func binding(with viewModel: ProfileSettingsViewModel) {
        viewModel.output
            .banner
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(bannerImage.rx.image)
            .disposed(by: disposeBag)
        
        viewModel.output
            .icon
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(iconImage.rx.image)
            .disposed(by: disposeBag)
        
        viewModel.output
            .name
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { name in
                self.nameTextArea.value = name
            }).disposed(by: disposeBag)
        
        viewModel.output
            .description
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { description in
                self.bioTextArea.value = description
            }).disposed(by: disposeBag)
        
        viewModel.output
            .isCat
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { isCat in
                self.catSwitch.value = isCat
            }).disposed(by: disposeBag)
        
        // trigger
        viewModel.output
            .pickImageTrigger
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { hasChanged in
                self.showImageMenu(hasChanged)
            }).disposed(by: disposeBag)
        
        viewModel.output
            .popViewControllerTrigger
            .asDriver(onErrorDriveWith: Driver.empty())
            .drive(onNext: { _ in
                self.navigationController?.popViewController(animated: true)
            }).disposed(by: disposeBag)
    }
    
    // MARK: Setup
    
    private func setupNavBar() {
        navigationItem.rightBarButtonItem = saveButtonItem
    }
    
    private func setupComponent() {
        title = "プロフィールの編集"
        changeSeparatorStyle()
        bannerImage.clipsToBounds = true
        iconImage.clipsToBounds = true
        bannerImage.backgroundColor = .lightGray
        iconImage.backgroundColor = .lightGray
        
        bannerImage.contentMode = .scaleAspectFill
    }
    
    private func setTable() {
        let headerSection = Section { section in // バナーimageをHeaderとしてEurekaに埋め込む
            section.header = {
                var header = HeaderFooterView<UIView>(.callback {
                    self.getHeader()
                    })
                header.height = { self.headerHeight }
                return header
            }()
        }
        
        let nameSection = getNameSection()
        let descSection = getDescSection()
        let miscSection = getMiscSection()
        
        form +++ headerSection +++ nameSection +++ descSection +++ miscSection
        
        bioTextArea.cell.textView.inputAccessoryView = getToolBar(for: bioTextArea.cell.textView)
        nameTextArea.cell.textField.inputAccessoryView = getToolBar(for: nameTextArea.cell.textField)
    }
    
    // MARK: Toolbar
    
    /// targetに対してToolBarを生成する
    /// - Parameter target: Target
    private func getToolBar(for target: UITextInput) -> UIToolbar {
        let toolBar = UIToolbar()
        let flexibleItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        let emojiButton = UIBarButtonItem(title: "laugh-squint", style: .plain, target: self, action: nil)
        let doneButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: nil)
        emojiButton.rx.tap.subscribe { _ in self.showReactionGen(target: target) }.disposed(by: disposeBag)
        doneButton.rx.tap.subscribe { _ in self.view.endEditing(true) }.disposed(by: disposeBag)
        toolBar.setItems([flexibleItem, flexibleItem,
                          flexibleItem,
                          flexibleItem, flexibleItem,
                          emojiButton, doneButton], animated: true)
        toolBar.sizeToFit()
        
        emojiButton.setTitleTextAttributes([NSAttributedString.Key.font: UIFont.awesomeSolid(fontSize: 17.0)!], for: .normal)
        emojiButton.setTitleTextAttributes([NSAttributedString.Key.font: UIFont.awesomeSolid(fontSize: 17.0)!], for: .selected)
        return toolBar
    }
    
    /// ReactionGen(絵文字ピッカー)を表示する
    /// - Parameter viewWithText: UITextInput
    private func showReactionGen(target viewWithText: UITextInput) {
        guard let reactionGen = getViewController(name: "reaction-gen") as? ReactionGenViewController else { return }
        
        reactionGen.onPostViewController = true
        reactionGen.selectedEmoji.subscribe(onNext: { emojiModel in // ReactionGenで絵文字が選択されたらに送られてくる
            self.insertCustomEmoji(with: emojiModel, to: viewWithText)
            reactionGen.dismiss(animated: true, completion: nil)
        }).disposed(by: disposeBag)
        
        presentWithSemiModal(reactionGen, animated: true, completion: nil)
    }
    
    /// StoryBoardからVCを生成する
    /// - Parameter name: name
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
    
    /// TextView, TextFiledに対して、現時点でのカーソル位置に絵文字を挿入する
    /// - Parameters:
    ///   - emojiModel: EmojiView.EmojiModel
    ///   - viewWithText: TextView, TextFiled...etc
    private func insertCustomEmoji(with emojiModel: EmojiView.EmojiModel, to viewWithText: UITextInput) {
        if let selectedTextRange = viewWithText.selectedTextRange {
            guard let emoji = emojiModel.isDefault ? emojiModel.defaultEmoji : ":\(emojiModel.rawEmoji):" else { return }
            viewWithText.replace(selectedTextRange,
                                 withText: emoji)
        }
    }
    
    // MARK: Section
    
    private func getNameSection() -> Section {
        return Section("Name") <<< nameTextArea
    }
    
    private func getDescSection() -> Section {
        return Section("Bio") <<< bioTextArea
    }
    
    private func getMiscSection() -> Section {
        return Section(header: "Cat", footer: "ONにすると自分の投稿がネコ語に翻訳されます") <<< catSwitch
    }
    
    // MARK: Header
    
    private func getHeader() -> UIView {
        iconImage.translatesAutoresizingMaskIntoConstraints = false
        bannerImage.addSubview(iconImage)
        
        // AutoLayout
        bannerImage.addConstraints([
            NSLayoutConstraint(item: iconImage,
                               attribute: .leading,
                               relatedBy: .equal,
                               toItem: bannerImage,
                               attribute: .leading,
                               multiplier: 1.0,
                               constant: 20),
            
            NSLayoutConstraint(item: iconImage,
                               attribute: .height,
                               relatedBy: .equal,
                               toItem: iconImage,
                               attribute: .width,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: iconImage,
                               attribute: .width,
                               relatedBy: .equal,
                               toItem: bannerImage,
                               attribute: .height,
                               multiplier: 0.45,
                               constant: 0),
            
            NSLayoutConstraint(item: iconImage,
                               attribute: .centerY,
                               relatedBy: .equal,
                               toItem: bannerImage,
                               attribute: .centerY,
                               multiplier: 1.0,
                               constant: 0)
        ])
        
        iconImage.maskCircle()
        return bannerImage
    }
    
    private func setIconCover() {
        setCover(on: iconImage, fontSize: 15)
        setCover(on: bannerImage, fontSize: 22)
    }
    
    private func setCover(on parentView: UIView, fontSize: CGFloat) {
        let bannerCover = UIView()
        let editableIcon = UILabel()
        
        editableIcon.font = .awesomeSolid(fontSize: fontSize)
        editableIcon.text = "camera"
        editableIcon.textColor = .white
        
        bannerCover.backgroundColor = .black
        bannerCover.alpha = 0.35
        
        bannerCover.translatesAutoresizingMaskIntoConstraints = false
        editableIcon.translatesAutoresizingMaskIntoConstraints = false
        
        parentView.addSubview(bannerCover)
        parentView.addSubview(editableIcon)
        
        parentView.addConstraints([
            NSLayoutConstraint(item: bannerCover,
                               attribute: .leading,
                               relatedBy: .equal,
                               toItem: parentView,
                               attribute: .leading,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: bannerCover,
                               attribute: .top,
                               relatedBy: .equal,
                               toItem: parentView,
                               attribute: .top,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: bannerCover,
                               attribute: .trailing,
                               relatedBy: .equal,
                               toItem: parentView,
                               attribute: .trailing,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: bannerCover,
                               attribute: .bottom,
                               relatedBy: .equal,
                               toItem: parentView,
                               attribute: .bottom,
                               multiplier: 1.0,
                               constant: 0)
        ])
        
        parentView.addConstraints([
            NSLayoutConstraint(item: editableIcon,
                               attribute: .centerX,
                               relatedBy: .equal,
                               toItem: parentView,
                               attribute: .centerX,
                               multiplier: 1.0,
                               constant: 0),
            
            NSLayoutConstraint(item: editableIcon,
                               attribute: .centerY,
                               relatedBy: .equal,
                               toItem: parentView,
                               attribute: .centerY,
                               multiplier: 1.0,
                               constant: 0)
        ])
    }
    
    // MARK: Alert
    
    private func showImageMenu(_ hasChanged: Bool) {
        let panelMenu = PanelMenuViewController()
        var menuItems: [PanelMenuViewController.MenuItem] = [.init(title: "カメラから", awesomeIcon: "", order: 0),
                                                             .init(title: "アルバムから", awesomeIcon: "", order: 1)]
        
        if hasChanged { // イメージが一度でも変更されたら、もとに戻すオプションを追加する
            menuItems.append(.init(title: "元に戻す", awesomeIcon: "", order: 2))
        }
        
        panelMenu.setupMenu(items: menuItems)
        panelMenu.tapTrigger.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { order in // どのメニューがタップされたのか
            guard order >= 0 else { return }
            panelMenu.dismiss(animated: true, completion: nil)
            
            switch order {
            case 0: // camera
                self.pickImage(type: .camera)
            case 1: // albam
                self.pickImage(type: .photoLibrary)
            case 2:
                guard hasChanged else { return }
                self.resetImage.accept(())
            default:
                break
            }
        }).disposed(by: disposeBag)
        
        present(panelMenu, animated: true, completion: nil)
    }
    
    // MARK: Delegate
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        transformAttachment(disposeBag: disposeBag, picker: picker, didFinishPickingMediaWithInfo: info) { _, editedImage, _ in
            guard let editedImage = editedImage else { return }
            self.selectedImage.accept(editedImage)
        }
    }
}
