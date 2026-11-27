unit Book_Mesh;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 本の局所座標は U=綴じ目から小口、V=背の長手方向、H=接地面からの高さ。

interface

uses
  Book_Settings;

type
  TBookVector = record
    U, V, H: Double;
  end;

  TTextureKind = (txSolid, txCover, txLining, txSpine, txPaper, txPaperEdge, txGutter);
  TSlice = (slWhole, slLeft, slRight, slTop, slBottom);
  TBookMaterial = record
    Kind: TTextureKind;
    Color, Ink: Cardinal;
    Pattern, Seed: Integer;
    Shine, Aspect: Double;
    Path: string;
    Fit: TImageFit;
    Slice: TSlice;
  end;

  TBookVertex = record
    Pos, Normal: TBookVector;
    S, T: Single;
  end;
  TBookQuad = record
    Vertices: array[0..3] of TBookVertex;
    Material: Integer;
  end;

  TBookMesh = class
  private
    FMaterials: array of TBookMaterial;
    FQuads: array of TBookQuad;
    FMaterialCount, FQuadCount: Integer;
    FBoardMaterialCount, FBoardQuadCount: Integer;
    FStructure: TBookSettings;
    FBoardPose: array[0..5] of Double;
    procedure ResetCounts(MaterialCount, QuadCount: Integer);
  public
    property Materials: TArray<TBookMaterial> read FMaterials;
    property Quads: TArray<TBookQuad> read FQuads;
    property MaterialCount: Integer read FMaterialCount;
    property QuadCount: Integer read FQuadCount;
    // ビルド済みバッファを再利用し、各カウント未満の要素を更新する。
    procedure Build(const S: TBookSettings; const M: TBookMotion);
    function AddMaterial(const Material: TBookMaterial): Integer;
    procedure AddQuad(Material: Integer; const A, B, C, D: TBookVertex;
      Reverse: Boolean = False);
  end;

function Vec(U, V, H: Double): TBookVector;
function Difference(const A, B: TBookVector): TBookVector;
function Cross(const A, B: TBookVector): TBookVector;
function UnitVector(const A: TBookVector): TBookVector;

implementation

uses
  System.Math, System.SysUtils;

const
  PageStrips = 24;
  PageRows = 8;
  SpineStrips = 12;

type
  TRibbonPoint = record
    U, H, Width: Double;
  end;
  TRibbon = array[0..PageStrips] of TRibbonPoint;
  THinge = record
    U, H, Angle: Double;
    function Point(Across, Along, Normal: Double): TBookVector;
  end;
  TMeshBuilder = record
    Mesh: TBookMesh;
    Settings: TBookSettings;
    Span, Length, Inset, BoardFront, BoardBack, Block, Seam: Double;
    Front, Back: THinge;
    function ColorMaterial(Color: Cardinal; Shine: Double = 0): Integer;
    function CoverMaterial(const Cover: TCoverSettings; Kind: TTextureKind;
      const Path: string; Aspect: Double; NewsPage: TPaperPattern = ppNewsStock;
      Seed: Integer = 0): Integer;
    function PaperMaterial(Page: Integer; LeftSide: Boolean; const M: TBookMotion): Integer;
    function FaceVertex(const Pos, Normal: TBookVector; U, V: Double;
      Positive: Boolean): TBookVertex;
    procedure SolidQuad(Material: Integer; const A, B, C, D: TBookVector);
    procedure Surface(const Axis: TRibbon; DrawLength, Crown: Double;
      Material: Integer; Positive: Boolean);
    procedure Board(const Hinge: THinge; const Cover: TCoverSettings;
      Thickness: Double; IsFront: Boolean);
    function StackAxis(const Hinge: THinge; Normal, Crown, Across: Double): TRibbon;
    procedure Stack(const Top, Bottom: TRibbon; Thickness, DrawLength, Crown: Double;
      Material: Integer; Positive: Boolean);
    procedure Spine;
    procedure Gutter(const LeftAxis, RightAxis: TRibbon);
    procedure Bindings;
    procedure Leaf(const RightAxis, LeftAxis: TRibbon; Phase, Strength, Depth: Double;
      FrontMat, BackMat: Integer);
    procedure BuildBoards;
    procedure Build(const M: TBookMotion);
  end;

function Vec(U, V, H: Double): TBookVector;
begin
  Result.U := U;
  Result.V := V;
  Result.H := H;
end;

function Difference(const A, B: TBookVector): TBookVector;
begin
  Result := Vec(A.U-B.U, A.V-B.V, A.H-B.H);
end;

function Cross(const A, B: TBookVector): TBookVector;
begin
  Result := Vec(A.V*B.H-A.H*B.V, A.H*B.U-A.U*B.H, A.U*B.V-A.V*B.U);
end;

function UnitVector(const A: TBookVector): TBookVector;
var
  Magnitude: Double;
begin
  Magnitude := Sqrt(Sqr(A.U) + Sqr(A.V) + Sqr(A.H));
  if Magnitude < 1e-12 then Exit(Vec(0,0,1));
  Result := Vec(A.U/Magnitude, A.V/Magnitude, A.H/Magnitude);
