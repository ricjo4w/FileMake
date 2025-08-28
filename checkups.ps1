<# 
Dump-ResearchIR-Dependencies.ps1
Recursively collects DLL dependencies for ResearchIR.exe using Dependencies.exe
and outputs a unique, absolute path list to a text file.

USAGE (PowerShell):
    .\Dump-ResearchIR-Dependencies.ps1 -DepsExe "C:\Tools\Dependencies\Dependencies.exe" `
        -TargetExe "C:\Program Files\FLIR ResearchIR\ResearchIR.exe" `
        -OutFile "C:\scratch\researchir_dependencies.txt"

Notes:
- Requires Dependencies.exe CLI (lucasg/Dependencies).
- We prefer JSON output for robust parsing; we fall back to text parsing if needed.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$DepsExe,

    [Parameter(Mandatory=$true)]
    [string]$TargetExe,

    [Parameter(Mandatory=$true)]
    [string]$OutFile,

    # Optional: extra search paths to help Dependencies resolve private DLLs
    [string[]]$SearchPaths = @()
)

function Resolve-FullPath {
    param([string]$PathCandidate)

    # Already absolute and exists?
    if ([System.IO.Path]::IsPathRooted($PathCandidate) -and (Test-Path -LiteralPath $PathCandidate)) {
        return (Resolve-Path -LiteralPath $PathCandidate).Path
    }

    # Try alongside the target EXE
    $sibling = Join-Path -Path (Split-Path -Parent $TargetExe) -ChildPath $PathCandidate
    if (Test-Path -LiteralPath $sibling) { return (Resolve-Path $sibling).Path }

    # Try each user-provided search path
    foreach ($p in $SearchPaths) {
        $cand = Join-Path -Path $p -ChildPath $PathCandidate
        if (Test-Path -LiteralPath $cand) { return (Resolve-Path $cand).Path }
    }

    # Try System32 / SysWOW64 (common for system DLLs)
    $sys32 = Join-Path $env:WINDIR "System32\$PathCandidate"
    if (Test-Path -LiteralPath $sys32) { return (Resolve-Path $sys32).Path }
    $wow64 = Join-Path $env:WINDIR "SysWOW64\$PathCandidate"
    if (Test-Path -LiteralPath $wow64) { return (Resolve-Path $wow64).Path }

    # Fallback: if not found, return the original (may be apiset or missing)
    return $PathCandidate
}

# --- Verify prerequisites ---
if (-not (Test-Path -LiteralPath $DepsExe)) {
    throw "Dependencies.exe not found at: $DepsExe"
}
if (-not (Test-Path -LiteralPath $TargetExe)) {
    throw "Target EXE not found at: $TargetExe"
}
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null

# We’ll ask for the whole chain in JSON. If JSON parsing fails (older builds),
# we fall back to text parsing of -modules / -chain output.
$depsArgs = @("-json", "-chain", "`"$TargetExe`"")
$raw = & $DepsExe @depsArgs 2>$null

$paths = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)

function Add-PathIfValid([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return }
    # Skip obvious apiset pseudo-DLL names; Dependencies usually resolves these,
    # but if a name slips through, we don't want to copy it.
    if ($p -match '^(api-ms-win|ext-ms-win)') { return }
    $full = Resolve-FullPath $p
    # Only add files that look like real DLL/EXE paths or genuine names we can later handle
    # Here we accept anything that ends with .dll/.exe OR exists as a file.
    if ($full -match '\.(dll|exe)$' -or (Test-Path -LiteralPath $full)) {
        $paths.Add($full) | Out-Null
    }
}

# --- Try parsing JSON first ---
$parsed = $null
try {
    $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    $parsed = $null
}

if ($parsed -ne $null) {
    # Schema has varied between releases; handle common shapes:
    # Case A: { "Modules": [ { "Filepath": "...", "Imports": [...] }, ... ] }
    if ($parsed.Modules) {
        foreach ($m in $parsed.Modules) {
            # Some builds use "Filepath", others "FullPath" or "Path"
            $name = $m.Filepath
            if (-not $name) { $name = $m.FullPath }
            if (-not $name) { $name = $m.Path }
            if (-not $name) { $name = $m.Name }
            Add-PathIfValid $name
        }
    } else {
        # Case B: flat list
        foreach ($item in $parsed) {
            $name = $item.Filepath
            if (-not $name) { $name = $item.FullPath }
            if (-not $name) { $name = $item.Path }
            if (-not $name) { $name = $item.Name }
            Add-PathIfValid $name
        }
    }
} else {
    # --- Fallback: parse text from -modules, and then -chain if needed ---
    $rawText = $raw
    if (-not $rawText) {
        $rawText = & $DepsExe "-modules" "`"$TargetExe`"" 2>$null
    }
    foreach ($line in ($rawText -split "`r?`n")) {
        # Heuristics: lines usually include resolved module names or full paths
        # Extract strings ending with .dll/.exe
        $matches = [regex]::Matches($line, '(?<p>[A-Za-z0-9_\-\.\(\)\\/: ]+\.(dll|exe))', 'IgnoreCase')
        foreach ($m in $matches) {
            Add-PathIfValid $m.Groups['p'].Value.Trim()
        }
    }
}

# Always include the target EXE itself (handy for later copying)
Add-PathIfValid $TargetExe

# Write to output file, sorted, one per line
$sorted = $paths.ToArray() | Sort-Object
$sorted | Set-Content -Encoding UTF8 -LiteralPath $OutFile

Write-Host "Wrote $($sorted.Count) entries to $OutFile"
