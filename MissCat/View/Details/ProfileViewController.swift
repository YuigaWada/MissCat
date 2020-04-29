//
//  ProfileViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Agrume
import RxCocoa
import RxSwift
import SkeletonView
import UIKit
import XLPagerTabStrip

private typealias ViewModel = ProfileViewModel
class ProfileViewController: ButtonBarPagerTabStripViewController, UITextViewDelegate {
    private let disposeBag = DisposeBag()
    private var blurAnimator: UIViewPropertyAnimator?
    
    @IBOutlet weak var pagerTab: ButtonBarView!
    
    @IBOutlet weak var containerScrollView: UIScrollView!
    
    @IBOutlet weak var bannerImageView: UIImageView!
    
    @IBOutlet weak var nameTextView: MisskeyTextView!
    
    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var introTextView: MisskeyTextView!
    
    @IBOutlet weak var notesCountButton: UIButton!
    @IBOutlet weak var followCountButton: UIButton!
    @IBOutlet weak var followerCountButton: UIButton!
    @IBOutlet weak var followButton: UIButton!
    
    @IBOutlet weak var notesCountLabel: UILabel!
    @IBOutlet weak var followCountLabel: UILabel!
    @IBOutlet weak var followerCountLabel: UILabel!
    
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var settingsButton: UIButton!
    @IBOutlet weak var containerHeightContraint: NSLayoutConstraint!
    
    @IBOutlet weak var catIcon: UIImageView!
    @IBOutlet weak var catYConstraint: NSLayoutConstraint!
    
    var homeViewController: HomeViewController?
    
    private var mainColor: UIColor = .systemBlue
    
    private var userId: String?
    private var scrollBegining: CGFloat = 0
    private var tlScrollView: UIScrollView?
    private var isMe: Bool = false
    
    private lazy var animateBlurView = getAnimateBlurView()
    
    private lazy var viewModel: ProfileViewModel = self.getViewModel()
    
    private var childVCs: [TimelineViewController] = []
    
    private var maxScroll: CGFloat {
        updateAnimateBlurHeight() // 自己紹介文の高さが変更されるので、Blurの高さも変更する
        pagerTab.layoutIfNeeded()
        return pagerTab.frame.origin.y - getSafeAreaSize().height - 10 // 10 = 微調整
    }
    
    // MARK: Life Cycle
    
    override func viewDidLoad() {
        viewModel.setUserId(userId ?? "", isMe: isMe)
        setTheme()
        bindTheme()
        
        super.viewDidLoad()
        setupComponent()
        setupSkeltonMode()
        binding()
        setBannerBlur()
        
        containerScrollView.delegate = self
        containerScrollView.contentInsetAdjustmentBehavior = .never
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        layoutIfNeeded(to: [iconImageView])
        
        iconImageView.layer.cornerRadius = iconImageView.frame.width / 2
        settingsButton.layer.cornerRadius = settingsButton.frame.width / 2
        backButton.layer.cornerRadius = backButton.frame.width / 2
        
        containerHeightContraint.constant = 2 * view.frame.height - (view.frame.height - containerScrollView.frame.origin.y)
        
        catYConstraint.constant = (-1) * catIcon.frame.width / 4 + 2
        catYConstraint.constant -= sqrt(abs(pow(iconImageView.layer.cornerRadius, 2) - pow(catIcon.frame.width / 2, 2)))
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.setNavigationBarHidden(true, animated: animated)
        childVCs.forEach { $0.homeViewController = homeViewController }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        introTextView.renderViewStrings()
        introTextView.transformText()
        
        nameTextView.renderViewStrings()
        nameTextView.transformText()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if blurAnimator == nil { setBlurAnimator() }
    }
    
    private func getViewModel() -> ViewModel {
        let input = ViewModel.Input(nameYanagi: nameTextView, introYanagi: introTextView)
        return .init(with: input, and: disposeBag)
    }
    
    private func setupComponent() {
        backButton.titleLabel?.font = .awesomeSolid(fontSize: 16.0)
        backButton.alpha = 0.5
        backButton.setTitleColor(.white, for: .normal)
        backButton.backgroundColor = .black
        backButton.alpha = 0.8
        
        settingsButton.titleLabel?.font = .awesomeSolid(fontSize: 16.0)
        settingsButton.alpha = 0.5
        settingsButton.setTitleColor(.white, for: .normal)
        settingsButton.backgroundColor = .black
        settingsButton.alpha = 0.8
        
        introTextView.font = UIFont(name: "Helvetica",
                                    size: 11.0)
        
        notesCountButton.titleLabel?.text = nil
        followCountButton.titleLabel?.text = nil
        followerCountButton.titleLabel?.text = nil
        followButton.titleLabel?.text = "..."
        followButton.backgroundColor = .clear
        followButton.layer.borderWidth = 1
        
        introTextView.delegate = self
    }
    
