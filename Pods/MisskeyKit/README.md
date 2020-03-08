<img src="./MisskeyKit/Resources/logo.png" width=100%>

[![License][license-image]][license-url]
[![Swift Version][swift-image]][swift-url]
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/EZSwiftExtensions.svg)](https://img.shields.io/cocoapods/v/LFAlertController.svg)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)


## MisskeyKit for iOS

MisskeyKit is a framework for [Misskey](https://misskey.io) written in swift. You can call Misskey API intuitively.
(日本語は[こちら](https://github.com/YuigaWada/MisskeyKit-for-iOS/blob/master/README_JP.md))


<br>

## Dependencies

- [Starscream](https://github.com/daltoniam/Starscream)
- Swift 5

<br>

## Contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [Installation](#installation)
    - [CocoaPods](#cocoapods)
    - [Manually](#manually)
- [How to use](#how-to-use)
  - [Singleton](#singleton)
  - [How to change Misskey Instance](#how-to-change-misskey-instance)
  - [Authentication](#authentication)
    - [CallBack Pattern](#callback-pattern)
    - [Delegation Pattern](#delegation-pattern)
  - [Authentication (Advanced)](#authentication-advanced)
    - [Get a ```Session Token```](#get-a-session-token)
    - [Get an ```Access Token```](#get-an-access-token)
    - [Get an ```Api Key```](#get-an-api-key)
  - [Recycle Api Key](#recycle-api-key)
  - [How to call API](#how-to-call-api)
  - [Api-Method correspondence table](#api-method-correspondence-table)
  - [Emojis](#emojis)
  - [Streaming API](#streaming-api)
    - [```MisskeyKit.Streaming.connect()```](#misskeykitstreamingconnect)
    - [```MisskeyKit.Streaming.captureNote()```](#misskeykitstreamingcapturenote)
    - [```MisskeyKit.Streaming.isConnected```](#misskeykitstreamingisconnected)
    - [```MisskeyKit.Streaming.stopListening()```](#misskeykitstreamingstoplistening)
  - [```MisskeyKitError```](#misskeykiterror)
- [Contribute](#contribute)
- [Others](#others)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

<br><br>

## Installation

#### CocoaPods
You can use [CocoaPods](http://cocoapods.org/) to install `MisskeyKit` by adding it to your `Podfile`:

```ruby
pod 'MisskeyKit'
```

To get the full benefits,  import `MisskeyKit`

``` swift
import MisskeyKit
```

<!-- #### Carthage
Create a `Cartfile` that lists the framework and run `carthage update`. Follow the [instructions](https://github.com/Carthage/Carthage#if-youre-building-for-ios) to add `$(SRCROOT)/Carthage/Build/iOS/PolioPager.framework` to an iOS project.

```
github "YuigaWada/PolioPager"
``` -->


#### Manually
1. Download and drop ```MisskeyKit``` in your project.  
2. Run ```carthage update```.
2. Congratulations!  

<br><br>

## How to use

### Singleton

MisskeyKit adopts [singleton pattern](https://en.wikipedia.org/wiki/Singleton_pattern), because of keeping account information instead of developers.

So you always have to communicate with MisskeyKit via the following instances.

```swift
open class MisskeyKit {
  static public let auth: Auth
  static public var notes: Notes
  static public var users: Users
  static public var groups: Groups
  static public var lists: Lists
  static public var search: Search
  static public var notifications: Notifications
  static public var meta: Meta
```

<br>

### How to change Misskey Instance

To change Misskey Instance, use  ```MisskeyKit.changeInstance()```.

```swift
MisskeyKit.changeInstance(instance: "misskey.dev")

```

<br>


### Authentication

There are 5 native steps for authentication.

1. Access to [Developer Center](https://misskey.io/dev) and Get ```Secret Key``` (aka ```appSecret```).
2. Get a ```Session Token```.
3. User authenticates via safari.
4. Get an ```Access Token```.
5. Finally, Get an ```Api Key``` !


<br>

**On the other hand, MisskeyKit is tooooo simple.**

All you need is setup and present ```MisskeyKit.auth.viewController``` , which launchs browser for authentication and does tedious process instead of you.

Additionally, You can choose whether to use callback pattern or delegation pattern!

<br>

#### CallBack Pattern

```swift
MisskeyKit.auth.appSecret = "Enter your Secret Key"

let authVC = MisskeyKit.auth.viewController
authVC.resultApiKey() { apiKey in

    guard let apiKey = apiKey else { return }
    print(apiKey) // u can get uesr's apikey.

}

self.present(authVC, animated: true)
```


#### Delegation Pattern

```swift
class ViewController: UIViewController, AuthViewControllerDelegate {

  func something() {
      MisskeyKit.auth.appSecret = "Enter your Secret Key"

      let authVC = MisskeyKit.auth.viewController
      authVC.delegate = self

      self.present(authVC, animated: true)
  }

  //....

  func resultApiKey(_ apiKey: String?) { // Need: AuthViewControllerDelegate
      guard let apiKey = apiKey else { return }

      print(apiKey) // u can get uesr's apikey.
  }

```

<br><br>

### Authentication (Advanced)

You can also call API of Authentication in the right order.


#### Get a ```Session Token```

```swift
MisskeyKit.auth.startSession(appSecret: "Enter your appSecret") { auth, error in
    guard let auth = auth, let token = auth.token, error == nil else { /* Error */ return }

    print(token) // u got a Session Token.
}
```

<br>

After getting, you need to let your user authenticate via safari.

For example,

```swift
MisskeyKit.auth.startSession(appSecret: "Enter your appSecret") { auth, error in
    guard let auth = auth, let token = auth.token, error == nil else { /* Error */ return }

    print(token) // u got a Session Token.

    guard let url = URL(string: token.url) else { /* Error */ return }
    DispatchQueue.main.async {
      if UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url)
      }
    }
}
```


#### Get an ```Access Token```

```swift
MisskeyKit.auth.getAccessToken() { auth, error in
    guard let auth = auth, error == nil else { return }

    print(auth.me) // u got a Session Token.
}
```


#### Get an ```Api Key```

```swift
// If u get user's Access Token correctly, u can get Api key.
guard let apikey = MisskeyKit.auth.getAPIKey() else {

      /* Error */

}

```

<br><br>

### Recycle Api Key

If wanting to recycle user's api key, you have to send it to MisskeyKit so use  ```MisskeyKit.auth.setAPIKey()```.

```swift
MisskeyKit.auth.setAPIKey("Enter saved api key!")

```

<br><br>

### How to call API

Look into my code of MisskeyKit and see how to describe.

Oh, it's too much hassle? Hmmm... Okay, I'll give you three examples.

<br>

For example, if you wanna post a note, check the following code.

(Once you get or set user's api key, you don't have to send Api key to each methods.)

<br>

```swift

 // Type of the first parameter "posts" will change according to purpose of methods you use.
 // In this method, type is NoteModel. You can see model class in "./MisskeyKit/APIs/Model".

 MisskeyKit.notes.createNote(text: "Enter some text!") { posts, error in  
            guard let posts = posts, error == nil else { /* Error */ return }

            // MisskeyKit.notes.createNote returns information of your post that you've just posted.
            // The fact itself that you receive it means that your request was accepted successfully.

            print(posts)
}
```

Second Example: If you wanna get one hundred notes from user's timeline, write like this code.

```swift
MisskeyKit.notes.getTimeline(limit: 100) { posts, error in
            guard let posts = posts, error == nil else { /* Error */ return }

            print(posts) // You can check 100 notes if your request was accepted successfully.
}
```


Final Example: ```MisskeyKit.drive.createFile``` , which is a method for "drive/create" api.

When using ```MisskeyKit.drive.createFile```, you always have to add fileType. (fileType is expected to be [MIME type](https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types/Complete_list_of_MIME_types).)


```swift
MisskeyKit.drive.createFile(fileData: targetImage, fileType: "image/jpeg", name: UUID().uuidString + ".jpeg", isSensitive: false, force: false) { result, error in
    guard let result = result, error == nil else { return }

    print(result.id)
}
```

<br><br><br>


### Api-Method correspondence table

|Misskey API|MisskeyKit Methods|
|---|---|
|users/show|Users.showUser|
|i|Users.i|
|i/favorites|Users.getAllFavorites|
|i/page-likes|Users.getLikedPages|
|i/pages|Users.getMyPages|
|i/update|Users.updateMyAccount|
|i/pin|Users.pin|
|i/unpin|Users.unpin|
|following/create|Users.follow|
|following/delete|Users.unfollow|
|users/followers|Users.getFollowers|
|users/following|Users.getFollowing|
|users/get-frequently-replied-users|Users.getFrequentlyRepliedUsers|
|users/relation|Users.getUserRelationship|
|blocking/create|Users.block|
|blocking/delete|Users.unblock|
|blocking/list|Users.getBlockingList|
|users/report-abuse|Users.reportAsAbuse|
|users/recommendation|Users.getUserRecommendation|
|following/requests/accept|Users.acceptFollowRequest|
|following/requests/cancel|Users.cancelFollowRequest|
|following/requests/reject|Users.rejectFollowRequest|
|notes|Notes.getAllNotes|
|notes/show|Notes.showNote|
|notes/conversation|Notes.getConversation, Notes.getChildren|
|users/notes|Notes.getUserNotes|
|notes/mentions|Notes.getMentionsForMe|
|notes/timeline|Notes.getTimeline|
|notes/global-timeline|Notes.getGlobalTimeline|
|notes/hybrid-timeline|Notes.getHybridTimeline|
|notes/local-timeline|Notes.getLocalTimeline|
|notes/user-list-timeline|Notes.getUserListTimeline|
|notes/featured|Notes.getFeatured|
|notes/create|Notes.createNote, Notes.renote|
|notes/delete|Notes.deletePost|
|notes/favorites/create|Notes.createFavorite|
|notes/favorites/delete|Notes.deleteFavorite|
|notes/reactions|Notes.getReactions|
|notes/reactions/create|Notes.createReaction|
|notes/reactions/delete|Notes.deleteReaction|
|notes/renotes|Notes.getRenotes|
|notes/unrenote|Notes.unrenote|
|notes/replies|Notes.getReplies|
|notes/watching/create|Notes.watchNote|
|notes/watching/delete|Notes.unWatchNote|
|i/read-all-unread-notes|Notes.readAllUnreadNotes|
|notes/polls/vote|Notes.vote|
|auth/session/generate|Auth.startSession|
|meta|Meta.get|
|users/groups/invitations/accept|Groups.acceptInvitation|
|users/groups/invitations/reject|Groups.rejectInvitation|
|users/groups/invite|Groups.invite|
|users/groups/pull|Groups.pullUser|
|users/groups/transfer|Groups.transferUser|
|mute/create|Mute.create|
|mute/delete|Mute.delete|
|mute/list|Mute.getList|
|drive/files/attached-notes|Drive.getAttachedNotes|
|drive/files/delete|Drive.deleteFile|
|drive/files/update|Drive.updateFile|
|drive/files/upload-from-url|Drive.uploadFileFromUrl|
|drive/folders/delete|Drive.deleteFolder|
|drive/folders/update|Drive.updateFolder|
|users/lists/pull|Lists.pullUser|
|users/lists/push|Lists.pushUser|
|users/lists/create|Lists.create|
|users/lists/delete|Lists.delete|
|users/lists/show|Lists.show|
|users/lists/list|Lists.getMyLists|
|users/lists/update|Lists.update|
|i/read-all-messaging-messages|Messaging.readAllMessaging|
|messaging/history|Messaging.getHistory|
|messaging/messages|Messaging.getMessageWithUser, Messaging.create|
|messaging/messages/delete|Messaging.delete|
|messaging/messages/read|Messaging.read|
|users/search|Search.user|
|notes/search|Search.notes|
|notes/search-by-tag|Search.notesByTag|
|i/notifications|Notificaitons.get|
|notifications/mark-all-as-read|Notificaitons.markAllAsRead|





<br><br>


### Emojis

Misskey Instances have their own custom emojis and user can use them for reactions and posts.

Sometimes, however, data of user's posts(notes) and reactions that Misskey server sent to us don't contain information of custom emojis user used.

Moreover, if you want to develop stuff like emoji pickers, you have to get default and custom emojis data.

So MisskeyKit provides some methods for getting default / custom emojis data.

```swift
MisskeyKit.Emojis.getDefault{ result in
guard let result = result else { /* Error */ return }

   dump(result) // you can see information of default emojis
}
```

```swift
MisskeyKit.Emojis.getCustom{ result in
guard let result = result else { /* Error */ return }

   dump(result) // you can see information of custom emojis
}
```

Once you get information of emojis from Misskey Instance server, MisskeyKit keeps the data unless user killing your app.

Hence you don't have to communicate with Misskey Instance Server many times and overhead will be reduced.




<br><br>

### Streaming API

MisskeyKit also provides wrapper of a [```streaming API```](https://misskey.io/docs/ja-JP/stream) as well as REST API!


(```Streaming API``` is a subscription mechanism for binding client to server so that you can receive events **in near real time**.)

<br>

```Streaming API``` adopts not HTTP protocol but WebSocket, so you need to connect to server by other methods.

However it's so easy to connect via WebSocket by MisskeyKit !　

<br>

#### ```MisskeyKit.Streaming.connect()```


All you have to do is just use ```MisskeyKit.Streaming.connect()``` !

(```MisskeyKit.Streaming``` does not provide singleton instance, so you have to generate instance yourself.)

```swift
guard let apiKey = MisskeyKit.auth.getAPIKey() else { return }

let streaming = MisskeyKit.Streaming() // u have to generate instance yourself.
streaming.connect(apiKey: apiKey, channels: [.main, .homeTimeline]) { response, channel, type, error in

        // Do something ...

        //apiKey: Your Api Key.
        //channels: [SentStreamModel.Channel] Type / channels which you wanna connect to.

        //This closure captures and sends you events through channels which you subscribed.
        //response: Any? Type / events itself. You have to cast it according to type(third params of callback).
        //channel: SentStreamModel.Channel? Type / shows which channel sent events.
        //type: String? Type / shows what kind of events was sent. You'll use it to cast response.
        //error: Error? Type / If something wrong happens, error is sent

}

```
<br><br>

#### ```MisskeyKit.Streaming.captureNote()```

Even if you use ```MisskeyKit.Streaming.connect()``` and listen to events, there are some notes you cannot receive.

For these notes, you have to call API that provides you capturing functions.(Click [here](https://misskey.io/docs/ja-JP/stream) for details.)

<br>

If you wanna capture some notes, use ```MisskeyKit.Streaming.captureNote()```

```swift
do {
  try streaming.captureNote(noteId: "Enter note Id.")
}
catch {
   /* Error */
}
```

Once you capture a note, each events related to the note will sent to your callback method of ```MisskeyKit.streaming.connect()```.

<br><br>

#### ```MisskeyKit.Streaming.isConnected```

This variable enables us to check whether streaming is connected now.

```swift
guard streaming.isConnected else { return }

// Good.
```

<br><br>

#### ```MisskeyKit.Streaming.stopListening()```

If you want to disconnect specific channel, use ```MisskeyKit.Streaming.stopListening()```.


```swift
streaming.stopListening(channnel: SentStreamModel.Channel)
streaming.stopListening(channnels: [SentStreamModel.Channel])
streaming.stopListening(noteId: String)
streaming.stopListening(noteIds: [String])
```


<br><br>


### ```MisskeyKitError```

MisskeyKit has own Error enumeration so that we could handle some error flexibility.

```swift
public enum MisskeyKitError: Error {

    //These Error are corresponded to error codes sent by Misskey server.

    //400
    case ClientError

    //401
    case AuthenticationError

    //403
    case ForbiddonError

    //418
    case ImAI

    //429
    case TooManyError

    //500
    case InternalServerError



    //These Error are related to internal error.

    case CannotConnectStream

    case NoStreamConnection

    case FailedToDecodeJson

    case FailedToCommunicateWithServer

    case UnknownTypeResponse

    case ResponseIsNull
}
```

<br><br>


## Contribute

We would love you for the contribution to **MisskeyKit**, check the ``LICENSE`` file for more info.



## Others

Yuiga Wada -  [WebSite](https://yuiga.dev)
Twitter         - [@YuigaWada](https://twitter.com/YuigaWada)





Distributed under the MIT license. See ``LICENSE`` for more information.

[https://github.com/YuigaWada/MisskeyKit-for-iOS](https://github.com/YuigaWada/MisskeyKit-for-iOS)




[swift-image]:https://img.shields.io/badge/swift-5.0-orange.svg
[swift-url]: https://swift.org/
[license-image]: https://img.shields.io/badge/License-MIT-blue.svg
[license-url]: LICENSE
[codebeat-image]: https://codebeat.co/badges/c19b47ea-2f9d-45df-8458-b2d952fe9dad
[codebeat-url]: https://codebeat.co/projects/github-com-vsouza-awesomeios-com
