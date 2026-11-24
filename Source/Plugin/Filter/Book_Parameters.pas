unit Book_Parameters;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// AviUtl2 の設定項目と、編集ボタンからの保存値更新。

interface

uses
  AviUtl2FilterTypes, Book_Settings;

procedure RegisterBookParameters;
// ホスト所有の現在値・文字列をフレーム内で読み取り、設定レコードに複製する。
function ReadBookSettings: TBookSettings;
// 現在の中間点区間の長さを秒で返す。取得できなければオブジェクト全体を使う。
function BookTransitionDuration(Video: PFILTER_PROC_VIDEO): Double;

implementation

uses
  System.SysUtils, System.Math, System.Win.ComObj, Winapi.Windows, Winapi.ActiveX, Winapi.Wincodec,
  PluginFilterTable;

type
  TControl = (btWidth, btRatio, btThickness, btOpeningGap, btProgress, btSpeed, btBulge,
    btSoftness, btPaperShine, btFrontThickness, btFrontShine, btFrontRadius,
    btBackThickness, btBackShine, btBackRadius, btSpineRadius, btSpineShine,
    btPositionA, btPositionB);
  TTrackSpec = record
    Name: PWideChar;
    Low, High, Step: Double;
  end;
  TChoice = (bcPreset, bcBinding, bcBindingStyle, bcTransition, bcTurn,
    bcFront, bcBack, bcSpine, bcPaper, bcStateA, bcStateB, bcImageA, bcImageB,
    bcFitA, bcFitB);
  TColorItem = (ciFront, ciBack, ciSpine, ciPaper, ciInk);
  TFileItem = (fiFrontOut, fiFrontIn, fiBackOut, fiBackIn, fiSpineOut,
    fiSpineIn, fiA1, fiA2, fiB1, fiB2);

const
  TrackSpec: array[TControl] of TTrackSpec = (
    (Name:'横幅'; Low:16; High:2400; Step:0.01),
    (Name:'縦横比'; Low:0.15; High:5; Step:0.01),
    (Name:'厚さ'; Low:1; High:500; Step:0.01),
    (Name:'開き残し角度'; Low:0; High:140; Step:0.01),
    (Name:'進行度'; Low:0; High:1; Step:0.01),
    (Name:'めくり速度'; Low:0; High:100; Step:0.01),
    (Name:'ページの膨らみ'; Low:0; High:100; Step:0.01),
    (Name:'ページの柔らかさ'; Low:0; High:100; Step:0.01),
    (Name:'ページの光沢'; Low:0; High:100; Step:0.01),
    (Name:'表紙の厚さ'; Low:0.05; High:100; Step:0.01),
    (Name:'表紙の光沢'; Low:0; High:100; Step:0.01),
    (Name:'表紙の角丸'; Low:0; High:100; Step:0.01),
    (Name:'裏表紙の厚さ'; Low:0.05; High:100; Step:0.01),
    (Name:'裏表紙の光沢'; Low:0; High:100; Step:0.01),
    (Name:'裏表紙の角丸'; Low:0; High:100; Step:0.01),
    (Name:'背表紙の丸み'; Low:0; High:100; Step:0.01),
    (Name:'背表紙の光沢'; Low:0; High:100; Step:0.01),
    (Name:'ページA位置'; Low:0; High:100; Step:0.01),
    (Name:'ページB位置'; Low:0; High:100; Step:0.01)
  );
  ColorNames: array[TColorItem] of PWideChar =
    ('表紙の色', '裏表紙の色', '背表紙の色', '用紙色', '描画色');
  FileNames: array[TFileItem] of PWideChar =
    ('表紙の外側画像', '表紙の内側画像', '裏表紙の外側画像', '裏表紙の内側画像',
     '背表紙の外側画像', '背表紙の内側画像', 'ページA画像1', 'ページA画像2',
     'ページB画像1', 'ページB画像2');
  ImageFilter = '画像 (*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff)'#0 +
    '*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff'#0'すべてのファイル (*.*)'#0'*.*'#0;
  PresetNames: array[TBookPreset] of PWideChar =
    ('ハードカバー','ソフトカバー','文庫本','古書','魔法書','絵本','漫画',
     '雑誌','ノート','リングノート','手帳','写真アルバム','和綴じ本');
  CoverNames: array[TCoverPattern] of PWideChar =
    ('無地','布張り','革張り','装飾付き');
  StateNames: array[TPageState] of PWideChar =
    ('通常の見開きページ','最初のページ','最終ページ');
  ImageNames: array[TImageMode] of PWideChar =
    ('内蔵描画','見開き画像','左（上）ページ画像','右（下）ページ画像','左右（上下）個別画像');
  FitNames: array[TImageFit] of PWideChar = ('引き伸ばす','比率を維持して切り抜く');