end;

function Mix(A, B, T: Double): Double;
begin
  Result := A + (B-A)*T;
end;

function Smooth(T: Double): Double;
begin
  T := EnsureRange(T, 0.0, 1.0);
  Result := T*T*(3-2*T);
end;

function Shade(Color: Cardinal; Factor: Double): Cardinal;
begin
  Result := (Cardinal(Min(255, Round(((Color shr 16) and 255)*Factor))) shl 16) or
    (Cardinal(Min(255, Round(((Color shr 8) and 255)*Factor))) shl 8) or
    Cardinal(Min(255, Round((Color and 255)*Factor)));
end;

function TBookMesh.AddMaterial(const Material: TBookMaterial): Integer;
begin
  Result := FMaterialCount;
  if FMaterialCount = System.Length(FMaterials) then
    SetLength(FMaterials, Max(32, FMaterialCount*2));
  FMaterials[Result] := Material;
  Inc(FMaterialCount);
end;

procedure TBookMesh.AddQuad(Material: Integer; const A, B, C, D: TBookVertex;
  Reverse: Boolean);
var
  Quad: ^TBookQuad;
begin
  if FQuadCount = System.Length(FQuads) then
    SetLength(FQuads, Max(2048, FQuadCount*2));
  Quad := @FQuads[FQuadCount];
  Inc(FQuadCount);
  Quad^.Material := Material;
  Quad^.Vertices[0] := A;
  Quad^.Vertices[2] := C;
  if Reverse then
  begin
    Quad^.Vertices[1] := D;
    Quad^.Vertices[3] := B;
  end else
  begin
    Quad^.Vertices[1] := B;
    Quad^.Vertices[3] := D;
  end;
end;

function THinge.Point(Across, Along, Normal: Double): TBookVector;
begin
  Result := Vec(U + Across*Cos(Angle) - Normal*Sin(Angle), Along,
    H + Across*Sin(Angle) + Normal*Cos(Angle));
end;

function TMeshBuilder.ColorMaterial(Color: Cardinal; Shine: Double): Integer;
var
  Mat: TBookMaterial;
begin
  Mat := Default(TBookMaterial);
  Mat.Color := Color;
  Mat.Shine := Shine;
  Result := Mesh.AddMaterial(Mat);
end;

function TMeshBuilder.CoverMaterial(const Cover: TCoverSettings;
  Kind: TTextureKind; const Path: string; Aspect: Double; NewsPage: TPaperPattern;
  Seed: Integer): Integer;
var
  Mat: TBookMaterial;
begin
  Mat := Default(TBookMaterial);
  Mat.Kind := Kind;
  Mat.Color := Cover.Color;
  Mat.Pattern := Ord(Cover.Pattern);
  Mat.Shine := Cover.Shine;
  Mat.Path := Path;
  Mat.Aspect := Aspect;
  if Cover.Pattern = cpNewsprint then
  begin
    Mat.Kind := txPaper;
    Mat.Ink := Settings.Paper.Ink;
    Mat.Pattern := Ord(NewsPage);
    Mat.Seed := Seed;
  end;
  Result := Mesh.AddMaterial(Mat);
end;

function TMeshBuilder.PaperMaterial(Page: Integer; LeftSide: Boolean;
  const M: TBookMotion): Integer;
const
  PositionSteps = 10000; // ページ位置 0～100 の 0.01 刻み。
var
  Mat: TBookMaterial;
  Spread: TSpreadSettings;
  DisplayLeft, RealPage: Boolean;
begin
  Mat := Default(TBookMaterial);
  Mat.Kind := txPaper;
  Mat.Color := Settings.Paper.Color;
  Mat.Ink := Settings.Paper.Ink;
  Mat.Pattern := Ord(Settings.Paper.Pattern);
  Mat.Shine := Settings.Paper.Shine;
  Mat.Aspect := (Length-2*Inset)/(Span-2*Inset);
  if Settings.Binding = bdTop then Mat.Aspect := 1/Mat.Aspect;
  RealPage := True;
  case Settings.Transition of
    trOpen:
      begin
        RealPage := Page = M.PageCount;
        Spread := Settings.A;
      end;
    trClose:
      begin
        RealPage := Page = 0;
        Spread := Settings.B;
      end;
  else
    if Page = 0 then
      Spread := Settings.A
    else if Page = M.PageCount then
      Spread := Settings.B
    else
      RealPage := False;
  end;
  if not RealPage then
  begin
    // 仮想ページは区間の始点・終点と順番から割り当てる。
    Mat.Seed := 2*(PositionSteps+1 + Page*127 +
      Round(M.StartPosition*PositionSteps)*17 + Round(M.EndPosition*PositionSteps)*31)
      + Ord(LeftSide) + 1;
    Exit(Mesh.AddMaterial(Mat));
  end;

  // 同じ紙面を隣のオブジェクトで A / B に入れ替えても模様を引き継ぐ。
  Mat.Seed := Round(SpreadPosition(Spread)*PositionSteps)*2 + Ord(LeftSide) + 1;
  Mat.Fit := Spread.Fit;
  DisplayLeft := LeftSide xor (Settings.Binding = bdRight);
  if (LeftSide and (Spread.State = psFirst)) or
    (not LeftSide and (Spread.State = psLast)) then
    Exit(Mesh.AddMaterial(Mat));
  case Spread.ImageMode of
    imSpread:
      begin
        Mat.Path := Spread.File1;
        if Settings.Binding = bdTop then
        begin
          if DisplayLeft then Mat.Slice := slTop else Mat.Slice := slBottom;
        end else
        begin
          if DisplayLeft then Mat.Slice := slLeft else Mat.Slice := slRight;
        end;
      end;
    imLeft: if DisplayLeft then Mat.Path := Spread.File1;
    imRight: if not DisplayLeft then Mat.Path := Spread.File1;
    imSeparate:
      if DisplayLeft then Mat.Path := Spread.File1 else Mat.Path := Spread.File2;
  end;
  Result := Mesh.AddMaterial(Mat);
