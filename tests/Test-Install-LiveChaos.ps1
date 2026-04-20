#Requires -Version 5.1
<#
.SYNOPSIS
    Testes para Install-LiveChaos.ps1 — simula um ambiente Windows sem GTA IV instalado,
    um com caminho padrão Steam e um com caminho manual.
#>

param(
    [string]$ScriptUnderTest = (Join-Path $PSScriptRoot 'Install-LiveChaos.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ────────────────────────────────────────────────────────────────────

$passed = 0
$failed = 0

function Assert([bool]$condition, [string]$label) {
    if ($condition) {
        Write-Host "  [PASS] $label" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [FAIL] $label" -ForegroundColor Red
        $script:failed++
    }
}

function New-TempDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $dir | Out-Null
    return $dir
}

# ── Fixture: cria um "repositório" local com as DLLs na pasta scripts\ ────────

$repoRoot = New-TempDir
$srcScripts = Join-Path $repoRoot 'scripts'
New-Item -ItemType Directory -Path $srcScripts | Out-Null

$dlls = @('LiveChaos.net.dll', 'IVSDKDotNetWrapper.dll', 'Newtonsoft.Json.dll')
foreach ($dll in $dlls) {
    [System.IO.File]::WriteAllText((Join-Path $srcScripts $dll), "FAKE_DLL_CONTENT_$dll")
}

# ── Fixture: cria um "GTA IV" falso ───────────────────────────────────────────

$fakeGameDir = New-TempDir
[System.IO.File]::WriteAllText((Join-Path $fakeGameDir 'GTAIV.exe'), 'FAKE_EXE')

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ' LiveChaos-IV — Testes do instalador PowerShell'            -ForegroundColor Cyan
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

# ══════════════════════════════════════════════════════════════════════════════
# CENÁRIO 1 — Caminho manual correto, pasta scripts\ ainda não existe
# ══════════════════════════════════════════════════════════════════════════════
Write-Host '▶ Cenário 1: caminho manual, scripts\ ausente' -ForegroundColor Yellow

& $ScriptUnderTest -GamePath $fakeGameDir -SourcePath $srcScripts 2>&1 | Out-Null

$destScripts = Join-Path $fakeGameDir 'scripts'
Assert (Test-Path $destScripts) 'Pasta scripts\ criada no diretório do jogo'
foreach ($dll in $dlls) {
    $dest = Join-Path $destScripts $dll
    Assert (Test-Path $dest) "DLL copiada: $dll"
    Assert ([System.IO.File]::ReadAllText($dest) -eq "FAKE_DLL_CONTENT_$dll") "Conteúdo correto: $dll"
}
Write-Host ''

# ══════════════════════════════════════════════════════════════════════════════
# CENÁRIO 2 — Re-execução (scripts\ já existe, DLLs atualizadas)
# ══════════════════════════════════════════════════════════════════════════════
Write-Host '▶ Cenário 2: re-execução — atualiza DLLs existentes' -ForegroundColor Yellow

# Modifica o conteúdo das DLLs de origem para simular uma nova versão
foreach ($dll in $dlls) {
    [System.IO.File]::WriteAllText((Join-Path $srcScripts $dll), "UPDATED_DLL_CONTENT_$dll")
}

& $ScriptUnderTest -GamePath $fakeGameDir -SourcePath $srcScripts 2>&1 | Out-Null

foreach ($dll in $dlls) {
    $dest = Join-Path $destScripts $dll
    Assert ([System.IO.File]::ReadAllText($dest) -eq "UPDATED_DLL_CONTENT_$dll") "DLL atualizada: $dll"
}
Write-Host ''

# ══════════════════════════════════════════════════════════════════════════════
# CENÁRIO 3 — SourcePath inválido: script deve falhar com mensagem clara
# ══════════════════════════════════════════════════════════════════════════════
Write-Host '▶ Cenário 3: SourcePath inválido — deve emitir erro' -ForegroundColor Yellow

$errored = $false
try {
    & $ScriptUnderTest -GamePath $fakeGameDir -SourcePath '/caminho/inexistente' 2>&1 | Out-Null
} catch {
    $errored = $true
}
Assert $errored 'Erro emitido quando SourcePath não existe'
Write-Host ''

# ══════════════════════════════════════════════════════════════════════════════
# CENÁRIO 4 — GamePath sem GTAIV.exe: script deve falhar com mensagem clara
# ══════════════════════════════════════════════════════════════════════════════
Write-Host '▶ Cenário 4: GamePath sem GTAIV.exe — deve emitir erro' -ForegroundColor Yellow

$emptyDir = New-TempDir
$errored2 = $false
try {
    & $ScriptUnderTest -GamePath $emptyDir -SourcePath $srcScripts 2>&1 | Out-Null
} catch {
    $errored2 = $true
}
Assert $errored2 'Erro emitido quando GTAIV.exe não está no GamePath'
Write-Host ''

# ══════════════════════════════════════════════════════════════════════════════
# CENÁRIO 5 — DLL de origem ausente: script continua, avisa mas não trava
# ══════════════════════════════════════════════════════════════════════════════
Write-Host '▶ Cenário 5: uma DLL ausente na source — instalação parcial sem falha' -ForegroundColor Yellow

$partialSrc = New-TempDir
[System.IO.File]::WriteAllText((Join-Path $partialSrc 'LiveChaos.net.dll'), 'PARTIAL')
# IVSDKDotNetWrapper.dll e Newtonsoft.Json.dll deliberadamente ausentes

$fakeGame2 = New-TempDir
[System.IO.File]::WriteAllText((Join-Path $fakeGame2 'GTAIV.exe'), 'FAKE')

$output = & $ScriptUnderTest -GamePath $fakeGame2 -SourcePath $partialSrc *>&1
$hasPartial = Test-Path (Join-Path $fakeGame2 'scripts\LiveChaos.net.dll')
$warnedMissing = (@($output | Where-Object { $_ -match 'AUSENTE|ausente|missing' })).Count -gt 0

Assert $hasPartial    'LiveChaos.net.dll foi copiado mesmo com DLLs ausentes'
Assert $warnedMissing 'Aviso de DLLs ausentes emitido'
Write-Host ''

# ══════════════════════════════════════════════════════════════════════════════
# Resultado final
# ══════════════════════════════════════════════════════════════════════════════
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
$total = $passed + $failed
if ($failed -eq 0) {
    Write-Host "  RESULTADO: $passed/$total testes passaram" -ForegroundColor Green
} else {
    Write-Host "  RESULTADO: $passed/$total passaram, $failed falharam" -ForegroundColor Red
}
Write-Host '════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

# ── Limpeza ───────────────────────────────────────────────────────────────────
Remove-Item -Recurse -Force $repoRoot, $fakeGameDir, $emptyDir, $partialSrc, $fakeGame2 -ErrorAction SilentlyContinue

if ($failed -gt 0) { exit 1 }
