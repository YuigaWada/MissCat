//
//  ReactionGenCell.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/17.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxDataSources
import RxSwift
import UIKit

protocol ReactionGenViewControllerDelegate {
    func scrollUp() // 半モーダルviewを上まで引き上げる
}

private typealias ViewModel = ReactionGenViewModel
typealias EmojisDataSource = RxCollectionViewSectionedReloadDataSource<ReactionGenViewController.EmojisSection>
class ReactionGenViewController: UIViewController, UISearchBarDelegate, UIScrollViewDelegate, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var iconImageView: MissCatImageView!
    @IBOutlet weak var displayNameLabel: UILabel!
    @IBOutlet weak var targetNoteTextView: UITextView!
    @IBOutlet weak var targetNoteDisplayView: UIView!
    
    @IBOutlet weak var settingsButton: UIButton!
    @IBOutlet weak var emojiCollectionView: UICollectionView!
    @IBOutlet weak var borderOriginXConstraint: NSLayoutConstraint!
    
    var delegate: ReactionGenViewControllerDelegate?
    var parentNavigationController: UINavigationController?
    var onPostViewController: Bool = false
    var owner: SecureUser?
    
    var selectedEmoji: PublishRelay<EmojiView.EmojiModel> = .init()
    
    private var viewModel: ReactionGenViewModel?
    private let disposeBag = DisposeBag()
    
    private var viewDidAppeared: Bool = false
    private var cellLoading: Bool = false
    private var previousCellCount = -1
    
    private lazy var defaultCellsize = view.frame.width / 8
    
    // MARK: Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupComponents()
        setupCollectionViewLayout()
        setTheme()
        bindTheme()
        
        let viewModel = setupViewModel()
        setEmojiModel(viewModel: viewModel)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        targetNoteDisplayView.isHidden = onPostViewController
        borderOriginXConstraint.isActive = !onPostViewController
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        viewDidAppeared = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        viewDidAppeared = false
    }
    
    // MARK: Design
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme
            .map { $0.colorMode == .light ? $0.colorPattern.ui.base : $0.colorPattern.ui.sub3 }
            .bind(to: view.rx.backgroundColor)
            .disposed(by: disposeBag)
        
        theme
            .map { $0.colorMode == .light ? $0.colorPattern.ui.base : $0.colorPattern.ui.sub3 }
            .bind(to: emojiCollectionView.rx.backgroundColor)
            .disposed(by: disposeBag)
        
        theme
            .map { $0.colorPattern.ui.sub3 }.subscribe(onNext: { textColor in
                self.displayNameLabel.textColor = textColor
        }).disposed(by: disposeBag)
        
        theme.filter { $0.colorMode == .light }.subscribe(onNext: { _ in
            self.searchBar.resetColor()
        }).disposed(by: disposeBag)
        
        theme.filter { $0.colorMode == .dark }
            .map { $0.colorPattern.ui }.subscribe(onNext: { colorPattern in
                self.searchBar.changeColor(background: colorPattern.sub1, text: colorPattern.sub3, placeholder: colorPattern.sub3)
        }).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        guard let theme = Theme.shared.currentModel else { return }
        let colorPattern = theme.colorPattern
        let backgroundColor = theme.colorMode == .light ? colorPattern.ui.base : colorPattern.ui.sub3
        
        view.backgroundColor = backgroundColor
        emojiCollectionView.backgroundColor = backgroundColor
        displayNameLabel.textColor = colorPattern.ui.text
        
        if theme.colorMode == .dark {
            searchBar.changeColor(background: colorPattern.ui.sub1, text: colorPattern.ui.text, placeholder: colorPattern.ui.sub3)
        }
    }
    
    // MARK: Setup
    
    private func setupViewModel() -> ReactionGenViewModel {
        guard let owner = owner else { fatalError("MUST SET OWNER!") }
        let viewModel = ReactionGenViewModel(with: .init(owner: owner, searchTrigger: getSearchTrigger()),
                                             and: disposeBag)
        let dataSource = setupDataSource()
        
        binding(dataSource: dataSource, viewModel: viewModel)
        self.viewModel = viewModel
        return viewModel
    }
    
    private func setupDataSource() -> EmojisDataSource {
        let dataSource = EmojisDataSource(
            configureCell: { dataSource, _, indexPath, _ in
                self.setupCell(dataSource, self.emojiCollectionView, indexPath)
            }
        )
        
        return dataSource
    }
    
    private func binding(dataSource: EmojisDataSource?, viewModel: ViewModel) {
        guard let dataSource = dataSource else { return }
        
        let output = viewModel.output
        output.emojis.bind(to: emojiCollectionView.rx.items(dataSource: dataSource)).disposed(by: disposeBag)
    }
    
    private func setupComponents() {
        // icon
        iconImageView.maskCircle()
        
        // collectionView
        emojiCollectionView.register(UINib(nibName: "ReactionCollectionHeader", bundle: nil), forCellWithReuseIdentifier: "ReactionCollectionHeader")
        emojiCollectionView.register(UINib(nibName: "EmojiViewCell", bundle: nil), forCellWithReuseIdentifier: "EmojiCell")
        emojiCollectionView.rx.setDelegate(self).disposed(by: disposeBag)
        
        // searchBar
        searchBar.delegate = self
        searchBar.autocorrectionType = .no
        searchBar.keyboardType = .emailAddress
        
        // targetNote
        targetNoteTextView.textContainer.lineBreakMode = .byTruncatingTail
        targetNoteTextView.textContainer.maximumNumberOfLines = 2
        
        // button
        settingsButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        settingsButton.rx.tap.subscribe(onNext: { _ in
            // ReactionGenが閉じてから設定を開く
            self.dismiss(animated: true, completion: {
                guard let reactionSettings = self.getViewController(name: "reaction-settings")
                    as? ReactionSettingsViewController else { return }
                self.parentNavigationController?.pushViewController(reactionSettings, animated: true)
            })
        }).disposed(by: disposeBag)
    }
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
    
    private func setupCollectionViewLayout() {
        let flowLayout = UICollectionViewFlowLayout()
        
        flowLayout.itemSize = CGSize(width: defaultCellsize, height: defaultCellsize)
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        emojiCollectionView.collectionViewLayout = flowLayout
    }
    
    private func setupTapGesture(to view: EmojiViewCell, emojiModel: EmojiView.EmojiModel) {
        let tapGesture = UITapGestureRecognizer()
        
        // 各々のEmojiViewに対してtap gestureを付加する
        tapGesture.rx.event.bind { _ in
            if self.onPostViewController { // Post画面のときは入力をPostViewControllerへと渡す
                self.sendEmojiInput(emojiModel: emojiModel)
            } else { // NoteCell上ではReactionGenが投稿に対してサーバーにリアクションを送信する
                self.react2Note(emojiModel)
                self.selectedEmoji.accept(emojiModel)
            }
            
        }.disposed(by: disposeBag)
        
        view.addGestureRecognizer(tapGesture)
    }
    
    private func sendEmojiInput(emojiModel: EmojiView.EmojiModel) {
        selectedEmoji.accept(emojiModel)
    }
    
    private func react2Note(_ emojiModel: EmojiView.EmojiModel) {
        guard let targetNoteId = viewModel!.targetNoteId else { return }
        
        if viewModel!.hasMarked {
            viewModel!.cancelReaction(noteId: targetNoteId)
        } else {
            viewModel!.registerReaction(noteId: targetNoteId, emojiModel: emojiModel)
        }
        
        dismiss(animated: true, completion: nil) // 半モーダルを消す
    }
    
    // MARK: Setup Cell
    
    private func setupCell(_ dataSource: CollectionViewSectionedDataSource<ReactionGenViewController.EmojisSection>, _ collectionView: UICollectionView, _ indexPath: IndexPath) -> UICollectionViewCell {
        let index = indexPath.row
        let item = dataSource.sectionModels[0].items[index]
        
        let isHeader = item is EmojiViewHeader
        if isHeader {
            guard let headerInfo = item as? EmojiViewHeader,
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ReactionCollectionHeader", for: indexPath) as? ReactionCollectionHeader else { fatalError("Internal Error.") }
            
            cell.backgroundColor = .clear
            cell.contentMode = .left
            cell.setTitle(headerInfo.title)
            return cell
        } else {
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "EmojiCell", for: indexPath) as? EmojiViewCell else { fatalError("Internal Error.") }
            
            cell.mainView.initialize()
            
            cell.mainView.emoji = item
            cell.mainView.isFake = item.isFake
            cell.contentMode = .left
            cell.backgroundColor = .clear
            setupTapGesture(to: cell, emojiModel: item)
            
            return cell
        }
    }
    
    private func getSearchTrigger() -> Observable<String> {
        let debounceInterval = DispatchTimeInterval.milliseconds(300)
        return searchBar.rx.text.compactMap { $0?.localizedLowercase }.asObservable()
            .skip(1)
            .debounce(debounceInterval, scheduler: MainScheduler.instance)
            .distinctUntilChanged()
    }
    
    // MARK: Set Methods
    
    private func setEmojiModel(viewModel: ReactionGenViewModel) {
        viewModel.setEmojiModel()
    }
    
    private func setTargetNoteId(_ id: String?) {
        viewModel!.targetNoteId = id
    }
    
    // MARK: CollectionView Delegate
    
    // Headerセルの場合はの幅を設定
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let defaultSize = CGSize(width: defaultCellsize, height: defaultCellsize)
        guard let viewModel = viewModel else { return defaultSize }
        let isHeader = viewModel.checkHeader(index: indexPath.row)
        
        return isHeader ? CGSize(width: emojiCollectionView.frame.width, height: 30) : defaultSize
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 0
    }
    
    // MARK: Public Methods
    
    func setOwner(_ owner: SecureUser) {
        self.owner = owner
    }
    
    func setTargetNote(noteId: String, iconUrl: String?, displayName: String, username: String, hostInstance: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool) {
        let colorMode = Theme.shared.currentModel?.colorMode ?? .light
        let isLightMode = colorMode == .light
        
        // noteId
        setTargetNoteId(noteId)
        
        // icon image
        if let image = Cache.shared.getIcon(username: "\(username)@\(hostInstance)") {
            iconImageView.image = image
        } else if let iconUrl = iconUrl, let url = URL(string: iconUrl) {
            _ = url.toUIImage { [weak self] image in
                guard let self = self, let image = image else { return }
                
                DispatchQueue.main.async {
                    Cache.shared.saveIcon(username: username, image: image) // CHACHE!
                    self.iconImageView.image = image
                }
            }
        }
        
        // displayName
        displayNameLabel.text = displayName
        
        // note
        targetNoteTextView.attributedText = note // .changeColor(to: .lightGray)
        targetNoteTextView.alpha = isLightMode ? 0.5 : 1
    }
    
    // MARK: TextField Delegate
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        guard let delegate = delegate else { return }
        
        delegate.scrollUp()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.endEditing(true)
    }
}

extension UISearchBar {
    func changeColor(background backgroundColor: UIColor, text textColor: UIColor, placeholder placeholderColor: UIColor) {
        guard let textField = value(forKey: "searchField") as? UITextField else { return }
//        textField.backgroundColor = backgroundColor
        textField.textColor = textColor
//        textField.attributedPlaceholder = .init(string: placeholder ?? "",
//                                                attributes: [.foregroundColor: placeholderColor])
    }
    
    func resetColor() {
        guard let textField = value(forKey: "searchField") as? UITextField else { return }
        textField.backgroundColor = nil
        textField.attributedPlaceholder = nil
    }
}
