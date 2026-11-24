unit Book_Settings;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 保存項目から独立した描画設定、プリセットと履歴を持たないアニメーション評価。

interface

type
  TBinding = (bdLeft, bdRight, bdTop);
  TBindingStyle = (bsCase, bsGlue, bsSewn, bsRing, bsJapanese, bsClasp);
  TTransition = (trOpen, trTurn, trClose);
  TTurnStyle = (tsNormal, tsCurl, tsBundle, tsFlip, tsSearch, tsWind);
  TBookPreset = (bpHardback, bpPaperback, bpPocket, bpAntique, bpMagic,
    bpPicture, bpManga, bpMagazine, bpNotebook, bpRing, bpPlanner, bpAlbum,
    bpJapanese);
  TCoverPattern = (cpPlain, cpCloth, cpLeather, cpOrnate);
  TPaperPattern = (ppBlank, ppRuled, ppVertical, ppGrid, ppText, ppVerticalText,
    ppFigures, ppMusic);
  TPageState = (psSpread, psFirst, psLast);
  TImageMode = (imBuiltIn, imSpread, imLeft, imRight, imSeparate);
  TImageFit = (ifStretch, ifCrop);

  TCoverSettings = record
    Color: Cardinal; // RRGGBB
    Pattern: TCoverPattern;
    Thickness, Shine, Radius: Double;
    OutsideFile, InsideFile: string;
  end;

  TPaperSettings = record
    Color, Ink: Cardinal;
    Pattern: TPaperPattern;
    Bulge, Softness, Shine: Double;
  end;

  TSpreadSettings = record
    Position: Double;
    State: TPageState;
    ImageMode: TImageMode;
    Fit: TImageFit;
    File1, File2: string;
  end;

  TBookSettings = record
    Width, Aspect, Thickness, OpeningGap: Double; // OpeningGap は全開から残す角度（度）。
    Binding: TBinding;
    BindingStyle: TBindingStyle;
    Transition: TTransition;
    TurnStyle: TTurnStyle;
    Progress, Speed: Double;
    Front, Back, Spine: TCoverSettings;
    Paper: TPaperSettings;
    A, B: TSpreadSettings;
  end;

  TBookMotion = record
    FrontOpen, BackClose: Double;
    StartPosition, EndPosition: Double;
    Position: Double; // 紙束のうち、読み終えた側へ移った割合
    FromPage, ToPage, PageCount: Integer;
    LeafPhase, LeafStrength: Double;
    LeafCount: Integer;
  end;

// プリセットの値を新規レコードとして返す。画像ファイルは空で返す。
function BookPreset(Preset: TBookPreset): TBookSettings;
function SpreadPosition(const Spread: TSpreadSettings): Double;
// 進行度と区間秒数だけから、表紙、紙束、めくり中の葉を決める。
function BookMotion(const S: TBookSettings; Duration: Double): TBookMotion;

implementation

uses
  System.Math;

type
  TPresetData = record
    Width, Aspect, Thickness, Board: Double;
    Cover, Spine, Paper, Ink: Cardinal;
    Pattern: TCoverPattern;
    Marks: TPaperPattern;
    Style: TBindingStyle;
    Direction: TBinding;
    Bulge, Soft, Shine, Radius, SpineRadius: Double;
  end;

