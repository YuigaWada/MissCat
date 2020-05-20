# MissCat

<img src="./images/Banner.png"><br>

<a href="https://apps.apple.com/app/id1505059993"><img src="./images/Badge.svg"  align="right" width=20%></a>

<br>

[公式ページ](https://yuiga.dev/misscat)


MissCatはMisskeyに特化したiOS向けのネイティブアプリです。

<br><br>
## Goals & Missions

MissCatの目標は以下の<u>5つ</u>です。

- Misskeyをより身近なSNSにすること
- スマホに適した直感的な操作性を提供すること
- インスタンスのバージョン差分を意識しないMisskey環境を提供すること
- iOSらしく分かりやすいデザインを提供すること
- Misskeyを広めること

<br><br>
これらに応じて、順に以下のようなミッションを設定しています。
<br><br>



- iOSネイティブアプリの提供・通知機能や拡張機能の実装
- スワイプやタップ、半モーダルによる直感的な操作と快適な画面遷移
- めいすきー等のサポート
- 奇抜なデザインを用いない、iOSらしいデザイン設計
- 新規登録画面までの動線

<br><br>
## Technical Aspects

### カスタム絵文字

Misskeyにはカスタム絵文字というモノが存在します。

一般に、複数行の文字列表示にはUITextViewを使いますが、純正のUITextViewが対応しているのは静止画(UIImage)の挿入のみで、GIFアニメやAPNGといったアニメーション画像を挿入することはできません。また、非同期で取得した画像を挿入することもできません。

そこで、UITextViewをベースに、任意のUIViewを挿入することができる[YanagiText](https://github.com/YuigaWada/YanagiText)というライブラリを作りました。

MissCatではこの[YanagiText](https://github.com/YuigaWada/YanagiText)がカスタム絵文字を支える大きな基盤となっています。

また、APNGの表示は[APNGKit](https://github.com/onevcat/APNGKit), アニメGIFの表示は[Gifu](https://github.com/kaishin/Gifu)を利用しています。



<br><br>
### MFM(Misskey Flavored Markdown)

Misskeyでは、独自の構文MFMを用いることで文章の修飾をすることができます。([参照](https://join.misskey.page/ja/wiki/usage/mfm))

MissCatでは、Foundationの[NSAttributedString](https://developer.apple.com/documentation/foundation/nsattributedstring)を利用することで一部のMFMに対応しています。

<br><br>

### 通知
MissCatはWeb版のMisskeyと同じように、WebPushと呼ばれる技術を利用して通知システムを構築しています。

<br>

Web版Misskeyは[`'sw/register'`](https://misskey.io/api-doc#operation/sw/register)というエンドポイントを叩き、イベントが発生した際に通知がブラウザにPushされるよう登録します。

MissCatでは、この仕組みを利用して、Misskey側で発火した通知イベントを、そのままサーバーへ送るよう[`'sw/register'`](https://misskey.io/api-doc#operation/sw/register)へ登録します。サーバー側は暗号化された通知メッセージを受け取ると、メッセージを復号して、適切なフォーマットに変換し、Firebaseへ投げることで各端末に通知を届けます。

※WebPushはprime256v1と言う楕円曲線暗号を元にメッセージが暗号化されているため、サーバーで通知メッセージを受け取った後、適切なカタチで復号してあげる必要があります。そこで、通知の実装にあたり、サーバー側で通知メッセージを復号するモジュールを作りました。[webPushDecipher.js](https://github.com/YuigaWada/MissCat/blob/develop/ApiServer/webPushDecipher.js)

<br><br>

### タブ

上タブは私の作った[PolioPager](https://github.com/YuigaWada/PolioPager)というライブラリを使っています。

<br><br>
## Others

- コード汚いです
- 実装していない機能が山程あります
- バグも山程あります

<br><br>

MissCatは皆様のご意見をお待ちしております。

[Twitter](https://twitter.com/yuigawada)か[Misskey](https://misskey.io/@wada)にて、ご気軽にリプライ/DMを頂けると幸いです。