end;

function TMeshBuilder.FaceVertex(const Pos, Normal: TBookVector;
  U, V: Double; Positive: Boolean): TBookVertex;
begin
  if not Positive then U := 1-U;
  case Settings.Binding of
    bdLeft: begin Result.S := U; Result.T := V end;
    bdRight: begin Result.S := 1-U; Result.T := V end;
    bdTop: begin Result.S := 1-V; Result.T := U end;
  end;
  Result.Pos := Pos;
  Result.Normal := Normal;
end;

procedure TMeshBuilder.SolidQuad(Material: Integer; const A, B, C, D: TBookVector);
var
  Normal: TBookVector;
begin
  Normal := UnitVector(Cross(Difference(B,A), Difference(D,A)));
  Mesh.AddQuad(Material, FaceVertex(A,Normal,0,0,True), FaceVertex(B,Normal,1,0,True),
    FaceVertex(C,Normal,1,1,True), FaceVertex(D,Normal,0,1,True));
end;

procedure TMeshBuilder.Surface(const Axis: TRibbon; DrawLength, Crown: Double;
  Material: Integer; Positive: Boolean);
var
  Vertices: array[0..PageStrips,0..PageRows] of TBookVertex;
  I, J: Integer;
  U, V, D, W: Double;
  Tangent, Along, Normal, P: TBookVector;
begin
  for I := 0 to PageStrips do
  begin
    U := I / PageStrips;
    Tangent := Vec(Axis[Min(PageStrips,I+1)].U-Axis[Max(0,I-1)].U, 0,
      Axis[Min(PageStrips,I+1)].H-Axis[Max(0,I-1)].H);
    W := Axis[I].Width * DrawLength;
    D := Crown*Sin(Pi*U);
    for J := 0 to PageRows do
    begin
      V := J / PageRows;
      P := Vec(Axis[I].U, (V-0.5)*W, Axis[I].H + D*Sin(Pi*V));
      Along := Vec(0, W, Pi*D*Cos(Pi*V));
      Normal := UnitVector(Cross(Vec(Tangent.U, 0,
        Tangent.H + Crown*Pi*Cos(Pi*U)*Sin(Pi*V)/PageStrips *
        (Min(PageStrips,I+1)-Max(0,I-1))), Along));
      if not Positive then Normal := Vec(-Normal.U,-Normal.V,-Normal.H);
      Vertices[I,J] := FaceVertex(P, Normal, U, V, Positive);
    end;
  end;
  for I := 0 to PageStrips-1 do
    for J := 0 to PageRows-1 do
      Mesh.AddQuad(Material, Vertices[I,J], Vertices[I+1,J],
        Vertices[I+1,J+1], Vertices[I,J+1], not Positive);
end;

procedure TMeshBuilder.Board(const Hinge: THinge; const Cover: TCoverSettings;
  Thickness: Double; IsFront: Boolean);
var
  Outer, Inner: TRibbon;
  I, Edge: Integer;
  Across, SignedThickness, Offset, Radius, W, X, EdgeShade: Double;
  P: TBookVector;
  OuterMat, InnerMat, EdgeMat: Integer;
  NewsPage: TPaperPattern;
  A, B, C, D: TBookVector;
