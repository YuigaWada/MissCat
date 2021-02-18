//
//  ChatViewController.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/04/16.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import InputBarAccessoryView
import MessageKit
import RxCocoa
import RxSwift
import UIKit

class ChatViewController: MessagesViewController, MessagesDataSource {
    // MARK: Input
    
    var sendCompleted: Binder<Bool> {
        return Binder(self) { vc, _ in
            vc.endSendAnimation()
        }
    }
    
    var messages: Binder<[DirectMessage]> { // こいつをDirectMessageViewControllerからbindするだけ
        return Binder(self) { vc, value in
            let initialLoad = vc.messageList.count == 0
            
            vc.messageList = value
            if initialLoad {
                vc.messagesCollectionView.reloadData()
                vc.messagesCollectionView.scrollToBottom()
            } else {
                vc.messagesCollectionView.reloadDataAndKeepOffset()
            }
        }
    }
    
    var loadTrigger: PublishRelay<Void> = .init()
    var sendTrigger: PublishRelay<String> = .init()
    var tapTrigger: PublishRelay<HyperLink> = .init()
    
    // MARK: Privates
    
    fileprivate lazy var mainColor = getMainColor()
    fileprivate var messageList: [DirectMessage] = []
    let refreshControl = UIRefreshControl()
    let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureMessageCollectionView()
        configureMessageInputBar()
        setupColor()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
//        becomeFirstResponder()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    private func getMainColor() -> UIColor {
        guard let model = Theme.shared.currentModel else { return .systemBlue }
        return UIColor(hex: model.mainColorHex)
    }
    
    // MARK: For Overrides
    
    func endRefreshing() {
        DispatchQueue.main.async {
            self.refreshControl.endRefreshing()
        }
    }
    
    @objc func loadMoreMessages() {
        loadTrigger.accept(())
    }
    
    // MARK: - Helpers
    
    func sendMessage(text: String) {
        sendTrigger.accept(text)
    }
    
    // MARK: Setup
    
    private func setupColor() {
        guard let flowLayout = messagesCollectionView.collectionViewLayout as? MessagesCollectionViewFlowLayout,
              let colorPattern = Theme.shared.currentModel?.colorPattern.ui else { return }
        
        flowLayout.collectionView?.backgroundColor = colorPattern.base
        messageInputBar.inputTextView.textColor = colorPattern.sub0
        messageInputBar.inputTextView.backgroundColor = colorPattern.sub2
        messageInputBar.backgroundView.backgroundColor = colorPattern.sub2
    }
    
    func configureMessageCollectionView() {
        messagesCollectionView.messagesDataSource = self
        messagesCollectionView.messageCellDelegate = self
        messagesCollectionView.messagesLayoutDelegate = self
        messagesCollectionView.messagesDisplayDelegate = self
        
        scrollsToBottomOnKeyboardBeginsEditing = true // default false
        maintainPositionOnKeyboardFrameChanged = true // default false
        
        messagesCollectionView.addSubview(refreshControl)
        refreshControl.addTarget(self, action: #selector(loadMoreMessages), for: .valueChanged)
    }
    
    func configureMessageInputBar() {
        messageInputBar.delegate = self
        messageInputBar.inputTextView.tintColor = mainColor
        messageInputBar.sendButton.setTitleColor(mainColor, for: .normal)
    }
    
    func isLastSectionVisible() -> Bool {
        guard !messageList.isEmpty else { return false }
        
        let lastIndexPath = IndexPath(item: 0, section: messageList.count - 1)
        
        return messagesCollectionView.indexPathsForVisibleItems.contains(lastIndexPath)
    }
    
    // MARK: - MessagesDataSource
    
    func currentSender() -> SenderType {
        let myId = Cache.UserDefaults.shared.getCurrentUser()?.userId ?? ""
        return DirectMessage.User(senderId: myId,
                                  displayName: "",
                                  iconUrl: "")
    }
    
    func numberOfSections(in messagesCollectionView: MessagesCollectionView) -> Int {
        return messageList.count
    }
    
    func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
        return messageList[indexPath.section]
    }
    
    func cellTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        if indexPath.section % 3 == 0 {
            return NSAttributedString(string: MessageKitDateFormatter.shared.string(from: message.sentDate), attributes: [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 10), NSAttributedString.Key.foregroundColor: UIColor.darkGray])
        }
        return nil
    }
    
    func cellBottomLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        guard let message = message as? DirectMessage else { return nil }
        
        return message.isRead ? NSAttributedString(string: "Read", attributes: [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 10), NSAttributedString.Key.foregroundColor: mainColor]) : nil
    }
    
    func messageTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        let name = message.sender.displayName
        return NSAttributedString(string: name, attributes: [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .caption1)])
    }
    
    func messageBottomLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        let ago = calculateAgo(message.sentDate)
        return nil
    }
    
    private func calculateAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyy-MM-dd"
        
        return interval.toAgo() ?? formatter.string(from: date)
    }
}

class DirectMessage: MessageType {
    struct User: SenderType, Equatable {
        var senderId: String
        var displayName: String
        var iconUrl: String
        
