const fcmNode = require('fcm-node');
const serverKey = require('./key/fcm_private_key.json');
const fcm = new fcmNode(serverKey);

exports.generateContents = function(rawJson, lang) {
  const json = JSON.parse(rawJson);
  const body = json.body;
  if (json.type != "notification") { return null; }

  const type = body.type;
  const fromUser = body.user.name != null ? body.user.name : body.user.username;

  // cf. https://github.com/YuigaWada/MissCat/blob/develop/MissCat/Model/Main/NotificationModel.swift
  if (type == "reaction") {
    const reaction = body.reaction;
    const myNote = body.note.text;

    var title = fromUser + "さんがリアクション\"" + reaction+ "\"を送信しました";
    var message = myNote;
    return [title,message];
  }
  else if (type == "follow") {
    const hostLabel = body.user.host != null ? "@" + body.user.host : ""; // 自インスタンスの場合 host == nullになる
    var title = "";
    var message = "@" + body.user.username + hostLabel + "さんに" + "フォローされました";
    return [title,message];
  }
  else if (type == "reply") {
    var title = fromUser + "さんの返信:";
    var message = body.note.text;
    return [title,message];
  }
  else if (type == "renote" || type == "quote") {
    const justRenote = body.note.text == null; // 引用RNでなければ body.note.text == null
    var renoteKind = justRenote ? "" : "引用";

    var title = fromUser + "さんが" + renoteKind + "Renoteしました";
    var message = justRenote ? body.note.renote.text : body.note.text;
    return [title,message];
  }

  return [null,null]
}


exports.send = function (token, title, body) {
  var message = {
     to: token,
     // collapse_key: key,

     notification: {
         title: title,
         body: body,
         badge: "1"
     }
  };

  fcm.send(message, function(error, response){
      const success = error == null
      if (!success) {
         console.log("FCM Error:",error);
      }
  });
}
