unit SYNC_Book_FilterPlugin;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 「本演出」のメディアオブジェクト登録と、エフェクトごとの描画資源の管理。

interface

uses
  AviUtl2FilterTypes;

const
  BOOK_REQUIRED_VERSION = 2011600;

// 初期化時にのみ SDK のバージョンを設定する。
procedure SetBookHostVersion(Version: Cardinal);
// DLL 所有のテーブルを返す。ホストから解放しない。
function GetBookFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.SyncObjs, System.SysUtils, Winapi.Windows,
  Book_Parameters, Book_Renderer, Book_Settings, PluginFilterTable;

type
  TBookSession = class
  private
    FLock: TCriticalSection;
    FRenderer: TBookRenderer;
  public
    constructor Create;
    destructor Destroy; override;
    // 渡された SDK ポインターは呼び出し中だけ利用する。
    procedure Draw(Video: PFILTER_PROC_VIDEO);
  end;

var
  TableRegistered: Boolean;
  CameraAPIAvailable: Boolean;

procedure SetBookHostVersion(Version: Cardinal);
begin
  CameraAPIAvailable := Version >= 2011700;
end;

constructor TBookSession.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
  FRenderer := TBookRenderer.Create;
end;

destructor TBookSession.Destroy;
begin
  FRenderer.Free;
  FLock.Free;
  inherited;
end;

procedure TBookSession.Draw(Video: PFILTER_PROC_VIDEO);
var
  S: TBookSettings;
  Duration: Double;
begin
  FLock.Acquire;
  try
    S := ReadBookSettings;
    Duration := 0;
    if S.TurnStyle in [tsFlip,tsSearch,tsWind] then
      Duration := BookTransitionDuration(Video);
    FRenderer.Draw(Video,S,Duration,CameraAPIAvailable);
  finally
    FLock.Release;
  end;
end;

function BookProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
begin
  Result := 0; // DrawPoly で描画し、標準画像の二重出力を止める。
  if (Video = nil) or (Video^.Object_ = nil) or (Video^.UserData = nil) then Exit;
  try
    TBookSession(Video^.UserData).Draw(Video);
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_Book render: '+E.Message));
  end;
end;

function BookCreate(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TBookSession.Create;
  except
    // 生成に失敗した場合は userdata を設定しない。
  end;
end;

procedure BookDestroy(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    TBookSession(UserData).Free;
  except
    // DLL 境界を保つ。
  end;
end;

function GetBookFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not TableRegistered then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA,
      '本演出','SYNC','本演出 / SYNC_Book v1.0.0',BookProcVideo,nil);
    RegisterBookParameters;
    GetPluginTable^.Func_Create := BookCreate;
    GetPluginTable^.Func_Destroy := BookDestroy;
    TableRegistered := True;
  end;
  Result := GetPluginTable;
end;

end.
