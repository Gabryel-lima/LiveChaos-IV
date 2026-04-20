# LiveChaos-IV

Um **mod de caos interativo** para **GTA IV** controlado pela audiência da sua live no Twitch e/ou YouTube.

Os espectadores votam no chat (digitando `1`, `2` ou `3`) para escolher qual efeito será ativado no jogo a cada rodada.

---

## Como Funciona

```
Chat do Twitch ──┐
                 ├──► chaos_bot.py (servidor TCP Python)  ──:9999──►  ChaosScript.dll (mod GTA IV)
Chat do YouTube ─┘         │                                                   │
                            └── contabiliza votos a cada N segundos            └── aplica o efeito no jogo
```

O bot Python funciona como um **servidor TCP**. O mod C# do GTA IV conecta-se como cliente na inicialização, e o bot envia o nome do efeito vencedor como uma string terminada em newline.

---

## Efeitos

| Voto | ID do Efeito      | O que acontece                                        |
|------|-------------------|-------------------------------------------------------|
| —    | `turbo`           | Acelera todos os veículos de NPCs próximos ao jogador |
| —    | `explode_player`  | Explode o jogador                                     |
| —    | `elevate_peds`    | Lança o jogador e pedestres próximos para o ar        |
| —    | `wanted_up`       | Aumenta o nível de procurado em 1 (máx. 6)            |
| —    | `wanted_clear`    | Zera o nível de procurado                             |
| —    | `heal_player`     | Cura completa                                         |
| —    | `ragdoll_peds`    | Faz pedestres próximos entrarem em ragdoll            |
| —    | `explode_cars`    | Explode todos os carros de NPCs próximos              |
| —    | `give_weapon`     | Dá uma arma aleatória (escopeta/M4/sniper/RPG)        |

A cada rodada, 3 efeitos aleatórios são sorteados e os espectadores votam. Após `VOTE_DURATION` segundos, o vencedor é enviado ao jogo.

---

## Pré-requisitos

