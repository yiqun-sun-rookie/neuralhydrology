# PowerShell script to download HydroBASINS Asia lev12 and unzip
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$destDir = 'data/haihe/hydrobasins/source'
$zipPath = Join-Path $destDir 'hybas_as_lev12_v1c.zip'
$null = New-Item -ItemType Directory -Force -Path $destDir

$urls = @(
  'https://data.hydrosheds.org/file/hydrobasins/standard/hybas_as_lev12_v1c.zip',
  'https://www.hydrosheds.org/downloads/hydrobasins/standard/hybas_as_lev12_v1c.zip'
)

$downloaded = $false
foreach ($u in $urls) {
  try {
    Write-Host "Downloading: $u"
    Invoke-WebRequest -Uri $u -OutFile $zipPath -UseBasicParsing -TimeoutSec 1800
    if ((Test-Path $zipPath) -and ((Get-Item $zipPath).Length -gt 5000000)) {
      $downloaded = $true
      break
    }
  } catch {
    Write-Warning "Failed: $u"
  }
}

if (-not $downloaded) {
  throw 'Failed to download HydroBASINS zip from all candidates.'
}

Write-Host 'Download OK'
Expand-Archive -Path $zipPath -DestinationPath $destDir -Force

$shp = Get-ChildItem -Path $destDir -Recurse -File -Filter '*lev12*.shp' | Select-Object -First 1
if (-not $shp) { $shp = Get-ChildItem -Path $destDir -Recurse -File -Filter '*.shp' | Select-Object -First 1 }
if (-not $shp) { throw 'Shapefile not found after unzip.' }

Write-Output $shp.FullName
