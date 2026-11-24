unit Book_Textures;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 内蔵の布・革・紙面を決定論的に生成し、オブジェクト単位で再利用する。

interface

uses
  AviUtl2FilterTypes, Book_Mesh;

type
  TBookPixels = TArray<TPIXEL_RGBA>;
  TTextureEntry = record
    Used: Boolean;
    Kind: TTextureKind;
    Color, Ink: Cardinal;
    Pattern, Seed, Width, Height: Integer;
    Age: UInt64;
    Pixels: TBookPixels;
  end;

  TBookTextures = class
  private
    FEntries: array[0..19] of TTextureEntry;
    FAge: UInt64;
  public
    // 返す配列は共有参照。呼び出し元は読み取りにのみ使う。
    function Pixels(const Mat: TBookMaterial; out Width, Height: Integer): TBookPixels;
  end;

implementation

uses
  System.Math, Book_Settings;

function Grain(X, Y, Seed: Integer): Integer;
var
  Bits: Cardinal;
begin
  Bits := Cardinal((X+107)*117313) xor Cardinal((Y+223)*98317) xor
    Cardinal(UInt64(Seed)*49157);
  Bits := Bits xor (Bits shl 13);
  Bits := Bits xor (Bits shr 17);
  Bits := Bits xor (Bits shl 5);
  if Seed <> 0 then
  begin
    // シードの上位ビットも画素ごとに混ぜ、紙面の模様が重複しにくくする。
    Bits := Cardinal(UInt64(Bits xor (Bits shr 16))*$045D9F3B);
    Bits := Bits xor (Bits shr 16);
  end;
  Result := Bits and 255;
end;

function PaperMarks(Pattern: TPaperPattern; X, Y, Seed, Layout: Integer;
  U, V: Double): Double;
var
  Row, Col, CX, CY, Sp, EndCol, FigureRow, FirstRow, LastRow, ParagraphLines, Line: Integer;
  Interval, Cell, Ax, Ay: Double;
begin
  Result := 0;
  if (U < 0.10) or (U > 0.90) or (V < 0.085) or (V > 0.92) then Exit;
  case Pattern of
    ppRuled, ppGrid:
      if Frac((V-0.085)*26) < 0.045 then Result := 0.43;
    ppVertical:
      if Frac((U-0.10)*17) < 0.054 then Result := 0.45;
    ppMusic:
      begin
        Interval := Frac((V-0.11)*7)*14;
        if (Interval >= 0) and (Interval < 5) and (Frac(Interval) < 0.24) then
          Result := 0.52;
        Row := Floor((V-0.11)*7);
        Col := Floor(U*21);
        Sp := Grain(Col,Row,Seed);
        if Sp mod 5 = 0 then Exit;
        Ax := (Frac(U*21)-0.46)*2.3;
        Ay := Interval-(Sp mod 6-0.25)*0.75;
        if (Sqr(Ax)+Sqr(Ay*2.1) < 0.49) or
          ((Abs(Ax-0.36)<0.11) and (Ay>-2) and (Ay<0)) then Result := 0.78;
      end;
    ppText, ppVerticalText, ppFigures:
      begin
        if Pattern = ppVerticalText then
        begin
          Cell := U;
          U := V;
          V := 1-Cell;
        end;
        FigureRow := 6 + Layout mod 6;
        Row := Floor((V-0.10)*34);
        Col := Floor((U-0.10)*55);
        if (Pattern = ppFigures) and (Row >= FigureRow) and (Row <= FigureRow+9) then
        begin
          Ax := (U-0.5)*(3.1 + ((Layout shr 3) mod 4)*0.26);
          Ay := (V-(0.10+(FigureRow+4.8)/34))*6.4;
          if (Abs(Ax)<1) and (Abs(Ay)<0.83) then
          begin
            Result := 0.13 + 0.03*(Grain(X,Y,Seed)/255);
            if (Abs(Ax)>0.96) or (Abs(Ay)>0.78) then Result := 0.5;
            case Layout mod 3 of
              0:
                begin
                  if Ay > 0.34-Abs(Ax*0.84+0.35) then Result := 0.36;
                  if Ay > 0.55-Abs(Ax*0.91-0.27) then Result := 0.51;
                  if Sqr(Ax-0.55)+Sqr(Ay+0.44)<0.028 then Result := 0.54;
                end;
              1:
                begin
                  if Sqr(Ax+0.29)+Sqr(Ay*1.18)<0.25 then Result := 0.33;
                  if Abs(Sqr(Ax-0.30)+Sqr(Ay*1.18)-0.25)<0.035 then Result := 0.56;
                end;
              2:
                begin
                  if (Abs(Ay-0.5)<0.025) or (Abs(Ax+0.75)<0.027) then Result := 0.42;
                  if Abs(Ay-0.36*Sin(4*Ax+Layout*0.05)+0.31*Ax)<0.05 then Result := 0.63;
                end;
            end;
          end;
          Exit;
        end;
        if (Row < 0) or (Col < 0) then Exit;
        if (Row = 0) and (Col >= 1) and (Col < 14 + Layout mod 19) and
          (Frac((V-0.10)*34) < 0.16) then Exit(0.42);
        FirstRow := 2 + ((Layout shr 2) mod 3);
        LastRow := 22 + ((Layout shr 4) mod 5);
        if Row >= LastRow then
        begin
          if (Row = 27) and (Abs(U-0.5)<0.035) and (Grain(Col,1,Seed) mod 7 <> 0) and
            (Frac(U*130)<0.60) and (Frac((V-0.10)*34)<0.45) then Result := 0.44;
          Exit;
        end;
        if Row < FirstRow then Exit;
        ParagraphLines := 4 + Layout mod 4;
        Line := (Row-FirstRow) mod ParagraphLines;
        if Line = ParagraphLines-1 then Exit;
        EndCol := 42 - (Grain(Row,1,Seed) mod 6);
        if Line = ParagraphLines-2 then EndCol := 14 + (Grain(Row,2,Seed) mod 23);
        if (Col > EndCol) or ((Col < 2) and (Line = 0)) then Exit;
        CX := Floor(Frac((U-0.10)*55)*4);
        CY := Floor(Frac((V-0.10)*34)*7);
        Sp := Grain(Col,Row,Seed);
        if (CX < 3) and (CY < 4) and (Sp mod 7 <> 0) and
          (((Sp shr ((CX+2*CY) mod 7)) and 1 <> 0) or
            ((CY=3) and (CX<2))) then Result := 0.72;
      end;
  end;
  if (Pattern = ppGrid) and (Frac((U-0.10)*18) < 0.05) then Result := 0.43;
