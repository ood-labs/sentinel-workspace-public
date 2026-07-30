param(
    [Parameter(Position = 0)]
    [ValidateSet('generate', 'validate', 'new')]
    [string]$Action = 'validate',

    [Parameter(Position = 1)]
    [string]$ModulePath,

    [string]$Name,
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

function Unquote([string]$Value) {
    $v = $Value.Trim().TrimEnd(',')
    if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
        return $v.Substring(1, $v.Length - 2)
    }
    return $v
}

function Safe-Id([string]$Value) {
    $id = ($Value -replace '[^A-Za-z0-9_]', '_').ToUpperInvariant()
    if ($id -match '^[0-9]') { $id = "_$id" }
    return $id
}

function Inline-Field([string]$Line, [string]$Key) {
    $pattern = '(?:^|[,\{]\s*)' + [regex]::Escape($Key) + '\s*:\s*("[^"]*"|''[^'']*''|\[[^\]]*\]|[^,\}]+)'
    $m = [regex]::Match($Line, $pattern)
    if (-not $m.Success) { return $null }
    return Unquote $m.Groups[1].Value
}

function Parse-Rect([string]$Value) {
    if (-not $Value) { return $null }
    $numbers = [regex]::Matches($Value, '-?(?:\d+\.?\d*|\.\d+)') | ForEach-Object { [double]::Parse($_.Value, [Globalization.CultureInfo]::InvariantCulture) }
    if ($numbers.Count -ne 4) { return $null }
    return @($numbers)
}

function Read-UiManifest([string]$ManifestPath) {
    $lines = Get-Content -LiteralPath $ManifestPath
    # Hash canonical LF text so generated headers stay stable across Git's
    # Windows checkout conversion and clean archive exports.
    $text = [IO.File]::ReadAllText($ManifestPath).Replace("`r`n", "`n")
    $resolution = @(960.0, 540.0)
    $name = Split-Path -Leaf (Split-Path -Parent $ManifestPath)
    $parameters = @{}
    $controls = [Collections.Generic.List[object]]::new()
    $labels = [Collections.Generic.List[object]]::new()
    $rootSection = ''
    $viewportSection = ''
    $pending = $null
    $pendingKind = ''

    foreach ($line in $lines) {
        if ($line -match '^\s*#\s*ui-label:\s*([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(.+?)\s*$') {
            $labels.Add([pscustomobject]@{ id = $Matches[1]; text = Unquote $Matches[2] })
            continue
        }
        if ($line -match '^name:\s*(.+)$') { $name = Unquote $Matches[1] }
        if ($line -match '^resolution:\s*\[\s*(\d+)\s*,\s*(\d+)\s*\]') {
            $resolution = @([double]$Matches[1], [double]$Matches[2])
        }
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*):\s*') {
            $rootSection = $Matches[1]
            $viewportSection = ''
            $pending = $null
        }
        if ($rootSection -eq 'viewport' -and $line -match '^\s{2}([A-Za-z_][A-Za-z0-9_]*):\s*') {
            $viewportSection = $Matches[1]
            $pending = $null
        }

        if ($rootSection -eq 'parameters' -and $line -match '^\s+-\s+\{') {
            $pname = Inline-Field $line 'name'
            $ptype = Inline-Field $line 'type'
            if ($pname) { $parameters[$pname] = $ptype }
        }

        if ($rootSection -eq 'viewport' -and $viewportSection -in @('controls', 'labels')) {
            if ($line -match '^\s{4}-\s+\{') {
                if ($viewportSection -eq 'controls') {
                    $controls.Add([pscustomobject]@{
                        id = Inline-Field $line 'id'
                        kind = Inline-Field $line 'kind'
                        param = Inline-Field $line 'param'
                        rect = Parse-Rect (Inline-Field $line 'rect')
                        label = Inline-Field $line 'label'
                    })
                } else {
                    $labels.Add([pscustomobject]@{
                        id = Inline-Field $line 'id'
                        text = Inline-Field $line 'text'
                    })
                }
                continue
            }

            if ($line -match '^\s{4}-\s+id:\s*(.+)$') {
                if ($pending) {
                    if ($pendingKind -eq 'controls') { $controls.Add([pscustomobject]$pending) } else { $labels.Add([pscustomobject]$pending) }
                }
                $pendingKind = $viewportSection
                if ($pendingKind -eq 'controls') {
                    $pending = [ordered]@{ id = Unquote $Matches[1]; kind = $null; param = $null; rect = $null; label = $null }
                } else {
                    $pending = [ordered]@{ id = Unquote $Matches[1]; text = $null }
                }
                continue
            }

            if ($pending -and $line -match '^\s{6}([A-Za-z_][A-Za-z0-9_]*):\s*(.+)$') {
                $key = $Matches[1]
                $value = Unquote $Matches[2]
                if ($key -eq 'rect') { $pending[$key] = Parse-Rect $value }
                elseif ($pending.Contains($key)) { $pending[$key] = $value }
            }
        }
    }
    if ($pending) {
        if ($pendingKind -eq 'controls') { $controls.Add([pscustomobject]$pending) } else { $labels.Add([pscustomobject]$pending) }
    }

    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }

    return [pscustomobject]@{
        Path = $ManifestPath
        Name = $name
        Resolution = $resolution
        Parameters = $parameters
        Controls = @($controls)
        Labels = @($labels)
        Hash = $hash
    }
}

