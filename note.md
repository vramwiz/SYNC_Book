# SYNC_Book 作業ノート

## プロジェクト

- プロジェクト名は `SYNC_Book`、登録名は「本演出」、ラベルは `SYNC`。本番 DLL は `SYNC_Book.dproj` の Win64 ビルドから生成する `SYNC_Book.auf2` の1つ。
- [制作仕様書](docs/SPECIFICATION.md) は受領した内容。公開向けの操作説明は [README](README.md)。
- オブジェクトの位置・回転・拡大率・透明度は AviUtl2 標準の「描画」欄を使う。本演出側の「基本設定」は削除した。ローカル座標を DrawPoly に渡し、標準値は奥行き順の計算に使う。旧「基本設定」に設定した値は標準欄での再設定が必要。
- WeatherFX から Delphi プロジェクト階層、ビルド手順、フィルターテーブル、SDK 宣言とライセンスを引き継いだ。SDK の宣言は手元の公式ヘッダー v2115 と 2.1.17 に照合し、必要なコールバックの型と位置を追加した。
- `setup` の配布バッチとカタログを SYNC_Book 用に更新した。利用者向けの README とライセンスを ZIP に収録する。
- PianoRoll のメディアオブジェクト登録と `DrawPoly` を参照。SDK の頂点・テクスチャ・光沢指定を使い、Direct3D のカメラと光源を AviUtl2 側で扱う。2.1.17 以降でカメラ制御が有効な場合は材質ごとに頂点をまとめる。2.1.16 およびカメラ制御の対象外では、通常描画の視点に対する奥行き順を補う。正確な面同士の遮蔽には、AviUtl2 のカメラ制御が必要。
- ユーザー画像は SDK の `image:` リソースと VRAM キャッシュを使う。内蔵テクスチャは各インスタンスで最大20枚保持し、必要なものをフレームのリソースとして渡す。表紙・背表紙・綴じ具の位置と設定が同じ場合はメッシュを再利用する。
- カメラ下の遮蔽・光源・輪郭のアンチエイリアスはホストの描画に従う。効果音は省略した。

## ビルドと検査

Delphi 37.0 の `rsvars.bat` を呼び、プロジェクトルートで Win64 Debug / Release を実行する。IDE を起動する場合は `SYNC_Book.dproj` を開く。

```powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_Book.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64'
.\Tests\run_tests.ps1
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_Book.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64'
.\Tests\run_tests.ps1
```