        func getAvatar(completion: @escaping (Avatar?) -> Void) {
            iconUrl.toUIImage {
                completion(Avatar(image: $0, initials: ""))
            }
        }
        
        static var me: User = {
            let myId = Cache.UserDefaults.shared.getCurrentUser()?.userId ?? UUID().uuidString
            return .init(senderId: myId,
                         displayName: "",
                         iconUrl: "")
        }()
        
        static var mock: User = {
            let id = (0 ... 2000).randomElement()?.description ?? "test"
            return .init(senderId: id, displayName: "user\(id)", iconUrl: "")
        }()
    }
    
    var messageId: String
    var sender: SenderType {
        return user
    }
    
    var sentDate: Date
    var kind: MessageKind
    
    var user: User
    var isRead: Bool = false
    
    private init(kind: MessageKind, user: User, messageId: String, date: Date) {
        self.kind = kind
        self.user = user
        self.messageId = messageId
        sentDate = date
    }
    
    convenience init(custom: Any?, user: User, messageId: String, date: Date) {
        self.init(kind: .custom(custom), user: user, messageId: messageId, date: date)
    }
    
    convenience init(text: String, user: User, messageId: String, date: Date) {
        self.init(kind: .text(text), user: user, messageId: messageId, date: date)
    }
    
    convenience init(attributedText: NSAttributedString, user: User, messageId: String, date: Date) {
        self.init(kind: .attributedText(attributedText), user: user, messageId: messageId, date: date)
    }
    
    convenience init(image: UIImage, user: User, messageId: String, date: Date) {
        let mediaItem = ImageMediaItem(image: image)
        self.init(kind: .photo(mediaItem), user: user, messageId: messageId, date: date)
    }
    
    convenience init(thumbnail: UIImage, user: User, messageId: String, date: Date) {
        let mediaItem = ImageMediaItem(image: thumbnail)
        self.init(kind: .video(mediaItem), user: user, messageId: messageId, date: date)
    }
    
    convenience init(emoji: String, user: User, messageId: String, date: Date) {
        self.init(kind: .emoji(emoji), user: user, messageId: messageId, date: date)
    }
    
    func changeReadStatus(read: Bool) {
        isRead = read
    }
}

extension DirectMessage {
    private struct ImageMediaItem: MediaItem {
        var url: URL?
        var image: UIImage?
        var placeholderImage: UIImage
        var size: CGSize
        
        init(image: UIImage) {
            self.image = image
            size = CGSize(width: 240, height: 240)
            placeholderImage = UIImage()
        }
    }
}

// MARK: - MessageCellDelegate

extension ChatViewController: MessageCellDelegate {
    func didTapAvatar(in cell: MessageCollectionViewCell) {
        print("Avatar tapped")
    }
    
    func didTapMessage(in cell: MessageCollectionViewCell) {
        print("Message tapped")
    }
    
    func didTapImage(in cell: MessageCollectionViewCell) {
        print("Image tapped")
    }
    
    func didTapCellTopLabel(in cell: MessageCollectionViewCell) {
        print("Top cell label tapped")
    }
    
    func didTapCellBottomLabel(in cell: MessageCollectionViewCell) {
        print("Bottom cell label tapped")
    }
    
    func didTapMessageTopLabel(in cell: MessageCollectionViewCell) {
        print("Top message label tapped")
    }
    
    func didTapMessageBottomLabel(in cell: MessageCollectionViewCell) {
        print("Bottom label tapped")
    }
    
    //
    //    func didTapPlayButton(in cell: AudioMessageCell) {
    //        guard let indexPath = messagesCollectionView.indexPath(for: cell),
    //            let message = messagesCollectionView.messagesDataSource?.messageForItem(at: indexPath, in: messagesCollectionView) else {
    //                print("Failed to identify message when audio cell receive tap gesture")
    //                return
    //        }
    //        guard audioController.state != .stopped else {
    //            // There is no audio sound playing - prepare to start playing for given audio message
    //            audioController.playSound(for: message, in: cell)
    //            return
    //        }
    //        if audioController.playingMessage?.messageId == message.messageId {
    //            // tap occur in the current cell that is playing audio sound
    //            if audioController.state == .playing {
    //                audioController.pauseSound(for: message, in: cell)
    //            } else {
    //                audioController.resumeSound()
    //            }
    //        } else {
    //            // tap occur in a difference cell that the one is currently playing sound. First stop currently playing and start the sound for given message
    //            audioController.stopAnyOngoingPlaying()
    //            audioController.playSound(for: message, in: cell)
    //        }
    //    }
    
    func didStartAudio(in cell: AudioMessageCell) {
        print("Did start playing audio sound")
    }
    
    func didPauseAudio(in cell: AudioMessageCell) {
        print("Did pause audio sound")
    }
    
    func didStopAudio(in cell: AudioMessageCell) {
        print("Did stop audio sound")
    }
    
    func didTapAccessoryView(in cell: MessageCollectionViewCell) {
        print("Accessory view tapped")
    }
}

// MARK: - MessageLabelDelegate

