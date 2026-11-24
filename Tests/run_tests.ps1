param(
  [string]$PluginPath = 'C:\ProgramData\aviutl2\Plugin\SYNC_Book\SYNC_Book.auf2'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$compiler = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$out = Join-Path $root 'Win64\BookTests'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$plugin = (Resolve-Path -LiteralPath $PluginPath).Path

Push-Location $PSScriptRoot
try {
    & $compiler -B -Q "-E$out" "-N$out" Book_RenderTests.dpr
    if ($LASTEXITCODE -ne 0) { throw "Book_RenderTests compilation failed ($LASTEXITCODE)" }
} finally {
    Pop-Location
}

Add-Type -AssemblyName System.Drawing
$image = Join-Path $out '縦横比確認.bmp'
$bitmap = [Drawing.Bitmap]::new(80, 120)
try {
    $bitmap.Save($image, [Drawing.Imaging.ImageFormat]::Bmp)
} finally {
    $bitmap.Dispose()
}
& (Join-Path $out 'Book_RenderTests.exe') $plugin $image
if ($LASTEXITCODE -ne 0) { throw "Book_RenderTests failed ($LASTEXITCODE)" }