    private func bindTheme() {
        let theme = Theme.shared.theme
        
        theme.map { UIColor(hex: $0.mainColorHex) }.subscribe(onNext: { mainColor in
//            self.settings.style.selectedBarBackgroundColor = mainColor
            
            // ↑のやつだとうまく変更できないのでworkaround
            self.buttonBarView.selectedBar.backgroundColor = mainColor
            self.followButton.layer.borderColor = mainColor.cgColor
            self.followButton.setTitleColor(mainColor, for: .normal)
            self.mainColor = mainColor
            
        }).disposed(by: disposeBag)
        
        theme.map { $0.colorPattern.ui.base }.bind(to: view.rx.backgroundColor).disposed(by: disposeBag)
    }
    
    private func setTheme() {
        guard let theme = Theme.shared.currentModel else { setupTabStyle(main: .systemBlue, back: .white); return }
        
        let mainColorHex = theme.mainColorHex
        let colorPattern = theme.colorPattern.ui
        let backgroundColor = theme.colorMode == .light ? colorPattern.base : colorPattern.sub3
        
        mainColor = UIColor(hex: mainColorHex)
        followButton.layer.borderColor = mainColor.cgColor
        setupTabStyle(main: mainColor, back: backgroundColor)
        
        view.backgroundColor = backgroundColor
        containerScrollView.backgroundColor = backgroundColor
        notesCountLabel.textColor = colorPattern.text
        followCountLabel.textColor = colorPattern.text
        followerCountLabel.textColor = colorPattern.text
    }
    
    // MARK: Public Methods
    
    func setUserId(_ userId: String, isMe: Bool) {
        self.userId = userId
        self.isMe = isMe
    }
    
    // MARK: Setup
    
    private func setupTabStyle(main mainColor: UIColor, back backgroundColor: UIColor) {
        let textColor = Theme.shared.currentModel?.colorPattern.ui.text ?? .black
        
        settings.style.buttonBarBackgroundColor = backgroundColor
        settings.style.buttonBarItemBackgroundColor = backgroundColor
        settings.style.buttonBarItemTitleColor = textColor
        settings.style.selectedBarBackgroundColor = mainColor
        
        settings.style.buttonBarItemFont = UIFont.systemFont(ofSize: 15)
        
        settings.style.buttonBarHeight = 6
        settings.style.selectedBarHeight = 2
        settings.style.buttonBarMinimumLineSpacing = 15
        settings.style.buttonBarLeftContentInset = 0
        settings.style.buttonBarRightContentInset = 0
    }
    
    private func binding() {
        let output = viewModel.output
        
        // メインスレッドで動作させたいのでDriverに変更しておく
        output.iconImage.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { image in
            self.iconImageView.hideSkeleton()
            self.iconImageView.image = image
        }).disposed(by: disposeBag)
        
