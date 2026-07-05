<#
.SYNOPSIS
Runs Claude Code against docs chapters and retries transient failures.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\review-chapters-with-claude.ps1

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\review-chapters-with-claude.ps1 -Chapters 3,8 -Force

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\review-chapters-with-claude.ps1 -MaxAttempts 5
#>

[CmdletBinding()]
param(
  [int[]]$Chapters,
  [int]$ChapterStart = 1,
  [int]$ChapterEnd = 10,
  [string]$ClaudeCommand = "claude",
  [string]$Model = "",
  [string]$FallbackModel = "",
  [ValidateSet("acceptEdits", "auto", "bypassPermissions", "default", "dontAsk", "plan")]
  [string]$PermissionMode = "bypassPermissions",
  [string]$LogDir = ".claude/review-logs",
  [int]$InitialDelaySeconds = 60,
  [int]$MaxDelaySeconds = 180,
  [double]$BackoffFactor = 1.6,
  [int]$MaxAttempts = 0,
  [switch]$Force,
  [switch]$SkipBuild,
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

function Get-ChapterDirectory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DocsRoot,
    [Parameter(Mandatory = $true)]
    [int]$ChapterNumber
  )

  $prefix = "{0:D2}-" -f $ChapterNumber
  $matches = @(Get-ChildItem -LiteralPath $DocsRoot -Directory | Where-Object { $_.Name.StartsWith($prefix) } | Sort-Object Name)

  if ($matches.Count -eq 0) {
    throw "Chapter directory not found: docs/$prefix*"
  }

  if ($matches.Count -gt 1) {
    $names = $matches.Name -join ", "
    throw "Chapter prefix $prefix matched multiple directories: $names"
  }

  return $matches[0]
}

function ConvertTo-SafeName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  return ($Name -replace '[\\/:*?"<>|]', '_')
}

function New-ChapterPrompt {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ChapterRelativePath,
    [Parameter(Mandatory = $true)]
    [string]$ChapterName
  )

  $lines = @(
    "You are reviewing a VitePress documentation site that records personal Kubernetes learning notes.",
    "",
    "Target chapter path: $ChapterRelativePath",
    "Target chapter directory name: $ChapterName",
    "",
    "Complete a full review of this chapter and directly edit or add Markdown where needed.",
    "",
    "Requirements:",
    "1. First read the repository root AGENTS.md. It is the source of truth for writing style, naming, examples, alert blocks, details containers, index.md rules, and Kubernetes documentation review rules. Follow it exactly, even where this prompt is shorter.",
    "2. The user grants permission to read, create, edit, and delete files under this repository root when it is necessary for the review. Keep changes relevant to this chapter review. Prefer the target chapter Markdown files; edit README.md, docs/index.md, navigation/config files, or other repository files only when the chapter review genuinely requires it. Do not touch files outside the repository root.",
    "3. Check every page in the chapter for factual mistakes, outdated APIs or commands, wrong field levels, incomplete or inconsistent YAML examples, non-compliant command output wording, missing topics, confused concept boundaries, and index.md style compliance.",
    "4. For Kubernetes, kubectl, API fields, defaults, deprecations, removals, feature gates, or command semantics, verify facts against current official English Kubernetes documentation, Kubernetes API Reference, kubectl reference, official task/concept pages, or https://k8s.io/examples/ before editing. Do not rely on old memory.",
    "5. Fix confirmed issues directly. Add missing content only when it is sufficiently grounded and fits this repository as personal notes rather than a generic tutorial. For topics that cannot be expanded responsibly now, record them as follow-up items according to AGENTS.md.",
    "6. Keep the repository positioning as personal learning notes. Do not add tutorial structures such as learning goals, prerequisites, target audience, curriculum plans, or interview questions. Avoid tutorial-style phrasing prohibited by AGENTS.md.",
    "7. Preserve existing user changes. File creation, edits, and deletion inside the repository are allowed when needed for the review, but do not run destructive git commands such as git reset, git checkout, or git clean. Do not delete repository metadata, dependency directories, generated build output, logs, or cache directories unless the review explicitly requires that cleanup.",
    "8. After finishing, briefly report changed files, issue categories fixed, remaining follow-up items, and official source URLs consulted. If no edits were needed, report the checked scope and residual risk."
  )

  return ($lines -join [Environment]::NewLine)
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

