
/** Test: Decrypt → convert json → generate contents → send the notification **/

const webPushDecipher = require('../webPushDecipher.js');
const fs = require('fs');
const notification = require('../notification.js');

publicKey = "BJgVD2cj1pNKNR2Ss3U_8e7P9AyoL5kWaxVio5aO16Cvnx-P1r7HH8SRb-h5tuxaydZ1ky3oO0V40s6t_uN1SdA"
privateKey = "ciQ800G-6jyKWf6KKG94g5rCSU_l_rgbHbyHny_UsIM"
authSecret = "43w_wOVYeF9XzyRyZL3O8g"

function decrypt(raw) {
  const reciverKey = webPushDecipher.reciverKeyBuilder(publicKey,privateKey,authSecret);
  var decrypted = webPushDecipher.decrypt(raw,reciverKey,false);
  return decrypted;
}


const rawBody = fs.readFileSync('./mock.text', 'utf8');
const lang = "ja";

const rawJson = decrypt(rawBody);
const contents = notification.generateContents(rawJson,lang);

console.log("title:",contents[0])
console.log("body:",contents[1])

const token =  fs.readFileSync('./fcm_token.txt', 'utf8');
notification.send(token, contents[0], contents[1])