function Get-UiErrors($Manifest) {
    $errors = [Collections.Generic.List[string]]::new()
    $warnings = [Collections.Generic.List[string]]::new()
    $ids = @{}
    $expectedTypes = @{ slider = @('float', 'int'); button = @('button'); toggle = @('bool'); xypad = @('vec2', 'point2D') }

    for ($i = 0; $i -lt $Manifest.Controls.Count; ++$i) {
        $c = $Manifest.Controls[$i]
        if (-not $c.id) { $errors.Add("control $i has no id"); continue }
        if ($ids.ContainsKey($c.id)) { $errors.Add("duplicate control id '$($c.id)'") } else { $ids[$c.id] = $true }
        if (-not $expectedTypes.ContainsKey($c.kind)) { $errors.Add("control '$($c.id)' has unsupported kind '$($c.kind)'") }
        if (-not $Manifest.Parameters.ContainsKey($c.param)) { $errors.Add("control '$($c.id)' references missing parameter '$($c.param)'") }
        elseif ($expectedTypes.ContainsKey($c.kind) -and $Manifest.Parameters[$c.param] -notin $expectedTypes[$c.kind]) {
            $errors.Add("control '$($c.id)' kind '$($c.kind)' is incompatible with parameter type '$($Manifest.Parameters[$c.param])'")
        }
        if (-not $c.rect -or $c.rect.Count -ne 4) { $errors.Add("control '$($c.id)' needs rect [x0,y0,x1,y1]"); continue }
        $r = $c.rect
        if ($r[0] -lt 0 -or $r[1] -lt 0 -or $r[2] -gt 1 -or $r[3] -gt 1 -or $r[0] -ge $r[2] -or $r[1] -ge $r[3]) {
            $errors.Add("control '$($c.id)' rect is outside normalized bounds or inverted")
        }
        $heightPx = ($r[3] - $r[1]) * $Manifest.Resolution[1]
        if ($heightPx -lt 32.0) { $errors.Add("control '$($c.id)' hit height is $([math]::Round($heightPx,1)) px; minimum is 32 px") }
        for ($j = 0; $j -lt $i; ++$j) {
            $o = $Manifest.Controls[$j].rect
            if ($o -and [math]::Max($r[0],$o[0]) -lt [math]::Min($r[2],$o[2]) -and [math]::Max($r[1],$o[1]) -lt [math]::Min($r[3],$o[3])) {
                $warnings.Add("controls '$($Manifest.Controls[$j].id)' and '$($c.id)' overlap")
            }
        }
    }

    $allText = @($Manifest.Labels | ForEach-Object text) + @($Manifest.Controls | ForEach-Object label)
    foreach ($text in $allText) {
        if ([string]::IsNullOrEmpty($text)) { $errors.Add('UI label text must not be empty'); continue }
        foreach ($ch in $text.ToCharArray()) {
            $code = [int][char]$ch
            if ($code -lt 32 -or $code -gt 126) { $errors.Add("unsupported non-ASCII character U+$($code.ToString('X4')) in '$text'") }
        }
    }
    return [pscustomobject]@{ Errors = $errors; Warnings = $warnings }
}

