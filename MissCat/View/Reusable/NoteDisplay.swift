//
//  NoteDisplay.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/26.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation


/// NoteCell上のタップ処理はすべてHomeViewControllerが行う。
/// そこで、NoteCellを表示するViewControllerはすべて、このNoteDisplayを継承することで、
/// それらのタップ処理は勝手にHomeViewControllerへと流れてくれる。
public class NoteDisplay: UIViewController, NoteCellDelegate {
    public var homeViewController: HomeViewController?
    
    public func tappedReply(note: NoteCell.Model) {
        homeViewController?.tappedReply(note: note)
    }
    
    public func tappedRenote(note: NoteCell.Model) {
        homeViewController?.tappedRenote(note: note)
    }
    
    public func tappedReaction(noteId: String, iconUrl: String?, displayName: String, username: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool) {
        let reactionGen = presentReactionGen(noteId: noteId,
                                             iconUrl: iconUrl,
                                             displayName: displayName,
                                             username: username,
                                             note: note,
                                             hasFile: hasFile,
                                             hasMarked: hasMarked)
    }
    
    public func tappedOthers() {}
    
    public func move2PostDetail(item: NoteCell.Model) {
        homeViewController?.tappedCell(item: item)
    }
    
    public func tappedLink(text: String) {
        homeViewController?.tappedLink(text: text)
    }
    
    public func openUser(username: String) {
        homeViewController?.openUserPage(username: username)
    }
    
    public func move2Profile(userId: String) {
        homeViewController?.move2Profile(userId: userId)
    }
    
    public func updateMyReaction(targetNoteId: String, rawReaction: String, plus: Bool) {}
    
    public func vote(choice: Int, to noteId: String) {
        homeViewController?.vote(choice: choice, to: noteId)
    }
    
    public func playVideo(url: String) {
        homeViewController?.playVideo(url: url)
    }
}
