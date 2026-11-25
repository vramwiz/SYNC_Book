# SYNC_Book の配布 ZIP

`make_release_zip.bat` で `SYNC_Book.zip` を作成します。カタログ JSON の末尾バージョンに、ZIP に入れた AUF2 の XXH3-128 を記録します。

- 標準の AUF2 参照先は `C:\ProgramData\aviutl2\Plugin\SYNC_Book` です。別の場所を使う場合は `-ReleaseDirectory` にフォルダーを指定します。
- ハッシュ計算には公式の Windows 64ビット版 `xxhsum.exe` を使用します。PATH、`Win64\Dependencies\xxHash-0.8.4\xxhsum.exe`、または `-XxhsumPath` で指定できます。[xxHash v0.8.4](https://github.com/Cyan4973/xxHash/releases/tag/v0.8.4)

```bat
setup\make_release_zip.bat
```

```bat
setup\make_release_zip.bat -ReleaseDirectory "D:\Release\SYNC_Book" -XxhsumPath "D:\Tools\xxhsum.exe"
```

ZIP は `SYNC_Book/` をルートとし、AUF2、利用者向け README、ライセンスを収録します。カタログのアンインストールでは ZIP からインストールしたファイルのみを個別に削除します。

GitHub Releases には ZIP と `SYNC_Book.catalog.json` を添付します。
