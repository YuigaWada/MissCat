
/** Test: generate contents → send the notification **/

const fs = require('fs');
const notification = require('../notification.js');

const rawJson = fs.readFileSync('./mock.json', 'utf8');
const lang = "ja";

const contents = notification.generateContents(rawJson,lang);
console.log("title:",contents[0])
console.log("body:",contents[1])

const token = fs.readFileSync('./fcm_token.txt', 'utf8');
notification.send(token, contents[0], contents[1])
