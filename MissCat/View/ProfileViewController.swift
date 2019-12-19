//
//  ProfileViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/12/07.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import UIKit
import XLPagerTabStrip
import RxSwift

public class ProfileViewController: ButtonBarPagerTabStripViewController {
    
    private let disposeBag = DisposeBag()
    private var blurAnimator: UIViewPropertyAnimator?
    
    @IBOutlet weak var pagerTab: ButtonBarView!
    
    @IBOutlet weak var containerScrollView: UIScrollView!
    
    @IBOutlet weak var bannerImageView: UIImageView!
    
    @IBOutlet weak var displayName: UILabel!
    @IBOutlet weak var usernameLabel: UILabel!
    
    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var introTextView: UITextView!
    
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var containerHeightContraint: NSLayoutConstraint!
    
    private var userId: String?
    private var scrollBegining: CGFloat = 0
    private var tlScrollView: UIScrollView?
    
    private lazy var viewModel: ProfileViewModel = .init()
    private var childVCs: [TimelineViewController] = []
    
    private var maxScroll: CGFloat {
        return pagerTab.frame.origin.y - self.getSafeAreaSize().height - 10 // 10 = 微調整
    }
    
    
    //MARK: Life Cycle
    override public func viewDidLoad() {
        self.setupTabStyle()
        
        super.viewDidLoad()
        
        self.setupComponent()
        self.setupSkeltonMode()
        self.binding()
        self.setBannerBlur()
        
        self.containerScrollView.delegate = self
        self.containerScrollView.contentInsetAdjustmentBehavior = .never
    }
    
//    public override func viewWillLayoutSubviews() {
//        super.viewWillLayoutSubviews()
//
//        //Fix: ここにおくとanimatorの関係でたまに失敗する？ animatorが不当なタイミングで破棄される問題
//        //        self.setBlurAnimator()
//    }
    
    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        self.layoutIfNeeded(to: [iconImageView])
        self.layoutIfNeeded(to: childVCs.map{$0.view})
        self.iconImageView.layer.cornerRadius = self.iconImageView.frame.width / 2
        
        self.containerHeightContraint.constant = 2 * self.view.frame.height - (self.view.frame.height - self.containerScrollView.frame.origin.y)
        
