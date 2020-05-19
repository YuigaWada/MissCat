'use strict';

const fs = require('fs');
const express = require('express');
const bodyParser = require('body-parser');

const notification = require('./notification.js');
const webPushDecipher = require('./webPushDecipher.js');

// For Distributed
const authSecret = "Q8Zgu-WDvN5EDT_emFGovQ"
const publicKey = "BJNAJpIOIJnXVVgCTAd4geduXEsNKre0XVvz0j-E_z-8CbGI6VaRPsVI7r-hF88MijMBZApurU2HmSNQ4e-cTmA"
const privateKey = fs.readFileSync('./key/edch_private_key.txt', 'utf8');


// For test
// const authSecret = "43w_wOVYeF9XzyRyZL3O8g"
// const publicKey = "BJgVD2cj1pNKNR2Ss3U_8e7P9AyoL5kWaxVio5aO16Cvnx-P1r7HH8SRb-h5tuxaydZ1ky3oO0V40s6t_uN1SdA"
// const privateKey = "ciQ800G-6jyKWf6KKG94g5rCSU_l_rgbHbyHny_UsIM"



function decrypt(raw) {
  // const converted = raw.toString('utf-8') // for debug
  const converted = raw.toString('base64')

  const reciverKey = webPushDecipher.reciverKeyBuilder(publicKey,privateKey,authSecret)
  var decrypted = webPushDecipher.decrypt(converted,reciverKey,false)
  return decrypted
}

const app = express();

var concat = require('concat-stream');
app.use(function(req, res, next){
  req.pipe(concat(function(data){
    req.body = data;
    next();
  }));
});


app.post("/api/:version/push/:lang/:userId/:deviceToken", function(req, res){
    if (req.params.version != "v1") { res.status(410).send('Invalid Version.').end(); return; }

    const rawBody = req.body;
    if (!rawBody) { res.status(200).send('Invalid Body.').end(); }

    const rawJson = decrypt(rawBody);
    const userId = req.params.userId;
    const deviceToken = req.params.deviceToken;
    const lang = req.params.lang;
    if (!rawJson||!userId||!deviceToken||!lang) { res.status(410).send('Invalid Url.').end(); return; }

    console.log(rawJson)
    const contents = notification.generateContents(rawJson,lang);
    const title = contents[0];
    const body = contents[1];
    if (!title) { res.status(200).send('Invalid Json.').end(); return; }

    // console.log("deviceToken",deviceToken);
    notification.send(deviceToken, title, body); // send!
    res.status(200).send('Ok').end();
});

// Start the server
const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`App listening on port ${PORT}`);
  console.log('Press Ctrl+C to quit.');
});

module.exports = app;