begin
  SignedThickness := Thickness;
  if IsFront then SignedThickness := -SignedThickness;
  Radius := Min(Cover.Radius, Min(Length*0.24, Span*0.24));
  for I := 0 to PageStrips do
  begin
    Across := Span*I/PageStrips;
    X := Max(0.0, Across - (Span-Radius));
    Offset := Radius - Sqrt(Max(0.0, Sqr(Radius)-Sqr(X)));
    W := Max(0.02, 1 - 2*Offset/Length);
    P := Hinge.Point(Across, 0, 0);
    Outer[I].U := P.U;
    Outer[I].H := P.H;
    Outer[I].Width := W;
    P := Hinge.Point(Across, 0, SignedThickness);
    Inner[I].U := P.U;
    Inner[I].H := P.H;
    Inner[I].Width := W;
  end;
  if IsFront then NewsPage := ppNewsFront else NewsPage := ppNewsBack;
  OuterMat := CoverMaterial(Cover, txCover, Cover.OutsideFile, Settings.Aspect, NewsPage);
  InnerMat := CoverMaterial(Cover, txLining, Cover.InsideFile, Settings.Aspect,
    ppNewsprint, 1000000+Ord(IsFront));
  EdgeShade := 0.74;
  if Cover.Pattern = cpNewsprint then EdgeShade := 0.89;
  EdgeMat := ColorMaterial(Shade(Cover.Color,EdgeShade), Cover.Shine*0.62);
  Surface(Outer, Length, 0, OuterMat, IsFront);
  Surface(Inner, Length, 0, InnerMat, not IsFront);
  for Edge := -1 to 1 do
  begin
    if Edge = 0 then Continue;
    for I := 0 to PageStrips-1 do
    begin
      A := Vec(Outer[I].U, Edge*Length*Outer[I].Width/2, Outer[I].H);
      B := Vec(Outer[I+1].U, Edge*Length*Outer[I+1].Width/2, Outer[I+1].H);
      C := Vec(Inner[I+1].U, Edge*Length*Inner[I+1].Width/2, Inner[I+1].H);
      D := Vec(Inner[I].U, Edge*Length*Inner[I].Width/2, Inner[I].H);
      if (Edge < 0) = IsFront then SolidQuad(EdgeMat, B,A,D,C)
      else SolidQuad(EdgeMat, A,B,C,D);
    end;
  end;
  W := Length*Outer[PageStrips].Width/2;
  A := Vec(Outer[PageStrips].U,-W,Outer[PageStrips].H);
  B := Vec(Outer[PageStrips].U,W,Outer[PageStrips].H);
  C := Vec(Inner[PageStrips].U,W,Inner[PageStrips].H);
  D := Vec(Inner[PageStrips].U,-W,Inner[PageStrips].H);
  if IsFront then SolidQuad(EdgeMat,B,A,D,C) else SolidQuad(EdgeMat,A,B,C,D);
  A := Vec(Outer[0].U,-Length/2,Outer[0].H);
  B := Vec(Outer[0].U,Length/2,Outer[0].H);
  C := Vec(Inner[0].U,Length/2,Inner[0].H);
  D := Vec(Inner[0].U,-Length/2,Inner[0].H);
  if IsFront then SolidQuad(EdgeMat,A,B,C,D) else SolidQuad(EdgeMat,B,A,D,C);
end;

function TMeshBuilder.StackAxis(const Hinge: THinge;
  Normal, Crown, Across: Double): TRibbon;
var
  I: Integer;
  P: TBookVector;
  U, Arc: Double;
begin
  for I := 0 to PageStrips do
  begin
    U := I / PageStrips;
    Arc := Sin(Pi*U)*Exp(-1.7*U);
    P := Hinge.Point(Inset + Across*U, 0, Normal + Crown*Arc);
    Result[I].U := P.U;
    Result[I].H := P.H;
    Result[I].Width := 1;
  end;
end;

procedure TMeshBuilder.Stack(const Top, Bottom: TRibbon;
  Thickness, DrawLength, Crown: Double; Material: Integer; Positive: Boolean);
var
  I, Edge, EdgeMat: Integer;
  V: Double;
  A, B, C, D: TBookVector;
  Mat: TBookMaterial;

  function Point(const Axis: TRibbon; Index: Integer; Along: Double): TBookVector;
  begin
    Result := Vec(Axis[Index].U,Along,Axis[Index].H);
  end;

  procedure EdgeQuad(const A, B, C, D: TBookVector; U0, U1: Single;
    Reverse: Boolean);
  var
    Normal: TBookVector;
    VA, VB, VC, VD: TBookVertex;
  begin
    Normal := UnitVector(Cross(Difference(B,A),Difference(D,A)));
    if Reverse then Normal := Vec(-Normal.U,-Normal.V,-Normal.H);
    VA := FaceVertex(A,Normal,0,0,True);
    VB := FaceVertex(B,Normal,0,0,True);
    VC := FaceVertex(C,Normal,0,0,True);
    VD := FaceVertex(D,Normal,0,0,True);
    VA.S := U0; VA.T := 0;
    VB.S := U1; VB.T := 0;
    VC.S := U1; VC.T := 1;
    VD.S := U0; VD.T := 1;
    Mesh.AddQuad(EdgeMat,VA,VB,VC,VD,Reverse);
  end;

