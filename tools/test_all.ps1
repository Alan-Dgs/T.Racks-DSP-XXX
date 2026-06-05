$ErrorActionPreference = 'Stop'

$Flutter = $env:FLUTTER_BIN
if ([string]::IsNullOrWhiteSpace($Flutter)) {
  $Flutter = 'flutter'
}

& $Flutter pub get
if ($LASTEXITCODE -ne 0) {
  Write-Warning 'flutter pub get reported a problem. If this mentions symlink support, enable Windows Developer Mode and rerun this script.'
}
& $Flutter analyze
& $Flutter test
