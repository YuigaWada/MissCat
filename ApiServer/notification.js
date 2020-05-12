const fcmNode = require('fcm-node');
const serverKey = require('./key/fcm_private_key.json');
const fcm = new fcmNode(serverKey);

exports.generateContents = function(rawJson, lang) {
  const json = JSON.parse(rawJson);
  const body = json.body;
  if (json.type != "notification") { return null; }

  const type = body.type;
  const fromUser = body.user.username // + "@" + body.user.host;

  // cf. https://github.com/YuigaWada/MissCat/blob/develop/MissCat/Model/Main/NotificationModel.swift
  if (type == "reaction") {
    const reaction = body.reaction;
    const myNote = body.note.text;

    var title = fromUser + "さんがリアクション\"" + reaction+ "\"を送信しました";
    var message = myNote;

    return [title,message];
  }
  else if (type == "follow") {
    var title = "";
    var message = fromUser + "さんが" + "フォローしました";

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
         body: body
     }
  };

  fcm.send(message, function(error, response){
      const success = error == null
      if (!success) {
         console.log("FCM Error:",error);
      }
  });
}
