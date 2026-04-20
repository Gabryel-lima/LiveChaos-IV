#Requires -Version 5.1
<#
.SYNOPSIS
    Instala o mod LiveChaos-IV na pasta correta do GTA IV e,
    opcionalmente, copia o overlay Lua para o OBS Studio.

.DESCRIPTION
    1. Detecta automaticamente a instalação do GTA IV (Steam ou Rockstar Launcher),
       cria a pasta scripts/ se necessário e copia as DLLs do mod.
    2. Se -OBSScriptsPath for fornecido (ou detectado), copia
       livechaos_overlay.lua e sources.json para o OBS.

.PARAMETER GamePath
    Caminho manual para a pasta raiz do GTA IV (que contém GTAIV.exe).
    Se omitido, o script tenta detectar automaticamente.

.PARAMETER SourcePath
    Pasta de onde as DLLs serão copiadas.
    Padrão: .\scripts\ (relativo ao diretório do script).

.PARAMETER OBSScriptsPath
    Caminho da pasta de scripts Lua do OBS Studio.
    Se omitido, tenta detectar automaticamente em %APPDATA%\obs-studio\scripts.
    Passe "none" para pular a instalação do overlay OBS.

.PARAMETER ServerBinPath
    Pasta de onde o binário do servidor Go será copiado.
    Padrão: .\bin\ (relativo ao diretório do script).

.EXAMPLE
    # Detecção automática completa
    .\Install-LiveChaos.ps1

.EXAMPLE
    # Caminho manual
    .\Install-LiveChaos.ps1 -GamePath "D:\Games\GTAIV"

.EXAMPLE
    # Com OBS manual
    .\Install-LiveChaos.ps1 -OBSScriptsPath "C:\Users\eu\AppData\Roaming\obs-studio\scripts"

.NOTES
    POLITICA DE EXECUCAO — antes de rodar, execute uma vez no PowerShell como Administrador:
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    Isso permite scripts locais sem assinatura digital.
#>