begin
  Surface(Top, DrawLength, Crown, Material, Positive);
  Mat := Default(TBookMaterial);
  Mat.Kind := txPaperEdge;
  Mat.Color := Shade(Settings.Paper.Color,0.89);
  Mat.Ink := Shade(Settings.Paper.Color,0.36);
  Mat.Pattern := EnsureRange(Ceil(Thickness*1.15),1,36);
  EdgeMat := Mesh.AddMaterial(Mat);
  A := Point(Bottom,PageStrips,-DrawLength/2);
  B := Point(Bottom,PageStrips,DrawLength/2);
  C := Point(Top,PageStrips,DrawLength/2);
  D := Point(Top,PageStrips,-DrawLength/2);
  EdgeQuad(A,B,C,D,0,1,not Positive);
  for Edge := -1 to 1 do
  begin
    if Edge = 0 then Continue;
    V := Edge*DrawLength/2;
    for I := 0 to PageStrips-1 do
      EdgeQuad(Point(Bottom,I,V),Point(Bottom,I+1,V),
        Point(Top,I+1,V),Point(Top,I,V),I/PageStrips,(I+1)/PageStrips,
        (Edge < 0) <> Positive);
  end;
  // 綴じ目側の端面で、紙束と背表紙の内側の間に厚みを持たせる。
  EdgeQuad(Point(Bottom,0,-DrawLength/2),Point(Bottom,0,DrawLength/2),
    Point(Top,0,DrawLength/2),Point(Top,0,-DrawLength/2),0,1,Positive);
end;

procedure TMeshBuilder.Gutter(const LeftAxis, RightAxis: TRibbon);
var
  I: Integer;
  T, Dip: Double;
  Axis: TRibbon;
  Mat: TBookMaterial;
begin
  if RightAxis[0].U-LeftAxis[0].U <= Inset then Exit;
  Dip := Min(Abs(RightAxis[0].U-LeftAxis[0].U)*0.55,
    Min(LeftAxis[0].H,RightAxis[0].H)*0.80);
  for I := 0 to PageStrips do
  begin
    T := I/PageStrips;
    Axis[I].U := Mix(LeftAxis[0].U,RightAxis[0].U,T);
    Axis[I].H := Mix(LeftAxis[0].H,RightAxis[0].H,T)-Dip*Sin(Pi*T);
    Axis[I].Width := 1;
  end;
  Mat := Default(TBookMaterial);
  Mat.Kind := txGutter;
  Mat.Color := Settings.Paper.Color;
  Mat.Shine := Settings.Paper.Shine*0.48;
  Mat.Pattern := Ord(Settings.Binding=bdTop);
  Surface(Axis,Length-2*Inset,0,Mesh.AddMaterial(Mat),True);
end;

procedure TMeshBuilder.Spine;
var
  I, Face, Material: Integer;
  T0, T1, Width, Roundness, Gap, Arc, Inlay: Double;
  A, B, C, D, Norm: TBookVector;
  VA, VB, VC, VD: TBookVertex;

  function Point(T, V: Double): TBookVector;
  begin
    Result := Vec(Mix(Back.U,Front.U,T) - Arc*Sin(Pi*T) + Inlay,
      V, Mix(Back.H,Front.H,T) + (Gap*0.5-Arc*0.25)*Sin(Pi*T));
    Result.H := Max(0.0, Result.H);
  end;

begin
  Width := Settings.Thickness;
  Roundness := Settings.Spine.Radius * 0.01;
  Gap := Abs(Front.U - Back.U);
  Arc := Min(Width*0.47, Span*0.12) * Roundness * (Width/(Width + Gap*3));
  if Settings.BindingStyle = bsRing then Exit;
  for Face := 0 to 1 do
  begin
    Inlay := Face * Min(0.8, Width*0.17);
    if Face = 0 then
      Material := CoverMaterial(Settings.Spine, txSpine, Settings.Spine.OutsideFile,
        Length/Width)
    else
      Material := CoverMaterial(Settings.Spine, txLining, Settings.Spine.InsideFile,
        Length/Width);
    for I := 0 to SpineStrips-1 do
    begin
      T0 := I/SpineStrips;
      T1 := (I+1)/SpineStrips;
      A := Point(T0,-Length/2);
      B := Point(T1,-Length/2);
      C := Point(T1,Length/2);
      D := Point(T0,Length/2);
      Norm := UnitVector(Cross(Difference(B,A),Difference(D,A)));
      if Face <> 0 then Norm := Vec(-Norm.U,-Norm.V,-Norm.H);
      VA := FaceVertex(A,Norm,T0,0,Face=0);
      VB := FaceVertex(B,Norm,T1,0,Face=0);
      VC := FaceVertex(C,Norm,T1,1,Face=0);
      VD := FaceVertex(D,Norm,T0,1,Face=0);
      Mesh.AddQuad(Material,VA,VB,VC,VD,Face<>0);
    end;
  end;
end;

procedure TMeshBuilder.Bindings;
const
  Segments = 22;
  Sides = 8;
var
  Count, I, J, K, Mat: Integer;
  V, CenterU, CenterH, RadiusU, RadiusH, Tube, T0, T1, S0, S1: Double;
  Color: Cardinal;

  function RingPoint(T, S: Double): TBookVector;
  begin
    Result := Vec(CenterU+(RadiusU+Tube*Cos(S))*Cos(T), V+Tube*Sin(S),
      CenterH+(RadiusH+Tube*Cos(S))*Sin(T));
  end;

