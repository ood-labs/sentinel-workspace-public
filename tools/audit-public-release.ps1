[CmdletBinding()]
param(
    [string]$Root,
    [string]$ConfigPath,
    [string]$ReportPath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'official-examples.config.psd1' }

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
}

function Get-RelativePath([string]$BasePath, [string]$TargetPath) {
    $base = Get-FullPath $BasePath
    $target = Get-FullPath $TargetPath
    $baseUri = [Uri]($base.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar)
    $targetUri = [Uri]$target
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('\', '/')
}

function Test-IsUnder([string]$ParentPath, [string]$CandidatePath) {
    $parent = (Get-FullPath $ParentPath) + [IO.Path]::DirectorySeparatorChar
    $candidate = Get-FullPath $CandidatePath
    return $candidate.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Release config is missing: $ConfigPath"
}

$rootFull = Get-FullPath $Root
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$trackedFiles = @(git -C $rootFull ls-files)
if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
$trackedFiles = @($trackedFiles | ForEach-Object { $_.Replace('\', '/') })

$errors = [Collections.Generic.List[string]]::new()

# Exact project-directory census, including explicitly configured review-only projects.
$expectedProjects = @($config.Projects.Keys | ForEach-Object { [string]$_ } | Sort-Object)
$actualProjects = @(
    $trackedFiles |
        ForEach-Object {
            if ($_ -match '^projects/([^/]+)/') { $Matches[1] }
        } |
        Where-Object { $_ } |
        Sort-Object -Unique
)
$missingProjects = @($expectedProjects | Where-Object { $_ -notin $actualProjects })
$unexpectedProjects = @($actualProjects | Where-Object { $_ -notin $expectedProjects })
foreach ($project in $missingProjects) { $errors.Add("missing configured project directory: projects/$project") }
foreach ($project in $unexpectedProjects) { $errors.Add("unexpected project directory: projects/$project") }

# Public entry manuals must be byte-identical and contain no temporary release-phase status.
$manualPaths = @('AGENTS.md', 'CLAUDE.md', 'GEMINI.md')
$manualHashes = @{}
foreach ($relative in $manualPaths) {
    $path = Join-Path $rootFull $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $errors.Add("missing public entry manual: $relative")
        continue
    }
    $manualHashes[$relative] = Get-Sha256 $path
    if ([IO.File]::ReadAllText($path).Contains('Active workspace phase:')) {
        $errors.Add("temporary phase status remains in public entry manual: $relative")
    }
}
$distinctManualHashes = @($manualHashes.Values | Sort-Object -Unique)
if ($distinctManualHashes.Count -gt 1) { $errors.Add('AGENTS.md, CLAUDE.md, and GEMINI.md are not identical.') }

# The Claude and cross-agent skill mirrors must have identical file inventories and contents.
$agentSkillRoot = Join-Path $rootFull '.agents/skills'
$claudeSkillRoot = Join-Path $rootFull '.claude/skills'
$agentSkillFiles = if (Test-Path -LiteralPath $agentSkillRoot) {
    @(Get-ChildItem -LiteralPath $agentSkillRoot -File -Recurse | ForEach-Object {
        Get-RelativePath $agentSkillRoot $_.FullName
    } | Sort-Object)
} else { @() }
$claudeSkillFiles = if (Test-Path -LiteralPath $claudeSkillRoot) {
    @(Get-ChildItem -LiteralPath $claudeSkillRoot -File -Recurse | ForEach-Object {
        Get-RelativePath $claudeSkillRoot $_.FullName
    } | Sort-Object)
} else { @() }
$skillInventoryDiff = @(Compare-Object -ReferenceObject $agentSkillFiles -DifferenceObject $claudeSkillFiles)
$skillContentDiff = [Collections.Generic.List[string]]::new()
foreach ($relative in $agentSkillFiles) {
    if ($relative -notin $claudeSkillFiles) { continue }
    $agentHash = Get-Sha256 (Join-Path $agentSkillRoot $relative.Replace('/', '\'))
    $claudeHash = Get-Sha256 (Join-Path $claudeSkillRoot $relative.Replace('/', '\'))
    if ($agentHash -ne $claudeHash) { $skillContentDiff.Add($relative) }
}
if ($skillInventoryDiff.Count -gt 0) { $errors.Add('The .agents and .claude skill inventories differ.') }
foreach ($relative in $skillContentDiff) { $errors.Add("skill mirror content differs: $relative") }

# Tracked secret/config scan.
$secretFindings = [Collections.Generic.List[object]]::new()
$secretFilePatterns = @('.env', '.env.*', 'provider*.json', 'vision.json')
$knownSecretPattern = [regex]'(?<![A-Za-z0-9])(?:sk-(?:proj-)?[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|hf_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|AIza[0-9A-Za-z_-]{20,})'
$assignmentPattern = [regex]'(?im)\b(?:api[_-]?key|access[_-]?token|secret|password)\b\s*[:=]\s*["'']([^"''\r\n]{12,})["'']'
$placeholderPattern = [regex]'(?i)(example|placeholder|redacted|replace|your[_ -]|<|\$\{|environment|not[_ -]?set)'
$textExtensions = @($config.TextExtensions | ForEach-Object { $_.ToLowerInvariant() })

foreach ($relative in $trackedFiles) {
    $name = [IO.Path]::GetFileName($relative)
    foreach ($pattern in $secretFilePatterns) {
        if ($name -like $pattern) {
            $secretFindings.Add([pscustomobject]@{ path = $relative; kind = 'forbidden_config_name' })
            break
        }
    }

    $extension = [IO.Path]::GetExtension($relative).ToLowerInvariant()
    if ($extension -notin $textExtensions) { continue }
    $path = Join-Path $rootFull $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $text = [IO.File]::ReadAllText($path)
    if ($knownSecretPattern.IsMatch($text)) {
        $secretFindings.Add([pscustomobject]@{ path = $relative; kind = 'known_key_prefix' })
    }
    foreach ($match in $assignmentPattern.Matches($text)) {
        $value = $match.Groups[1].Value
        if (-not $placeholderPattern.IsMatch($value)) {
            $secretFindings.Add([pscustomobject]@{ path = $relative; kind = 'literal_secret_assignment' })
        }
    }
}
foreach ($finding in $secretFindings) { $errors.Add("secret scan: $($finding.kind): $($finding.path)") }

# Relative Markdown links from shipped entry points.
$markdownEntryPoints = @(
    $trackedFiles |
        Where-Object {
            $_ -ieq 'README.md' -or
            $_ -like 'knowledge/*.md' -or
            $_ -like '.agents/skills/*.md' -or
            $_ -like '.agents/skills/*/*.md' -or
            $_ -like '.claude/skills/*.md' -or
            $_ -like '.claude/skills/*/*.md' -or
            $_ -like 'projects/*/README*.md'
        } |
        Sort-Object -Unique
)
$linkFindings = [Collections.Generic.List[object]]::new()
$markdownLinkPattern = [regex]'!?\[[^\]]*\]\(([^)\r\n]+)\)'
foreach ($relative in $markdownEntryPoints) {
    $path = Join-Path $rootFull $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $text = [IO.File]::ReadAllText($path)
    foreach ($match in $markdownLinkPattern.Matches($text)) {
        $rawTarget = $match.Groups[1].Value.Trim()
        $target = if ($rawTarget.StartsWith('<') -and $rawTarget.Contains('>')) {
            $rawTarget.Substring(1, $rawTarget.IndexOf('>') - 1)
        } else {
            ([regex]::Match($rawTarget, '^\S+')).Value
        }
        if ([string]::IsNullOrWhiteSpace($target)) { continue }
        if ($target.StartsWith('#') -or $target -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or $target.StartsWith('//')) { continue }
        $target = $target.Split('#')[0]
        if ([string]::IsNullOrWhiteSpace($target)) { continue }
        $target = [Uri]::UnescapeDataString($target)
        if ([IO.Path]::IsPathRooted($target)) {
            $linkFindings.Add([pscustomobject]@{ source = $relative; target = $target; kind = 'rooted_path' })
            continue
        }
        $resolved = Get-FullPath (Join-Path (Split-Path -Parent $path) $target.Replace('/', '\'))
        if (-not (Test-IsUnder $rootFull $resolved) -or -not (Test-Path -LiteralPath $resolved)) {
            $linkFindings.Add([pscustomobject]@{ source = $relative; target = $target; kind = 'missing_or_escaping' })
        }
    }
}
foreach ($finding in $linkFindings) {
    $errors.Add("Markdown link: $($finding.kind): $($finding.source) -> $($finding.target)")
}

# Tracked file-size thresholds.
$largeFiles = [Collections.Generic.List[object]]::new()
$topFiles = [Collections.Generic.List[object]]::new()
foreach ($relative in $trackedFiles) {
    $path = Join-Path $rootFull $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $bytes = (Get-Item -LiteralPath $path).Length
    $record = [pscustomobject]@{
        path = $relative
        bytes = $bytes
        mib = [math]::Round($bytes / 1MB, 3)
    }
    $topFiles.Add($record)
    if ($bytes -gt 50MB) { $largeFiles.Add($record) }
}
$topFiles = @($topFiles | Sort-Object bytes -Descending | Select-Object -First 20)
foreach ($file in $largeFiles) {
    $severity = if ($file.bytes -gt 100MB) { 'hard-stop' } else { 'review-required' }
    $errors.Add("large tracked file ($severity): $($file.path) [$($file.mib) MiB]")
}

# Asset/license coverage. Generated proof media is covered by pattern; input media needs a ledger row.
$mediaExtensions = @('.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp', '.tif', '.tiff', '.mp4', '.mov', '.wav')
$assetLedger = @($config.AssetLedger)
$generatedMediaPatterns = @($config.GeneratedMediaPatterns)
$ledgerByPath = @{}
foreach ($asset in $assetLedger) { $ledgerByPath[[string]$asset.Path] = $asset }
$assetFindings = [Collections.Generic.List[object]]::new()
$mediaLedger = [Collections.Generic.List[object]]::new()
foreach ($asset in $assetLedger) {
    $relative = [string]$asset.Path
    $path = Join-Path $rootFull $relative.Replace('/', '\')
    $evidence = Join-Path $rootFull ([string]$asset.Evidence).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $assetFindings.Add([pscustomobject]@{ path = $relative; issue = 'ledger_path_missing' })
    }
    if (-not (Test-Path -LiteralPath $evidence -PathType Leaf)) {
        $assetFindings.Add([pscustomobject]@{ path = $relative; issue = 'evidence_missing' })
    }
    if ([string]$asset.RedistributionStatus -ne 'cleared') {
        $assetFindings.Add([pscustomobject]@{ path = $relative; issue = 'redistribution_not_cleared' })
    }
}
foreach ($relative in $trackedFiles) {
    if ([IO.Path]::GetExtension($relative).ToLowerInvariant() -notin $mediaExtensions) { continue }
    if ($ledgerByPath.ContainsKey($relative)) {
        $asset = $ledgerByPath[$relative]
        $mediaLedger.Add([pscustomobject]@{
            path = $relative
            kind = 'input_dependency'
            source = [string]$asset.Source
            purpose = [string]$asset.Purpose
            redistribution_status = [string]$asset.RedistributionStatus
            evidence = [string]$asset.Evidence
        })
        continue
    }
    $generated = $false
    foreach ($pattern in $generatedMediaPatterns) {
        if ($relative -like [string]$pattern) { $generated = $true; break }
    }
    if ($generated) {
        $mediaLedger.Add([pscustomobject]@{
            path = $relative
            kind = 'generated_artifact'
            source = 'Repository-generated fixture or Sentinel project output'
            purpose = 'Project proof, review artifact, or deterministic test fixture'
            redistribution_status = 'cleared'
            evidence = ''
        })
    } else {
        $assetFindings.Add([pscustomobject]@{ path = $relative; issue = 'unclassified_media' })
    }
}
foreach ($finding in $assetFindings) { $errors.Add("asset ledger: $($finding.issue): $($finding.path)") }

# Declared version and capability proof.
$minimumVersion = [Version]([string]$config.MinimumSentinelVersion)
$proofHostVersion = [Version]([string]$config.LiveProofHostVersion)
$versionCompatible = $proofHostVersion -ge $minimumVersion
if (-not $versionCompatible) {
    $errors.Add("proof host $proofHostVersion is older than declared minimum $minimumVersion")
}
if ([int]$config.CapabilityCommandCount -le 0 -or [string]::IsNullOrWhiteSpace([string]$config.CapabilitySchemaHash)) {
    $errors.Add('capability proof metadata is incomplete')
}

$head = (git -C $rootFull rev-parse HEAD)
$statusLines = @(git -C $rootFull status --porcelain)
$report = [pscustomobject]@{
    schema_version = 1
    root = $rootFull
    commit = $head
    working_tree_clean = ($statusLines.Count -eq 0)
    project_set = [pscustomobject]@{
        expected = $expectedProjects
        actual = $actualProjects
        missing = $missingProjects
        unexpected = $unexpectedProjects
        exact = ($missingProjects.Count -eq 0 -and $unexpectedProjects.Count -eq 0)
    }
    manuals = [pscustomobject]@{
        hashes = $manualHashes
        identical = ($distinctManualHashes.Count -eq 1)
    }
    skills = [pscustomobject]@{
        agent_files = $agentSkillFiles.Count
        claude_files = $claudeSkillFiles.Count
        inventory_differences = @($skillInventoryDiff)
        content_differences = @($skillContentDiff)
        mirrored = ($skillInventoryDiff.Count -eq 0 -and $skillContentDiff.Count -eq 0)
    }
    secrets = [pscustomobject]@{
        findings = @($secretFindings)
        clean = ($secretFindings.Count -eq 0)
    }
    markdown_links = [pscustomobject]@{
        entry_points_checked = $markdownEntryPoints.Count
        findings = @($linkFindings)
        clean = ($linkFindings.Count -eq 0)
    }
    file_sizes = [pscustomobject]@{
        review_threshold_mib = 50
        hard_stop_mib = 100
        over_threshold = @($largeFiles)
        top_twenty = @($topFiles)
        clean = ($largeFiles.Count -eq 0)
    }
    assets = [pscustomobject]@{
        media_files = $mediaLedger.Count
        ledger = @($mediaLedger)
        findings = @($assetFindings)
        clean = ($assetFindings.Count -eq 0)
    }
    version = [pscustomobject]@{
        minimum = [string]$config.MinimumSentinelVersion
        proof_host = [string]$config.LiveProofHostVersion
        compatible = $versionCompatible
        capability_command_count = [int]$config.CapabilityCommandCount
        capability_schema_hash = [string]$config.CapabilitySchemaHash
    }
    errors = @($errors)
    passed = ($errors.Count -eq 0)
}

$jsonText = $report | ConvertTo-Json -Depth 12
if ($ReportPath) {
    $reportFull = if ([IO.Path]::IsPathRooted($ReportPath)) {
        $ReportPath
    } else {
        Join-Path $rootFull $ReportPath
    }
    $parent = Split-Path -Parent $reportFull
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [IO.File]::WriteAllText($reportFull, $jsonText + "`n", [Text.UTF8Encoding]::new($false))
}

if ($Json) {
    Write-Output $jsonText
} else {
    Write-Host ("Project set: {0} expected, {1} actual, exact={2}" -f $expectedProjects.Count, $actualProjects.Count, $report.project_set.exact)
    Write-Host ("Manuals identical={0}; skills mirrored={1}" -f $report.manuals.identical, $report.skills.mirrored)
    Write-Host ("Secrets={0}; links={1}; large files={2}; asset findings={3}" -f $secretFindings.Count, $linkFindings.Count, $largeFiles.Count, $assetFindings.Count)
    Write-Host ("Release audit: passed={0}, errors={1}, working_tree_clean={2}" -f $report.passed, $errors.Count, $report.working_tree_clean)
    foreach ($errorText in $errors) { Write-Host "  - $errorText" }
}

if (-not $report.passed) { exit 1 }