const
  Presets: array[TBookPreset] of TPresetData = (
    (Width:300; Aspect:1.42; Thickness:42; Board:5; Cover:$29493E; Spine:$20392F; Paper:$F3E5CA; Ink:$56453A; Pattern:cpOrnate; Marks:ppText; Style:bsCase; Direction:bdLeft; Bulge:42; Soft:54; Shine:17; Radius:4; SpineRadius:56),
    (Width:280; Aspect:1.51; Thickness:25; Board:1.4; Cover:$395B89; Spine:$32486C; Paper:$F5EADA; Ink:$4F525D; Pattern:cpPlain; Marks:ppText; Style:bsGlue; Direction:bdLeft; Bulge:53; Soft:72; Shine:22; Radius:1; SpineRadius:22),
    (Width:208; Aspect:1.48; Thickness:21; Board:0.8; Cover:$A65A3F; Spine:$7A4734; Paper:$F1DDBB; Ink:$4E4035; Pattern:cpPlain; Marks:ppVerticalText; Style:bsGlue; Direction:bdRight; Bulge:58; Soft:80; Shine:12; Radius:1; SpineRadius:27),
    (Width:307; Aspect:1.36; Thickness:66; Board:6.5; Cover:$714636; Spine:$573529; Paper:$E1BD7C; Ink:$684536; Pattern:cpLeather; Marks:ppText; Style:bsSewn; Direction:bdLeft; Bulge:65; Soft:43; Shine:13; Radius:8; SpineRadius:79),
    (Width:340; Aspect:1.30; Thickness:82; Board:9; Cover:$452C54; Spine:$332340; Paper:$EAD0A2; Ink:$73544E; Pattern:cpOrnate; Marks:ppFigures; Style:bsClasp; Direction:bdLeft; Bulge:55; Soft:38; Shine:30; Radius:12; SpineRadius:82),
    (Width:380; Aspect:0.87; Thickness:29; Board:5.5; Cover:$257E8A; Spine:$1C6671; Paper:$F8EFDC; Ink:$6692A6; Pattern:cpOrnate; Marks:ppFigures; Style:bsCase; Direction:bdLeft; Bulge:25; Soft:30; Shine:30; Radius:11; SpineRadius:38),
    (Width:237; Aspect:1.45; Thickness:31; Board:1.1; Cover:$406079; Spine:$294860; Paper:$EEE7DC; Ink:$514E56; Pattern:cpPlain; Marks:ppFigures; Style:bsGlue; Direction:bdRight; Bulge:55; Soft:75; Shine:12; Radius:1; SpineRadius:25),
    (Width:343; Aspect:1.30; Thickness:10; Board:0.7; Cover:$B34C49; Spine:$90383C; Paper:$F8F4ED; Ink:$4C5965; Pattern:cpPlain; Marks:ppFigures; Style:bsSewn; Direction:bdLeft; Bulge:35; Soft:80; Shine:47; Radius:1; SpineRadius:12),
    (Width:282; Aspect:1.42; Thickness:17; Board:1.2; Cover:$9A7352; Spine:$78553B; Paper:$F8EFDC; Ink:$7290A4; Pattern:cpCloth; Marks:ppRuled; Style:bsSewn; Direction:bdLeft; Bulge:35; Soft:63; Shine:7; Radius:3; SpineRadius:29),
    (Width:286; Aspect:1.30; Thickness:20; Board:1.8; Cover:$467E90; Spine:$304754; Paper:$FBF8ED; Ink:$83A6B6; Pattern:cpCloth; Marks:ppGrid; Style:bsRing; Direction:bdTop; Bulge:27; Soft:62; Shine:15; Radius:8; SpineRadius:18),
    (Width:212; Aspect:1.56; Thickness:31; Board:3.2; Cover:$403E58; Spine:$302D42; Paper:$F5EBDA; Ink:$8D8291; Pattern:cpLeather; Marks:ppGrid; Style:bsSewn; Direction:bdLeft; Bulge:39; Soft:50; Shine:19; Radius:11; SpineRadius:65),
    (Width:394; Aspect:1.05; Thickness:52; Board:6; Cover:$58373D; Spine:$42262F; Paper:$ECE0CC; Ink:$9B8375; Pattern:cpCloth; Marks:ppBlank; Style:bsCase; Direction:bdLeft; Bulge:29; Soft:27; Shine:25; Radius:9; SpineRadius:58),
    (Width:287; Aspect:1.49; Thickness:20; Board:1.5; Cover:$394B73; Spine:$2A3959; Paper:$EEE1C2; Ink:$584F4C; Pattern:cpCloth; Marks:ppVerticalText; Style:bsJapanese; Direction:bdRight; Bulge:58; Soft:67; Shine:7; Radius:2; SpineRadius:12)
  );

function BookPreset(Preset: TBookPreset): TBookSettings;
var
  P: TPresetData;
