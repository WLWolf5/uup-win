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
      $env:UUP_SKIP_BUILDS = $skippedBuilds -join ","

      Write-Host "Build attempt $attempt of $maxBuildAttempts for $targetId. Skipped builds: $env:UUP_SKIP_BUILDS"

      $metadataPath = Join-Path $workDir "metadata.json"
      $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json

      pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/run-uup-build.ps1 `
      -WorkDir $workDir -OutputDir $outputDir -ImageFormat $ImageFormat `
      -IncludeUpdates:$IncludeUpdates -Cleanup:$Cleanup -NetFx3:$NetFx3 `
      -KMS $KMS
      if ($LASTEXITCODE -eq 0) {
        $built = $true
        break
      }

      Write-Warning "Build failed for $targetId build $($metadata.build) with exit code $LASTEXITCODE."
      $skippedBuilds += [string]$metadata.build
    }

    if (-not $built) {
      throw "Build failed for $targetId after $maxBuildAttempts attempts. Skipped builds: $($skippedBuilds -join ', ')"
    }

    pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/publish-release.ps1 -OutputDir $outputDir
    if ($LASTEXITCODE -ne 0) {
      throw "Release publish failed for $targetId with exit code $LASTEXITCODE"
    }

    if ($PreserveOutput) {
      Write-Host "Preserving workspace for $targetId so the workflow can upload artifacts."
    }
    else {
      Write-Host "Cleaning workspace for $targetId after release publish."
      Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $outputDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  catch {
    Write-Error $_
    $failures += $targetId
    if (-not $AllowFailures) {
      break
    }
  }
  finally {
    Write-Host "::endgroup::"
  }


if ($failures.Count -gt 0 -and -not $AllowFailures) {
  throw "Failed targets: $($failures -join ', ')"
}
elseif ($failures.Count -gt 0) {
  Write-Warning "Failed targets ignored because AllowFailures is enabled: $($failures -join ', ')"
}
