# ChimeraXP — niezalezny instalator dla prywatnego repozytorium GitHub.
# Offline: .\install.cmd (z pobranego ZIP/klonu)
# Online:  .\update.cmd  (wymaga dostepu do repo i 'gh auth login')
[CmdletBinding()]
param(
    [ValidateSet('Local', 'GitHub')]
    [string]$Source = 'Local',
    [string]$ProfileDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = 'gnomidlo/ChimeraXP'
$branch = 'main'
$onlyPluginFile = 'plugins/chimera_autoexp/init.lua'
$marker = '-- Chimera AutoExp 5 / standalone plugin'

function Say([string]$text) { Write-Host ("[ChimeraXP] " + $text) }
function Sha256([byte[]]$data) {
    $digest = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($digest.ComputeHash($data))).Replace('-', '').ToLowerInvariant()
    } finally {
        $digest.Dispose()
    }
}
function Get-PrivateFile([string]$path) {
    # 'gh' korzysta z indywidualnych uprawnien zalogowanego uzytkownika.
    # Nie zapisujemy, nie pobieramy ani nie przekazujemy tokenow GitHub.
    $endpoint = "repos/$repo/contents/$path`?ref=$branch"
    $contentLines = @(& gh api $endpoint --jq '.content' 2>$null)
    if ($LASTEXITCODE -ne 0 -or $contentLines.Count -eq 0) {
        throw "Nie mozna pobrac $path. Sprawdz dostep do $repo i gh auth login."
    }
    $b64 = ($contentLines -join '') -replace '\s', ''
    try { return [Convert]::FromBase64String($b64) }
    catch { throw "Niepoprawna odpowiedz GitHub API przy pobieraniu $path." }
}
function Get-SourceFile([string]$path) {
    if ($Source -eq 'GitHub') { return Get-PrivateFile $path }
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $localPath = Join-Path $repoRoot ($path -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        throw "Brak pliku $localPath. Uruchom instalator z rozpakowanego repozytorium lub uzyj -Source GitHub."
    }
    return [IO.File]::ReadAllBytes($localPath)
}
function Resolve-Profile([string]$explicit) {
    if (-not [string]::IsNullOrWhiteSpace($explicit)) {
        $absolute = [IO.Path]::GetFullPath($explicit.Trim('"'))
        if (-not (Test-Path -LiteralPath $absolute -PathType Container)) {
            throw "Katalog profilu nie istnieje: $absolute"
        }
        return $absolute
    }
    $bases = @()
    if ($env:LOCALAPPDATA) { $bases += (Join-Path $env:LOCALAPPDATA 'Mudlet\profiles') }
    if ($env:USERPROFILE) { $bases += (Join-Path $env:USERPROFILE '.config\mudlet\profiles') }
    $candidates = @()
    foreach ($base in $bases) {
        if (Test-Path -LiteralPath $base -PathType Container) {
            $candidates += @(Get-ChildItem -LiteralPath $base -Directory | Select-Object -ExpandProperty FullName)
        }
    }
    $candidates = @($candidates | Select-Object -Unique)
    if ($candidates.Count -eq 1) { return $candidates[0] }
    if ($candidates.Count -gt 1) {
        Say 'Znalezione profile Mudleta:'
        for ($i = 0; $i -lt $candidates.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $candidates[$i])
        }
        $choice = Read-Host 'Wybierz numer profilu'
        $index = 0
        if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $candidates.Count) {
            throw 'Nieprawidlowy wybor profilu.'
        }
        return $candidates[$index - 1]
    }
    Say 'Nie wykryto automatycznie profilu Mudleta.'
    Say 'Odczytaj katalog w Mudlecie komenda: lua getMudletHomeDir()'
    $typed = Read-Host 'Wklej pelna sciezke katalogu profilu'
    if ([string]::IsNullOrWhiteSpace($typed)) { throw 'Nie podano katalogu profilu.' }
    return Resolve-Profile $typed
}

