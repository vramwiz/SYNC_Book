library SYNC_Book;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// AviUtl2 の DLL エントリーポイント。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  Book_Settings in 'Source\Common\Book_Settings.pas',
  Book_Mesh in 'Source\Common\Book_Mesh.pas',
  Book_Textures in 'Source\Common\Book_Textures.pas',
  Book_Renderer in 'Source\Common\Book_Renderer.pas',
  Book_Parameters in 'Source\Plugin\Filter\Book_Parameters.pas',
  SYNC_Book_FilterPlugin in 'Source\Plugin\Filter\SYNC_Book_FilterPlugin.pas';

{$R *.res}

function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 0;
  try
    if Version < BOOK_REQUIRED_VERSION then Exit;
    SetBookHostVersion(Version);
    GetBookFilterTable;
    Result := 1;
  except
    // 初期化に失敗した場合は SDK の false を返す。
  end;
end;

procedure UninitializePlugin; cdecl;
begin
  // エフェクトの描画資源は func_destroy で回収される。
end;

function RequiredVersion: Cardinal; cdecl;
begin
  Result := BOOK_REQUIRED_VERSION;
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := nil;
  try
    Result := GetBookFilterTable;
  except
    // DLL の外へ例外を伝播させない。
  end;
end;

exports
  RequiredVersion name 'RequiredVersion',
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