- Debug / Release の出力先は `C:\ProgramData\aviutl2\Plugin\SYNC_Book\`。WeatherFX と同じビルド後イベントで DLL を AUF2 にコピーして DLL を削除する。Release は RSM も削除する。DCU は `Win64\Debug\DCU` / `Win64\Release\DCU`。
- デバッガーホストは WeatherFX と同じ `D:\aviutl2_v2.1.16\aviutl2.exe`。コマンドラインのビルドと検査でアプリは起動しない。
- 検査 EXE は本番 AUF2 をロードして SDK コールバックを模擬する。14プリセット、ページ画像、アニメーション全18組、綴じ方向、フレームシーク、連続配置の端点を検査する。
- ユニットを追加するときは `.dpr` の `in` と `.dproj` の `DCCReference` を揃える。日本語を含むソースと検査スクリプトは UTF-8 BOM と CRLF。

### 2026-11-24 の検査結果

- Win64 Debug / Release とも Rebuild は警告0・エラー0。両 AUF2 で単体検査に合格し、初期フレームの描画データの SHA-256 が一致した。
- 最後に Release の AUF2 を配置した。
- `setup` の5ファイルと制作仕様書を SHA-256 でコピー元と照合した。
- AviUtl2 は起動していない。ホスト内のプレビュー、カメラ制御下の実画質、実機の再生速度は未検証。

### 2026-11-24 標準描画への統一後

- ビルド時の `DCC_ExeOutput` 指定で出力先を `Win64\Debug` / `Win64\Release` に変更した。Win64 Debug / Release とも警告0・エラー0で、両 AUF2 が単体検査に合格した。
- 単体検査では標準項目と重複する追加項目が登録されていないこと、標準回転が奥行き順に反映されること、頂点とアンカーへの変換が重複しないことを確認した。
- AviUtl2 が配布先の AUF2 を使用中だったため、検査は `Win64/Release/SYNC_Book.auf2` で実施した。AviUtl2 の終了確認後、ハッシュが一致する Release 版を `C:\ProgramData\aviutl2\Plugin\SYNC_Book\SYNC_Book.auf2` に配置した。

### 開き残し角度

- 本体形状の「開き残し角度」は全開（180°）から残す角度。新規配置とプリセット反映時は 0°で、進行度 1.00 で表紙が平らになる。ページの膨らみは別の設定で調整する。
- 旧「開き角度」の見た目を再現する場合は、180° から旧値を引いた角度を入力する。
- Win64 Debug / Release は警告0・エラー0。単体検査で、全3綴じ方向の 180° と 150° の描画および全13プリセットの初期値を確認した。確認済みの Release 版を配置した。

### 内蔵ページの模様

- ページ A / B の内蔵紙面は「ページ位置」と紙面の向きから決める。前後のオブジェクトで同じ位置を使うと同じ模様を表示する。途中の紙面は始点・終点・枚数順から決まり、まとめめくりでも紙ごとに表裏の模様を生成する。
- 文章の段落・行の長さ、挿絵、楽譜の音符がページごとに変わる。Win64 Debug / Release で左右の紙面、A / B、連続めくり、まとめめくり、シーク後の再現性を検査し、Release 版を配置した。

### v1.0.0 の公開

- 2026-11-24 に、ソースとタグを GitHub へ公開した。[本演出 v1.0.0](https://github.com/vramwiz/SYNC_Book/releases/tag/v1.0.0)
- `setup\make_release_zip.bat` から `SYNC_Book.zip` と AUF2 の XXH3-128 を反映したカタログを作成した。アンインストールは `{pluginsDir}/SYNC_Book` の削除1件。
- Release の AUF2 を単体検査し、配置先と ZIP 内の本体を照合した。公開した ZIP と JSON を認証なしで取得し、ローカルの成果物との SHA-256 一致を確認した。AviUtl2 は起動していない。

- 公開後、デバッグ出力、ビルド中間ファイル、検査用の出力、ログ、WeatherFX の参照コピーを作業フォルダーから削除した。

### 2026-11-27 新聞プリセット

- 「本の種類」に新聞を追加した。左綴じの薄い折り形状で、表紙・裏表紙・中面は同じ色と光沢の新聞紙。表に題字と縦見出し、中面に段組み、裏にテレビ・ラジオ番組表を生成する。
- Win64 Debug / Release の Rebuild と検査に合格した。初期フレームのハッシュは配置済みの更新前の版と一致した。生成した表・中面・裏の紙面を画像で確認した。
- 検査済みの Release 版は `Win64\Release\SYNC_Book.auf2`。左綴じの初期値を検査し、Release 版を AviUtl2 のプラグインフォルダーに配置した。ホスト上での表示確認は未実施。

## ソースの配置

- `SYNC_Book.dpr` はエクスポート、最低対応バージョンと初期化。
- `Source/Plugin/Filter` は登録、SDK との入出力、折り畳みグループ、プリセット反映。
- `Source/Common/Book_Settings.pas` は形状と材質の初期値、タイムラインの進行度から求める姿勢。
- `Source/Common/Book_Mesh.pas` は表紙、背、紙束、めくり中の両面メッシュ。
- `Source/Common/Book_Textures.pas` は内蔵の紙面・装丁・断面とキャッシュ。
- `Source/Common/Book_Renderer.pas` は頂点座標と UV の変換、SDK への描画送信。

## AviUtl2カタログ登録時の共通ルール

1. **概要は35文字以内。** `Setup/*.catalog.json` の `summary` は、JSONのエスケープ表記ではなく実際の表示文字列を数える。機能の詳細や補足は概要に詰め込まず、説明・READMEに記載する。
2. **既存タグを優先する。** [公開カタログの `index.json`](https://github.com/Neosku/aviutl2-catalog-data/blob/main/index.json) で、同じ製品や近い用途に使われているタグの表記を確認し、用途を表すものだけを選ぶ。同義語を重ねたり、製品ごとに新しいタグを量産したりしない。
3. **配布専用フォルダー単位で導入・削除する。** ZIP内を製品専用フォルダーにまとめ、ダウンロード・展開後の配置はフォルダーの `copy` 1件、アンインストールはその専用フォルダーだけを指定する `delete` 1件を基本とする。共有フォルダーや、ユーザー素材・設定を含むフォルダーは一括削除しない。既存パッケージで変更する際は、配布ZIPの配置とセットアップスクリプトの検証条件も確認し、整合しない場合は既存の手順を維持する。
