<#
.SYNOPSIS
Runs Claude Code with a prompt loaded from a file and retries until success.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\run-claude-prompt-file.ps1 .\prompts\review.md

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\run-claude-prompt-file.ps1 .\prompts\review.md -RunName review-01 -MaxAttempts 5
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$PromptFile,
  [string]$ClaudeCommand = "claude",
  [string]$Model = "",
  [string]$FallbackModel = "",
  [ValidateSet("acceptEdits", "auto", "bypassPermissions", "default", "dontAsk", "plan")]
  [string]$PermissionMode = "bypassPermissions",
  [string]$RunName = "",
  [string]$LogDir = ".claude/prompt-runs",
  [int]$InitialDelaySeconds = 120,
  [int]$MaxDelaySeconds = 900,
  [double]$BackoffFactor = 1.6,
  [int]$MaxAttempts = 0,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Initialize-Utf8Console {
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false

  [Console]::InputEncoding = $utf8NoBom
  [Console]::OutputEncoding = $utf8NoBom
  Set-Variable -Name OutputEncoding -Value $utf8NoBom -Scope Script

  $env:LANG = "C.UTF-8"
  $env:LC_ALL = "C.UTF-8"
  $env:PYTHONIOENCODING = "utf-8"

  if ($env:OS -eq "Windows_NT") {
    try {
      & cmd /c chcp 65001 | Out-Null
    } catch {
      Write-Warning "Failed to switch console code page to UTF-8. Continuing with PowerShell UTF-8 settings."
    }
  }
}

function Get-RepoRoot {
  $scriptDir = Split-Path -Parent $PSCommandPath
  return (Resolve-Path (Join-Path $scriptDir "..")).Path
}

function Resolve-InputPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PathValue,
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $candidates = @()

  if ([IO.Path]::IsPathRooted($PathValue)) {
    $candidates += $PathValue
  } else {
    $candidates += (Join-Path (Get-Location).Path $PathValue)
    $repoCandidate = Join-Path $RepoRoot $PathValue
    if ($repoCandidate -notin $candidates) {
      $candidates += $repoCandidate
    }
  }

  foreach ($candidate in $candidates) {
    $resolved = Resolve-Path -LiteralPath $candidate -ErrorAction SilentlyContinue
    if ($resolved) {
      return $resolved.Path
    }
  }

  throw "Prompt file not found: $PathValue"
}

function ConvertTo-SafeName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  return ($Name -replace '[\\/:*?"<>|]', '_')
}

function Get-RetryDelay {
  param(
    [Parameter(Mandatory = $true)]
    [int]$FailureCount,
    [Parameter(Mandatory = $true)]
    [int]$InitialDelay,
    [Parameter(Mandatory = $true)]
    [int]$MaxDelay,
    [Parameter(Mandatory = $true)]
    [double]$Factor
  )

  $baseDelay = [Math]::Min($MaxDelay, [Math]::Round($InitialDelay * [Math]::Pow($Factor, [Math]::Max(0, $FailureCount - 1))))
  $jitterMax = [Math]::Max(1, [int][Math]::Round($baseDelay * 0.25))
  $jitter = Get-Random -Minimum 0 -Maximum ($jitterMax + 1)
  return [int]([Math]::Min($MaxDelay, $baseDelay + $jitter))
}

function Invoke-ClaudeWithPrompt {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ClaudeExe,
    [Parameter(Mandatory = $true)]
    [string[]]$ClaudeArgs,
    [Parameter(Mandatory = $true)]
    [string]$Prompt,
    [Parameter(Mandatory = $true)]
    [string]$LogPath
  )

  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
  Add-Content -LiteralPath $LogPath -Value "===== $timestamp START =====" -Encoding UTF8

  & $ClaudeExe @ClaudeArgs $Prompt 2>&1 | ForEach-Object {
    $line = [string]$_
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    Write-Host $line
  }
  $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }

  $finished = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
  Add-Content -LiteralPath $LogPath -Value "===== $finished EXIT $exitCode =====" -Encoding UTF8

  return [int]$exitCode
}

Initialize-Utf8Console

$repoRoot = Get-RepoRoot
$promptPath = Resolve-InputPath -PathValue $PromptFile -RepoRoot $repoRoot
$promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8

if ($promptText.Trim().Length -eq 0) {
  throw "Prompt file is empty: $promptPath"
}

$runBaseName = if ($RunName.Trim().Length -gt 0) { $RunName } else { [IO.Path]::GetFileNameWithoutExtension($promptPath) }
$safeRunName = ConvertTo-SafeName -Name $runBaseName
$logRoot = if ([IO.Path]::IsPathRooted($LogDir)) { $LogDir } else { Join-Path $repoRoot $LogDir }

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

$claudeCommandInfo = Get-Command $ClaudeCommand -ErrorAction SilentlyContinue
if (-not $claudeCommandInfo) {
  throw "Claude CLI not found: $ClaudeCommand. Make sure the command works in this terminal."
}

$claudeExe = $claudeCommandInfo.Source
$promptSnapshotPath = Join-Path $logRoot ("$safeRunName.prompt.md")
Set-Content -LiteralPath $promptSnapshotPath -Value $promptText -Encoding UTF8

Set-Location $repoRoot

Write-Host "Repository: $repoRoot"
Write-Host "Prompt file: $promptPath"
Write-Host "Prompt snapshot: $promptSnapshotPath"
Write-Host "Log directory: $logRoot"
Write-Host "Claude CLI: $claudeExe"
Write-Host "Permission mode: $PermissionMode"
Write-Host "Run name: $safeRunName"

if ($DryRun) {
  Write-Host "DryRun: Claude was not called."
  exit 0
}

$attempt = 0
$failureCount = 0

while ($true) {
  $attempt++
  $attemptStamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $logPath = Join-Path $logRoot ("$safeRunName.attempt-$attemptStamp.log")

  $claudeArgs = @(
    "--print",
    "--output-format", "text",
    "--dangerously-skip-permissions",
    "--permission-mode", $PermissionMode,
    "--name", $safeRunName
  )

  if ($Model.Trim().Length -gt 0) {
    $claudeArgs += @("--model", $Model)
  }

  if ($FallbackModel.Trim().Length -gt 0) {
    $claudeArgs += @("--fallback-model", $FallbackModel)
  }

  Write-Host ""
  Write-Host "Calling Claude, attempt $attempt"
  $exitCode = Invoke-ClaudeWithPrompt -ClaudeExe $claudeExe -ClaudeArgs $claudeArgs -Prompt $promptText -LogPath $logPath

  if ($exitCode -eq 0) {
    $completedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
    $successPath = Join-Path $logRoot ("$safeRunName.success")
    $successText = @(
      "prompt=$promptPath",
      "completed_at=$completedAt",
      "log=$logPath"
    )
    Set-Content -LiteralPath $successPath -Value $successText -Encoding UTF8
    Write-Host "Completed successfully. Log: $logPath"
    break
  }

  if ($MaxAttempts -gt 0 -and $attempt -ge $MaxAttempts) {
    throw "Claude reached MaxAttempts. Attempts: $MaxAttempts. Last log: $logPath"
  }

  $failureCount++
  $delaySeconds = Get-RetryDelay -FailureCount $failureCount -InitialDelay $InitialDelaySeconds -MaxDelay $MaxDelaySeconds -Factor $BackoffFactor
  Write-Warning "Claude exited with code $exitCode. Retrying in $delaySeconds seconds. Log: $logPath"
  Start-Sleep -Seconds $delaySeconds
}