begin
  case Settings.BindingStyle of
    bsRing: begin Count := 12; Color := $838D97 end;
    bsSewn: begin Count := 4; Color := $AA8B68 end;
    bsJapanese: begin Count := 5; Color := $D0AD70 end;
    bsClasp: begin Count := 2; Color := $AE8145 end;
  else
    Exit;
  end;
  Mat := ColorMaterial(Color,55);
  Tube := EnsureRange(Span*0.0046, 0.34, 3.6);
  if Settings.BindingStyle = bsClasp then
  begin
    for I := 1 to Count do
    begin
      V := Length*(I/(Count+1)-0.5);
      // 表紙の小口から少し張り出す金具を表紙と共に動かす。
      SolidQuad(Mat, Front.Point(Span*0.90,V-2*Tube,0.5),
        Front.Point(Span+Tube,V-2*Tube,0.5), Front.Point(Span+Tube,V+2*Tube,0.5),
        Front.Point(Span*0.90,V+2*Tube,0.5));
      SolidQuad(Mat, Front.Point(Span+Tube,V-2*Tube,0.5),
        Front.Point(Span+Tube,V-2*Tube,-BoardFront),
        Front.Point(Span+Tube,V+2*Tube,-BoardFront),
        Front.Point(Span+Tube,V+2*Tube,0.5));
    end;
    Exit;
  end;
  CenterU := (Front.U+Back.U)*0.5;
  CenterH := (Front.H+Back.H)*0.5 + Tube;
  RadiusU := Max(Tube*3, Settings.Thickness*0.22 + Abs(Front.U-Back.U)*0.5);
  RadiusH := Max(Tube*2, Abs(Front.H-Back.H)*0.5);
  if Settings.BindingStyle <> bsRing then
  begin
    RadiusU := Max(Tube,RadiusU*0.64);
    Tube := Tube*0.5;
  end;
  for I := 1 to Count do
  begin
    V := Length*(I/(Count+1)-0.5)*0.94;
    for J := 0 to Segments-1 do
    begin
      T0 := 2*Pi*J/Segments;
      T1 := 2*Pi*(J+1)/Segments;
      for K := 0 to Sides-1 do
      begin
        S0 := 2*Pi*K/Sides;
        S1 := 2*Pi*(K+1)/Sides;
        SolidQuad(Mat,RingPoint(T0,S0),RingPoint(T0,S1),
          RingPoint(T1,S1),RingPoint(T1,S0));
      end;
    end;
  end;
end;

procedure TMeshBuilder.Leaf(const RightAxis, LeftAxis: TRibbon;
  Phase, Strength, Depth: Double; FrontMat, BackMat: Integer);
var
  Axis: TRibbon;
  I: Integer;
  U, Angle, Curl, Across, LeftU, RightU, LeftH, RightH, Offset,
    ActualU, ActualH, Blend, A, Curvature, Rise: Double;
begin
  Angle := Mix(Back.Angle,Front.Angle,Phase);
  Curl := Mix(0.20,1.18,Settings.Paper.Softness*0.01);
  case Settings.TurnStyle of
    tsCurl: Curl := Curl*1.60;
    tsBundle: Curl := Curl*0.51;
    tsWind: Curl := Curl*(1.08+0.35*Sin(Phase*Pi*3));
  end;
  Curvature := Curl*Strength;
  Offset := 0.24+Depth;
  Rise := Offset + Strength * Min(Span*0.036, 4.6);
  Across := (Span-2*Inset)/PageStrips;
  ActualU := 0;
  ActualH := 0;
  Axis[0].Width := 1;
  for I := 0 to PageStrips do
  begin
    U := I/PageStrips;
    if I > 0 then
    begin
      A := Angle + Curvature*(0.52-Cos(Pi*(U-0.5/PageStrips)));
      A := EnsureRange(A, Back.Angle, Max(Back.Angle,Front.Angle));
      ActualU := ActualU + Cos(A)*Across;
      ActualH := ActualH + Sin(A)*Across;
    end;
    Blend := Min(1.0,Strength*3.5);
    LeftU := LeftAxis[I].U-LeftAxis[0].U;
    RightU := RightAxis[I].U-RightAxis[0].U;
    LeftH := LeftAxis[I].H-LeftAxis[0].H;
    RightH := RightAxis[I].H-RightAxis[0].H;
    Axis[I].U := Mix(RightAxis[0].U,LeftAxis[0].U,Phase) +
      Mix(Mix(RightU,LeftU,Phase),ActualU,Blend) - Depth*Sin(Angle);
    Axis[I].H := Mix(RightAxis[0].H,LeftAxis[0].H,Phase) +
      Mix(Mix(RightH,LeftH,Phase),ActualH,Blend) + Rise;
    Axis[I].Width := 1;
  end;
  Surface(Axis, Length-2*Inset, Strength*Span*0.016, FrontMat, True);
  Surface(Axis, Length-2*Inset, Strength*Span*0.016, BackMat, False);
