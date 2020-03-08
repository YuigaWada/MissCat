//  CallbackTypealias.swift
//  MisskeyKit
//
//  Created by Yuiga Wada on 2019/11/05.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//


public typealias AuthCallBack = (MisskeyKit.Auth?, MisskeyKitError?)->Void
public typealias BooleanCallBack = (Bool, MisskeyKitError?)->Void
public typealias OneNoteCallBack = (NoteModel?, MisskeyKitError?)->Void
public typealias NotesCallBack = ([NoteModel]?, MisskeyKitError?)->Void

public typealias OneUserCallBack = (UserModel?, MisskeyKitError?)->Void
public typealias UsersCallBack = ([UserModel]?, MisskeyKitError?)->Void

public typealias OneUserRelationshipCallBack = (UserRelationship?, MisskeyKitError?)->Void
public typealias UserRelationshipsCallBack = ([UserRelationship]?, MisskeyKitError?)->Void

public typealias ReactionsCallBack = ([ReactionModel]?, MisskeyKitError?)->Void

public typealias NotificationsCallBack = ([NotificationModel]?, MisskeyKitError?)->Void

public typealias OneMessageCallBack = (MessageModel?, MisskeyKitError?)->Void
public typealias MessagesCallBack = ([MessageModel]?, MisskeyKitError?)->Void

public typealias MutesCallBack = ([MuteModel]?, MisskeyKitError?)->Void

public typealias ListCallBack = (ListModel?, MisskeyKitError?)->Void
public typealias ListsCallBack = ([ListModel]?, MisskeyKitError?)->Void

public typealias PagesCallBack = ([PageModel]?, MisskeyKitError?)->Void

public typealias BlockListCallBack = ([BlockList]?, MisskeyKitError?)->Void

public typealias MetaCallBack = (MetaModel?, MisskeyKitError?)->Void
public typealias AppCallBack = (AppModel?, MisskeyKitError?)->Void
