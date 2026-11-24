unit Book_Renderer;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// ポリゴンを AviUtl2 の Direct3D フレームバッファへ渡す。ホストの描画資源は
// コールバック中だけ利用し、独自デバイスやホスト所有ポインターを保持しない。

interface

uses
  AviUtl2FilterTypes, Book_Settings, Book_Mesh, Book_Textures,
  System.Generics.Defaults;

type
  TDrawOrder = record
    Quad, Material: Integer;
    Depth: Double;
  end;
  TDrawMaterial = record
    Resource: string;
    U0, V0, U1, V1: Single;
    R, G, B, Shine: Single;
    Available: Boolean;
  end;

  TBookRenderer = class
  private
    FMesh: TBookMesh;
    FTextures: TBookTextures;
    FMaterials: TArray<TDrawMaterial>;
    FOrder: TArray<TDrawOrder>;
    FColorVertices: TArray<TVertexColorNorm>;
    FTextureVertices: TArray<TVertexTextureNorm>;
    FCompare: IComparer<TDrawOrder>;
    procedure ResolveMaterial(Video: PFILTER_PROC_VIDEO; Index: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    // 描画はフレームバッファへ直接行う。通常画像出力は呼び出し側で抑止する。
    procedure Draw(Video: PFILTER_PROC_VIDEO; const S: TBookSettings;
      Duration: Double; CameraAPIAvailable: Boolean);
  end;

implementation

uses
  System.Math, System.SysUtils, System.Generics.Collections;

const
  // 初期メディアに標準描画と DrawPoly が参照する画像を確保する。
  // 映像コールバックは false を返すため、この画像は通常出力されない。
  WhitePixel: TPIXEL_RGBA = (R:255; G:255; B:255; A:255);

function OutputDepthAxis(const Output: TOBJECT_IMAGE_PARAM): TBookVector;
var
  SX, CX, SY, CY: Double;
begin
  // 標準描画の拡大と X/Y 回転が、ポリゴン間の奥行き差に影響する。
  SinCos(DegToRad(Output.RX),SX,CX);
  SinCos(DegToRad(Output.RY),SY,CY);
  Result := Vec(-SY*Output.SX, SX*CY*Output.SY, CX*CY*Output.SZ);
end;

function HostBasis(const Point: TBookVector; Binding: TBinding): TBookVector;
begin
  case Binding of
    bdLeft: Result := Vec(Point.U,Point.V,-Point.H);
    bdRight: Result := Vec(-Point.U,Point.V,-Point.H);
  else
    Result := Vec(-Point.V,Point.U,-Point.H);
  end;
end;

function CompareDrawOrder(const A, B: TDrawOrder): Integer;
begin
  if A.Depth < B.Depth then Exit(1);
  if A.Depth > B.Depth then Exit(-1);
  Result := A.Material-B.Material;
  if Result = 0 then Result := A.Quad-B.Quad;
end;

constructor TBookRenderer.Create;
begin
  inherited;
  FMesh := TBookMesh.Create;
  FTextures := TBookTextures.Create;
  FCompare := TComparer<TDrawOrder>.Construct(CompareDrawOrder);
end;

destructor TBookRenderer.Destroy;
begin
  FTextures.Free;
  FMesh.Free;
  inherited;
end;

procedure TBookRenderer.ResolveMaterial(Video: PFILTER_PROC_VIDEO; Index: Integer);
var
  Mat: TBookMaterial;
  OutMat: ^TDrawMaterial;
  Data: TBookPixels;
  Width, Height: Integer;
  ImageAspect, TargetAspect, Pad, Mid: Double;
  FileOK: Boolean;
begin
  Mat := FMesh.Materials[Index];
  OutMat := @FMaterials[Index];
  OutMat^.Available := True;
  OutMat^.U0 := 0;
  OutMat^.V0 := 0;
  OutMat^.U1 := 1;
  OutMat^.V1 := 1;
  OutMat^.R := ((Mat.Color shr 16) and 255)/255;
  OutMat^.G := ((Mat.Color shr 8) and 255)/255;
  OutMat^.B := (Mat.Color and 255)/255;
  OutMat^.Shine := Mat.Shine*0.01;
  if Mat.Kind = txSolid then Exit;
  FileOK := False;
  if (Mat.Path <> '') and Assigned(Video^.GetImageResourceSize) then
  begin
    OutMat^.Resource := 'image:' + Mat.Path;
    FileOK := Video^.GetImageResourceSize(PWideChar(OutMat^.Resource),@Width,@Height) and
      (Width > 0) and (Height > 0);
  end;
  if not FileOK then
  begin
    OutMat^.Resource := '';
    if Assigned(Video^.CreateImageResource) then
    begin
      Data := FTextures.Pixels(Mat,Width,Height);
      OutMat^.Resource := 'resource:SYNC_Book_' + IntToStr(Index);
      Video^.CreateImageResource(PWideChar(OutMat^.Resource),@Data[0],Width,Height);
    end;
    Exit;
  end;
  TargetAspect := Mat.Aspect;
  if Mat.Slice in [slLeft, slRight] then TargetAspect := TargetAspect*0.5;
  if Mat.Slice in [slTop, slBottom] then TargetAspect := TargetAspect*2;
  if (Mat.Fit = ifCrop) and (TargetAspect > 0) then
  begin
    ImageAspect := Height / Width;
    if ImageAspect > TargetAspect then
    begin
      Pad := 0.5*(1-TargetAspect/ImageAspect);
      OutMat^.V0 := Pad;
      OutMat^.V1 := 1-Pad;
    end else
    begin
      Pad := 0.5*(1-ImageAspect/TargetAspect);
      OutMat^.U0 := Pad;
      OutMat^.U1 := 1-Pad;
    end;
  end;
  // 見開き全体の切り抜きから左右または上下を取る。
  if Mat.Slice in [slLeft, slRight] then
  begin
    Mid := (OutMat^.U0+OutMat^.U1)*0.5;
    Pad := Min(0.5/Width,(OutMat^.U1-OutMat^.U0)*0.25);
    if Mat.Slice=slLeft then OutMat^.U1 := Mid-Pad
    else OutMat^.U0 := Mid+Pad;
  end else if Mat.Slice in [slTop, slBottom] then
  begin
    Mid := (OutMat^.V0+OutMat^.V1)*0.5;
    Pad := Min(0.5/Height,(OutMat^.V1-OutMat^.V0)*0.25);
    if Mat.Slice=slTop then OutMat^.V1 := Mid-Pad
    else OutMat^.V0 := Mid+Pad;
  end;
end;

procedure TBookRenderer.Draw(Video: PFILTER_PROC_VIDEO; const S: TBookSettings;
  Duration: Double; CameraAPIAvailable: Boolean);
var
  Output: TOBJECT_IMAGE_PARAM;
  HasOutput, CameraDepth, Mirrored: Boolean;
  Motion: TBookMotion;
  Quad: ^TBookQuad;
  Mat: ^TDrawMaterial;
  I, J, Index, Count, Capacity, BeginRun, EndRun, Used, MatIndex, Corner: Integer;
  Depth, Light, AnchorWidth, AnchorHeight: Double;
  Pos, Normal, DepthAxis: TBookVector;
  Vertex: TBookVertex;
begin
  if not Assigned(Video^.DrawPoly) or not Assigned(Video^.SetImageData) then Exit;
  Motion := BookMotion(S, Duration);
  FMesh.Build(S, Motion);
  if FMesh.QuadCount = 0 then Exit;
  Video^.SetImageData(@WhitePixel,1,1);
  Output := Default(TOBJECT_IMAGE_PARAM);
  HasOutput := Assigned(Video^.GetOutputImageParam) and
    Video^.GetOutputImageParam(nil,0,@Output,SizeOf(Output));
  if HasOutput then DepthAxis := OutputDepthAxis(Output)
  else DepthAxis := Vec(0,0,1);
  CameraDepth := CameraAPIAvailable and Assigned(Video^.GetCameraMode) and
    (Video^.GetCameraMode() <> 0) and (not HasOutput or (Output.Alpha >= 1));

  Mirrored := S.Binding = bdRight;
  if Length(FOrder) < FMesh.QuadCount then
  begin
    Capacity := Max(2048,FMesh.QuadCount*2);
    SetLength(FOrder,Capacity);
    SetLength(FColorVertices,Capacity*4);
    SetLength(FTextureVertices,Capacity*4);
  end;
  if Length(FMaterials) < FMesh.MaterialCount then
    SetLength(FMaterials,Max(48,FMesh.MaterialCount*2));
  for I := 0 to High(FMaterials) do
    FMaterials[I] := Default(TDrawMaterial);

  Count := 0;
  for I := 0 to FMesh.QuadCount-1 do
  begin
    Quad := @FMesh.Quads[I];
    Depth := 0;
    if not CameraDepth then
    begin
      // カメラ無しのフレームバッファでは、通常描画の奥行き順へ並べる。
      for J := 0 to 3 do
      begin
        Pos := HostBasis(Quad^.Vertices[J].Pos,S.Binding);
        Depth := Depth+Pos.U*DepthAxis.U+Pos.V*DepthAxis.V+Pos.H*DepthAxis.H;
      end;
    end;
    FOrder[Count].Quad := I;
    FOrder[Count].Material := Quad^.Material;
    FOrder[Count].Depth := Depth;
    Inc(Count);
  end;
  TArray.Sort<TDrawOrder>(FOrder,FCompare,0,Count);
  if Assigned(Video^.SetCullingState) then Video^.SetCullingState(True);
  if Assigned(Video^.SetSamplerMode) then Video^.SetSamplerMode(SAMPLER_CLAMP);
  try
    BeginRun := 0;
    while BeginRun < Count do
    begin
      MatIndex := FOrder[BeginRun].Material;
      EndRun := BeginRun+1;
      while (EndRun < Count) and (FOrder[EndRun].Material = MatIndex) do Inc(EndRun);
      Mat := @FMaterials[MatIndex];
      if not Mat^.Available then ResolveMaterial(Video,MatIndex);
      if Assigned(Video^.SetMaterialShine) then Video^.SetMaterialShine(Mat^.Shine);
      Used := 0;
      for Index := BeginRun to EndRun-1 do
      begin
        Quad := @FMesh.Quads[FOrder[Index].Quad];
        for J := 0 to 3 do
        begin
          Corner := J;
          if Mirrored then Corner := (4-J) mod 4;
          Vertex := Quad^.Vertices[Corner];
          // DrawPoly にローカル座標を渡し、位置・回転・拡大・透明度は標準描画に任せる。
          Pos := HostBasis(Vertex.Pos,S.Binding);
          Normal := HostBasis(Vertex.Normal,S.Binding);
          if Mat^.Resource <> '' then
            with FTextureVertices[Used] do
            begin
              X := Pos.U;
              Y := Pos.V;
              Z := Pos.H;
              U := Mat^.U0 + (Mat^.U1-Mat^.U0)*Vertex.S;
              V := Mat^.V0 + (Mat^.V1-Mat^.V0)*Vertex.T;
              A := 1;
              NX := Normal.U;
              NY := Normal.V;
              NZ := Normal.H;
            end
          else
            with FColorVertices[Used] do
            begin
              Light := 0.74+0.26*Max(0.0,-Normal.U*0.36-Normal.V*0.50-Normal.H*0.79);
              X := Pos.U;
              Y := Pos.V;
              Z := Pos.H;
              R := Mat^.R*Light;
              G := Mat^.G*Light;
              B := Mat^.B*Light;
              A := 1;
              NX := Normal.U;
              NY := Normal.V;
              NZ := Normal.H;
            end;
          Inc(Used);
        end;
      end;
      if Mat^.Resource <> '' then
        Video^.DrawPoly(VERTEX_QUAD_TEXTURE_NORM,@FTextureVertices[0],Used,PWideChar(Mat^.Resource))
      else
        Video^.DrawPoly(VERTEX_QUAD_COLOR_NORM,@FColorVertices[0],Used,nil);
      BeginRun := EndRun;
    end;
  finally
    if Assigned(Video^.SetMaterialShine) then Video^.SetMaterialShine(0);
    if Assigned(Video^.SetCullingState) then Video^.SetCullingState(False);
    // 「通常」状態に近いフィルタリングへ戻す。
    if Assigned(Video^.SetSamplerMode) then Video^.SetSamplerMode(0);
  end;
  if Assigned(Video^.SetDefaultAnchor) then
  begin
    AnchorWidth := S.Width;
    AnchorHeight := S.Width*S.Aspect;
    if S.Binding = bdTop then AnchorHeight := AnchorHeight*2
    else AnchorWidth := AnchorWidth*2;
    Video^.SetDefaultAnchor(Max(1,Round(AnchorWidth)),Max(1,Round(AnchorHeight)));
  end;
end;

end.