end;

procedure TBookMesh.ResetCounts(MaterialCount, QuadCount: Integer);
var
  I: Integer;
begin
  for I := MaterialCount to FMaterialCount-1 do
    FMaterials[I] := Default(TBookMaterial);
  FMaterialCount := MaterialCount;
  FQuadCount := QuadCount;
end;

function SameCover(const A, B: TCoverSettings): Boolean;
begin
  Result := (A.Color = B.Color) and (A.Pattern = B.Pattern) and
    (A.Thickness = B.Thickness) and (A.Shine = B.Shine) and
    (A.Radius = B.Radius) and (A.OutsideFile = B.OutsideFile) and
    (A.InsideFile = B.InsideFile);
end;

procedure TMeshBuilder.BuildBoards;
var
  Pose: array[0..5] of Double;
begin
  Pose[0] := Front.U;
  Pose[1] := Front.H;
  Pose[2] := Front.Angle;
  Pose[3] := Back.U;
  Pose[4] := Back.H;
  Pose[5] := Back.Angle;
  with Mesh.FStructure do
    if (Mesh.FBoardQuadCount > 0) and
      CompareMem(@Pose[0],@Mesh.FBoardPose[0],SizeOf(Pose)) and
      (Width = Settings.Width) and (Aspect = Settings.Aspect) and
      (Thickness = Settings.Thickness) and (Binding = Settings.Binding) and
      (BindingStyle = Settings.BindingStyle) and SameCover(Front,Settings.Front)
      and SameCover(Back,Settings.Back) and SameCover(Spine,Settings.Spine)
      and (Paper.Ink = Settings.Paper.Ink) then
    begin
      Mesh.ResetCounts(Mesh.FBoardMaterialCount,Mesh.FBoardQuadCount);
      Exit;
    end;
  Mesh.FBoardQuadCount := 0;
  Mesh.ResetCounts(0,0);
  Board(Back,Settings.Back,BoardBack,False);
  Board(Front,Settings.Front,BoardFront,True);
  Spine;
  Bindings;
  Mesh.FStructure := Settings;
  Move(Pose[0],Mesh.FBoardPose[0],SizeOf(Pose));
  Mesh.FBoardMaterialCount := Mesh.FMaterialCount;
  Mesh.FBoardQuadCount := Mesh.FQuadCount;
end;

procedure TMeshBuilder.Build(const M: TBookMotion);
var
  TopLeft, BottomLeft, TopRight, BottomRight: TRibbon;
  Angle, Flatness, PageLeft, PageRight, LeftCrown, RightCrown, Depth,
    Position, P, Phase, Strength, PaperWidth, ThicknessLimit: Double;
  LeftMat, RightMat, LeafFront, LeafBack, LeftPage, RightPage, I: Integer;
  ShowLeftPaper, ShowRightPaper, OpenLeaf: Boolean;
  VisibleSpread: TSpreadSettings;
