//
//  NoteDisplay.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/26.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Foundation
import UIKit

/// NoteCell上のタップ処理はすべてHomeViewControllerが行う。
/// そこで、NoteCellを表示するViewControllerはすべて、このNoteDisplayを継承することで、
/// それらのタップ処理は勝手にHomeViewControllerへと流れてくれる。
class NoteDisplay: UIViewController, NoteCellDelegate, UserCellDelegate {
    var homeViewController: HomeViewController?
    
    func tappedReply(note: NoteCell.Model) {
        homeViewController?.tappedReply(note: note)
    }
    
    func tappedRenote(note: NoteCell.Model) {
        homeViewController?.tappedRenote(note: note)
    }
    
    func tappedReaction(reactioned: Bool, noteId: String, iconUrl: String?, displayName: String, username: String, hostInstance: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool, myReaction: String?) {
        _ = presentReactionGen(noteId: noteId,
                               iconUrl: iconUrl,
                               displayName: displayName,
                               username: username,
                               hostInstance: hostInstance,
                               note: note,
                               hasFile: hasFile,
                               hasMarked: hasMarked,
                               navigationController: nil)
    }
    
    func tappedOthers(note: NoteCell.Model) {
        homeViewController?.tappedOthers(note: note)
    }
    
    func move2PostDetail(item: NoteCell.Model) {
        homeViewController?.tappedCell(item: item)
    }
    
    func tappedLink(text: String, owner: SecureUser) {
        homeViewController?.tappedLink(text: text, owner: owner)
    }
    
    func openUser(username: String, owner: SecureUser) {
        homeViewController?.openUserPage(username: username, owner: owner)
    }
    
    func move2Profile(userId: String, owner: SecureUser) {
        homeViewController?.move2Profile(userId: userId, owner: owner)
    }
    
    func updateMyReaction(targetNoteId: String, rawReaction: String, plus: Bool) {}
    
    func vote(choice: [Int], to noteId: String) {
        homeViewController?.vote(choice: choice, to: noteId)
    }
    
    func showImage(_ urls: [URL], start startIndex: Int) {
        homeViewController?.showImage(urls, start: startIndex)
    }
    
    func playVideo(url: String) {
        homeViewController?.playVideo(url: url)
    }
}
