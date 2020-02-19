//
//  ProfileViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import RxCocoa
import RxSwift
import UIKit
import XLPagerTabStrip

private typealias ViewModel = ProfileViewModel
public class ProfileViewController: ButtonBarPagerTabStripViewController {
    private let disposeBag = DisposeBag()
    private var blurAnimator: UIViewPropertyAnimator?
    
    @IBOutlet weak var pagerTab: ButtonBarView!
    
    @IBOutlet weak var containerScrollView: UIScrollView!
    
    @IBOutlet weak var bannerImageView: UIImageView!
    
    @IBOutlet weak var displayName: UILabel!
    @IBOutlet weak var usernameLabel: UILabel!
    
    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var introTextView: MisskeyTextView!
    
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var containerHeightContraint: NSLayoutConstraint!
    
    private var userId: String?
    private var scrollBegining: CGFloat = 0
    private var tlScrollView: UIScrollView?
    private var isMe: Bool = false
    
    private lazy var viewModel: ProfileViewModel = self.getViewModel()
    
    private var childVCs: [TimelineViewController] = []
    
    private var maxScroll: CGFloat {
        pagerTab.layoutIfNeeded()
        return pagerTab.frame.origin.y - getSafeAreaSize().height - 10 // 10 = 微調整
    }
    
    // MARK: Life Cycle
    
    public override func viewDidLoad() {
        viewModel.setUserId(userId ?? "", isMe: isMe)
        setupTabStyle()
        
        super.viewDidLoad()
        setupComponent()
        setupSkeltonMode()
        binding()
        setBannerBlur()
        
        containerScrollView.delegate = self
        containerScrollView.contentInsetAdjustmentBehavior = .never
    }
    
    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        layoutIfNeeded(to: [iconImageView])
        iconImageView.layer.cornerRadius = iconImageView.frame.width / 2
        
        containerHeightContraint.constant = 2 * view.frame.height - (view.frame.height - containerScrollView.frame.origin.y)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if blurAnimator == nil { setBlurAnimator() }
    }
    
    private func getViewModel() -> ViewModel {
        let input = ViewModel.Input(yanagi: introTextView)
        return .init(with: input, and: disposeBag)
    }
    
    private func setupComponent() {
        backButton.titleLabel?.font = .awesomeSolid(fontSize: 18.0)
        backButton.alpha = 0.5
        backButton.setTitleColor(.black, for: .normal)
        
        introTextView.font = UIFont(name: "Helvetica",
                                    size: 11.0)
    }
    
    // MARK: Public Methods
    
    public func setUserId(_ userId: String, isMe: Bool) {
        self.userId = userId
        self.isMe = isMe
    }
    
    // MARK: Setup
    
    private func setupTabStyle() {
        settings.style.buttonBarBackgroundColor = .white
        settings.style.buttonBarItemBackgroundColor = .white
        settings.style.buttonBarItemTitleColor = .black
        settings.style.selectedBarBackgroundColor = .systemBlue
        
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
            self.self.iconImageView.image = image
        }).disposed(by: disposeBag)
        
        output.intro.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { attributedText in
            self.introTextView.hideSkeleton()
            self.introTextView.attributedText = attributedText
        }).disposed(by: disposeBag)
        
        output.bannerImage.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { image in
            self.bannerImageView.image = image
            
            let opticaTextColor = image.opticalTextColor
            
            UIView.animate(withDuration: 1.5, animations: {
                self.backButton.titleLabel?.textColor = opticaTextColor
            })
        }).disposed(by: disposeBag)
        
        output.displayName.asDriver(onErrorDriveWith: Driver.empty()).drive(displayName.rx.text).disposed(by: disposeBag)
        output.username.asDriver(onErrorDriveWith: Driver.empty()).drive(usernameLabel.rx.text).disposed(by: disposeBag)
        
        backButton.rx.tap.subscribe(onNext: {
            _ = self.navigationController?.popViewController(animated: true)
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
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        blurView.frame = CGRect(x: 0,
                                y: 0,
                                width: containerScrollView.frame.width,
                                height: maxScroll + getSafeAreaSize().height)
        
        blurView.alpha = 0
        blurView.isUserInteractionEnabled = true
        containerScrollView.addSubview(blurView)
        
        blurAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .easeInOut) {
            blurView.alpha = 1
        }
    }
    
    // MARK: XLPagerTabStrip
    
    public override func viewControllers(for pagerTabStripController: PagerTabStripViewController) -> [UIViewController] {
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
                                              loadLimit: 10)
        
        let allUserNote = generateTimelineVC(xlTitle: "Notes & Replies",
                                             userId: userId,
                                             includeReplies: true,
                                             onlyFiles: false,
                                             scrollable: false,
                                             loadLimit: 10)
        
        let userMedia = generateTimelineVC(xlTitle: "Media",
                                           userId: userId,
                                           includeReplies: false,
                                           onlyFiles: true,
                                           scrollable: false,
                                           loadLimit: 10)
        
        childVCs = [userNoteOnly, allUserNote, userMedia]
        
//        childVCs.forEach { // VCの表示がずれるのを防ぐ(XLPagerTabStripの不具合？？)
//            $0.view.frame = CGRect(x: 0, y: 0, width: self.view.frame.width, height: $0.view.frame.height)
//        }
        
        return childVCs
    }
    
    private func generateTimelineVC(xlTitle: IndicatorInfo, userId: String, includeReplies: Bool, onlyFiles: Bool, scrollable: Bool, loadLimit: Int) -> TimelineViewController {
        guard let viewController = self.getViewController(name: "timeline") as? TimelineViewController else { fatalError("Internal Error.") }
        
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
    
    public override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        super.scrollViewWillBeginDragging(scrollView) // XLPagerTabStripの処理
        
        scrollBegining = scrollView.contentOffset.y
    }
    
    // 二重構造になっているユーザー画面のScrollViewのスクロールを制御する
    public override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView) // XLPagerTabStripの処理
        
        let scroll = scrollView.contentOffset.y - scrollBegining
        guard childVCs.count > currentIndex,
            let blurAnimator = blurAnimator,
            let tlScrollView = childVCs[self.currentIndex].mainTableView else { return }
        
        var needContainerScroll: Bool = true
        // tlScrollViewをスクロール
        if scroll > 0 {
            if containerScrollView.contentOffset.y >= maxScroll {
                tlScrollView.contentOffset.y += scroll
                needContainerScroll = false
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
        displayName.text = nil
        usernameLabel.text = nil
        
        changeSkeltonState(on: true)
    }
    
    private func changeSkeltonState(on: Bool) {
        if on {
            iconImageView.showAnimatedGradientSkeleton()
            introTextView.showAnimatedGradientSkeleton()
        } else {
            iconImageView.hideSkeleton()
            introTextView.hideSkeleton()
        }
    }
}