begin
  Span := Settings.Width;
  Length := Settings.Width*Settings.Aspect;
  if Settings.Binding = bdTop then
  begin
    Span := Settings.Width*Settings.Aspect;
    Length := Settings.Width;
  end;
  Inset := Min(Span,Length)*0.012;
  if Settings.BindingStyle = bsFolded then Inset := Inset*0.2;
  ThicknessLimit := Settings.Thickness*0.82;
  Depth := Settings.Front.Thickness+Settings.Back.Thickness;
  BoardFront := Settings.Front.Thickness*Min(1.0,ThicknessLimit/Depth);
  BoardBack := Settings.Back.Thickness*Min(1.0,ThicknessLimit/Depth);
  Block := Settings.Thickness-BoardFront-BoardBack;
  P := Settings.Progress;
  Position := M.Position;
  Angle := Pi-DegToRad(Settings.OpeningGap);
  Front.Angle := Mix(Angle*M.FrontOpen,Pi,M.BackClose);
  Back.Angle := Pi*M.BackClose;
  Flatness := Sin(Max(0.0,Front.Angle-Back.Angle)*0.5);
  Seam := Min(Span*0.04, Max(Inset,Settings.Thickness*0.10))*Flatness;
  Front.U := -Seam;
  Back.U := Seam;
  PageLeft := Block*Position;
  PageRight := Block*(1-Position);
  Front.H := Settings.Thickness * (1-Smooth((M.FrontOpen-0.19)*1.24));
  Front.H := Max(Front.H, (BoardFront+PageLeft)*Max(0.0,Cos(Front.Angle)));
  Back.H := Settings.Thickness * Smooth((M.BackClose-0.12)*1.61);
  Back.H := Max(Back.H, (BoardBack+PageRight)*Max(0.0,-Cos(Back.Angle)));

  BuildBoards;

  LeftPage := M.FromPage;
  RightPage := M.ToPage;
  VisibleSpread := Settings.A;
  ShowLeftPaper := True;
  ShowRightPaper := True;
  OpenLeaf := (Settings.Transition = trTurn) and (M.LeafStrength > 1e-6);
  case Settings.Transition of
    trOpen:
      begin
        LeftPage := M.PageCount;
        RightPage := M.PageCount;
        VisibleSpread := Settings.A;
        ShowLeftPaper := (P > 0.32) and (VisibleSpread.State <> psFirst);
        ShowRightPaper := (P < 1) or (VisibleSpread.State <> psLast);
        OpenLeaf := (Settings.TurnStyle <> tsNormal) and (Position > 0.01) and
          (Angle*M.FrontOpen > Pi*0.38) and (M.LeafStrength > 1e-6);
      end;
    trClose:
      begin
        LeftPage := 0;
        RightPage := 0;
        VisibleSpread := Settings.B;
        ShowLeftPaper := (P > 0) or (VisibleSpread.State <> psFirst);
        ShowRightPaper := (P < 0.72) and (VisibleSpread.State <> psLast);
        OpenLeaf := (Settings.TurnStyle <> tsNormal) and (Position < 0.99) and
          (Front.Angle-Back.Angle > Pi*0.28) and (M.LeafStrength > 1e-6);
      end;
  else
    if not OpenLeaf then
    begin
      if M.LeafPhase >= 0.5 then LeftPage := M.ToPage;
      RightPage := LeftPage;
      if LeftPage = 0 then VisibleSpread := Settings.A else VisibleSpread := Settings.B;
      if (LeftPage = 0) or (LeftPage = M.PageCount) then
      begin
        ShowLeftPaper := VisibleSpread.State <> psFirst;
        ShowRightPaper := VisibleSpread.State <> psLast;
      end;
    end else
    begin
      // 最初の見開きの表紙は、移動中の葉の下でも紙に置き換えない。
      ShowLeftPaper := (M.FromPage <> 0) or (Settings.A.State <> psFirst);
      // 裏表紙は最後の1枚が離れ始めるまで仮想ページに隠す。
      ShowRightPaper := (M.ToPage <> M.PageCount) or (Settings.B.State <> psLast);
    end;
  end;

  // 通常の見開きでは、位置が範囲端でも少なくとも紙1枚を表示する。
  Depth := Min(Block*0.2,0.22);
  if ShowLeftPaper and (PageLeft < Depth) then
  begin
    PageLeft := Depth;
    PageRight := Block-Depth;
  end;
  if ShowRightPaper and (PageRight < Depth) then
  begin
    PageRight := Depth;
    PageLeft := Block-Depth;
  end;
  PaperWidth := Span-2*Inset;
  LeftCrown := Min(PageLeft*0.95+Span*0.015,Span*0.088)*Flatness*Settings.Paper.Bulge*0.015;
  RightCrown := Min(PageRight*0.95+Span*0.015,Span*0.088)*Flatness*Settings.Paper.Bulge*0.015;
  TopLeft := StackAxis(Front,-BoardFront-PageLeft,-LeftCrown,PaperWidth);
  BottomLeft := StackAxis(Front,-BoardFront,0,PaperWidth);
  TopRight := StackAxis(Back,BoardBack+PageRight,RightCrown,PaperWidth);
  BottomRight := StackAxis(Back,BoardBack,0,PaperWidth);

  LeftMat := PaperMaterial(LeftPage,True,M);
  RightMat := PaperMaterial(RightPage,False,M);
  if ShowLeftPaper and (PageLeft > 0.001) then
    Stack(TopLeft,BottomLeft,PageLeft,Length-2*Inset,LeftCrown*0.13,LeftMat,False);
  if ShowRightPaper and (PageRight > 0.001) then
    Stack(TopRight,BottomRight,PageRight,Length-2*Inset,RightCrown*0.13,RightMat,True);

  if ShowLeftPaper and ShowRightPaper and (Flatness>0.46) then
    Gutter(TopLeft,TopRight);

  if OpenLeaf then
  begin
    for I := 0 to M.LeafCount-1 do
    begin
      Phase := M.LeafPhase;
      Strength := M.LeafStrength;
      if M.LeafCount > 1 then
      begin
        Phase := EnsureRange(Phase + (I-1.5)*0.09*Strength, 0.0, 1.0);
        Strength := Sin(Pi*Phase);
      end;
      if I = M.LeafCount-1 then
      begin
        LeafFront := PaperMaterial(M.FromPage,False,M);
        LeafBack := PaperMaterial(M.ToPage,True,M);
      end else
      begin
        // 束の中の紙も表裏別の模様を使う。
        LeafFront := PaperMaterial(M.PageCount+1+I,False,M);
        LeafBack := PaperMaterial(M.PageCount+1+I,True,M);
      end;
      Leaf(TopRight,TopLeft,Phase,Strength,Min(0.85,Block*0.025)*I,LeafFront,LeafBack);
    end;
  end;
end;

procedure TBookMesh.Build(const S: TBookSettings; const M: TBookMotion);
var
  Builder: TMeshBuilder;
begin
  Builder := Default(TMeshBuilder);
  Builder.Mesh := Self;
  Builder.Settings := S;
  Builder.Build(M);
end;

end.