function Get-GeneratedText($Manifest) {
    $moduleId = Safe-Id $Manifest.Name
    $labels = [Collections.Generic.List[object]]::new()
    foreach ($l in $Manifest.Labels) { $labels.Add([pscustomobject]@{ id = $l.id; text = $l.text }) }
    foreach ($c in $Manifest.Controls) { $labels.Add([pscustomobject]@{ id = "control_$($c.id)"; text = $c.label }) }

    $b = [Text.StringBuilder]::new()
    [void]$b.AppendLine("#ifndef ${moduleId}_UI_GENERATED_HLSLI")
    [void]$b.AppendLine("#define ${moduleId}_UI_GENERATED_HLSLI")
    [void]$b.AppendLine('')
    [void]$b.AppendLine("// Generated by tools/module-ui.ps1 from manifest.yaml. Do not hand edit.")
    [void]$b.AppendLine("// manifest-sha256: $($Manifest.Hash)")
    [void]$b.AppendLine("static const uint UI_CONTROL_COUNT = $($Manifest.Controls.Count)u;")
    [void]$b.AppendLine("static const uint UI_LABEL_COUNT = $($labels.Count)u;")
    [void]$b.AppendLine("static const uint4 UI_MANIFEST_HASH = uint4(0x$($Manifest.Hash.Substring(0,8))u, 0x$($Manifest.Hash.Substring(8,8))u, 0x$($Manifest.Hash.Substring(16,8))u, 0x$($Manifest.Hash.Substring(24,8))u);")
    [void]$b.AppendLine('')
    for ($i = 0; $i -lt $Manifest.Controls.Count; ++$i) {
        $c = $Manifest.Controls[$i]
        $id = Safe-Id $c.id
        $nums = $c.rect | ForEach-Object { $_.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture) }
        [void]$b.AppendLine("static const uint UI_INDEX_${id} = ${i}u;")
        [void]$b.AppendLine("static const float4 UI_RECT_${id} = float4($($nums -join ', '));")
    }
    [void]$b.AppendLine('')
    for ($i = 0; $i -lt $labels.Count; ++$i) {
        [void]$b.AppendLine("static const uint UI_LABEL_$(Safe-Id $labels[$i].id) = ${i}u;")
    }
    [void]$b.AppendLine('')
    [void]$b.AppendLine('int uiLabelLength(uint labelId) {')
    for ($i = 0; $i -lt $labels.Count; ++$i) { [void]$b.AppendLine("    if (labelId == ${i}u) return $($labels[$i].text.Length);") }
    [void]$b.AppendLine('    return 0;')
    [void]$b.AppendLine('}')
    [void]$b.AppendLine('')
    [void]$b.AppendLine('int uiLabelCode(uint labelId, int characterIndex) {')
    for ($i = 0; $i -lt $labels.Count; ++$i) {
        $codes = $labels[$i].text.ToCharArray() | ForEach-Object { [int][char]$_ }
        [void]$b.AppendLine("    if (labelId == ${i}u) {")
        [void]$b.AppendLine("        int codes[$($codes.Count)] = { $($codes -join ', ') };")
        [void]$b.AppendLine("        return characterIndex >= 0 && characterIndex < $($codes.Count) ? codes[characterIndex] : 32;")
        [void]$b.AppendLine('    }')
    }
    [void]$b.AppendLine('    return 32;')
    [void]$b.AppendLine('}')
    [void]$b.AppendLine('')
    [void]$b.AppendLine('#endif')
    return $b.ToString().Replace("`r`n", "`n")
}

function Resolve-Module([string]$PathValue) {
    if (-not $PathValue) { throw 'A module directory is required.' }
    $path = if ([IO.Path]::IsPathRooted($PathValue)) { $PathValue } else { Join-Path $Root $PathValue }
    $path = [IO.Path]::GetFullPath($path)
    if (-not (Test-Path -LiteralPath (Join-Path $path 'manifest.yaml'))) { throw "No manifest.yaml found in $path" }
    return $path
}

