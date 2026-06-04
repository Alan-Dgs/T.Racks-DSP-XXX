$ErrorActionPreference = 'Stop'

$Flutter = $env:FLUTTER_BIN
if ([string]::IsNullOrWhiteSpace($Flutter)) {
  $Flutter = 'flutter'
}
$Python = $env:PYTHON_BIN
if ([string]::IsNullOrWhiteSpace($Python)) {
  $Python = 'python'
}
$Port = 54545
$Root = Join-Path $PSScriptRoot '..'
$BuildDir = Join-Path $Root 'build\web'

Push-Location $Root
try {
  & $Flutter build web
  Write-Host "Serving http://127.0.0.1:$Port from $BuildDir"
  Push-Location $BuildDir
  try {
    & $Python -m http.server $Port --bind 127.0.0.1
  } finally {
    Pop-Location
  }
} finally {
  Pop-Location
}
