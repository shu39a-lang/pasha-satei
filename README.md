# パシャ査定 iOS 試作版 0.1

Apple向けSwiftUI試作版です。

## 現在できること
- カメラ撮影
- 写真ライブラリから選択
- 仮査定結果の表示
- 商品状態の切替
- 販売先・買取店候補の表示

## 次段階
- 商品画像認識API接続
- JAN/型番認識
- 実価格データ接続
- 店舗検索・位置情報
- アイコン/プライバシーポリシー
- App Store Connect署名・TestFlight

## Bundle ID
`com.shu39a.pashasatei`

## Codemagic
`codemagic.yaml` はまずシミュレータ向けにビルド確認する設定です。署名設定後にIPA/TestFlight用へ切り替えます。