try {
    Say ("Instalacja zrodla: " + $Source)
    if ($Source -eq 'GitHub') {
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            throw "GitHub CLI (gh) jest wymagany do aktualizacji prywatnej paczki. Zainstaluj gh i uruchom gh auth login."
        }
        & gh auth status 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Brak autoryzacji GitHub. Uruchom: gh auth login' }
    }
    $manifestBytes = Get-SourceFile 'manifest.json'
    $manifest = [Text.Encoding]::UTF8.GetString($manifestBytes) | ConvertFrom-Json
    if ($null -eq $manifest -or $manifest.schema -ne 1 -or $manifest.name -ne 'ChimeraXP' -or
        [string]::IsNullOrWhiteSpace([string]$manifest.version) -or $manifest.files.Count -ne 1) {
        throw 'Niepoprawny manifest ChimeraXP.'
    }
    $file = $manifest.files[0]
    if ($file.path -cne $onlyPluginFile -or [string]$file.sha256 -notmatch '^[a-f0-9]{64}$') {
        throw 'Manifest wskazuje na nieobslugiwany plik lub niepoprawny SHA-256.'
    }
    $data = Get-SourceFile $onlyPluginFile
    if ((Sha256 $data) -cne [string]$file.sha256) { throw 'Blad integralnosci SHA-256. Instalacja przerwana.' }
    $text = [Text.Encoding]::UTF8.GetString($data)
    if (-not $text.StartsWith($marker)) { throw 'Nie rozpoznano kodu wtyczki AutoExp 5.' }

    $profile = Resolve-Profile $ProfileDir
    $pluginDir = Join-Path $profile 'chimera_wtyczki\chimera_autoexp'
    $target = Join-Path $pluginDir 'init.lua'
    $stateDir = Join-Path $profile 'ChimeraXP'
    New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

    $unchanged = $false
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        $existing = [IO.File]::ReadAllBytes($target)
        $existingText = [Text.Encoding]::UTF8.GetString($existing)
        if (-not $existingText.StartsWith($marker)) {
            throw "Nie nadpisuje nieznanej wtyczki: $target"
        }
        $unchanged = (Sha256 $existing) -ceq [string]$file.sha256
    }
    if ($unchanged) {
        Say ("Wtyczka jest juz aktualna (" + $manifest.version + ").")
    } else {
        $temp = Join-Path $pluginDir ('init.lua.tmp-' + [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllBytes($temp, $data)
        $backup = $null
        try {
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                $backupDir = Join-Path $stateDir 'backups'
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                $backup = Join-Path $backupDir ('init-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.lua')
                [IO.File]::Move($target, $backup)
            }
            [IO.File]::Move($temp, $target)
        } catch {
            if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force }
            if ($backup -and (Test-Path -LiteralPath $backup -PathType Leaf) -and
                -not (Test-Path -LiteralPath $target -PathType Leaf)) { [IO.File]::Move($backup, $target) }
            throw
        }
        Say ('Zainstalowano wersje ' + $manifest.version + '.')
        if ($backup) { Say ('Kopia poprzedniego kodu: ' + $backup) }
    }
    [IO.File]::WriteAllText((Join-Path $stateDir 'VERSION'), [string]$manifest.version + "`n", (New-Object Text.UTF8Encoding($false)))
    if ($Source -eq 'Local' -and $PSCommandPath -ne (Join-Path $stateDir 'ChimeraXP.ps1')) {
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $stateDir 'ChimeraXP.ps1') -Force
    }
    Say ('Profil: ' + $profile)
    Say 'W Mudlecie wylacz STARY pakiet EXP (XML), aby nie dublowac aliasow.'
    Say 'Nastepnie wykonaj /przeladuj, /wtyczki i /exp test.'
    Say 'Kolejna aktualizacja z prywatnego repo: .\update.cmd lub PowerShell -File ChimeraXP.ps1 -Source GitHub'
} catch {
    Write-Host ('[ChimeraXP] BLAD: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}