begin
  P := Presets[Preset];
  Result := Default(TBookSettings);
  Result.Width := P.Width;
  Result.Aspect := P.Aspect;
  Result.Thickness := P.Thickness;
  Result.Binding := P.Direction;
  Result.BindingStyle := P.Style;
  Result.Speed := 50;
  Result.Front.Color := P.Cover;
  Result.Front.Pattern := P.Pattern;
  Result.Front.Thickness := P.Board;
  Result.Front.Shine := P.Shine;
  Result.Front.Radius := P.Radius;
  Result.Back := Result.Front;
  Result.Spine := Result.Front;
  Result.Spine.Color := P.Spine;
  Result.Spine.Radius := P.SpineRadius;
  Result.Paper.Color := P.Paper;
  Result.Paper.Ink := P.Ink;
  Result.Paper.Pattern := P.Marks;
  Result.Paper.Bulge := P.Bulge;
  Result.Paper.Softness := P.Soft;
  Result.Paper.Shine := P.Shine * 0.65;
  Result.A.Position := 35;
  Result.A.Fit := ifCrop;
  Result.B := Result.A;
  Result.B.Position := 65;
end;

function SpreadPosition(const Spread: TSpreadSettings): Double;
begin
  case Spread.State of
    psFirst: Result := 0;
    psLast: Result := 1;
  else
    Result := EnsureRange(Spread.Position * 0.01, 0.0, 1.0);
  end;
end;

function Smooth(T: Double): Double;
begin
  T := EnsureRange(T, 0.0, 1.0);
  Result := T * T * (3 - 2*T);
end;

function BookMotion(const S: TBookSettings; Duration: Double): TBookMotion;
var
  P, Eased, Cursor, Cycle, Envelope: Double;
begin
  Result := Default(TBookMotion);
  P := EnsureRange(S.Progress, 0.0, 1.0);
  Eased := Smooth(P);
  Result.StartPosition := SpreadPosition(S.A);
  Result.EndPosition := SpreadPosition(S.B);
  Result.FrontOpen := 1;
  case S.Transition of
    trOpen:
      begin
        Result.StartPosition := 0;
        Result.FrontOpen := Eased;
        Result.EndPosition := SpreadPosition(S.A);
      end;
    trClose:
      begin
        Result.StartPosition := SpreadPosition(S.B);
        Result.EndPosition := 1;
        Result.BackClose := Eased;
      end;
  end;
  Result.Position := Result.StartPosition + (Result.EndPosition-Result.StartPosition)*Eased;
  // 表紙を起こしてから紙を移す。閉じるときは先に紙をまとめる。
  case S.Transition of
    trOpen: Result.Position := Result.EndPosition*Smooth((P-0.32)/0.68);
    trClose: Result.Position := Result.StartPosition+(1-Result.StartPosition)*Smooth(P/0.72);
  end;
  Result.PageCount := 1;
  Result.ToPage := 1;
  Result.LeafCount := 1;

  if S.TurnStyle in [tsFlip, tsSearch, tsWind] then
    Result.PageCount := EnsureRange(1 + Round(EnsureRange(Duration, 0.0, 60.0) *
      S.Speed * 0.12), 1, 40);

  Cycle := P;
  case S.Transition of
    trOpen: Cycle := EnsureRange((P-0.40)/0.60,0.0,1.0);
    trClose: Cycle := EnsureRange(P/0.60,0.0,1.0);
  end;
  Cursor := Cycle * Result.PageCount;
  Envelope := Sqr(Sin(Pi*Cycle));
  if S.TurnStyle = tsSearch then
    Cursor := Cursor + Min(3.25, Result.PageCount*0.36) *
      Sin(2*Pi*Cycle*(1 + Result.PageCount*0.34)) * Envelope
  else if S.TurnStyle = tsWind then
    Cursor := Cursor + 0.75 * Sin(2*Pi*Cycle*(1 + Result.PageCount*0.5)) * Envelope;

  Cursor := EnsureRange(Cursor, 0.0, Result.PageCount * 1.0);
  if S.Transition = trTurn then
    Result.Position := Result.StartPosition + (Result.EndPosition-Result.StartPosition)*
      Smooth(Cursor/Result.PageCount);
  Result.FromPage := Min(Result.PageCount-1, Floor(Cursor));
  Result.ToPage := Result.FromPage + 1;
  Cycle := Cursor - Result.FromPage;
  Result.LeafPhase := Smooth(Cycle);
  Result.LeafStrength := Sin(Pi * Result.LeafPhase);
  if S.TurnStyle = tsBundle then
    Result.LeafCount := 4;
  if (P <= 0) or (P >= 1) then
    Result.LeafStrength := 0;
end;

end.