[CmdletBinding()]
param(
    [string]$GamePath,
    [string]$SourcePath = (Join-Path $PSScriptRoot 'scripts'),
    [string]$OBSScriptsPath,
    [string]$ServerBinPath = (Join-Path $PSScriptRoot 'bin')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# DLLs que serão copiadas para GTAIV\scripts\
$RequiredDLLs = @(
    'LiveChaos.net.dll',
    'IVSDKDotNetWrapper.dll',
    'Newtonsoft.Json.dll'
)

# ── Funções auxiliares ─────────────────────────────────────────────────────────

function Get-RegistryValue([string]$Key, [string]$Property) {
    try {
        return (Get-ItemProperty -Path $Key -Name $Property -ErrorAction Stop).$Property
    } catch {
        return $null
    }
}

function Find-GTAIVPath {
    $candidates = [System.Collections.Generic.List[string]]::new()

    # 1 — Registro do Steam (32-bit e 64-bit)
    foreach ($regKey in @(
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )) {
        $steamRoot = Get-RegistryValue $regKey 'SteamPath'
        if ($steamRoot) {
            $candidates.Add((Join-Path $steamRoot 'steamapps\common\Grand Theft Auto IV\GTAIV'))
            # Alguns usuários instalam em libraryfolders diferentes — tente as mais comuns
            $candidates.Add((Join-Path $steamRoot 'steamapps\common\Grand Theft Auto IV'))
        }
    }

    # 2 — Registro do Rockstar Launcher
    foreach ($regKey in @(
        'HKLM:\SOFTWARE\WOW6432Node\Rockstar Games\Grand Theft Auto IV',
        'HKLM:\SOFTWARE\Rockstar Games\Grand Theft Auto IV'
    )) {
        $installFolder = Get-RegistryValue $regKey 'InstallFolder'
        if ($installFolder) { $candidates.Add($installFolder) }
    }

    # 3 — Caminhos padrão (fallback)
    $candidates.AddRange([string[]]@(
        'C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto IV\GTAIV',
        'C:\Program Files\Steam\steamapps\common\Grand Theft Auto IV\GTAIV',
        'C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto IV',
        'C:\Program Files\Rockstar Games\Grand Theft Auto IV',
        'C:\Program Files (x86)\Rockstar Games\Grand Theft Auto IV'
    ))

    foreach ($path in $candidates) {
        if ($path -and (Test-Path (Join-Path $path 'GTAIV.exe'))) {
            return $path
        }
    }

    return $null
}

# ── Resolver caminho do jogo ───────────────────────────────────────────────────

if (-not $GamePath) {
    Write-Host '==> Procurando instalacao do GTA IV...' -ForegroundColor Cyan
    $GamePath = Find-GTAIVPath
}

if (-not $GamePath -or -not (Test-Path (Join-Path $GamePath 'GTAIV.exe'))) {
    Write-Warning 'Instalacao do GTA IV nao encontrada automaticamente.'
    $GamePath = Read-Host 'Digite o caminho completo da pasta do GTA IV (que contem GTAIV.exe)'
    $GamePath = $GamePath.Trim('"')

    if (-not (Test-Path (Join-Path $GamePath 'GTAIV.exe'))) {
        Write-Error "GTAIV.exe nao encontrado em: $GamePath"
        exit 1
    }
}

Write-Host "==> GTA IV encontrado em: $GamePath" -ForegroundColor Green

# ── Validar pasta de origem ────────────────────────────────────────────────────

if (-not (Test-Path $SourcePath)) {
    Write-Error (
        "Pasta de origem nao encontrada: $SourcePath`n" +
        "Execute o script a partir da raiz do repositorio, ou passe -SourcePath com o caminho correto."
    )
    exit 1
}

# ── Criar pasta scripts\ no jogo se necessario ────────────────────────────────

$destination = Join-Path $GamePath 'scripts'
if (-not (Test-Path $destination)) {
    Write-Host "==> Criando pasta: $destination" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $destination | Out-Null
}

# ── Copiar DLLs ───────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '==> Copiando DLLs...' -ForegroundColor Cyan

$copied  = 0
$missing = 0

foreach ($dll in $RequiredDLLs) {
    $src = Join-Path $SourcePath $dll
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $destination -Force
        Write-Host "  [OK]      $dll" -ForegroundColor Green
        $copied++
    } else {
        Write-Host "  [AUSENTE] $dll  (nao encontrado em $SourcePath)" -ForegroundColor Yellow
        $missing++
    }
}

# ── Resumo do mod ─────────────────────────────────────────────────────────────

Write-Host ''
if ($missing -eq 0) {
    Write-Host "==> Mod instalado! $copied DLL(s) copiada(s) para:" -ForegroundColor Green
    Write-Host "    $destination" -ForegroundColor Green
} else {
    Write-Host "==> Mod parcialmente instalado: $copied copiada(s), $missing ausente(s)." -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Para gerar as DLLs ausentes, compile o projeto:'
    Write-Host '    No Visual Studio: Release | x86 -> Build Solution'
    Write-Host '    Ou baixe a versao pre-compilada em:'
    Write-Host '    https://github.com/Gabryel-lima/LiveChaos-IV/releases/latest'
}

# ── Copiar servidor Go (se existir) ──────────────────────────────────────────

