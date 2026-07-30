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

function Add-Unique([Collections.Generic.List[string]]$List, [string]$Value) {
    if ($Value -and -not $List.Contains($Value)) { $List.Add($Value) }
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

$projectRoot = Join-Path $rootFull 'projects'
$filesystemProjects = if (Test-Path -LiteralPath $projectRoot -PathType Container) {
    @(
        Get-ChildItem -LiteralPath $projectRoot -Directory -Force |
            ForEach-Object { $_.Name } |
            Sort-Object -Unique
    )
} else { @() }
$missingFilesystemProjects = @($expectedProjects | Where-Object { $_ -notin $filesystemProjects })
$unexpectedFilesystemProjects = @($filesystemProjects | Where-Object { $_ -notin $expectedProjects })
foreach ($project in $missingFilesystemProjects) {
    $errors.Add("configured project directory is absent from the filesystem: projects/$project")
}
foreach ($project in $unexpectedFilesystemProjects) {
    $errors.Add("unexpected filesystem project directory (including ignored content): projects/$project")
}

$expectedProjectFiles = @(
    foreach ($projectName in $config.Projects.Keys) {
        $definition = $config.Projects[$projectName]
        $fileNames = if ($null -ne $definition.ProjectFiles) {
            @($definition.ProjectFiles)
        } else {
            @($definition.ProjectFile)
        }
        foreach ($fileName in $fileNames) {
            "projects/$projectName/$fileName"
        }
    }
)
$expectedProjectFiles = @($expectedProjectFiles | Sort-Object -Unique)
$actualProjectFiles = @(
    $trackedFiles |
        Where-Object { [IO.Path]::GetExtension($_) -ieq '.sentinel' } |
        Sort-Object -Unique
)
$missingProjectFiles = @($expectedProjectFiles | Where-Object { $_ -notin $actualProjectFiles })
$unexpectedProjectFiles = @($actualProjectFiles | Where-Object { $_ -notin $expectedProjectFiles })
foreach ($path in $missingProjectFiles) { $errors.Add("missing configured project file: $path") }
foreach ($path in $unexpectedProjectFiles) {
    $errors.Add("unexpected tracked Sentinel project file outside the curated set: $path")
}

# Exact root-module census. Project-bundled modules remain under
# projects/<name>/modules and are validated by validate-official-examples.ps1.
# The curated public seed config declares no root modules, so any tracked or
# filesystem entry under modules/ is a release failure.
$configuredModulePaths = [Collections.Generic.List[string]]::new()
$standaloneModules = if ($config.ContainsKey('StandaloneModules')) {
    @($config.StandaloneModules)
} else { @() }
foreach ($path in @($config.GlobalSharedPaths)) {
    $configuredModulePaths.Add(([string]$path).Replace('\', '/').TrimEnd('/'))
}
foreach ($projectName in $config.Projects.Keys) {
    foreach ($path in @($config.Projects[$projectName].SharedModules)) {
        $configuredModulePaths.Add(([string]$path).Replace('\', '/').TrimEnd('/'))
    }
}
foreach ($entry in $standaloneModules) {
    $configuredModulePaths.Add(([string]$entry.Path).Replace('\', '/').TrimEnd('/'))
}

$invalidConfiguredModules = @(
    $configuredModulePaths |
        Where-Object {
            [string]::IsNullOrWhiteSpace($_) -or
            [IO.Path]::IsPathRooted($_) -or
            $_ -match '(^|/)\.\.($|/)' -or
            $_ -notmatch '^modules/[^/]+$'
        } |
        Sort-Object -Unique
)
foreach ($path in $invalidConfiguredModules) {
    $errors.Add("invalid configured root-module path: $path")
}

$duplicateConfiguredModules = @(
    $configuredModulePaths |
        Group-Object { $_.ToLowerInvariant() } |
        Where-Object { $_.Count -gt 1 } |
        ForEach-Object { @($_.Group) -join ', ' }
)
foreach ($paths in $duplicateConfiguredModules) {
    $errors.Add("duplicate configured root-module path: $paths")
}

$expectedModules = @(
    $configuredModulePaths |
        Where-Object { $_ -notin $invalidConfiguredModules } |
        Sort-Object -Unique
)
$actualModules = @(
    $trackedFiles |
        ForEach-Object {
            if ($_ -match '^modules/([^/]+)/') { "modules/$($Matches[1])" }
        } |
        Where-Object { $_ } |
        Sort-Object -Unique
)
$missingModules = @($expectedModules | Where-Object { $_ -notin $actualModules })
$unexpectedModules = @($actualModules | Where-Object { $_ -notin $expectedModules })
$moduleCaseMismatches = @(
    foreach ($expected in $expectedModules) {
        $actual = @($actualModules | Where-Object { $_ -ieq $expected } | Select-Object -First 1)
        if ($actual.Count -eq 1 -and $actual[0] -cne $expected) {
            "$($actual[0]) -> $expected"
        }
    }
)
$directModuleFiles = @($trackedFiles | Where-Object { $_ -match '^modules/[^/]+$' })

$moduleIndex = @(git -C $rootFull ls-files -s -- modules)
if ($LASTEXITCODE -ne 0) { throw 'git ls-files -s -- modules failed.' }
$moduleSymlinks = @(
    $moduleIndex |
        ForEach-Object {
            if ($_ -match '^120000\s+\S+\s+\d+\t(.+)$') { $Matches[1].Replace('\', '/') }
        } |
        Where-Object { $_ } |
        Sort-Object -Unique
)

$moduleRoot = Join-Path $rootFull 'modules'
$filesystemModuleEntries = if (Test-Path -LiteralPath $moduleRoot -PathType Container) {
    @(Get-ChildItem -LiteralPath $moduleRoot -Force)
} else { @() }
$filesystemModules = @(
    $filesystemModuleEntries |
        Where-Object { $_.PSIsContainer } |
        ForEach-Object { "modules/$($_.Name)" } |
        Sort-Object -Unique
)
$missingFilesystemModules = @($expectedModules | Where-Object { $_ -notin $filesystemModules })
$unexpectedFilesystemModules = @($filesystemModules | Where-Object { $_ -notin $expectedModules })
$filesystemDirectModuleFiles = @(
    $filesystemModuleEntries |
        Where-Object { -not $_.PSIsContainer } |
        ForEach-Object { "modules/$($_.Name)" } |
        Sort-Object -Unique
)
$moduleReparsePoints = @(
    $filesystemModuleEntries |
        Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } |
        ForEach-Object { "modules/$($_.Name)" } |
        Sort-Object -Unique
)

foreach ($path in $missingModules) { $errors.Add("missing configured root module in Git: $path") }
foreach ($path in $unexpectedModules) { $errors.Add("unexpected tracked root module: $path") }
foreach ($path in $moduleCaseMismatches) { $errors.Add("root-module path casing mismatch: $path") }
foreach ($path in $directModuleFiles) { $errors.Add("tracked file is not allowed directly under modules/: $path") }
foreach ($path in $moduleSymlinks) { $errors.Add("tracked symlink is not allowed under modules/: $path") }
foreach ($path in $missingFilesystemModules) {
    $errors.Add("configured root module is absent from the filesystem: $path")
}
foreach ($path in $unexpectedFilesystemModules) {
    $errors.Add("unexpected filesystem root module (including ignored content): $path")
}
foreach ($path in $filesystemDirectModuleFiles) {
    $errors.Add("filesystem file is not allowed directly under modules/: $path")
}
foreach ($path in $moduleReparsePoints) {
    $errors.Add("filesystem reparse point is not allowed directly under modules/: $path")
}

foreach ($path in $expectedModules) {
    if ($path -ieq 'modules/_shared') { continue }
    $manifest = "$path/manifest.yaml"
    if ($manifest -notin $trackedFiles) {
        $errors.Add("configured root module has no tracked manifest: $manifest")
    }
}

$standaloneEvidence = [Collections.Generic.List[object]]::new()
foreach ($entry in $standaloneModules) {
    $modulePath = ([string]$entry.Path).Replace('\', '/').TrimEnd('/')
    $evidencePath = ([string]$entry.Evidence).Replace('\', '/').TrimEnd('/')
    $evidenceFull = Join-Path $rootFull $evidencePath.Replace('/', '\')
    $evidenceExists = Test-Path -LiteralPath $evidenceFull -PathType Leaf
    $mentionsModule = $false
    if ($evidenceExists) {
        $mentionsModule = [IO.File]::ReadAllText($evidenceFull).Contains($modulePath)
    }
    $standaloneEvidence.Add([pscustomobject]@{
        path = $modulePath
        evidence = $evidencePath
        evidence_exists = $evidenceExists
        mentions_module = $mentionsModule
    })
    if (-not $evidenceExists) {
        $errors.Add("standalone root-module evidence is missing: $modulePath -> $evidencePath")
    } elseif (-not $mentionsModule) {
        $errors.Add("standalone root-module evidence does not name the module: $modulePath -> $evidencePath")
    }
}

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
$workspaceVersionPath = Join-Path $rootFull '.sentinel-workspace-version'
$workspaceVersion = $null
if (-not (Test-Path -LiteralPath $workspaceVersionPath -PathType Leaf)) {
    $errors.Add('missing .sentinel-workspace-version')
} else {
    try {
        $workspaceVersion = [Version]([IO.File]::ReadAllText($workspaceVersionPath).Trim())
    } catch {
        $errors.Add(".sentinel-workspace-version is invalid: $($_.Exception.Message)")
    }
}
if (-not $versionCompatible) {
    $errors.Add("proof host $proofHostVersion is older than declared minimum $minimumVersion")
}
if ($null -ne $workspaceVersion -and $workspaceVersion -lt $minimumVersion) {
    $errors.Add("workspace version $workspaceVersion is older than declared minimum $minimumVersion")
}
if ([int]$config.CapabilityCommandCount -le 0 -or [string]::IsNullOrWhiteSpace([string]$config.CapabilitySchemaHash)) {
    $errors.Add('capability proof metadata is incomplete')
}

$head = (git -C $rootFull rev-parse HEAD)
if ($LASTEXITCODE -ne 0) { throw 'git rev-parse HEAD failed.' }

# Installed-workspace manifest. Its managed set must be derived from the same
# exact project/config policy as this audit, and every hash must match the
# candidate checkout. Orphan candidates are deletion tombstones only.
$workspaceManifestPath = Join-Path $rootFull '.sentinel-workspace-manifest.json'
$workspaceManifest = $null
$manifestExpectedPaths = @()
$manifestActualPaths = @()
$manifestMissingPaths = @()
$manifestUnexpectedPaths = @()
$manifestDuplicatePaths = @()
$manifestHashMismatches = [Collections.Generic.List[string]]::new()
$manifestOrphanOverlaps = @()
$manifestSourceReachable = $false
$manifestSourceIsAncestor = $false
if (-not $config.ContainsKey('WorkspaceManifest')) {
    $errors.Add('release config has no WorkspaceManifest policy')
} elseif (-not (Test-Path -LiteralPath $workspaceManifestPath -PathType Leaf)) {
    $errors.Add('missing .sentinel-workspace-manifest.json')
} else {
    try {
        $workspaceManifest = [IO.File]::ReadAllText($workspaceManifestPath) | ConvertFrom-Json
    } catch {
        $errors.Add(".sentinel-workspace-manifest.json is invalid: $($_.Exception.Message)")
    }
}

if ($null -ne $workspaceManifest) {
    $manifestCandidateFiles = @(
        git -C $rootFull ls-files --cached --others --exclude-standard |
            ForEach-Object { $_.Replace('\', '/') } |
            Sort-Object -Unique
    )
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files for workspace manifest failed.' }
    $manifestProjectPrefixes = @(
        $expectedProjects |
            ForEach-Object { "projects/$($_)/" } |
            Sort-Object
    )
    $manifestPrefixes = @(
        $config.WorkspaceManifest.Prefixes |
            ForEach-Object { ([string]$_).Replace('\', '/').Trim('/') + '/' } |
            Where-Object { $_ -notmatch '^projects/$' } |
            Sort-Object -Unique
    )
    $manifestFiles = @(
        $config.WorkspaceManifest.Files |
            ForEach-Object { ([string]$_).Replace('\', '/').TrimStart('/') } |
            Sort-Object -Unique
    )
    $manifestExpectedPaths = @(
        $manifestCandidateFiles |
            Where-Object {
                $path = $_
                if ($path -in $manifestFiles) { return $true }
                if (@($manifestPrefixes | Where-Object {
                    $path.StartsWith($_, [StringComparison]::Ordinal)
                }).Count -gt 0) { return $true }
                return @($manifestProjectPrefixes | Where-Object {
                    $path.StartsWith($_, [StringComparison]::Ordinal)
                }).Count -gt 0
            } |
            Sort-Object -Unique
    )
    $manifestActualPaths = @(
        $workspaceManifest.files |
            ForEach-Object { ([string]$_.path).Replace('\', '/') } |
            Sort-Object
    )
    $manifestDuplicatePaths = @(
        $manifestActualPaths |
            Group-Object { $_.ToLowerInvariant() } |
            Where-Object { $_.Count -gt 1 } |
            ForEach-Object { @($_.Group) -join ', ' }
    )
    $manifestMissingPaths = @(
        $manifestExpectedPaths | Where-Object { $_ -cnotin $manifestActualPaths }
    )
    $manifestUnexpectedPaths = @(
        $manifestActualPaths | Where-Object { $_ -cnotin $manifestExpectedPaths }
    )
    foreach ($path in $manifestDuplicatePaths) {
        $errors.Add("workspace manifest contains duplicate path: $path")
    }
    foreach ($path in $manifestMissingPaths) {
        $errors.Add("workspace manifest is missing managed path: $path")
    }
    foreach ($path in $manifestUnexpectedPaths) {
        $errors.Add("workspace manifest contains unexpected managed path: $path")
    }

    foreach ($entry in @($workspaceManifest.files)) {
        $relative = ([string]$entry.path).Replace('\', '/')
        $full = Join-Path $rootFull $relative.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $actualHash = Get-Sha256 $full
        $declaredHash = ([string]$entry.sha256).ToLowerInvariant()
        if ($actualHash -ne $declaredHash) {
            $manifestHashMismatches.Add($relative)
            $errors.Add("workspace manifest hash mismatch: $relative")
        }
    }

    $manifestManagedLookup = @{}
    foreach ($path in $manifestActualPaths) {
        $manifestManagedLookup[$path.ToLowerInvariant()] = $true
    }
    $manifestOrphanOverlaps = @(
        $workspaceManifest.orphan_candidates |
            ForEach-Object { ([string]$_.path).Replace('\', '/') } |
            Where-Object { $manifestManagedLookup.ContainsKey($_.ToLowerInvariant()) } |
            Sort-Object -Unique
    )
    foreach ($path in $manifestOrphanOverlaps) {
        $errors.Add("workspace manifest path is both managed and orphaned: $path")
    }

    $manifestSourceCommit = ([string]$workspaceManifest.source_commit).Trim()
    if ($manifestSourceCommit -notmatch '^[0-9a-fA-F]{40}$') {
        $errors.Add("workspace manifest source_commit is not a full Git commit id: $manifestSourceCommit")
    } else {
        git -C $rootFull cat-file -e "$manifestSourceCommit^{commit}" 2>$null
        $manifestSourceReachable = ($LASTEXITCODE -eq 0)
        if (-not $manifestSourceReachable) {
            $errors.Add("workspace manifest source_commit is not present in this repository: $manifestSourceCommit")
        } else {
            git -C $rootFull merge-base --is-ancestor $manifestSourceCommit $head
            $manifestSourceIsAncestor = ($LASTEXITCODE -eq 0)
            if (-not $manifestSourceIsAncestor) {
                $errors.Add("workspace manifest source_commit is not an ancestor of HEAD: $manifestSourceCommit")
            }
        }
    }
}

$statusLines = @(git -C $rootFull status --porcelain)
if ($statusLines.Count -gt 0) {
    $errors.Add('working tree is not clean')
}

$ignoredStatusLines = @(git -C $rootFull status --porcelain --ignored --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw 'git status --ignored failed.' }
$nontrackedForbiddenArtifacts = [Collections.Generic.List[string]]::new()
$forbiddenDirectoryNames = @($config.ForbiddenDirectoryNames | ForEach-Object { $_.ToLowerInvariant() })
foreach ($line in $ignoredStatusLines) {
    if ($line.Length -lt 4 -or $line.Substring(0, 2) -notin @('??', '!!')) { continue }
    $relative = $line.Substring(3).Trim('"').Replace('\', '/')
    $segments = @($relative -split '/')
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $name = $segments[$index].ToLowerInvariant()
        if ($name -in $forbiddenDirectoryNames -or $name -match '^checkpoint(?:_|$)') {
            Add-Unique $nontrackedForbiddenArtifacts (($segments[0..$index] -join '/'))
            break
        }
    }
    $leaf = if ($segments.Count -gt 0) { $segments[-1] } else { '' }
    foreach ($pattern in $config.ForbiddenFileNames) {
        if ($leaf -like $pattern) {
            Add-Unique $nontrackedForbiddenArtifacts $relative
            break
        }
    }
}
foreach ($path in $nontrackedForbiddenArtifacts) {
    $errors.Add("untracked or ignored forbidden artifact is visible in the checkout: $path")
}

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
        filesystem_actual = $filesystemProjects
        filesystem_missing = $missingFilesystemProjects
        filesystem_unexpected = $unexpectedFilesystemProjects
        expected_files = $expectedProjectFiles
        actual_files = $actualProjectFiles
        missing_files = $missingProjectFiles
        unexpected_files = $unexpectedProjectFiles
        exact = (
            $missingProjects.Count -eq 0 -and
            $unexpectedProjects.Count -eq 0 -and
            $missingFilesystemProjects.Count -eq 0 -and
            $unexpectedFilesystemProjects.Count -eq 0 -and
            $missingProjectFiles.Count -eq 0 -and
            $unexpectedProjectFiles.Count -eq 0
        )
    }
    module_set = [pscustomobject]@{
        expected = $expectedModules
        actual = $actualModules
        missing = $missingModules
        unexpected = $unexpectedModules
        case_mismatches = $moduleCaseMismatches
        direct_files = $directModuleFiles
        symlinks = $moduleSymlinks
        filesystem_actual = $filesystemModules
        filesystem_missing = $missingFilesystemModules
        filesystem_unexpected = $unexpectedFilesystemModules
        filesystem_direct_files = $filesystemDirectModuleFiles
        reparse_points = $moduleReparsePoints
        standalone_evidence = @($standaloneEvidence)
        exact = (
            $missingModules.Count -eq 0 -and
            $unexpectedModules.Count -eq 0 -and
            $moduleCaseMismatches.Count -eq 0 -and
            $directModuleFiles.Count -eq 0 -and
            $moduleSymlinks.Count -eq 0 -and
            $missingFilesystemModules.Count -eq 0 -and
            $unexpectedFilesystemModules.Count -eq 0 -and
            $filesystemDirectModuleFiles.Count -eq 0 -and
            $moduleReparsePoints.Count -eq 0 -and
            @($standaloneEvidence | Where-Object {
                -not $_.evidence_exists -or -not $_.mentions_module
            }).Count -eq 0
        )
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
        untracked_or_ignored_forbidden_artifacts = @($nontrackedForbiddenArtifacts)
        clean = ($secretFindings.Count -eq 0 -and $nontrackedForbiddenArtifacts.Count -eq 0)
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
        workspace = if ($null -ne $workspaceVersion) { [string]$workspaceVersion } else { '' }
        proof_host = [string]$config.LiveProofHostVersion
        compatible = $versionCompatible
        capability_command_count = [int]$config.CapabilityCommandCount
        capability_schema_hash = [string]$config.CapabilitySchemaHash
    }
    workspace_manifest = [pscustomobject]@{
        source_commit = if ($null -ne $workspaceManifest) {
            [string]$workspaceManifest.source_commit
        } else { '' }
        source_reachable = $manifestSourceReachable
        source_is_ancestor = $manifestSourceIsAncestor
        expected_files = $manifestExpectedPaths.Count
        actual_files = $manifestActualPaths.Count
        missing = $manifestMissingPaths
        unexpected = $manifestUnexpectedPaths
        duplicates = $manifestDuplicatePaths
        hash_mismatches = @($manifestHashMismatches)
        orphan_candidates = if ($null -ne $workspaceManifest) {
            @($workspaceManifest.orphan_candidates).Count
        } else { 0 }
        orphan_overlaps = $manifestOrphanOverlaps
        exact = (
            $null -ne $workspaceManifest -and
            $manifestSourceReachable -and
            $manifestSourceIsAncestor -and
            $manifestMissingPaths.Count -eq 0 -and
            $manifestUnexpectedPaths.Count -eq 0 -and
            $manifestDuplicatePaths.Count -eq 0 -and
            $manifestHashMismatches.Count -eq 0 -and
            $manifestOrphanOverlaps.Count -eq 0
        )
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
    Write-Host ("Root module set: {0} expected, {1} actual, exact={2}" -f $expectedModules.Count, $actualModules.Count, $report.module_set.exact)
    Write-Host ("Manuals identical={0}; skills mirrored={1}" -f $report.manuals.identical, $report.skills.mirrored)
    Write-Host ("Secrets={0}; links={1}; large files={2}; asset findings={3}" -f $secretFindings.Count, $linkFindings.Count, $largeFiles.Count, $assetFindings.Count)
    Write-Host ("Release audit: passed={0}, errors={1}, working_tree_clean={2}" -f $report.passed, $errors.Count, $report.working_tree_clean)
    foreach ($errorText in $errors) { Write-Host "  - $errorText" }
}

if (-not $report.passed) { exit 1 }
