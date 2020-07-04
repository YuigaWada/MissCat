const fcmNode = require('fcm-node');
const serverKey = require('./key/fcm_private_key.json');
const fcm = new fcmNode(serverKey);

exports.generateContents = function(rawJson, lang) {
  const json = JSON.parse(rawJson);
  const body = json.body;
  if (json.type != "notification") { return [null,null]; }

  const type = body.type;
  const fromUser = body.user.name != null ? body.user.name : body.user.username;

  var title;
  var messages;
  var extra = generateExtraContents(body); // アプリ内通知で利用するデータ

  // cf. https://github.com/YuigaWada/MissCat/blob/develop/MissCat/Model/Main/NotificationModel.swift

  if (type == "reaction") {
    const reaction = body.reaction;
    const myNote = body.note.text;

    title = fromUser + "さんがリアクション: \"" + reaction+ "\"";
    message = myNote;
  }
  else if (type == "follow") {
    const hostLabel = body.user.host != null ? "@" + body.user.host : ""; // 自インスタンスの場合 host == nullになる
    title = "";
    message = "@" + body.user.username + hostLabel + "さんに" + "フォローされました";
  }
  else if (type == "reply" || type == "mention") {
    title = fromUser + "さんの返信:";
    message = body.note.text;
  }
  else if (type == "renote" || type == "quote") {
    const justRenote = body.note.text == null; // 引用RNでなければ body.note.text == null
    var renoteKind = justRenote ? "" : "引用";

    title = fromUser + "さんが" + renoteKind + "Renoteしました";
    message = justRenote ? body.note.renote.text : body.note.text;
  }
  else { return [null,null,null]; }

  return [title,message,extra];
}


exports.send = function (token, title, body, extra) {
  // cf. https://www.npmjs.com/package/fcm-node

  var message = {
     to: token,

     notification: {
         title: title,
         body: body,
         badge: "1"
     }
  };

  // アプリ内通知で利用するデータをペイロードに積む
  if(extra){
    message.data = extra
  }

  fcm.send(message, function(error, response){
      const success = error == null
      if (!success) {
         console.log("FCM Error:",error);
      }
  });
}


// アプリ内通知で利用するデータを適切なフォーマットに変換しておく
function generateExtraContents(body) {
    const id = body.id;

    // TODO: 宛先のユーザーを識別するためにはuserIdが必要なのでapi.jsから持ってくる
    return {
      notification_id: id
    }
}