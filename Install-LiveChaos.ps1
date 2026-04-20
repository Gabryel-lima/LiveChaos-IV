#Requires -Version 5.1
<#
.SYNOPSIS
    Instala o mod LiveChaos-IV na pasta correta do GTA IV.

.DESCRIPTION
    Detecta automaticamente a instalação do GTA IV (Steam ou Rockstar Launcher),
    cria a pasta scripts/ se necessário e copia as DLLs do mod.

.PARAMETER GamePath
    Caminho manual para a pasta raiz do GTA IV (que contém GTAIV.exe).
    Se omitido, o script tenta detectar automaticamente.

.PARAMETER SourcePath
    Pasta de onde as DLLs serão copiadas.
    Padrão: .\scripts\ (relativo ao diretório do script).

.EXAMPLE
    # Detecção automática
    .\Install-LiveChaos.ps1

.EXAMPLE
    # Caminho manual
    .\Install-LiveChaos.ps1 -GamePath "D:\Games\GTAIV"

.NOTES
    POLITICA DE EXECUCAO — antes de rodar, execute uma vez no PowerShell como Administrador:
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    Isso permite scripts locais sem assinatura digital.
#>

[CmdletBinding()]
param(
    [string]$GamePath,
    [string]$SourcePath = (Join-Path $PSScriptRoot 'scripts')
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

# ── Resumo ────────────────────────────────────────────────────────────────────

Write-Host ''
if ($missing -eq 0) {
    Write-Host "==> Instalacao concluida! $copied DLL(s) copiada(s) para:" -ForegroundColor Green
    Write-Host "    $destination" -ForegroundColor Green
    Write-Host ''
    Write-Host 'Proximo passo: inicie o bot Python ANTES de abrir o GTA IV:'
    Write-Host '    python bot\chaos_bot.py'
} else {
    Write-Host "==> Parcialmente concluido: $copied copiada(s), $missing ausente(s)." -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Para gerar as DLLs ausentes, compile o projeto:'
    Write-Host '    No Visual Studio: Release | x86 -> Build Solution'
    Write-Host '    Ou baixe a versao pre-compilada em:'
    Write-Host '    https://github.com/Gabryel-lima/LiveChaos-IV/releases/latest'
}
