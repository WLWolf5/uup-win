param(
  [string]$Target = "11",
  [string]$Code = "26H2",
  [string]$Edition = "professional",
  [string]$KMS = "ProfessionalWorkstation",
  [string]$Arch = "amd64",
  [string]$Lang = "zh-cn",
  [ValidateSet("wim", "esd")]
  [string]$ImageFormat = "wim",
  [bool]$IncludeUpdates = $true,
  [bool]$Cleanup = $false,
  [bool]$NetFx3 = $false,
  [switch]$All,
  [switch]$AllowFailures,
  [switch]$PreserveOutput
)

$ErrorActionPreference = "Stop"

$targetId = "$Target-$Code"
$failures = @()
$maxBuildAttempts = 5

  $workDir = "uup-work-$targetId"
  $outputDir = "uup-output-$targetId"

  Write-Host "::group::Build $targetId"
  try {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $outputDir -Recurse -Force -ErrorAction SilentlyContinue

    $env:UUP_TARGET = $Target
    $env:UUP_CODE = $Code
    $env:UUP_SEARCH = "Windows $Target $Code"
    $env:UUP_ARCH = $Arch
    $env:UUP_LANG = $Lang
    $env:UUP_EDITION = $Edition
    $env:UUP_KMS = $KMS
    $env:UUP_OUT_DIR = $workDir
    $env:UUP_IMAGE_FORMAT = $ImageFormat
    $env:UUP_INCLUDE_UPDATES = if ($IncludeUpdates) { "1" } else { "0" }
    $env:UUP_CLEANUP = if ($Cleanup) { "1" } else { "0" }
    $env:UUP_NETFX3 = if ($NetFx3) { "1" } else { "0" }

    $skippedBuilds = @()
    $built = $false
    for ($attempt = 1; $attempt -le $maxBuildAttempts; $attempt++) {
      Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $outputDir -Recurse -Force -ErrorAction SilentlyContinue
      $env:UUP_SKIP_BUILDS = $skippedBuilds -join ","

      Write-Host "Build attempt $attempt of $maxBuildAttempts for $targetId. Skipped builds: $env:UUP_SKIP_BUILDS"
      npm run resolve
      if ($LASTEXITCODE -ne 0) {
        throw "Resolve failed for $targetId with exit code $LASTEXITCODE"
      }

      if ($LASTEXITCODE -eq 0) {
        $built = $true
        break
      }
    }
  }
  catch {
    Write-Error $_
    $failures += $targetId
    if (-not $AllowFailures) {
      break
    }
  }