        self.childVCs.forEach { // VCの表示がずれるのを防ぐ(XLPagerTabStripの不具合？？)
            $0.view.frame = CGRect(x:0, y: 0, width: self.view.frame.width, height: $0.view.frame.height)
        }
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if blurAnimator == nil { self.setBlurAnimator() }
    }
    
    
    private func setupComponent() {
        self.backButton.titleLabel?.font = .awesomeSolid(fontSize: 18.0)
        self.backButton.alpha = 0.5
        self.backButton.setTitleColor(.lightGray, for: .normal)
    }
    
    
    //MARK: Public Methods
    public func setUserId(_ userId: String, isMe: Bool) {
        self.userId = userId
        viewModel.setUserId(userId, isMe: isMe)
    }
    
    //MARK: Setup
    private func setupTabStyle() {
        self.settings.style.buttonBarBackgroundColor = .white
        self.settings.style.buttonBarItemBackgroundColor = .white
        self.settings.style.buttonBarItemTitleColor = .black
        self.settings.style.selectedBarBackgroundColor = .systemBlue
        
        self.settings.style.buttonBarItemFont = UIFont.systemFont(ofSize: 15)
        
        self.settings.style.buttonBarHeight = 6
        self.settings.style.selectedBarHeight = 2
        self.settings.style.buttonBarMinimumLineSpacing = 15
        self.settings.style.buttonBarLeftContentInset = 0
        self.settings.style.buttonBarRightContentInset = 0
    }
    
    private func binding() {
        let output = viewModel.output
        
        output.iconImage.drive(onNext: { image in
            self.iconImageView.hideSkeleton()
            self.self.iconImageView.image = image
        }).disposed(by: disposeBag)
        
        output.intro.drive(onNext: { attributedText in
            self.introTextView.hideSkeleton()
            self.introTextView.attributedText = attributedText
        }).disposed(by: disposeBag)
        
        output.bannerImage.drive(self.bannerImageView.rx.image).disposed(by: disposeBag)
        output.displayName.drive(self.displayName.rx.text).disposed(by: disposeBag)
        output.username.drive(self.usernameLabel.rx.text).disposed(by: disposeBag)
        
        self.backButton.isHidden = output.isMe
    }
    
    private func setBannerBlur() {
        let quaterHeight = self.bannerImageView.frame.height / 4
        
        let topColor = UIColor(red:0, green:0, blue:0, alpha:0)
        let bottomColor = UIColor(red:0, green:0, blue:0, alpha:0.7)
        let gradientLayer: CAGradientLayer = CAGradientLayer()
        
        gradientLayer.colors = [topColor.cgColor, bottomColor.cgColor]
        gradientLayer.frame =  CGRect(x: 0,
                                      y: quaterHeight * 2,
                                      width: self.view.frame.width,
                                      height: quaterHeight * 2)
        
        self.bannerImageView.layer.addSublayer(gradientLayer)
    }
    
    private func setBlurAnimator() {
//        let frame = self.introTextView.frame
        
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        blurView.frame = CGRect(x: 0,
                                y: 0,
                                width: self.containerScrollView.frame.width,
                                height: self.maxScroll + self.getSafeAreaSize().height)
        
        blurView.alpha = 0
        self.containerScrollView.addSubview(blurView)
        
        self.blurAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .easeInOut) {
            blurView.alpha = 1
        }
    }
    
    
    //MARk: XLPagerTabStrip
    public override func viewControllers(for pagerTabStripController: PagerTabStripViewController) -> [UIViewController] {
        return self.getChildVC()
    }
    
    
    //MARK: Utilities
    private func getChildVC()-> [UIViewController] {
        guard let userId = userId else { fatalError("Internal Error") }
        
        let userNoteOnly = generateTimelineVC(xlTitle: "Notes", userId: userId, includeReplies: false, onlyFiles: false, scrollable: false)
        let allUserNote = generateTimelineVC(xlTitle: "Notes & Replies", userId: userId, includeReplies: true, onlyFiles: false, scrollable: false)
        let userMedia = generateTimelineVC(xlTitle: "Media", userId: userId, includeReplies: false, onlyFiles: true, scrollable: false)
        
        self.childVCs = [userNoteOnly, allUserNote, userMedia]
        
        return self.childVCs
    }
    
    private func generateTimelineVC(xlTitle: IndicatorInfo, userId: String, includeReplies: Bool, onlyFiles: Bool, scrollable: Bool)-> TimelineViewController {
        guard let viewController = self.getViewController(name: "timeline") as? TimelineViewController else { fatalError("Internal Error.") }
        
        viewController.setup(type: .OneUser,
                             includeReplies: includeReplies,
                             onlyFiles: onlyFiles,
                             userId: userId,
                             withNavBar: false,
                             scrollable: scrollable,
                             xlTitle: xlTitle)
        
        return viewController
    }
    
    private func getViewController(name: String)-> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: name)
        
        return viewController
    }
    
    public override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        super.scrollViewWillBeginDragging(scrollView) //XLPagerTabStripの処理
        
        self.scrollBegining = scrollView.contentOffset.y
    }
    
    public override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView) //XLPagerTabStripの処理
        
        let scroll = scrollView.contentOffset.y - self.scrollBegining
        guard childVCs.count > self.currentIndex,
            let blurAnimator = blurAnimator,
            let tlScrollView = childVCs[self.currentIndex].mainTableView else { return }
        
        
        var needContainerScroll: Bool = true
        // tlScrollViewをスクロール
        if scroll > 0 {
            if containerScrollView.contentOffset.y >= maxScroll {
                tlScrollView.contentOffset.y += scroll
                needContainerScroll = false
            }
        }
        else { // scroll < 0 ...
            let positiveScroll = (-1) * scroll
            if tlScrollView.contentOffset.y >= positiveScroll {
                tlScrollView.contentOffset.y -= positiveScroll
                needContainerScroll = false
            }
        }
        
        //containerScrollViewをスクロール
        if !needContainerScroll {
            scrollView.contentOffset.y = self.scrollBegining
        }
        else {
            // スクロールがmaxScrollの半分を超えたあたりから、fractionComplete: 0→1と動かしてanimateさせる
            let blurProportion = containerScrollView.contentOffset.y * 2 / maxScroll - 1
            self.scrollBegining = scrollView.contentOffset.y
            
             //ブラーアニメーションをかける
            if 0 < blurProportion, blurProportion < 1 {
                blurAnimator.fractionComplete = blurProportion
            }
            else {
                blurAnimator.fractionComplete = blurProportion <= 0 ? 0 : 1
            }
        }
    }
    
    
    //MARK: SkeltonView Utilities
    private func setupSkeltonMode() {
        self.iconImageView.isSkeletonable = true
        self.introTextView.isSkeletonable = true
        self.displayName.text = nil
        self.usernameLabel.text = nil
        
        self.changeSkeltonState(on: true)
    }
    
    
    private func changeSkeltonState(on: Bool) {
        if on {
            self.iconImageView.showAnimatedGradientSkeleton()
            self.introTextView.showAnimatedGradientSkeleton()
        }
        else {
            self.iconImageView.hideSkeleton()
            self.introTextView.hideSkeleton()
        }
    }
}