function Test-IsUnder([string]$ParentPath, [string]$CandidatePath) {
    $parent = [IO.Path]::GetFullPath($ParentPath).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $candidate = [IO.Path]::GetFullPath($CandidatePath)
    return $candidate.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-ProjectModuleTarget([string]$PathValue) {
    if (-not $PathValue) { throw 'A project-local module directory is required.' }
    $path = if ([IO.Path]::IsPathRooted($PathValue)) { $PathValue } else { Join-Path $Root $PathValue }
    $path = [IO.Path]::GetFullPath($path)
    $projectsRoot = [IO.Path]::GetFullPath((Join-Path $Root 'projects'))
    if (-not (Test-IsUnder $projectsRoot $path)) {
        throw "New Modules must be created under projects/<project>/modules/: $path"
    }

    $relative = $path.Substring($projectsRoot.TrimEnd('\', '/').Length).TrimStart('\', '/')
    $segments = @($relative -split '[\\/]')
    if ($segments.Count -ne 3 -or $segments[1] -cne 'modules' -or $segments[2] -eq '_shared') {
        throw "New Modules must use the exact shape projects/<project>/modules/<module>: $path"
    }

    $projectPath = Join-Path $projectsRoot $segments[0]
    if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
        throw "Project directory does not exist: $projectPath"
    }
    return $path
}

function Get-TemplatePaths {
    $templateRoot = Join-Path $PSScriptRoot 'templates/module-ui'
    $moduleTemplate = Join-Path $templateRoot 'module'
    $sharedTemplate = Join-Path $templateRoot 'shared'
    foreach ($required in @(
        (Join-Path $moduleTemplate 'manifest.yaml'),
        (Join-Path $moduleTemplate 'render.hlsl'),
        (Join-Path $sharedTemplate 'ui/sui3_core.hlsli'),
        (Join-Path $sharedTemplate 'ui/sui3_controls.hlsli'),
        (Join-Path $sharedTemplate 'ui/sui3_text.hlsli'),
        (Join-Path $sharedTemplate 'ui/sui3_theme.hlsli'),
        (Join-Path $sharedTemplate 'fonts/scientifica_ascii.hlsli'),
        (Join-Path $sharedTemplate 'fonts/SCIENTIFICA_LICENSE.txt')
    )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Module UI template is incomplete: $required"
        }
    }
    return [pscustomobject]@{
        Root = $templateRoot
        Module = $moduleTemplate
        Shared = $sharedTemplate
    }
}

function Get-ProjectModuleManifests {
    $projectsRoot = Join-Path $Root 'projects'
    if (-not (Test-Path -LiteralPath $projectsRoot -PathType Container)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $projectsRoot -Filter manifest.yaml -File -Recurse |
            Where-Object {
                $_.FullName -match '[\\/]projects[\\/][^\\/]+[\\/]modules[\\/][^\\/]+[\\/]manifest\.yaml$' -and
                $_.Directory.Name -ne '_shared'
            } |
            Sort-Object FullName
    )
}

function Validate-One([string]$Path, [switch]$CheckStale) {
    $manifest = Read-UiManifest (Join-Path $Path 'manifest.yaml')
    $result = Get-UiErrors $manifest
    foreach ($w in $result.Warnings) { Write-Warning "$($manifest.Name): $w" }
    $errors = [Collections.Generic.List[string]]::new()
    foreach ($e in $result.Errors) { $errors.Add($e) }
    if ($CheckStale -and $manifest.Controls.Count -gt 0) {
        $generatedPath = Join-Path $Path '_ui.generated.hlsli'
        $expected = Get-GeneratedText $manifest
        if (-not (Test-Path -LiteralPath $generatedPath)) { $errors.Add('missing _ui.generated.hlsli') }
        elseif ([IO.File]::ReadAllText($generatedPath).Replace("`r`n", "`n") -ne $expected) { $errors.Add('_ui.generated.hlsli is stale') }
    }
    if ($errors.Count -gt 0) { throw "$($manifest.Name):`n - $($errors -join "`n - ")" }
    Write-Host "OK  $($manifest.Name) ($($manifest.Controls.Count) controls)"
    return $manifest
}

switch ($Action) {
    'generate' {
        $path = Resolve-Module $ModulePath
        $manifest = Validate-One $path
        $output = Join-Path $path '_ui.generated.hlsli'
        [IO.File]::WriteAllText($output, (Get-GeneratedText $manifest), [Text.UTF8Encoding]::new($false))
        Write-Host "WROTE $output"
    }
    'validate' {
        if ($ModulePath) {
            [void](Validate-One (Resolve-Module $ModulePath) -CheckStale)
        } else {
            $manifests = @(Get-ProjectModuleManifests)
            if ($manifests.Count -eq 0) { throw 'No project-local Module manifests were found.' }
            foreach ($manifestPath in $manifests) {
                [void](Validate-One $manifestPath.Directory.FullName -CheckStale)
            }
        }
    }
    'new' {
        if (-not $ModulePath -or -not $Name) { throw 'new requires ModulePath and -Name.' }
        $target = Resolve-ProjectModuleTarget $ModulePath
        if (Test-Path -LiteralPath $target) { throw "Target already exists: $target" }
        $template = Get-TemplatePaths
        $moduleRoot = Split-Path -Parent $target
        $sharedRoot = Join-Path $moduleRoot '_shared'
        $createdSharedFiles = [Collections.Generic.List[string]]::new()
        $createdDirectories = [Collections.Generic.List[string]]::new()
        $stage = Join-Path $moduleRoot ('.module-ui-stage-' + [guid]::NewGuid().ToString('N'))

        # Compare every existing shared dependency before changing the project.
        foreach ($source in Get-ChildItem -LiteralPath $template.Shared -File -Recurse) {
            $relative = $source.FullName.Substring($template.Shared.TrimEnd('\', '/').Length).TrimStart('\', '/')
            $destination = Join-Path $sharedRoot $relative
            if (Test-Path -LiteralPath $destination -PathType Leaf) {
                if ((Get-FileHash -LiteralPath $source.FullName).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) {
                    throw "Shared dependency conflict: $destination"
                }
            } elseif (Test-Path -LiteralPath $destination) {
                throw "Shared dependency target is not a file: $destination"
            }
        }

        try {
            if (-not (Test-Path -LiteralPath $moduleRoot -PathType Container)) {
                New-Item -ItemType Directory -Path $moduleRoot | Out-Null
                $createdDirectories.Add($moduleRoot)
            }
            New-Item -ItemType Directory -Path $stage | Out-Null
            Copy-Item -Path (Join-Path $template.Module '*') -Destination $stage -Recurse

            $manifestPath = Join-Path $stage 'manifest.yaml'
            $manifestText = [IO.File]::ReadAllText($manifestPath).Replace('{{NAME}}', $Name)
            [IO.File]::WriteAllText($manifestPath, $manifestText.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
            $manifest = Validate-One $stage
            [IO.File]::WriteAllText(
                (Join-Path $stage '_ui.generated.hlsli'),
                (Get-GeneratedText $manifest),
                [Text.UTF8Encoding]::new($false)
            )

            foreach ($source in Get-ChildItem -LiteralPath $template.Shared -File -Recurse) {
                $relative = $source.FullName.Substring($template.Shared.TrimEnd('\', '/').Length).TrimStart('\', '/')
                $destination = Join-Path $sharedRoot $relative
                if (Test-Path -LiteralPath $destination -PathType Leaf) { continue }
                $parent = Split-Path -Parent $destination
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                }
                Copy-Item -LiteralPath $source.FullName -Destination $destination
                $createdSharedFiles.Add($destination)
            }

            Move-Item -LiteralPath $stage -Destination $target
            [void](Validate-One $target -CheckStale)
            Write-Host "CREATED $target"
        } catch {
            if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
            foreach ($path in $createdSharedFiles) {
                if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
            }
            foreach ($directory in @($createdDirectories | Sort-Object Length -Descending)) {
                if ((Test-Path -LiteralPath $directory -PathType Container) -and
                    ((Get-ChildItem -LiteralPath $directory -Force | Measure-Object).Count -eq 0)) {
                    Remove-Item -LiteralPath $directory
                }
            }
            throw
        }
    }
}