extension ChatViewController: MessageLabelDelegate {
    struct HyperLink {
        let value: String
        let type: Type
        
        enum `Type` {
            case url
            case hashtag
            case mention
        }
    }
    
    func didSelectURL(_ url: URL) {
        let link: HyperLink = .init(value: url.absoluteString, type: .url)
        tapTrigger.accept(link)
    }
    
    func didSelectHashtag(_ hashtag: String) {
        let link: HyperLink = .init(value: hashtag, type: .hashtag)
        tapTrigger.accept(link)
    }
    
    func didSelectMention(_ mention: String) {
        let link: HyperLink = .init(value: mention, type: .mention)
        tapTrigger.accept(link)
    }
}

// MARK: - MessageInputBarDelegate

extension ChatViewController: InputBarAccessoryViewDelegate {
    func inputBar(_ inputBar: InputBarAccessoryView, didPressSendButtonWith text: String) {
        // Here we can parse for which substrings were autocompleted
        let attributedText = messageInputBar.inputTextView.attributedText!
        let range = NSRange(location: 0, length: attributedText.length)
        attributedText.enumerateAttribute(.autocompleted, in: range, options: []) { _, range, _ in
            
            let substring = attributedText.attributedSubstring(from: range)
            let context = substring.attribute(.autocompletedContext, at: 0, effectiveRange: nil)
            print("Autocompleted: `", substring, "` with context: ", context ?? [])
        }
        
        let components = inputBar.inputTextView.components
        messageInputBar.inputTextView.text = String()
        messageInputBar.invalidatePlugins()
        
        // Send button activity animation
        messageInputBar.sendButton.startAnimating()
        messageInputBar.inputTextView.placeholder = "Sending..."
        
        sendMessages(components)
    }
    
    private func endSendAnimation() {
        DispatchQueue.main.async { [weak self] in
            self?.messageInputBar.sendButton.stopAnimating()
            self?.messageInputBar.inputTextView.placeholder = "Aa"
            self?.messagesCollectionView.scrollToBottom(animated: true)
        }
    }
    
    private func sendMessages(_ data: [Any]) {
        for component in data {
            if let str = component as? String {
                sendMessage(text: str)
            } else if let img = component as? UIImage {}
        }
    }
}

// MARK: - MessagesDisplayDelegate

extension ChatViewController: MessagesDisplayDelegate {
    // MARK: - Text Messages
    
    func textColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return isFromCurrentSender(message: message) ? .white : .darkText
    }
    
    func detectorAttributes(for detector: DetectorType, and message: MessageType, at indexPath: IndexPath) -> [NSAttributedString.Key: Any] {
        switch detector {
        case .hashtag, .mention, .url: return [.underlineStyle: NSUnderlineStyle.single.rawValue]
        default: return MessageLabel.defaultAttributes
        }
    }
    
    func enabledDetectors(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> [DetectorType] {
        return [.url, .mention, .hashtag]
    }
    
    // MARK: - All Messages
    
    func backgroundColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return isFromCurrentSender(message: message) ? mainColor : UIColor(red: 230 / 255, green: 230 / 255, blue: 230 / 255, alpha: 1)
    }
    
    func messageStyle(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageStyle {
        let tail: MessageStyle.TailCorner = isFromCurrentSender(message: message) ? .bottomRight : .bottomLeft
        return .bubbleTail(tail, .curved)
    }
    
    func configureAvatarView(_ avatarView: AvatarView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        guard let sender = message.sender as? DirectMessage.User else { return }
        sender.getAvatar { avatar in
            guard let avatar = avatar else { return }
            DispatchQueue.main.async {
                avatarView.set(avatar: avatar)
            }
        }
    }
    
    //    // MARK: - Location Messages
    //
    //    func annotationViewForLocation(message: MessageType, at indexPath: IndexPath, in messageCollectionView: MessagesCollectionView) -> MKAnnotationView? {
    //        let annotationView = MKAnnotationView(annotation: nil, reuseIdentifier: nil)
    //        let pinImage = #imageLiteral(resourceName: "misskey")
    //        annotationView.image = pinImage
    //        annotationView.centerOffset = CGPoint(x: 0, y: -pinImage.size.height / 2)
    //        return annotationView
    //    }
    //
    //    func animationBlockForLocation(message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> ((UIImageView) -> Void)? {
    //        return { view in
    //            view.layer.transform = CATransform3DMakeScale(2, 2, 2)
    //            UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [], animations: {
    //                view.layer.transform = CATransform3DIdentity
    //            }, completion: nil)
    //        }
    //    }
    //
    //    func snapshotOptionsForLocation(message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> LocationMessageSnapshotOptions {
    //
    //        return LocationMessageSnapshotOptions(showsBuildings: true, showsPointsOfInterest: true, span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10))
    //    }
}

// MARK: - MessagesLayoutDelegate

extension ChatViewController: MessagesLayoutDelegate {
    func cellTopLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return 18
    }
    
    func cellBottomLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return 17
    }
    
    func messageTopLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return 20
    }
    
    func messageBottomLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return 8
    }
}