end;

function CoverMarks(Kind: TTextureKind; U, V: Double): Double;
var
  Edge, CornerX, CornerY, R, T: Double;
begin
  Result := 0;
  Edge := Min(Min(U,1-U),Min(V,1-V));
  case Kind of
    txSpine:
      begin
        if (Abs(V-0.19) < 0.006) or (Abs(V-0.81) < 0.006) or
          (Abs(V-0.24) < 0.004) or (Abs(V-0.76) < 0.004) then
          Result := 0.72;
        if (Abs(U-0.5)<0.29) and (Abs(V-0.50)<0.105) and
          ((Abs(U-0.5)>0.26) or (Abs(V-0.50)>0.099)) then Result := 0.67;
      end;
    txCover:
      begin
        if (Abs(Edge-0.053)<0.0042) or (Abs(Edge-0.069)<0.0025) then
          Result := 0.76;
        CornerX := Min(U,1-U)-0.103;
        CornerY := (Min(V,1-V)-0.095)*1.2;
        R := Sqrt(Sqr(CornerX)+Sqr(CornerY));
        if (Abs(R-0.021)<0.005) or (R<0.009) then Result := 0.79;
        R := Sqrt(Sqr((U-0.5)*1.40)+Sqr(V-0.42));
        if (Abs(R-0.145)<0.004) or (Abs(R-0.127)<0.0025) then
          Result := 0.78;
        T := Abs(U-0.5)*1.4 + Abs(V-0.42);
        if (Abs(T-0.088)<0.005) or (T<0.023) then Result := 0.84;
        if (Abs(V-0.66)<0.003) and (Abs(U-0.5)<0.19) then Result := 0.67;
      end;
    txLining:
      if (Abs(Edge-0.034)<0.003) or (Abs(Edge-0.062)<0.002) then
        Result := 0.24;
  end;
end;

procedure Generate(var Entry: TTextureEntry);
const
  Gold = $DCB36C;
var
  X, Y, Noise, Thread, ScaledNoise, Layout: Integer;
  U, V, Light, InkAmount, Edge: Double;
  Ink: Cardinal;
  Pixel: PPIXEL_RGBA;

  function Channel(Shift: Integer): Byte;
  var
    Base, Mark: Integer;
  begin
    Base := (Entry.Color shr Shift) and 255;
    Mark := (Ink shr Shift) and 255;
    Result := Byte(EnsureRange(Round(Light*(Base+(Mark-Base)*InkAmount)), 0, 255));
  end;