var
  Tracks: array[TControl] of TFILTER_ITEM_TRACK;
  Selects: array[TChoice] of TFILTER_ITEM_SELECT;
  Options: array[TChoice] of array[0..Ord(High(TBookPreset))+1] of TFILTER_ITEM_SELECT_ITEM;
  Colors: array[TColorItem] of TFILTER_ITEM_COLOR;
  Files: array[TFileItem] of TFILTER_ITEM_FILE;
  Groups, GroupEnds: array[0..8] of TFILTER_ITEM_GROUP;
  PresetButton, RatioButton: TFILTER_ITEM_BUTTON;

function TrackValue(Item: TControl): Double;
begin
  Result := Tracks[Item].Value;
  if IsNan(Result) or IsInfinite(Result) then
    Result := 0;
  Result := EnsureRange(Result, TrackSpec[Item].Low, TrackSpec[Item].High);
end;

function Selected(Item: TChoice): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Options[Item]) do
  begin
    if Options[Item,I].Name = nil then Exit;
    if Options[Item,I].Value = Selects[Item].Value then
      Exit(Selects[Item].Value);
  end;
end;

function ReadColor(Item: TColorItem): Cardinal;
begin
  with Colors[Item] do
    Result := (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or B;
end;

function ReadBookSettings: TBookSettings;
begin
  Result := Default(TBookSettings);
  with Result do
  begin
    Width := TrackValue(btWidth);
    Aspect := TrackValue(btRatio);
    Thickness := TrackValue(btThickness);
    OpeningGap := TrackValue(btOpeningGap);
    Binding := TBinding(Selected(bcBinding));
    BindingStyle := TBindingStyle(Selected(bcBindingStyle));
    Transition := TTransition(Selected(bcTransition));
    TurnStyle := TTurnStyle(Selected(bcTurn));
    Progress := TrackValue(btProgress);
    Speed := TrackValue(btSpeed);

    Front.Color := ReadColor(ciFront);
    Front.Pattern := TCoverPattern(Selected(bcFront));
    Front.Thickness := TrackValue(btFrontThickness);
    Front.Shine := TrackValue(btFrontShine);
    Front.Radius := TrackValue(btFrontRadius);
    Front.OutsideFile := Files[fiFrontOut].Value;
    Front.InsideFile := Files[fiFrontIn].Value;
    Back.Color := ReadColor(ciBack);
    Back.Pattern := TCoverPattern(Selected(bcBack));
    Back.Thickness := TrackValue(btBackThickness);
    Back.Shine := TrackValue(btBackShine);
    Back.Radius := TrackValue(btBackRadius);
    Back.OutsideFile := Files[fiBackOut].Value;
    Back.InsideFile := Files[fiBackIn].Value;
    Spine.Color := ReadColor(ciSpine);
    Spine.Pattern := TCoverPattern(Selected(bcSpine));
    Spine.Shine := TrackValue(btSpineShine);
    Spine.Radius := TrackValue(btSpineRadius);
    Spine.OutsideFile := Files[fiSpineOut].Value;
    Spine.InsideFile := Files[fiSpineIn].Value;

    Paper.Color := ReadColor(ciPaper);
    Paper.Ink := ReadColor(ciInk);
    Paper.Pattern := TPaperPattern(Selected(bcPaper));
    Paper.Bulge := TrackValue(btBulge);
    Paper.Softness := TrackValue(btSoftness);
    Paper.Shine := TrackValue(btPaperShine);
    A.Position := TrackValue(btPositionA);
    A.State := TPageState(Selected(bcStateA));
    A.ImageMode := TImageMode(Selected(bcImageA));
    A.Fit := TImageFit(Selected(bcFitA));
    A.File1 := Files[fiA1].Value;
    A.File2 := Files[fiA2].Value;
    B.Position := TrackValue(btPositionB);
    B.State := TPageState(Selected(bcStateB));
    B.ImageMode := TImageMode(Selected(bcImageB));
    B.Fit := TImageFit(Selected(bcFitB));
    B.File1 := Files[fiB1].Value;
    B.File2 := Files[fiB2].Value;
  end;
end;

function BookTransitionDuration(Video: PFILTER_PROC_VIDEO): Double;
var
  Obj: POBJECT_INFO;
  Edit: PEDIT_SECTION;
  Info: TTrackInfo;
  Frame, Low, High, Mid, BoundaryFrame, StartFrame, EndFrame: Integer;
begin
  Obj := Video^.Object_;
  Result := Obj^.TimeTotal;
  Edit := Video^.Edit;
  if (Video^.Scene = nil) or (Video^.Scene^.Rate <= 0) or
    (Video^.Scene^.Scale <= 0) or (Edit = nil) or (Obj^.Handle = nil) or
    not Assigned(Edit^.GetObjectSectionFrame) then Exit;
  Info := Default(TTrackInfo);
  if Assigned(Edit^.GetEffectTrackInfo) and (Obj^.EffectHandle <> nil) and
    Edit^.GetEffectTrackInfo(Obj^.EffectHandle, TrackSpec[btProgress].Name,
      @Info, SizeOf(Info)) and Info.TwoPoint then Exit;
  Frame := Obj^.FrameS + Obj^.Frame;
  Low := 0;
  High := 1;
  while High < Max(Obj^.FrameTotal, 2) do
  begin
    BoundaryFrame := Edit^.GetObjectSectionFrame(Obj^.Handle, High);
    if (BoundaryFrame < 0) or (BoundaryFrame > Frame) then Break;
    Low := High;
    High := High + Min(High, Max(Obj^.FrameTotal, 2)-High);
  end;
  while High-Low > 1 do
  begin
    Mid := Low + (High-Low) div 2;
    BoundaryFrame := Edit^.GetObjectSectionFrame(Obj^.Handle, Mid);
    if (BoundaryFrame >= 0) and (BoundaryFrame <= Frame) then
      Low := Mid
    else
      High := Mid;
  end;
  StartFrame := Obj^.FrameS;
  EndFrame := Obj^.FrameE + 1;
  if Low > 0 then
    StartFrame := Edit^.GetObjectSectionFrame(Obj^.Handle, Low);
  BoundaryFrame := Edit^.GetObjectSectionFrame(Obj^.Handle, High);
  if BoundaryFrame >= 0 then
    EndFrame := BoundaryFrame;
  if EndFrame > StartFrame then
    Result := (EndFrame-StartFrame) * (Video^.Scene^.Scale / Video^.Scene^.Rate);
end;

procedure SetItem(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect, Name: PWideChar;
  const Text: UTF8String);
begin
  if not Edit^.SetObjectItemValue(Obj, Effect, Name, PAnsiChar(Text)) then
    raise EInvalidOp.CreateFmt('設定項目を更新できません: %s', [string(Name)]);
end;

procedure ApplyPreset(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE;
  Effect, Item: PWideChar); cdecl;
var
  S: TBookSettings;
  Preset: TBookPreset;
  Value: PAnsiChar;
  PresetText: string;

  procedure SetTrack(Id: TControl; Number: Double);
  begin
    SetItem(Edit, Obj, Effect, TrackSpec[Id].Name,
      UTF8String(FloatToStr(Number, TFormatSettings.Invariant)));
  end;

  procedure SetChoice(Id: TChoice; Index: Integer);
  begin
    SetItem(Edit, Obj, Effect, Selects[Id].Name, UTF8String(string(Options[Id,Index].Name)));
  end;

  procedure SetColor(Id: TColorItem; Color: Cardinal);
  begin
    SetItem(Edit, Obj, Effect, ColorNames[Id], UTF8String(LowerCase(IntToHex(Color, 6))));
  end;

begin
  if (Edit = nil) or (Obj = nil) or (Effect = nil) or
    not Assigned(Edit^.SetObjectItemValue) then Exit;
  try
    Preset := TBookPreset(Selected(bcPreset));
    if Assigned(Edit^.GetObjectItemValue) then
    begin
      Value := Edit^.GetObjectItemValue(Obj, Effect, Selects[bcPreset].Name);
      if Value <> nil then
      begin
        PresetText := UTF8ToString(Value);
        for Preset := Low(TBookPreset) to High(TBookPreset) do
          if PresetText = PresetNames[Preset] then Break;
        if PresetText <> PresetNames[Preset] then
          Preset := TBookPreset(Selected(bcPreset));
      end;
    end;
    S := BookPreset(Preset);
    SetTrack(btWidth, S.Width);
    SetTrack(btRatio, S.Aspect);
    SetTrack(btThickness, S.Thickness);
    SetTrack(btOpeningGap, S.OpeningGap);
    SetChoice(bcBinding, Ord(S.Binding));
    SetChoice(bcBindingStyle, Ord(S.BindingStyle));
    SetColor(ciFront, S.Front.Color);
    SetChoice(bcFront, Ord(S.Front.Pattern));
    SetTrack(btFrontThickness, S.Front.Thickness);
    SetTrack(btFrontShine, S.Front.Shine);
    SetTrack(btFrontRadius, S.Front.Radius);
    SetColor(ciBack, S.Back.Color);
    SetChoice(bcBack, Ord(S.Back.Pattern));
    SetTrack(btBackThickness, S.Back.Thickness);
    SetTrack(btBackShine, S.Back.Shine);
    SetTrack(btBackRadius, S.Back.Radius);
    SetColor(ciSpine, S.Spine.Color);
    SetChoice(bcSpine, Ord(S.Spine.Pattern));
    SetTrack(btSpineRadius, S.Spine.Radius);
    SetTrack(btSpineShine, S.Spine.Shine);
    SetColor(ciPaper, S.Paper.Color);
    SetColor(ciInk, S.Paper.Ink);
    SetChoice(bcPaper, Ord(S.Paper.Pattern));
    SetTrack(btBulge, S.Paper.Bulge);
    SetTrack(btSoftness, S.Paper.Softness);
    SetTrack(btPaperShine, S.Paper.Shine);
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_Book preset: ' + E.Message));
  end;
end;

procedure ApplyImageRatio(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE;
  Effect, Item: PWideChar); cdecl;
const
  Candidates: array[0..7] of TFileItem = (fiFrontOut, fiFrontIn, fiA1, fiA2,
    fiB1, fiB2, fiBackOut, fiBackIn);
var
  Factory: IWICImagingFactory;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  Candidate: TFileItem;
  Path: string;
  Value: PAnsiChar;
  Mode: TImageMode;
  ModeItem: TChoice;
  Width, Height: Cardinal;
  Ratio: Double;
  ComStatus: HRESULT;
begin
  if (Edit = nil) or (Obj = nil) or (Effect = nil) or
    not Assigned(Edit^.GetObjectItemValue) or not Assigned(Edit^.SetObjectItemValue) then Exit;
  ComStatus := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  try
    OleCheck(CoCreateInstance(CLSID_WICImagingFactory, nil, CLSCTX_INPROC_SERVER,
      IWICImagingFactory, Factory));
    for Candidate in Candidates do
    begin
      Mode := imSeparate;
      if Candidate in [fiA1,fiA2,fiB1,fiB2] then
      begin
        if Candidate in [fiA1,fiA2] then ModeItem := bcImageA else ModeItem := bcImageB;
        Mode := TImageMode(Selected(ModeItem));
        Value := Edit^.GetObjectItemValue(Obj, Effect, Selects[ModeItem].Name);
        if Value <> nil then
          for Mode := Low(TImageMode) to High(TImageMode) do
            if UTF8ToString(Value)=ImageNames[Mode] then Break;
        if (Mode=imBuiltIn) or ((Candidate in [fiA2,fiB2]) and (Mode<>imSeparate)) then
          Continue;
      end;
      Value := Edit^.GetObjectItemValue(Obj, Effect, FileNames[Candidate]);
      if Value = nil then Continue;
      Path := UTF8ToString(Value);
      if (Path = '') or Failed(Factory.CreateDecoderFromFilename(PWideChar(Path),
        PGUID(nil)^, GENERIC_READ, WICDecodeMetadataCacheOnDemand, Decoder)) then Continue;
      if Failed(Decoder.GetFrame(0, Frame)) or Failed(Frame.GetSize(Width, Height))
        or (Width = 0) or (Height = 0) then Continue;
      Ratio := Height / Width;
      if Mode=imSpread then
      begin
        Value := Edit^.GetObjectItemValue(Obj, Effect, Selects[bcBinding].Name);
        if (Value <> nil) and (UTF8ToString(Value) = Options[bcBinding,Ord(bdTop)].Name) then
          Ratio := Ratio*0.5
        else
          Ratio := Ratio*2;
      end;
      SetItem(Edit, Obj, Effect, TrackSpec[btRatio].Name, UTF8String(FloatToStr(
        EnsureRange(Ratio, TrackSpec[btRatio].Low, TrackSpec[btRatio].High),
        TFormatSettings.Invariant)));
      Break;
    end;
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_Book image ratio: ' + E.Message));
  end;
  Frame := nil;
  Decoder := nil;
  Factory := nil;
  if Succeeded(ComStatus) then CoUninitialize;
end;

procedure RegisterBookParameters;
var
  S: TBookSettings;

  procedure Group(Index: Integer; Name: PWideChar; Visible: Boolean = False);
  begin
    AddGroup(Groups[Index], Name, Ord(Visible));
  end;

  procedure EndGroup(Index: Integer);
  begin
    AddGroup(GroupEnds[Index], '', 0);
  end;

  procedure Track(Id: TControl; Value: Double);
  begin
    with TrackSpec[Id] do
      AddTrack(Tracks[Id], Name, Value, Low, High, Step);
  end;

  procedure Select(Id: TChoice; Name: PWideChar; Value: Integer;
    const Names: array of PWideChar);
  var
    I: Integer;
  begin
    for I := 0 to High(Names) do
    begin
      Options[Id,I].Name := Names[I];
      Options[Id,I].Value := I;
    end;
    Options[Id,Length(Names)].Name := nil;
    AddSelect(Selects[Id], Name, Value, @Options[Id,0]);
  end;

  procedure Color(Id: TColorItem; Value: Cardinal);
  begin
    AddColor(Colors[Id], ColorNames[Id], Byte(Value), Byte(Value shr 8),
      Byte(Value shr 16), 0);
  end;

  procedure FileField(Id: TFileItem);
  begin
    AddFile(Files[Id], FileNames[Id], '', ImageFilter);
  end;

begin
  S := BookPreset(bpHardback);
  Group(0, 'プリセット', True);
  Select(bcPreset, '本の種類', Ord(bpHardback), PresetNames);
  AddButton(PresetButton, '設定を反映', ApplyPreset);
  EndGroup(0);
  Group(1, '本体形状', True);
  Track(btWidth, S.Width);
  Track(btRatio, S.Aspect);
  Track(btThickness, S.Thickness);
  Track(btOpeningGap, S.OpeningGap);
  Select(bcBinding, '綴じ方向', Ord(S.Binding), ['左綴じ','右綴じ','上綴じ']);
  Select(bcBindingStyle, '綴じ方', Ord(S.BindingStyle),
    ['上製本','無線綴じ','糸綴じ','リング','和綴じ','留め具付き']);
  AddButton(RatioButton, '画像の縦横比を反映', ApplyImageRatio);
  EndGroup(1);
  Group(2, 'アニメーション', True);
  Select(bcTransition, '切替パターン', 0,
    ['表紙 → ページA','ページA → ページB','ページB → 裏表紙']);
  Select(bcTurn, 'めくり方', 0, ['通常（1枚）','大きく湾曲','複数ページ',
    '連続めくり','ページを探す','風めくり']);
  Track(btProgress, 0);
  Track(btSpeed, S.Speed);
  EndGroup(2);
  Group(3, '表紙');
  Color(ciFront, S.Front.Color);
  Select(bcFront, '表紙の描画', Ord(S.Front.Pattern), CoverNames);
  Track(btFrontThickness, S.Front.Thickness);
  Track(btFrontShine, S.Front.Shine);
  Track(btFrontRadius, S.Front.Radius);
  FileField(fiFrontOut);
  FileField(fiFrontIn);
  EndGroup(3);
  Group(4, 'ページ（共通）');
  Color(ciPaper, S.Paper.Color);
  Color(ciInk, S.Paper.Ink);
  Select(bcPaper, 'ページの描画', Ord(S.Paper.Pattern), ['白紙','横罫線','縦罫線','方眼',
    'ダミー文字（横書き）','ダミー文字（縦書き）','ダミー文字と図形','楽譜']);
  Track(btBulge, S.Paper.Bulge);
  Track(btSoftness, S.Paper.Softness);
  Track(btPaperShine, S.Paper.Shine);
  EndGroup(4);
  Group(5, 'ページA');
  Track(btPositionA, S.A.Position);
  Select(bcStateA, 'ページA状態', Ord(S.A.State), StateNames);
  Select(bcImageA, 'ページA画像形式', Ord(S.A.ImageMode), ImageNames);
  FileField(fiA1);
  FileField(fiA2);
  Select(bcFitA, 'ページA画像配置', Ord(S.A.Fit), FitNames);
  EndGroup(5);
  Group(6, 'ページB');
  Track(btPositionB, S.B.Position);
  Select(bcStateB, 'ページB状態', Ord(S.B.State), StateNames);
  Select(bcImageB, 'ページB画像形式', Ord(S.B.ImageMode), ImageNames);
  FileField(fiB1);
  FileField(fiB2);
  Select(bcFitB, 'ページB画像配置', Ord(S.B.Fit), FitNames);
  EndGroup(6);
  Group(7, '裏表紙');
  Color(ciBack, S.Back.Color);
  Select(bcBack, '裏表紙の描画', Ord(S.Back.Pattern), CoverNames);
  Track(btBackThickness, S.Back.Thickness);
  Track(btBackShine, S.Back.Shine);
  Track(btBackRadius, S.Back.Radius);
  FileField(fiBackOut);
  FileField(fiBackIn);
  EndGroup(7);
  Group(8, '背表紙');
  Color(ciSpine, S.Spine.Color);
  Select(bcSpine, '背表紙の描画', Ord(S.Spine.Pattern), CoverNames);
  Track(btSpineRadius, S.Spine.Radius);
  Track(btSpineShine, S.Spine.Shine);
  FileField(fiSpineOut);
  FileField(fiSpineIn);
  EndGroup(8);
end;

end.