function Invoke-ClaudeForChapter {
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
$docsRoot = Join-Path $repoRoot "docs"
$logRoot = if ([IO.Path]::IsPathRooted($LogDir)) { $LogDir } else { Join-Path $repoRoot $LogDir }
$doneRoot = Join-Path $logRoot "done"

if (-not (Test-Path -LiteralPath $docsRoot)) {
  throw "docs directory not found: $docsRoot"
}

if (-not $Chapters -or $Chapters.Count -eq 0) {
  if ($ChapterStart -gt $ChapterEnd) {
    throw "ChapterStart cannot be greater than ChapterEnd."
  }

  $Chapters = $ChapterStart..$ChapterEnd
}

$Chapters = @($Chapters | Sort-Object -Unique)

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
New-Item -ItemType Directory -Path $doneRoot -Force | Out-Null

$claudeCommandInfo = Get-Command $ClaudeCommand -ErrorAction SilentlyContinue
if (-not $claudeCommandInfo) {
  throw "Claude CLI not found: $ClaudeCommand. Make sure the command works in this terminal."
}

$claudeExe = $claudeCommandInfo.Source
Set-Location $repoRoot

Write-Host "Repository: $repoRoot"
Write-Host "Log directory: $logRoot"
Write-Host "Claude CLI: $claudeExe"
Write-Host "Permission mode: $PermissionMode"

foreach ($chapterNumber in $Chapters) {
  if ($chapterNumber -lt 1 -or $chapterNumber -gt 99) {
    throw "Unsupported chapter number: $chapterNumber"
  }

  $chapterDir = Get-ChapterDirectory -DocsRoot $docsRoot -ChapterNumber $chapterNumber
  $chapterName = $chapterDir.Name
  $chapterRelativePath = "docs/$chapterName"
  $safeName = ConvertTo-SafeName -Name $chapterName
  $donePath = Join-Path $doneRoot ("$safeName.done")
  $promptPath = Join-Path $logRoot ("$safeName.prompt.md")

  if ((Test-Path -LiteralPath $donePath) -and -not $Force) {
    Write-Host "Skipping $chapterRelativePath because it is already marked done. Use -Force to rerun."
    continue
  }

  $prompt = New-ChapterPrompt -ChapterRelativePath $chapterRelativePath -ChapterName $chapterName
  Set-Content -LiteralPath $promptPath -Value $prompt -Encoding UTF8

  Write-Host ""
  Write-Host "Starting review: $chapterRelativePath"
  Write-Host "Prompt file: $promptPath"

  if ($DryRun) {
    Write-Host "DryRun: Claude was not called."
    continue
  }

  $attempt = 0
  $failureCount = 0

  while ($true) {
    $attempt++
    $attemptStamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logPath = Join-Path $logRoot ("$safeName.attempt-$attemptStamp.log")

    $claudeArgs = @(
      "--print",
      "--output-format", "text",
      "--dangerously-skip-permissions",
      "--permission-mode", $PermissionMode,
      "--name", "review-$safeName"
    )

    if ($Model.Trim().Length -gt 0) {
      $claudeArgs += @("--model", $Model)
    }

    if ($FallbackModel.Trim().Length -gt 0) {
      $claudeArgs += @("--fallback-model", $FallbackModel)
    }

    Write-Host "Calling Claude for $chapterRelativePath, attempt $attempt"
    $exitCode = Invoke-ClaudeForChapter -ClaudeExe $claudeExe -ClaudeArgs $claudeArgs -Prompt $prompt -LogPath $logPath

    if ($exitCode -eq 0) {
      $completedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
      $doneText = @(
        "chapter=$chapterRelativePath",
        "completed_at=$completedAt",
        "log=$logPath"
      )
      Set-Content -LiteralPath $donePath -Value $doneText -Encoding UTF8
      Write-Host "Completed: $chapterRelativePath"
      break
    }

    if ($MaxAttempts -gt 0 -and $attempt -ge $MaxAttempts) {
      throw "Claude reached MaxAttempts for $chapterRelativePath. Attempts: $MaxAttempts. Last log: $logPath"
    }

    $failureCount++
    $delaySeconds = Get-RetryDelay -FailureCount $failureCount -InitialDelay $InitialDelaySeconds -MaxDelay $MaxDelaySeconds -Factor $BackoffFactor
    Write-Warning "Claude exited with code $exitCode. Retrying in $delaySeconds seconds. Log: $logPath"
    Start-Sleep -Seconds $delaySeconds
  }
}

if (-not $DryRun -and -not $SkipBuild) {
  Write-Host ""
  Write-Host "Running build verification: npm run docs:build"
  npm run docs:build
  if ($LASTEXITCODE -ne 0) {
    throw "npm run docs:build failed with exit code $LASTEXITCODE"
  }
}

Write-Host ""
Write-Host "All requested chapters are done."
