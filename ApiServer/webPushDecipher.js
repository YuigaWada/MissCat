// WebPushをdecryptするヤツ(on Node.js)
//
//
// **参考**
// https://tools.ietf.org/html/rfc8188
// https://tools.ietf.org/html/rfc8291
// https://tools.ietf.org/html/rfc8291#appendix-A
// https://gist.github.com/tateisu/685eab242549d9c9ffc85020f09a4b71
// ↑一部 @tateisu氏のコードを参考にしています
// (アドバイスありがとうございました！→ https://mastodon.juggler.jp/@tateisu/104098620591598243)

const util = require('util')
const crypto = require('crypto')

function decodeBase64(src){
    return new Buffer(src,'base64')
}

function sha256(key,data) {
  return crypto.createHmac('sha256', key)
  .update(data)
  .digest()
}

function log(varbose,label,text){
  if (!varbose) { return }
  console.log(label,text)
}

// 通知を受け取る側で生成したキーを渡す
exports.reciverKeyBuilder = function (public, private, authSecret,varbose) {
  this.public = decodeBase64(public)
  this.private = decodeBase64(private)
  this.authSecret = decodeBase64(authSecret)
  return this
}

// WebPushで流れてきた通知をdecrypt
exports.decrypt = function (body64,receiverKey,verbose) {
  body = decodeBase64(body64)
  auth_secret = receiverKey.authSecret
  receiver_public = receiverKey.public

  receiver_private = receiverKey.private

  /*
  +-----------+--------+-----------+---------------+
  | salt (16) | rs (4) | idlen (1) | keyid (idlen) |
  +-----------+--------+-----------+---------------+
  */

  const salt = body.slice(0,16)
  const rs = body.slice(16,16+4)

  const idlen_hex = body.slice(16+4,16+4+1).toString('hex')
  const idlen = parseInt(idlen_hex,16)
  const keyid = body.slice(16+4+1,16+4+1+idlen)

  const content = body.slice(16+4+1+idlen,body.length)


  const sender_public = decodeBase64(keyid.toString('base64'))


  log(verbose,"salt",salt.toString('base64'))
  log(verbose,"rs",rs.toString('hex'))
  log(verbose,"idlen_hex",idlen_hex)
  log(verbose,"idlen",idlen)
  log(verbose,"keyid",keyid.toString('base64'))
  log(verbose,"content",content.toString('base64'))
  log(verbose,"sender_public",sender_public.toString('base64'))

  // 共有秘密鍵
  receiver_curve = crypto.createECDH('prime256v1')
  receiver_curve.setPrivateKey(receiver_private)
  sharedSecret = receiver_curve.computeSecret( keyid ) // = ikm?

  log(verbose,"sharedSecret:", sharedSecret.toString('base64'))

  /*
    # HKDF-Extract(salt=auth_secret, IKM=ecdh_secret)
    PRK_key = HMAC-SHA-256(auth_secret, ecdh_secret)
    # HKDF-Expand(PRK_key, key_info, L_key=32)
    key_info = "WebPush: info" || 0x00 || ua_public || as_public
    IKM = HMAC-SHA-256(PRK_key, key_info || 0x01)

    ## HKDF calculations from RFC 8188
    # HKDF-Extract(salt, IKM)
    PRK = HMAC-SHA-256(salt, IKM)
    # HKDF-Expand(PRK, cek_info, L_cek=16)
    cek_info = "Content-Encoding: aes128gcm" || 0x00
    CEK = HMAC-SHA-256(PRK, cek_info || 0x01)[0..15]
    # HKDF-Expand(PRK, nonce_info, L_nonce=12)
    nonce_info = "Content-Encoding: nonce" || 0x00
    NONCE = HMAC-SHA-256(PRK, nonce_info || 0x01)[0..11]
  */

  const prk_key = sha256(auth_secret,sharedSecret)
  const keyInfo = Buffer.concat([Buffer.from('WebPush: info\0'),receiver_public,sender_public,Buffer.from('\1')])
  const ikm = sha256(prk_key, keyInfo);

  const prk = sha256(salt,ikm)
  log(verbose,"prk",prk.toString('base64'))

  const contentEncryptionKeyInfo = Buffer.from('Content-Encoding: aes128gcm\0\1')
  const cek = sha256(prk, contentEncryptionKeyInfo).slice(0,16);
  log(verbose,"cek",cek.toString('base64'))


  const nonceInfo = Buffer.from('Content-Encoding: nonce\0\1')
  const nonce = sha256(prk, nonceInfo).slice(0,12);
  const iv = nonce
  log(verbose,"nonce:",nonce.toString('base64'))



  const decipher = crypto.createDecipheriv('aes-128-gcm', cek, iv);
  result = decipher.update(content)
  log(verbose,"Ans:",result.toString('UTF-8'))

  // remove padding and GCM auth tag
  var pad_length = 0
  if( result.length >= 3 && result[2]==0){
  	pad_length = 2+ result.readUInt16BE(0)
  }
  result = result.slice(pad_length, result.length-16)

  log(verbose,"Shaped Ans:",result.toString('UTF-8'))
  return result.toString('UTF-8')
}