$serverExe = Join-Path $ServerBinPath 'livechaos-server.exe'
if (Test-Path $serverExe) {
    $serverDest = Join-Path $GamePath 'livechaos-server.exe'
    Copy-Item -Path $serverExe -Destination $serverDest -Force
    Write-Host "  [OK]      livechaos-server.exe -> $GamePath" -ForegroundColor Green

    # Copiar config.toml junto se existir
    $configSrc = Join-Path $PSScriptRoot 'server\config.toml'
    if (Test-Path $configSrc) {
        $configDest = Join-Path $GamePath 'config.toml'
        if (-not (Test-Path $configDest)) {
            Copy-Item -Path $configSrc -Destination $configDest
            Write-Host "  [OK]      config.toml copiado (edite com seus tokens)" -ForegroundColor Green
        } else {
            Write-Host "  [SKIP]    config.toml ja existe em $GamePath (nao sobrescrito)" -ForegroundColor Cyan
        }
    }
} else {
    Write-Host ''
    Write-Host '  [INFO]    livechaos-server.exe nao encontrado em bin\.' -ForegroundColor Cyan
    Write-Host '            Compile com: cd server && go build -o ..\bin\livechaos-server.exe .' -ForegroundColor Cyan
    Write-Host '            Ou baixe em: https://github.com/Gabryel-lima/LiveChaos-IV/releases/latest' -ForegroundColor Cyan
}

# ── Instalar overlay OBS (Lua) ────────────────────────────────────────────────

$obsSourceDir = Join-Path $PSScriptRoot 'obs'

if ($OBSScriptsPath -eq 'none') {
    Write-Host ''
    Write-Host '  [SKIP]    Overlay OBS pulado (-OBSScriptsPath "none")' -ForegroundColor Cyan
} else {
    # Auto-detectar pasta de scripts do OBS
    if (-not $OBSScriptsPath) {
        $obsDefault = Join-Path $env:APPDATA 'obs-studio'
        if (Test-Path $obsDefault) {
            $OBSScriptsPath = $obsDefault
        }
    }

    if ($OBSScriptsPath -and (Test-Path $OBSScriptsPath)) {
        Write-Host ''
        Write-Host '==> Instalando overlay OBS...' -ForegroundColor Cyan

        $obsFiles = @('livechaos_overlay.lua', 'sources.json')
        foreach ($f in $obsFiles) {
            $src = Join-Path $obsSourceDir $f
            if (Test-Path $src) {
                Copy-Item -Path $src -Destination $OBSScriptsPath -Force
                Write-Host "  [OK]      $f -> $OBSScriptsPath" -ForegroundColor Green
            } else {
                Write-Host "  [AUSENTE] $f nao encontrado em obs\" -ForegroundColor Yellow
            }
        }

        Write-Host ''
        Write-Host '  Para ativar no OBS:' -ForegroundColor Cyan
        Write-Host '    1. Abra OBS -> Ferramentas -> Scripts' -ForegroundColor Cyan
        Write-Host '    2. Clique "+" e selecione livechaos_overlay.lua' -ForegroundColor Cyan
        Write-Host '    3. Crie as fontes de texto: LC_Effect, LC_Phase, LC_Votes' -ForegroundColor Cyan
        Write-Host '    4. Crie barra de timer: LC_Timer_BG (fundo) + LC_Timer_Fill (preenchimento)' -ForegroundColor Cyan
    } else {
        Write-Host ''
        Write-Host '  [INFO]    OBS Studio nao detectado automaticamente.' -ForegroundColor Cyan
        Write-Host '            Para instalar o overlay, re-execute com:' -ForegroundColor Cyan
        Write-Host '            .\Install-LiveChaos.ps1 -OBSScriptsPath "C:\...\obs-studio"' -ForegroundColor Cyan
    }
}

# ── Instrucoes finais ─────────────────────────────────────────────────────────

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  Proximos passos:' -ForegroundColor Cyan
Write-Host '    1. Configure server\config.toml com seu canal Twitch/YouTube' -ForegroundColor Cyan
Write-Host '    2. Inicie o servidor Go ANTES de abrir o GTA IV:' -ForegroundColor Cyan
Write-Host '       set TWITCH_OAUTH=oauth:xxx && livechaos-server.exe' -ForegroundColor Cyan
Write-Host '    3. Abra o GTA IV — o mod conecta automaticamente ao servidor' -ForegroundColor Cyan
Write-Host '    4. (Opcional) Ative o overlay Lua no OBS' -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
