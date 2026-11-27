program Book_RenderTests;

// 実際の AUF2 の登録・編集・ポリゴン送信を、AviUtl2 を起動せずに検査する。

{$APPTYPE CONSOLE}
{$POINTERMATH ON}

uses
  System.SysUtils, System.Classes, System.Math, System.Hash, Winapi.Windows,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas';

type
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  TInitialize = function(Version: Cardinal): Byte; cdecl;
  TRequired = function: Cardinal; cdecl;
  PItemOption = ^TFILTER_ITEM_SELECT_ITEM;
  PItemPointer = ^Pointer;
  TInitItem = record
    Ptr: Pointer;
    Size: Integer;
    Data: array[0..63] of Byte;
  end;

var
  Table: PFILTER_PLUGIN_TABLE;
  Items: array of TInitItem;
  Video: TFILTER_PROC_VIDEO;
  Scene: TSCENE_INFO;
  Obj: TOBJECT_INFO;
  StandardOutput: TOBJECT_IMAGE_PARAM;
  ImageReady: Boolean;
  Edit: TEDIT_SECTION;
  Bytes: TMemoryStream;
  DrawCount, VertexCount, TextureCount, SectionReads: Integer;
  AnchorWidth, AnchorHeight, CameraMode: Integer;
  Paths: TStringList;
  CapturePaperWidth: Integer;
  NewsMargin: TPIXEL_RGBA;
  PaperHashes: TArray<string>;
  CurrentAlpha, MinImageU, MaxImageU, MinImageV, MaxImageV: Single;
  FrontCoverNormalZ, FrontCoverMaxAbsZ: Single;
  PresetWrites: TStringList;
  Reply: UTF8String;
  ImagePath, TestPresetName: string;

