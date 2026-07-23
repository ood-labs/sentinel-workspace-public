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
            $sourceByName = @{}
            Get-ChildItem -LiteralPath (Join-Path $Root 'modules') -Directory | ForEach-Object {
                $manifestPath = Join-Path $_.FullName 'manifest.yaml'
                if (Test-Path -LiteralPath $manifestPath) {
                    $m = Read-UiManifest $manifestPath
                    if ($m.Controls.Count -gt 0) { [void](Validate-One $_.FullName -CheckStale); $sourceByName[$m.Name] = $_.FullName }
                }
            }
            Get-ChildItem -LiteralPath (Join-Path $Root 'projects') -Filter manifest.yaml -File -Recurse | Where-Object { $_.FullName -match '[\\/]modules[\\/]' } | ForEach-Object {
                $bundle = Read-UiManifest $_.FullName
                if ($sourceByName.ContainsKey($bundle.Name)) {
                    $source = $sourceByName[$bundle.Name]
                    $bundleDir = $_.Directory.FullName
                    foreach ($file in Get-ChildItem -LiteralPath $source -File) {
                        $other = Join-Path $bundleDir $file.Name
                        if (-not (Test-Path -LiteralPath $other) -or (Get-FileHash $file.FullName).Hash -ne (Get-FileHash $other).Hash) {
                            throw "source/bundle drift: $($bundle.Name) file '$($file.Name)'"
                        }
                    }
                }
            }
        }
    }
    'new' {
        if (-not $ModulePath -or -not $Name) { throw 'new requires ModulePath and -Name.' }
        $target = if ([IO.Path]::IsPathRooted($ModulePath)) { $ModulePath } else { Join-Path $Root $ModulePath }
        if (Test-Path -LiteralPath $target) { throw "Target already exists: $target" }
        New-Item -ItemType Directory -Path $target | Out-Null
        $template = Join-Path $Root 'modules/_shared/ui/template'
        Copy-Item -LiteralPath (Join-Path $template 'manifest.yaml') -Destination (Join-Path $target 'manifest.yaml')
        Copy-Item -LiteralPath (Join-Path $template 'render.hlsl') -Destination (Join-Path $target 'render.hlsl')
        (Get-Content -Raw -LiteralPath (Join-Path $target 'manifest.yaml')).Replace('{{NAME}}', $Name) | Set-Content -NoNewline -LiteralPath (Join-Path $target 'manifest.yaml')
        & $PSCommandPath generate $target
        Write-Host "CREATED $target"
    }
}