begin
  SetLength(Entry.Pixels,Entry.Width*Entry.Height);
  Layout := Grain(0,0,Entry.Seed);
  for Y := 0 to Entry.Height-1 do
  begin
    V := (Y+0.5)/Entry.Height;
    for X := 0 to Entry.Width-1 do
    begin
      U := (X+0.5)/Entry.Width;
      Noise := Grain(X,Y,Entry.Seed);
      Light := 1;
      InkAmount := 0;
      Ink := Gold;
      Edge := Min(Min(U,1-U),Min(V,1-V));
      if Entry.Kind = txGutter then
      begin
        if Entry.Pattern = 1 then Edge := V else Edge := U;
        Light := 0.94-0.49*Power(Sin(Pi*Edge),1.35)+Noise*0.00020;
      end else if Entry.Kind = txPaperEdge then
      begin
        Ink := Entry.Ink;
        Light := 0.93 + 0.043*Sin(Pi*U) + Noise*0.00015;
        InkAmount := 0.24 * Sqr(1-Frac(V*Entry.Pattern +
          0.07*Sin(U*18+V*13)));
      end else if Entry.Kind = txPaper then
      begin
        Ink := Entry.Ink;
        InkAmount := PaperMarks(TPaperPattern(Entry.Pattern),X,Y,Entry.Seed,Layout,U,V);
        Light := 0.98 + Noise*0.00016 + Min(0.02,Edge*0.12)
          - 0.095*Sqr(Max(0.0,1-Edge*18));
      end else
      begin
        case TCoverPattern(Entry.Pattern) of
          cpPlain:
            Light := 0.98 + Noise*0.00023;
          cpCloth:
            begin
              Thread := (X mod 3)*13 + (Y mod 3)*9;
              Light := 0.77 + Thread*0.004 + Noise*0.00062;
            end;
          cpLeather, cpOrnate:
            begin
              ScaledNoise := Grain(X div 3,Y div 3,Entry.Seed);
              Light := 0.88 + Noise*0.00038 + ScaledNoise*0.00038;
              if (Entry.Pattern = Ord(cpOrnate)) or (Entry.Kind = txSpine) then
                InkAmount := CoverMarks(Entry.Kind,U,V);
            end;
        end;
        if Entry.Kind = txLining then
          Light := Light*1.20;
        Light := Light*(0.85+Min(0.15,Edge*3.6));
      end;
      Pixel := @Entry.Pixels[Y*Entry.Width+X];
      Pixel^.R := Channel(16);
      Pixel^.G := Channel(8);
      Pixel^.B := Channel(0);
      Pixel^.A := 255;
    end;
  end;
end;

function TBookTextures.Pixels(const Mat: TBookMaterial;
  out Width, Height: Integer): TBookPixels;
var
  I, Oldest: Integer;
  Slot: ^TTextureEntry;
begin
  Width := 224;
  if Mat.Kind = txSpine then Width := 96;
  Height := EnsureRange(Round(Width*Mat.Aspect),96,352);
  if Mat.Kind in [txPaperEdge,txGutter] then
  begin
    Width := 128;
    Height := 128;
  end;
  Inc(FAge);
  Oldest := 0;
  for I := 0 to High(FEntries) do
  begin
    Slot := @FEntries[I];
    if Slot^.Used and (Slot^.Kind = Mat.Kind) and (Slot^.Color = Mat.Color)
      and (Slot^.Ink = Mat.Ink) and (Slot^.Pattern = Mat.Pattern)
      and (Slot^.Seed = Mat.Seed) and (Slot^.Width = Width) and (Slot^.Height = Height) then
    begin
      Slot^.Age := FAge;
      Exit(Slot^.Pixels);
    end;
    if Slot^.Age < FEntries[Oldest].Age then Oldest := I;
  end;
  Slot := @FEntries[Oldest];
  Slot^.Used := False;
  Slot^.Kind := Mat.Kind;
  Slot^.Color := Mat.Color;
  Slot^.Ink := Mat.Ink;
  Slot^.Pattern := Mat.Pattern;
  Slot^.Seed := Mat.Seed;
  Slot^.Width := Width;
  Slot^.Height := Height;
  Generate(Slot^);
  Slot^.Age := FAge;
  Slot^.Used := True;
  Result := Slot^.Pixels;
end;

end.
