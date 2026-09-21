[CmdletBinding()]
param(
    [string]$EnvFile = 'F:\keys\PDF_daeri\.env'
)

$ErrorActionPreference = 'Stop'

function Read-ReleaseEnvironment([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Release environment file not found: $path"
    }

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            continue
        }
        $values[$matches[1]] = $matches[2]
    }
    return $values
}

function Require-AdUnitId([hashtable]$values, [string]$name) {
    $value = $values[$name]
    if ([string]::IsNullOrWhiteSpace($value) -or $value -notmatch '^ca-app-pub-\d{16}/\d+$') {
        throw "$name is missing or invalid in the release environment file."
    }
    if ($value -like 'ca-app-pub-3940256099942544/*') {
        throw "$name must not use Google's test ad unit in a release build."
    }
    return $value
}

function Assert-ReleaseAdUnits([string[]]$libraries, [string]$bannerId, [string]$interstitialId) {
    $googleTestBanner = 'ca-app-pub-3940256099942544/6300978111'
    foreach ($library in $libraries) {
        $content = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($library))
        if (-not $content.Contains($bannerId) -or -not $content.Contains($interstitialId)) {
            throw "Release artifact is missing a production AdMob unit ID: $library"
        }
        if ($content.Contains($googleTestBanner)) {
            throw "Release artifact still contains Google's test banner unit ID: $library"
        }
    }
}

$releaseValues = Read-ReleaseEnvironment $EnvFile
$bannerId = Require-AdUnitId $releaseValues 'ADMOB_BANNER_UNIT_ID'
$interstitialId = Require-AdUnitId $releaseValues 'ADMOB_INTERSTITIAL_UNIT_ID'
$dartDefines = @(
    "--dart-define=ADMOB_BANNER_UNIT_ID=$bannerId",
    "--dart-define=ADMOB_INTERSTITIAL_UNIT_ID=$interstitialId"
)

& flutter build apk --release @dartDefines
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& flutter build appbundle --release @dartDefines
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$releaseLibraries = Get-ChildItem -LiteralPath 'build\app\intermediates\flutter\release' -Filter 'app.so' -Recurse -File |
    Select-Object -ExpandProperty FullName
if ($releaseLibraries.Count -eq 0) { throw 'Release native libraries were not produced.' }
Assert-ReleaseAdUnits $releaseLibraries $bannerId $interstitialId

Write-Host 'Release APK/AAB completed with verified production AdMob unit IDs.'