        output.intro.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { attributedText in
            self.introTextView.hideSkeleton()
            self.introTextView.attributedText = attributedText
        }).disposed(by: disposeBag)
        
        output.bannerImage.asDriver(onErrorDriveWith: Driver.empty()).drive(bannerImageView.rx.image).disposed(by: disposeBag)
        output.isCat.asDriver(onErrorDriveWith: Driver.empty()).map { !$0 }.drive(catIcon.rx.isHidden).disposed(by: disposeBag)
        
        output.displayName.asDriver(onErrorDriveWith: Driver.empty()).drive(nameTextView.rx.attributedText).disposed(by: disposeBag)
        output.notesCount.asDriver(onErrorDriveWith: Driver.empty()).drive(notesCountButton.rx.title()).disposed(by: disposeBag)
        output.followCount.asDriver(onErrorDriveWith: Driver.empty()).drive(followCountButton.rx.title()).disposed(by: disposeBag)
        output.followerCount.asDriver(onErrorDriveWith: Driver.empty()).drive(followerCountButton.rx.title()).disposed(by: disposeBag)
        
        iconImageView.setTapGesture(disposeBag) {
            guard let icon = self.iconImageView.image else { return }
            Agrume(image: icon).show(from: self) // 画像を表示
        }
        
        if !isMe {
            output.relation.asDriver(onErrorDriveWith: Driver.empty()).map {
                let isFollowing = $0.isFollowing ?? false
                return isFollowing ? "フォロー解除" : "フォロー"
            }.drive(followButton.rx.title()).disposed(by: disposeBag)
            
            output.relation.asDriver(onErrorDriveWith: Driver.empty()).map {
                let isFollowing = $0.isFollowing ?? false
                return !isFollowing ? self.mainColor : UIColor.clear
            }.drive(followButton.rx.backgroundColor).disposed(by: disposeBag)
            
            output.relation.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: {
                let isFollowing = $0.isFollowing ?? false
                self.followButton.setTitleColor(isFollowing ? self.mainColor : UIColor.clear, for: .normal)
            }).disposed(by: disposeBag)
            
            followButton.rx.tap.subscribe(onNext: {
                guard let isFollowing = self.viewModel.state.isFollowing else { return }
                
                if isFollowing { // try フォロー解除
                    self.showUnfollowAlert()
                } else {
                    self.viewModel.follow()
                }
                
            }).disposed(by: disposeBag)
        } else { // 自分のプロフィール画面の場合
            followButton.setTitle("編集", for: .normal)
            followButton.setTitleColor(mainColor, for: .normal)
        }
        
        backButton.rx.tap.subscribe(onNext: {
            _ = self.navigationController?.popViewController(animated: true)
        }).disposed(by: disposeBag)
        
        settingsButton.rx.tap.subscribe(onNext: {
            self.homeViewController?.openSettings()
        }).disposed(by: disposeBag)
        
        backButton.isHidden = output.isMe
    }
    
    private func setBannerBlur() {
        let quaterHeight = bannerImageView.frame.height / 4
        
        let topColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
        let bottomColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.7)
        let gradientLayer: CAGradientLayer = CAGradientLayer()
        
        gradientLayer.colors = [topColor.cgColor, bottomColor.cgColor]
        gradientLayer.frame = CGRect(x: 0,
                                     y: quaterHeight * 2,
                                     width: view.frame.width,
                                     height: quaterHeight * 2)
        
        bannerImageView.layer.addSublayer(gradientLayer)
    }
    
    private func setBlurAnimator() {
        animateBlurView.frame = CGRect(x: 0,
                                       y: 0,
                                       width: containerScrollView.frame.width,
                                       height: pagerTab.frame.origin.y + getSafeAreaSize().height - 10)
        
        animateBlurView.alpha = 0
        animateBlurView.isUserInteractionEnabled = false
        containerScrollView.addSubview(animateBlurView)
        
        blurAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .easeInOut) {
            self.animateBlurView.alpha = 1
        }
        blurAnimator?.pausesOnCompletion = true // 別のVCに飛ぶとアニメーションが完了状態になってしまうため、stateを.activeで維持させる
    }
    
    private func getAnimateBlurView() -> UIVisualEffectView {
        let colorMode = Theme.shared.currentModel?.colorMode ?? .light
        let style: UIBlurEffect.Style = colorMode == .light ? .light : .dark
        
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    private func updateAnimateBlurHeight() {
        let newHeight = pagerTab.frame.origin.y // containerScrollView.frameの座標はsafe areaの下から始点が始まるのでsafe areaは考えなくてOK
        
        guard animateBlurView.frame.height != newHeight else { return }
        animateBlurView.frame = CGRect(x: 0,
                                       y: 0,
                                       width: containerScrollView.frame.width,
                                       height: newHeight)
    }
    
    private func showUnfollowAlert() {
        let alert = UIAlertController(title: "フォロー解除", message: "本当にフォロー解除しますか？", preferredStyle: UIAlertController.Style.alert)
        
        let defaultAction: UIAlertAction = UIAlertAction(title: "Unfollow", style: UIAlertAction.Style.destructive, handler: {
            (_: UIAlertAction!) -> Void in
            self.viewModel.unfollow()
        })
        let cancelAction: UIAlertAction = UIAlertAction(title: "いいえ", style: UIAlertAction.Style.cancel, handler: nil)
        
        alert.addAction(cancelAction)
        alert.addAction(defaultAction)
        
        present(alert, animated: true, completion: nil)
    }
    
    // MARK: UITextViewDelegate
    
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        tappedLink(text: URL.absoluteString)
        return false
    }
    
    func tappedLink(text: String) {
        let (linkType, value) = text.analyzeHyperLink()
        switch linkType {
        case .url:
            homeViewController?.openLink(url: value)
        case .user:
            homeViewController?.move2Profile(userId: value)
        case .hashtag:
            navigationController?.popViewController(animated: true)
            homeViewController?.emulateFooterTabTap(tab: .home)
            homeViewController?.searchHashtag(tag: value)
        }
    }
    
    // MARK: XLPagerTabStrip
    
    override func viewControllers(for pagerTabStripController: PagerTabStripViewController) -> [UIViewController] {
        return getChildVC()
    }
    
    // MARK: Utilities
    
    private func getChildVC() -> [UIViewController] {
        guard let userId = userId else { fatalError("Internal Error") }
        
        let userNoteOnly = generateTimelineVC(xlTitle: "Notes",
                                              userId: userId,
                                              includeReplies: false,
                                              onlyFiles: false,
                                              scrollable: false,
                                              loadLimit: 30)
        
        let allUserNote = generateTimelineVC(xlTitle: "Notes & Replies",
                                             userId: userId,
                                             includeReplies: true,
                                             onlyFiles: false,
                                             scrollable: false,
                                             loadLimit: 30)
        
        let userMedia = generateTimelineVC(xlTitle: "Media",
                                           userId: userId,
                                           includeReplies: false,
                                           onlyFiles: true,
                                           scrollable: false,
                                           loadLimit: 30)
        
        childVCs = [userNoteOnly, allUserNote, userMedia]
        
        //        childVCs.forEach { // VCの表示がずれるのを防ぐ(XLPagerTabStripの不具合？？)
        //            $0.view.frame = CGRect(x: 0, y: 0, width: self.view.frame.width, height: $0.view.frame.height)
        //        }
        
        return childVCs
    }
    
    private func generateTimelineVC(xlTitle: IndicatorInfo, userId: String, includeReplies: Bool, onlyFiles: Bool, scrollable: Bool, loadLimit: Int) -> TimelineViewController {
        guard let viewController = getViewController(name: "timeline") as? TimelineViewController else { fatalError("Internal Error.") }
        
        viewController.setup(type: .OneUser,
                             includeReplies: includeReplies,
                             onlyFiles: onlyFiles,
                             userId: userId,
                             withNavBar: false,
                             scrollable: scrollable,
                             loadLimit: loadLimit,
                             xlTitle: xlTitle)
        
        return viewController
    }
    
    private func getViewController(name: String) -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
    
    // MARK: Scrolling...
    
    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        super.scrollViewWillBeginDragging(scrollView) // XLPagerTabStripの処理
        
        scrollBegining = scrollView.contentOffset.y
    }
    
    // 二重構造になっているユーザー画面のScrollViewのスクロールを制御する
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView) // XLPagerTabStripの処理
        
        let scroll = scrollView.contentOffset.y - scrollBegining
        guard childVCs.count > currentIndex,
            let blurAnimator = blurAnimator,
            let tlScrollView = childVCs[currentIndex].mainTableView else { return }
        
        var needContainerScroll: Bool = true
        // tlScrollViewをスクロール
        if scroll > 0 {
            if containerScrollView.contentOffset.y >= maxScroll {
                tlScrollView.contentOffset.y += scroll
                needContainerScroll = false
                
                if tlScrollView.contentOffset.y >= tlScrollView.contentSize.height - containerView.frame.height { // スクロールの上限
                    tlScrollView.contentOffset.y -= scroll
                }
            }
        } else { // scroll < 0 ...
            let positiveScroll = (-1) * scroll
            if tlScrollView.contentOffset.y >= positiveScroll {
                tlScrollView.contentOffset.y -= positiveScroll
                needContainerScroll = false
            }
        }
        
        // containerScrollViewをスクロール
        if !needContainerScroll {
            scrollView.contentOffset.y = scrollBegining
        } else {
            // スクロールがmaxScrollの半分を超えたあたりから、fractionComplete: 0→1と動かしてanimateさせる
            let blurProportion = containerScrollView.contentOffset.y * 2 / maxScroll - 1
            scrollBegining = scrollView.contentOffset.y
            
            // ブラーアニメーションをかける
            if blurProportion > 0, blurProportion < 1 {
                blurAnimator.fractionComplete = blurProportion
            } else {
                blurAnimator.fractionComplete = blurProportion <= 0 ? 0 : 1
            }
        }
    }
    
    // MARK: SkeltonView Utilities
    
    private func setupSkeltonMode() {
        iconImageView.isSkeletonable = true
        introTextView.isSkeletonable = true
        
        nameTextView.text = nil
        changeSkeltonState(on: true)
    }
    
    private func changeSkeltonState(on: Bool) {
        if on {
            let gradient = SkeletonGradient(baseColor: Theme.shared.currentModel?.colorPattern.ui.sub3 ?? .lightGray)
            
            iconImageView.showAnimatedGradientSkeleton(usingGradient: gradient)
            introTextView.showAnimatedGradientSkeleton(usingGradient: gradient)
        } else {
            iconImageView.hideSkeleton()
            introTextView.hideSkeleton()
        }
    }
}