procedure Check(Value: Boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
end;

function Item(const Name: string): Pointer;
var
  P: PItemPointer;
begin
  P := PItemPointer(Table^.Items);
  while P^ <> nil do
  begin
    if Name = PFILTER_ITEM_TRACK(P^)^.Name then Exit(P^);
    Inc(P);
  end;
  raise Exception.Create('Missing item: '+Name);
end;

procedure RecordDefaults;
var
  P: PItemPointer;
  Entry: TInitItem;
  Kind, Name: string;
  GroupCount, CloseCount: Integer;
begin
  P := PItemPointer(Table^.Items);
  GroupCount := 0;
  CloseCount := 0;
  while P^ <> nil do
  begin
    Kind := PFILTER_ITEM_TRACK(P^)^.ItemType;
    Name := PFILTER_ITEM_TRACK(P^)^.Name;
    Check((Name<>'基本設定') and (Name<>'X') and (Name<>'Y') and (Name<>'Z') and
      (Name<>'X軸回転') and (Name<>'Y軸回転') and (Name<>'Z軸回転') and
      (Name<>'拡大率') and (Name<>'透明度'),'Duplicate draw parameter: '+Name);
    Entry := Default(TInitItem);
    Entry.Ptr := P^;
    if Kind = 'track' then Entry.Size := SizeOf(TFILTER_ITEM_TRACK)
    else if Kind = 'select' then Entry.Size := SizeOf(TFILTER_ITEM_SELECT)
    else if Kind = 'color' then Entry.Size := SizeOf(TFILTER_ITEM_COLOR)
    else if Kind = 'file' then Entry.Size := SizeOf(TFILTER_ITEM_FILE)
    else if Kind = 'group' then
    begin
      if PFILTER_ITEM_GROUP(P^)^.Name^ = #0 then Inc(CloseCount)
      else Inc(GroupCount);
    end;
    if Entry.Size > 0 then
    begin
      Move(PByte(Entry.Ptr)^,Entry.Data[0],Entry.Size);
      Items := Items + [Entry];
    end;
    Inc(P);
    Check(NativeUInt(P)-NativeUInt(Table^.Items) < 100*SizeOf(Pointer),'Unterminated table');
  end;
  Check((GroupCount=9) and (CloseCount=9),'Group count or nesting');
end;

procedure RestoreDefaults;
var
  Entry: TInitItem;
begin
  for Entry in Items do
    Move(Entry.Data[0],PByte(Entry.Ptr)^,Entry.Size);
end;

procedure Track(const Name: string; Value: Double);
begin
  PFILTER_ITEM_TRACK(Item(Name))^.Value := Value;
end;

procedure Select(const Name: string; Value: Integer);
begin
  PFILTER_ITEM_SELECT(Item(Name))^.Value := Value;
end;

procedure FileItem(const Name: string; Value: PWideChar);
begin
  PFILTER_ITEM_FILE(Item(Name))^.Value := Value;
end;

procedure SetBaseImage(Pixels: PPIXEL_RGBA; Width, Height: Integer); cdecl;
begin
  Check((Width=1) and (Height=1) and (Pixels<>nil) and (Pixels^.A=255),
    'Invalid base image for media object');
  ImageReady := True;
end;

function ReadStandardOutput(Handle: OBJECT_HANDLE; Offset: Double;
  Output: POBJECT_IMAGE_PARAM; Size: Integer): Boolean; cdecl;
begin
  Check(ImageReady,'Standard output queried before creating the base image');
  Check((Handle=nil) and (Offset=0) and (Size=SizeOf(StandardOutput)) and
    (Output<>nil),'Invalid standard output query');
  Output^ := StandardOutput;
  Result := True;
end;

function CaptureDraw(Kind: Integer; Vertices: Pointer; Count: Integer;
  Resource: LPCWSTR): Boolean; cdecl;
var
  I, Stride, AlphaOffset: Integer;
  P: ^Single;
  T: ^TVertexTextureNorm;
  Name: string;
begin
  Check(ImageReady,'DrawPoly called before creating the base image');
  Check((Count > 0) and (Count mod 4=0),'Invalid quad count');
  if Kind=VERTEX_QUAD_COLOR_NORM then
  begin
    Stride := SizeOf(TVertexColorNorm);
    AlphaOffset := 6;
  end else
  begin
    Check(Kind=VERTEX_QUAD_TEXTURE_NORM,'Unexpected vertex type');
    Stride := SizeOf(TVertexTextureNorm);
    AlphaOffset := 5;
  end;
  for I := 0 to Count-1 do
    Check(PSingle(NativeUInt(Vertices)+NativeUInt(I*Stride+AlphaOffset*SizeOf(Single)))^=1,
      'Standard output alpha was applied to a vertex');
  P := Vertices;
  for I := 0 to Count*(Stride div SizeOf(Single))-1 do
  begin
    Check(not IsNan(P^) and not IsInfinite(P^),'Non-finite vertex');
    Inc(P);
  end;
  if Resource <> nil then
  begin
    Name := Resource;
    Bytes.WriteBuffer(PWideChar(Name)^,Length(Name)*SizeOf(WideChar));
    if Name.StartsWith('image:') then
    begin
      Paths.Add(Name);
      T := Vertices;
      for I := 0 to Count-1 do
      begin
        MinImageU := Min(MinImageU,T^.U);
        MaxImageU := Max(MaxImageU,T^.U);
        MinImageV := Min(MinImageV,T^.V);
        MaxImageV := Max(MaxImageV,T^.V);
        if Name='image:mock-opening-angle' then
        begin
          FrontCoverNormalZ := T^.NZ;
          FrontCoverMaxAbsZ := Max(FrontCoverMaxAbsZ,Abs(T^.Z));
        end;
        Inc(T);
      end;
    end;
  end;
  Bytes.WriteBuffer(Kind,SizeOf(Kind));
  Bytes.WriteBuffer(Vertices^,Count*Stride);
  Inc(DrawCount);
  Inc(VertexCount,Count);
  Result := True;
end;

procedure CaptureTexture(Name: LPCWSTR; Pixels: PPIXEL_RGBA; Width, Height: Integer); cdecl;
var
  Hash: THashSHA2;
  Size: Integer;
begin
  Check((Pixels<>nil) and (Width>0) and (Height>0),'Empty texture');
  Check(Pixels^.A=255,'Unexpected built-in alpha');
  Size := Width*Height*SizeOf(TPIXEL_RGBA);
  Bytes.WriteBuffer(Pixels^,Size);
  Inc(TextureCount);
  if Width=CapturePaperWidth then
  begin
    if CapturePaperWidth=320 then
    begin
      if Length(PaperHashes)=0 then NewsMargin := Pixels^
      else Check(CompareMem(Pixels,@NewsMargin,SizeOf(NewsMargin)),
        'Newspaper faces must have the same unprinted paper stock');
    end;
    Hash := THashSHA2.Create;
    Hash.Update(Pixels^,Size);
    PaperHashes := PaperHashes+[Hash.HashAsString];
  end;
end;

function MockImageSize(Name: LPCWSTR; Width, Height: PInteger): Boolean; cdecl;
begin
  Result := string(Name).StartsWith('image:mock-');
  if Result then
  begin
    Width^ := 800;
    Height^ := 540;
  end;
end;

procedure SetAnchor(Width, Height: Integer); cdecl;
begin
  AnchorWidth := Width;
  AnchorHeight := Height;
end;

procedure SetShine(Value: Single); cdecl;
begin
  CurrentAlpha := Value;
end;

function ReadCameraMode: Integer; cdecl;
begin
  Result := CameraMode;
end;

function ReadSection(Handle: OBJECT_HANDLE; Index: Integer): Integer; cdecl;
begin
  Inc(SectionReads);
  case Index of
    0: Result := 100;
    1: Result := 115;
    2: Result := 160;
  else
    Result := -1;
  end;
end;

function ReadEditItem(Handle: OBJECT_HANDLE; Effect, Name: LPCWSTR): PAnsiChar; cdecl;
begin
  Reply := '';
  if string(Name)='本の種類' then Reply := UTF8String(TestPresetName);
  if string(Name)='表紙の外側画像' then Reply := UTF8String(ImagePath);
  Result := PAnsiChar(Reply);
end;

function WriteEditItem(Handle: OBJECT_HANDLE; Effect, Name: LPCWSTR;
  Value: PAnsiChar): Boolean; cdecl;
begin
  PresetWrites.Values[string(Name)] := UTF8ToString(Value);
  Result := True;
end;

function Render(const Digest: Boolean = True): string;
begin
  Paths.Clear;
  PaperHashes := nil;
  ImageReady := False;
  Bytes.Size := 0;
  DrawCount := 0;
  VertexCount := 0;
  TextureCount := 0;
  AnchorWidth := 0;
  CurrentAlpha := -1;
  MinImageU := 1; MaxImageU := 0; MinImageV := 1; MaxImageV := 0;
  FrontCoverNormalZ := -2;
  FrontCoverMaxAbsZ := 0;
  Check(Table^.Func_Proc_Video(@Video)=0,'Host image was not suppressed');
  Check((DrawCount > 0) and (VertexCount > 100) and (TextureCount > 0),'Empty book');
  Check((AnchorWidth > 0) and (AnchorHeight > 0),'Anchor missing');
  Check(CurrentAlpha=0,'Material state was not reset');
  Result := '';
  if Digest then
  begin
    Bytes.Position := 0;
    Result := THashSHA2.GetHashString(Bytes);
  end;
end;

procedure ApplyMockValues;
var
  Index, OptionIndex: Integer;
  Value, Kind: string;
  P: Pointer;
  Selector: PFILTER_ITEM_SELECT;
  Option: PItemOption;
  Color: Integer;
begin
  for Index := 0 to PresetWrites.Count-1 do
  begin
    P := Item(PresetWrites.Names[Index]);
    Value := PresetWrites.ValueFromIndex[Index];
    Kind := PFILTER_ITEM_TRACK(P)^.ItemType;
    if Kind='track' then
      PFILTER_ITEM_TRACK(P)^.Value := StrToFloat(Value,TFormatSettings.Invariant)
    else if Kind='color' then
    begin
      Color := StrToInt('$'+Value);
      PFILTER_ITEM_COLOR(P)^.R := Byte(Color shr 16);
      PFILTER_ITEM_COLOR(P)^.G := Byte(Color shr 8);
      PFILTER_ITEM_COLOR(P)^.B := Byte(Color);
    end else if Kind='select' then
    begin
      Selector := P;
      Option := PItemOption(Selector^.List);
      OptionIndex := 0;
      while (Option[OptionIndex].Name<>nil) and
        (Value<>Option[OptionIndex].Name) do Inc(OptionIndex);
      Check(Option[OptionIndex].Name<>nil,'Preset selected an unknown option');
      Selector^.Value := Option[OptionIndex].Value;
    end else
      raise Exception.Create('Unexpected preset write');
  end;
end;

procedure VerifyStandardOutput;
var
  Saved: TOBJECT_IMAGE_PARAM;
  LocalHash, OrderedHash: string;
  Width, Height: Integer;
begin
  Saved := StandardOutput;
  CameraMode := 1;
  LocalHash := Render;
  Width := AnchorWidth;
  Height := AnchorHeight;
  CameraMode := 0;
  OrderedHash := Render;

  StandardOutput.X := -130;
  StandardOutput.Y := 46;
  StandardOutput.Z := 34;
  StandardOutput.RX := -135;
  StandardOutput.RY := 21;
  StandardOutput.RZ := -8;
  StandardOutput.SX := 1.5;
  StandardOutput.SY := 2.0;
  StandardOutput.SZ := 1.5;
  StandardOutput.CX := 32;
  StandardOutput.CY := -12;
  StandardOutput.CZ := 7;
  Check(Render<>OrderedHash,'Standard rotation did not affect drawing order');
  Check((AnchorWidth=Width) and (AnchorHeight=Height),'Anchor was scaled twice');

  CameraMode := 1;
  Check(Render=LocalHash,'Standard transform was applied to camera vertices');
  StandardOutput.Alpha := 0.4;
  Render(False);
  CameraMode := 0;
  StandardOutput := Saved;
end;

procedure VerifyOpeningGap;
var
  Gap: PFILTER_ITEM_TRACK;
  Binding: Integer;
begin
  Gap := Item('開き残し角度');
  Check((Gap^.S=0) and (Gap^.E=140) and (Gap^.Value=0),'Opening gap range or default');
  FileItem('表紙の外側画像','mock-opening-angle');
  for Binding := 0 to 2 do
  begin
    Select('綴じ方向',Binding);
    Track('進行度',1);
    Track('開き残し角度',0);
    Render(False);
    Check((Abs(FrontCoverNormalZ-1)<1e-6) and (FrontCoverMaxAbsZ<1e-5),
      'Front cover is not flat at the fully open endpoint');
    Track('開き残し角度',30);
    Render(False);
    Check(Abs(FrontCoverNormalZ-Cos(DegToRad(30.0)))<1e-6,
      'Front cover did not stop 30 degrees short of flat');
  end;
  RestoreDefaults;
end;

procedure VerifyPaperVariation;
var
  A, B: TArray<string>;
  I, J: Integer;
  MidHash: string;
begin
  CameraMode := 1;
  CapturePaperWidth := 224;
  FileItem('表紙の外側画像','mock-board');
  FileItem('表紙の内側画像','mock-board');
  FileItem('裏表紙の外側画像','mock-board');
  FileItem('裏表紙の内側画像','mock-board');
  FileItem('背表紙の外側画像','mock-board');
  FileItem('背表紙の内側画像','mock-board');
  Select('切替パターン',1);
  Track('進行度',0);
  Render(False);
  A := PaperHashes;
  Check((Length(A)=2) and (A[0]<>A[1]),'Both sides of spread A have the same paper');
  Track('進行度',1);
  Render(False);
  B := PaperHashes;
  Check((Length(B)=2) and (B[0]<>B[1]) and (B[0]<>A[0]) and (B[1]<>A[1]),
    'Changing page position did not change the paper on both sides');

  Track('進行度',0);
  Track('ページA位置',65);
  Render(False);
  Check((Length(PaperHashes)=2) and (PaperHashes[0]=B[0]) and (PaperHashes[1]=B[1]),
    'The same spread did not reproduce its paper after reusing it as A');

  Track('ページA位置',35);
  Select('めくり方',2);
  Track('進行度',0.5);
  MidHash := Render;
  Check(Length(PaperHashes)=10,'A bundle must supply paper for both sides of all four sheets');
  for I := 0 to High(PaperHashes) do
    for J := 0 to I-1 do
      Check(PaperHashes[I]<>PaperHashes[J],'A bundle reused the same paper on multiple faces');
  Track('進行度',0.67);
  Render(False);
  Track('進行度',0.5);
  Check(Render=MidHash,'Bundle paper changed after seeking');

  Select('めくり方',3);
  Track('進行度',0.15);
  Render(False);
  A := PaperHashes;
  Track('進行度',0.25);
  Render(False);
  B := PaperHashes;
  Check((Length(A)=4) and (Length(B)=4),'Continuous turning did not produce virtual paper');
  Check((B[0]=A[3]) and (B[2]=A[1]),'Virtual paper changed between consecutive turns');
  Check((B[1]<>A[1]) and (B[3]<>A[3]),'Consecutive turns reused virtual paper');

  CapturePaperWidth := 0;
  CameraMode := 0;
  RestoreDefaults;
end;

procedure VerifyNewspaper;
var
  Original: TArray<string>;
  I, J: Integer;
begin
  Check((PresetWrites.Values['綴じ方向']='左綴じ') and
    (PresetWrites.Values['綴じ方']='折り') and
    (PresetWrites.Values['表紙の描画']='新聞紙') and
    (PresetWrites.Values['裏表紙の描画']='新聞紙') and
    (PresetWrites.Values['ページの描画']='新聞記事'),'Newspaper preset settings');
  Check((PresetWrites.Values['表紙の色']=PresetWrites.Values['用紙色']) and
    (PresetWrites.Values['裏表紙の色']=PresetWrites.Values['用紙色']) and
    (PresetWrites.Values['表紙の光沢']='0') and
    (PresetWrites.Values['裏表紙の光沢']='0') and
    (PresetWrites.Values['ページの光沢']='0'),'Newspaper stock settings');
  CameraMode := 1;
  CapturePaperWidth := 320;
  Select('切替パターン',1);
  Track('進行度',0);
  Render(False);
  Original := PaperHashes;
  Check(Length(Original)=6,'Newspaper must render four cover faces and two inside pages');
  for I := 0 to High(Original) do
    for J := 0 to I-1 do
      Check(Original[I]<>Original[J],'Newspaper faces must have distinct print layouts');

  Track('進行度',1);
  Render(False);
  Check((Length(PaperHashes)=6) and (PaperHashes[4]<>Original[4]) and
    (PaperHashes[5]<>Original[5]),'Newspaper articles must vary with page position');

  Track('進行度',0);
  PresetWrites.Values['描画色'] := '762c2c';
  ApplyMockValues;
  Render(False);
  Check(Length(PaperHashes)=6,'Newspaper faces missing after changing print color');
  for I := 0 to High(Original) do
    Check(PaperHashes[I]<>Original[I],'Newspaper face reused its previous print color');

  FileItem('裏表紙の外側画像','mock-newspaper');
  Render(False);
  Check((Length(PaperHashes)=5) and (Paths.IndexOf('image:mock-newspaper')>=0),
    'Newspaper rear cover must accept a custom image');
  CapturePaperWidth := 0;
  CameraMode := 0;
  RestoreDefaults;
end;

procedure Verify;
var
  Preset, Style, Transition, Binding: Integer;
  StartHash, EndHash, MidHash, PreviousHash: string;
  Options: PItemOption;
  Progress: PFILTER_ITEM_TRACK;
  PresetHashes: TArray<string>;
begin
  RecordDefaults;
  Check(Table^.Flag=21,'Expected a video media object with userdata');
  Check((string(Table^.Name)='本演出') and (string(Table^.Label_)='SYNC'),'Registration name');
  Progress := Item('進行度');
  Check((Progress^.S=0) and (Progress^.E=1) and
    (Abs(Progress^.Step-0.01)<1e-9) and (Progress^.Value=0),'Progress range');
  Options := PItemOption(PFILTER_ITEM_SELECT(Item('本の種類'))^.List);
  Check((Options[12].Name<>nil) and (string(Options[13].Name)='新聞') and
    (Options[14].Name=nil),'Preset count and newspaper option');

  MidHash := Render;
  Check(MidHash=Render,'Default frame changed after caching');
  Writeln('Default frame SHA256 ',MidHash);
  VerifyStandardOutput;
  VerifyOpeningGap;
  VerifyPaperVariation;
  TestPresetName := 'リングノート';
  PFILTER_ITEM_BUTTON(Item('設定を反映'))^.Callback2(@Edit, Obj.Handle, '本演出', '設定を反映');
  Check((PresetWrites.Values['綴じ方向']='上綴じ') and
    (PresetWrites.Values['綴じ方']='リング') and
    (PresetWrites.Values['横幅']='286') and (PresetWrites.Count=26),'Preset did not apply');
  if ImagePath<>'' then
  begin
    PFILTER_ITEM_BUTTON(Item('画像の縦横比を反映'))^.Callback2(@Edit,Obj.Handle,
      '本演出','画像の縦横比を反映');
    Check(PresetWrites.Values['縦横比']='1.5','Image aspect was not applied');
  end;

  for Preset := 0 to 13 do
  begin
    RestoreDefaults;
    TestPresetName := Options[Preset].Name;
    PresetWrites.Clear;
    Select('本の種類',Preset);
    Check(Options[Preset].Value=Preset,'Preset selector order');
    PFILTER_ITEM_BUTTON(Item('設定を反映'))^.Callback2(@Edit,Obj.Handle,'本演出','設定を反映');
    Check(PresetWrites.Count=26,'Preset fields missing');
    Check(PresetWrites.Values['開き残し角度']='0','Preset must open flat by default');
    ApplyMockValues;
    Track('進行度',1);
    MidHash := Render;
    for PreviousHash in PresetHashes do
      Check(MidHash<>PreviousHash,'Presets render identical books');
    PresetHashes := PresetHashes+[MidHash];
  end;
  VerifyNewspaper;

  RestoreDefaults;
  for Binding := 0 to 2 do
  begin
    Select('綴じ方向',Binding);
    for Transition := 0 to 2 do
    begin
      Select('切替パターン',Transition);
      for Style := 0 to 5 do
      begin
        Select('めくり方',Style);
        Track('進行度',0);
        if Style=0 then StartHash := Render else Check(Render=StartHash,'Start pose changed by style');
        Track('進行度',1);
        if Style=0 then EndHash := Render else Check(Render=EndHash,'End pose changed by style');
        Check(StartHash<>EndHash,'Transition endpoints are identical');
        Track('進行度',0.46);
        MidHash := Render;
        Check((MidHash<>StartHash) and (MidHash<>EndHash),'Intermediate geometry missing');
        Track('進行度',0.81);
        Render(False);
        Track('進行度',0.46);
        Check(Render=MidHash,'Frame varies after reverse seek');
      end;
    end;
  end;
  Check(SectionReads>0,'Timeline section API was not used');
  RestoreDefaults;
  Select('切替パターン',1);
  Select('めくり方',3);
  Track('進行度',0.37);
  MidHash := Render;
  Edit.GetObjectSectionFrame := nil;
  Check(Render<>MidHash,'Section duration did not affect flip speed');
  Edit.GetObjectSectionFrame := ReadSection;

  RestoreDefaults;
  Select('切替パターン',1);
  CameraMode := 1;
  for Style := 0 to 5 do
  begin
    Select('めくり方',Style);
    Track('進行度',0.48);
    Render(False);
  end;
  CameraMode := 0;
  RestoreDefaults;
  Select('ページA状態',1);
  FileItem('表紙の内側画像','mock-lining');
  Select('ページA画像形式',4);
  FileItem('ページA画像1','mock-left');
  FileItem('ページA画像2','mock-right');
  Track('進行度',1);
  PreviousHash := Render;
  Check((Paths.IndexOf('image:mock-lining')>=0) and
    (Paths.IndexOf('image:mock-left')<0) and (Paths.IndexOf('image:mock-right')>=0),
    'First page did not use the inside of the front cover');
  Select('切替パターン',1);
  Track('進行度',0);
  Check(Render=PreviousHash,'Cover-to-A and A-to-B do not connect');

  RestoreDefaults;
  Select('切替パターン',1);
  Select('ページB状態',2);
  FileItem('裏表紙の内側画像','mock-back');
  Select('ページB画像形式',4);
  FileItem('ページB画像1','mock-left');
  FileItem('ページB画像2','mock-right');
  Track('進行度',1);
  PreviousHash := Render;
  Check((Paths.IndexOf('image:mock-back')>=0) and
    (Paths.IndexOf('image:mock-left')>=0) and (Paths.IndexOf('image:mock-right')<0),
    'Last page did not use the inside of the back cover');
  Select('切替パターン',2);
  Track('進行度',0);
  Check(Render=PreviousHash,'A-to-B and B-to-back do not connect');

  RestoreDefaults;
  Track('進行度',1);
  Select('ページA画像形式',1);
  Select('ページA画像配置',0);
  FileItem('ページA画像1','mock-spread');
  Render(False);
  Check((MinImageU<0.2) and (MaxImageU>0.8),'Horizontal UV split missing');
  Select('綴じ方向',2);
  Render(False);
  Check((MinImageV<0.2) and (MaxImageV>0.8),'Vertical UV split missing');
  Select('ページA画像配置',1);
  Render(False);
  Check((MinImageU>0.2) and (MaxImageU<0.8),'Spread crop was not applied');
  Select('ページA画像形式',2);
  FileItem('ページA画像2','mock-unused');
  Render(False);
  Check((Paths.Count=1) and (Paths[0]='image:mock-spread'),'Single page image was not isolated');

  RestoreDefaults;
  FileItem('表紙の外側画像','invalid');
  Render(False);
  Track('厚さ',1);
  Track('進行度',0.23);
  StandardOutput.RX := 74;
  StandardOutput.RY := 89;
  Render(False);
  Track('厚さ',450);
  Track('開き残し角度',140);
  Render(False);
end;

var
  DLL: HMODULE;
  Initialize: TInitialize;
  Required: TRequired;
  GetTable: TGetTable;
begin
  try
    Check(ParamCount>=1,'Specify the AUF2 path');
    if ParamCount>=2 then ImagePath := ParamStr(2);
    DLL := LoadLibrary(PWideChar(ParamStr(1)));
    Check(DLL<>0,'Could not load AUF2');
    try
      Initialize := TInitialize(GetProcAddress(DLL,'InitializePlugin'));
      Required := TRequired(GetProcAddress(DLL,'RequiredVersion'));
      GetTable := TGetTable(GetProcAddress(DLL,'GetFilterPluginTable'));
      Check(Assigned(Initialize) and Assigned(Required) and Assigned(GetTable),'Missing export');
      Check(Required=2011600,'Minimum host version');
      Check(Initialize(2011500)=0,'Unsupported version accepted');
      Check(Initialize(2011700)=1,'Could not initialize');
      Table := GetTable;
      Check(Table<>nil,'Missing table');
      Bytes := TMemoryStream.Create;
      Paths := TStringList.Create;
      Paths.Sorted := True;
      Paths.Duplicates := dupIgnore;
      PresetWrites := TStringList.Create;
      Obj.Handle := @Obj;
      Obj.FrameS := 100;
      Obj.FrameE := 219;
      Obj.FrameTotal := 120;
      Obj.Frame := 29;
      Obj.TimeTotal := 4;
      Scene.Rate := 30;
      Scene.Scale := 1;
      Edit.GetObjectSectionFrame := ReadSection;
      Edit.GetObjectItemValue := ReadEditItem;
      Edit.SetObjectItemValue := WriteEditItem;
      Video.Scene := @Scene;
      Video.Object_ := @Obj;
      Video.Edit := @Edit;
      StandardOutput.SX := 1;
      StandardOutput.SY := 1;
      StandardOutput.SZ := 1;
      StandardOutput.Alpha := 1;
      Video.SetImageData := SetBaseImage;
      Video.GetOutputImageParam := ReadStandardOutput;
      Video.DrawPoly := CaptureDraw;
      Video.CreateImageResource := CaptureTexture;
      Video.GetImageResourceSize := MockImageSize;
      Video.SetDefaultAnchor := SetAnchor;
      Video.SetMaterialShine := SetShine;
      Video.GetCameraMode := ReadCameraMode;
      Video.UserData := Table^.Func_Create(42);
      Check(Video.UserData<>nil,'Missing render session');
      try
        Verify;
        Writeln('PASS: AUF2 registration, editing, materials, geometry and frame reproduction');
      finally
        Table^.Func_Destroy(42,Video.UserData);
        PresetWrites.Free;
        Paths.Free;
        Bytes.Free;
      end;
      Initialize(2011600);
    finally
      FreeLibrary(DLL);
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput,E.ClassName,': ',E.Message);
      Halt(1);
    end;
  end;
end.