| Componente | Versão | Observações |
|------------|--------|-------------|
| GTA IV (PC) | qualquer | Steam / Rockstar Launcher (Complete Edition recomendado) |
| [ScriptHook](https://gtaforums.com/topic/945746-iv-sdk-net/) | — | Necessário para carregar ASIs |
| [IV-SDK .NET](https://github.com/ClonkAndre/IV-SDK-DotNet/releases) | ≥ 1.9.1 | Carregador de mods gerenciado |
| Python | ≥ 3.9 | Para o bot |
| Runtime .NET 4.5 | nativo | Já vem instalado no Windows |
| **Apenas build no Linux** → Mono | ≥ 6.0 | `sudo apt install mono-complete` |

---

## Download sem compilar (Windows)

Se não quiser compilar o projeto, baixe a DLL mais recente diretamente na aba **[Releases](https://github.com/Gabryel-lima/LiveChaos-IV/releases/latest)** e siga a seção [Instalação Automática no Windows (PowerShell)](#instala%C3%A7%C3%A3o-autom%C3%A1tica-no-windows--powershell) abaixo.

---

## Início Rápido

### 1 — Clonar

```bash
git clone https://github.com/Gabryel-lima/LiveChaos-IV.git
cd LiveChaos-IV
```

### 2 — Compilar o mod do GTA IV

**Linux / macOS:**

```bash
# Primeira vez: baixa o IV-SDK .NET e copia as DLLs de referência
make setup

# Compila o ChaosScript.dll em scripts/
make build
```

**Windows (Visual Studio 2019+):**

Abra `LiveChaos-IV.sln`, defina a configuração como **Release | x86** e compile.  
A DLL será gerada em `scripts/`.

> **Requer Mono** no Linux: `sudo apt install mono-complete` ou `sudo dotnet-sdk install mono`. Alternativamente, compile no Windows com Visual Studio.

### 3 — Configurar o bot

```bash
cp .env.example .env
# Edite o .env com seu token OAuth do Twitch e/ou chave da API do YouTube
```

### 4 — Instalar dependências Python

```bash
make bot-setup
# ou: pip install -r bot/requirements.txt
```

### 5 — Instalar o mod no GTA IV

**Windows (automático):** execute o script PowerShell incluído no repositório:

```powershell
# Habilite a política de execução uma vez (se ainda não fez):
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Instale o mod (detecção automática do GTA IV):
.\Install-LiveChaos.ps1
```

Consulte a seção **[Instalação Automática no Windows (PowerShell)](#instala%C3%A7%C3%A3o-autom%C3%A1tica-no-windows--powershell)** para mais detalhes, ou **[Guia de Instalação no GTA IV](#guia-de-instalação-no-gta-iv)** para instalação manual.

> A pasta de configuração `IVSDKDotNet/` será criada automaticamente pelo IV-SDK .NET na primeira execução.

### 6 — Executar

Inicie o bot Python **antes** de abrir o GTA IV:

```bash
cd bot
python chaos_bot.py
```

Depois, abra o GTA IV. O mod se conecta a `127.0.0.1:9999` automaticamente.

---

## Configuração

Todas as configurações ficam no `.env` (copie de `.env.example`):

```env
# Twitch (https://twitchapps.com/tmi/ para o token OAuth)
TWITCH_ENABLED=true
TWITCH_TOKEN=oauth:xxxxxxxxxxxxxxxxxxxxxxxx
TWITCH_CHANNEL=seu_canal

# YouTube (opcional — requer chave da YouTube Data API v3)
YOUTUBE_ENABLED=false
YOUTUBE_API_KEY=AIza...
YOUTUBE_LIVE_ID=dQw4w9WgXcQ

# Sistema de votação
VOTE_DURATION=30        # segundos por rodada de votação
VOTE_OPTIONS=3          # quantos efeitos são oferecidos por rodada
```

---

## Adicionando Novos Efeitos

**1.** Adicione o ID do efeito em `ALL_EFFECTS` no `bot/chaos_bot.py`:

```python
ALL_EFFECTS = [
    ...
    "meu_novo_efeito",
]
```

**2.** Adicione um `case` em `ChaosScript/ChaosScript.cs`:

```csharp
case "meu_novo_efeito":
    // chamada de native do IV-SDK .NET aqui
    break;
```

**3.** Recompile com `make build` e copie o novo `LiveChaos.net.dll` para o GTA IV.

---

## Estrutura do Projeto

```
LiveChaos-IV/
├── .github/
│   └── workflows/
│       └── release.yml       ← CI/CD: compila no Windows e publica GitHub Release em tags v*.*.*
├── ChaosScript/
│   ├── ChaosScript.cs        ← mod do GTA IV (C#, IV-SDK .NET)
│   └── ChaosScript.csproj
├── bot/
│   ├── chaos_bot.py          ← servidor TCP Python + bot Twitch/YouTube
│   └── requirements.txt
├── tests/
│   └── Test-Install-LiveChaos.ps1  ← testes do script de instalação (14/14 ✅)
├── .env.example              ← modelo de configuração
├── Install-LiveChaos.ps1     ← instalador automático para Windows (PowerShell)
├── Makefile                  ← sistema de build (Linux/macOS + CLI Windows)
├── LiveChaos-IV.sln          ← solução Visual Studio (Windows)
└── README.md
```

> `scripts/` contém as DLLs pré-compiladas e é **rastreado pelo git** para facilitar a instalação. `libs/` é gerado por `make setup` e está no gitignore.

---

## Referência de Build

```bash
make setup      # Baixa o IV-SDK .NET v1.9.1, extrai as DLLs de referência
make build      # Compila o ChaosScript.dll (inclui setup)
make bot-setup  # pip install -r bot/requirements.txt
make clean      # Remove arquivos compilados
make distclean  # Remove arquivos compilados + libs baixadas
```

Sobrescrever a versão do IV-SDK:

```bash
make setup IVSDK_VER=1.9.2
```

---

## Instalação Automática no Windows — PowerShell

O script `Install-LiveChaos.ps1` detecta a instalação do GTA IV (Steam ou Rockstar Launcher) e copia as DLLs automaticamente.

### Pré-requisito: habilitar a política de execução

Por padrão, o Windows bloqueia scripts PowerShell não assinados. Execute **uma única vez** em um terminal PowerShell:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

> `RemoteSigned` permite rodar scripts locais sem assinatura digital, mas exige assinatura para scripts baixados da internet. Essa é a configuração recomendada para uso geral.

### Executar o instalador

```powershell
# Na raiz do repositório:
.\Install-LiveChaos.ps1
```

O script irá:
1. Pesquisar o GTA IV no registro do Steam e do Rockstar Launcher
2. Tentar caminhos padrão como fallback
3. Pedir o caminho manualmente se não encontrar
4. Criar `GTAIV\scripts\` se não existir
5. Copiar `LiveChaos.net.dll`, `IVSDKDotNetWrapper.dll` e `Newtonsoft.Json.dll`

```powershell
# Ou com caminho manual:
.\Install-LiveChaos.ps1 -GamePath "D:\Games\GTAIV"
```

---

## Guia de Instalação no GTA IV

Esta seção detalha onde cada arquivo deve ser colocado na pasta de instalação do GTA IV.  
A pasta raiz do GTA IV é normalmente:

| Plataforma | Caminho padrão |
|------------|----------------|
| Steam | `C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto IV\GTAIV\` |
| Rockstar Launcher | `C:\Program Files\Rockstar Games\Grand Theft Auto IV\` |

### Estrutura de pastas esperada

```
Grand Theft Auto IV/
└── GTAIV/                          ← pasta raiz do jogo
    ├── GTAIV.exe
    ├── dinput8.dll                  ← ASI Loader (instale manualmente)
    ├── IVSDKDotNet.asi              ← IV-SDK .NET loader (instale manualmente)
    ├── ScriptHookDotNet.asi         ← ScriptHook.NET (instale manualmente)
    └── scripts/                    ← crie esta pasta se não existir
        ├── LiveChaos.net.dll        ← ✅ este repositório (scripts/)
        ├── IVSDKDotNetWrapper.dll   ← ✅ este repositório (scripts/)
        ├── Newtonsoft.Json.dll      ← ✅ este repositório (scripts/)
        ├── ScriptHookDotNet.dll     ← ✅ este repositório (scripts/)
        └── ScriptHookDotNet_IVSDK.dll  ← ✅ este repositório (scripts/)
```

> **Itens marcados com ✅** já estão incluídos na pasta `scripts/` deste repositório — basta copiar.  
> **Itens sem marcação** devem ser baixados e instalados manualmente (veja os pré-requisitos).

### Passo a passo

**Passo 1 — Instalar os pré-requisitos na raiz do GTA IV**

Baixe e instale na pasta raiz (`GTAIV/`):

| Arquivo | Onde baixar |
|---------|-------------|
| `dinput8.dll` (ASI Loader) | [Silent's ASI Loader](https://gtaforums.com/topic/523982-relopensrcsa-asi-loader/) |
| `IVSDKDotNet.asi` | [IV-SDK .NET Releases](https://github.com/ClonkAndre/IV-SDK-DotNet/releases) |
| `ScriptHookDotNet.asi` | Incluído no pacote do IV-SDK .NET |

**Passo 2 — Copiar as DLLs do mod**

Copie **toda a pasta `scripts/`** deste repositório para dentro de `GTAIV/scripts/`:

```bash
# Exemplo (ajuste os caminhos)
cp -r scripts/* "/caminho/para/GTAIV/scripts/"
```

Ou no Windows Explorer: copie o conteúdo de `scripts\` deste projeto para `GTAIV\scripts\`.

**Passo 3 — Verificar a estrutura**

Após a instalação, `GTAIV/scripts/` deve conter pelo menos:

```
scripts/
├── LiveChaos.net.dll
├── IVSDKDotNetWrapper.dll
├── Newtonsoft.Json.dll
├── ScriptHookDotNet.dll
└── ScriptHookDotNet_IVSDK.dll
```

**Passo 4 — Iniciar o bot e o jogo**

```bash
cd bot
python chaos_bot.py   # inicie o bot ANTES de abrir o GTA IV
```

Abra o GTA IV. O mod conecta-se automaticamente ao bot em `127.0.0.1:9999`.

> **Dica:** Se o mod não carregar, verifique se o `IVSDKDotNet/` existe dentro de `GTAIV/scripts/`. O IV-SDK .NET o cria na primeira execução. Consulte `GTAIV/scripts/IVSDKDotNet/logs/` para mensagens de erro.

---

## Licença

Este projeto é distribuído sob a [Licença MIT](LICENSE).  
IV-SDK .NET é Copyright © ClonkAndre — consulte o [repositório deles](https://github.com/ClonkAndre/IV-SDK-DotNet) para informações de licença.
