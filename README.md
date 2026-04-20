# LiveChaos-IV

Um **mod de caos interativo** para **GTA IV** controlado pela audiência da sua live no **Twitch** e/ou **YouTube**.

Os espectadores votam no chat com `!vote EFEITO` para escolher qual efeito será ativado no jogo a cada rodada.

---

## Arquitetura

O sistema é composto por **3 componentes** independentes que se comunicam em tempo real:

```
Chat do Twitch ──┐                                                   ┌── mod C# (GTA IV)
                 ├──► Servidor Go ──── named pipe (JSON) ───────────►│    PipeClient → EffectRunner → HUD
Chat do YouTube ─┘    │  (Twitch IRC + YouTube API)                  └── aplica efeitos no jogo
                      │
                      └──── WebSocket :9001/ws ─────────────────────►  OBS overlay (Lua)
                      └──── HTTP GET  :9001/state                       (texto + barra de timer)
```

| Componente | Linguagem | Responsabilidade |
|---|---|---|
| **Servidor** (`server/`) | Go 1.22+ | Twitch IRC, YouTube polling, votação, timer, IPC (named pipe) e WebSocket para OBS |
| **Mod** (`mod/`) | C# .NET 4.8 | Recebe efeitos via named pipe, executa natives do GTA IV, desenha HUD in-game |
| **Overlay** (`obs/`) | Lua 5.1 | Atualiza fontes de texto/barra de timer no OBS via polling HTTP |

> O bot Python (`bot/chaos_bot.py`) foi **aposentado** — o servidor Go o substituiu integralmente.

---

## Efeitos

| ID | O que acontece |
|---|---|
| `SPAWN_TANKS` | Spawna um Rhino (tanque) perto do jogador |
| `BLOW_ALL` | Explode todos os veículos de NPCs próximos |
| `RANDOM_PED` | Spawna um ped hostil perto do jogador |
| `WANTED_MAX` | Define procurado no máximo (6 estrelas) |
| `FLIP_CARS` | Lança veículos próximos para o ar |
| `EXPLODE_PLAYER` | Explode o jogador |
| `ELEVATE_PEDS` | Lança o jogador e peds para o alto |
| `WANTED_UP` | Aumenta procurado em 1 estrela |
| `WANTED_CLEAR` | Zera o nível de procurado |
| `HEAL_PLAYER` | Cura completa |
| `RAGDOLL_PEDS` | Faz peds próximos entrarem em ragdoll |
| `EXPLODE_CARS` | Explode carros de NPCs próximos |
| `GIVE_WEAPON` | Dá uma arma aleatória (shotgun/M4/sniper/RPG) |

A cada rodada, os espectadores votam com `!vote EFEITO_ID`. Após o tempo de votação (padrão 30s), o efeito mais votado é ativado.

---

## Pré-requisitos

| Componente | Versão | Observações |
|---|---|---|
| GTA IV (PC) | qualquer | Steam / Rockstar Launcher (Complete Edition recomendado) |
| [IV-SDK .NET](https://github.com/ClonkAndre/IV-SDK-DotNet/releases) | ≥ 1.9.1 | Carregador de mods gerenciado |
| Go | ≥ 1.22 | Para compilar o servidor |
| Runtime .NET 4.8 | nativo | Já vem instalado no Windows 10+ |
| **Apenas build Linux** → Mono | ≥ 6.0 | `sudo apt install mono-complete` |
| OBS Studio | qualquer | Opcional — para o overlay de stream |

---

## Download sem compilar (Windows)

Baixe os artefatos pré-compilados na aba **[Releases](https://github.com/Gabryel-lima/LiveChaos-IV/releases/latest)**:
- `LiveChaos.net.dll` + DLLs de referência — mod para GTA IV
- `livechaos-server.exe` — servidor Go
- `livechaos_overlay.lua` + `sources.json` — overlay OBS

---

## Início Rápido

### 1 — Clonar

```bash
git clone https://github.com/Gabryel-lima/LiveChaos-IV.git
cd LiveChaos-IV
```

### 2 — Compilar o mod C# (GTA IV)

**Linux / macOS:**

```bash
make setup      # baixa IV-SDK .NET e copia DLLs de referência
make mod-build  # compila mod/LiveChaos.net.dll em scripts/
```

**Windows (Visual Studio 2022):**

Abra `LiveChaos-IV.sln`, defina **Release | x86** e compile. A DLL será gerada em `scripts/`.

### 3 — Compilar o servidor Go

```bash
make server-build  # gera bin/livechaos-server(.exe)
```

Ou diretamente:

```bash
cd server && go build -o ../bin/livechaos-server .
```

### 4 — Configurar

Edite `server/config.toml`:

```toml
[twitch]
channel = "seu_canal"
# oauth via variável de ambiente TWITCH_OAUTH

[youtube]
enabled = false
# live_video_id = "xxxx"
# api_key via variável de ambiente YOUTUBE_API_KEY

[timer]
vote_duration_s    = 30
cooldown_duration_s = 5

[effects]
pool = ["SPAWN_TANKS", "BLOW_ALL", "RANDOM_PED", ...]
```

### 5 — Instalar no GTA IV

**Windows (automático):**

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser  # uma vez
.\Install-LiveChaos.ps1
```

O script detecta o GTA IV automaticamente, copia as DLLs, o servidor Go e o overlay OBS.

**Manual:** copie `scripts/LiveChaos.net.dll`, `IVSDKDotNetWrapper.dll` e `Newtonsoft.Json.dll` para `<GTAIV>\scripts\`.

### 6 — Executar

```bash
# 1. Inicie o servidor Go ANTES do GTA IV:
TWITCH_OAUTH=oauth:xxx bin/livechaos-server

# 2. Abra o GTA IV — o mod conecta automaticamente via named pipe

# 3. (Opcional) Ative o overlay no OBS:
#    Ferramentas → Scripts → + → livechaos_overlay.lua
```

---

## Overlay OBS

O script Lua `obs/livechaos_overlay.lua` faz polling a `http://localhost:9001/state` e atualiza fontes de texto no OBS.

### Fontes necessárias no OBS

| Fonte | Tipo | Conteúdo |
|---|---|---|
| `LC_Effect` | Texto (GDI+) | Nome do efeito ativo |
| `LC_Phase` | Texto (GDI+) | Fase atual (voting/active/cooldown) |
| `LC_Votes` | Texto (GDI+) | Contagem de votos |
| `LC_Timer_BG` | Fonte de cor | Fundo da barra de timer |
| `LC_Timer_Fill` | Fonte de cor | Preenchimento da barra de timer |

### Ativar

1. Crie as fontes acima na sua cena OBS
2. `Ferramentas → Scripts → +` → selecione `livechaos_overlay.lua`
3. Configure o endereço do servidor se necessário (padrão: `http://localhost:9001/state`)

---

## Adicionando Novos Efeitos

**1.** Adicione o ID em `server/config.toml`:

```toml
[effects]
pool = [..., "MEU_NOVO_EFEITO"]
```

**2.** Adicione a constante em `mod/Effects.cs`:

```csharp
public const string MeuNovoEfeito = "MEU_NOVO_EFEITO";
```

**3.** Adicione o `case` em `mod/EffectRunner.cs`:

```csharp
case Effects.MeuNovoEfeito:
    // chamada de native do IV-SDK .NET
    break;
```

**4.** Recompile: `make mod-build` e copie a DLL para `<GTAIV>\scripts\`.

---

## Estrutura do Projeto

```
LiveChaos-IV/
├── .github/workflows/
│   └── release.yml            ← CI: compila C# + Go, publica GitHub Release em tags v*.*.*
├── server/                    ← Servidor Go (Twitch IRC + YouTube + votação + IPC + WebSocket)
│   ├── main.go                   ponto de entrada, config, wiring
│   ├── config.toml               configuração (canais, timer, efeitos)
│   ├── bot/
│   │   ├── twitch.go             cliente Twitch IRC
│   │   └── youtube.go            polling YouTube Live Chat
│   ├── vote/
│   │   └── aggregator.go         contagem de votos, ciclo de timer
│   ├── ipc/
│   │   ├── pipe.go               servidor named pipe (JSON)
│   │   ├── listener_windows.go   listener Windows (go-winio)
│   │   └── listener_other.go     stub Linux/macOS
│   ├── overlay/
│   │   └── ws.go                 WebSocket + HTTP /state
│   └── state/
│       └── state.go              State struct + Bus broadcaster
├── mod/                       ← Mod C# do GTA IV (IV-SDK .NET)
│   ├── LiveChaos.cs              ponto de entrada (Script)
│   ├── PipeClient.cs             cliente named pipe (background thread)
│   ├── HUD.cs                    overlay in-game (timer, efeito, votos)
│   ├── EffectRunner.cs           execução dos 13 efeitos
│   ├── Effects.cs                constantes de IDs
│   └── LiveChaos.csproj
├── obs/                       ← Overlay OBS (Lua)
│   ├── livechaos_overlay.lua     polling HTTP + atualização de fontes
│   └── sources.json              nomes das fontes OBS
├── ChaosScript/               ← Mod legado (monolítico, mantido para referência)
│   ├── ChaosScript.cs
│   └── ChaosScript.csproj
├── bot/                       ← Bot Python (DEPRECADO — substituído pelo servidor Go)
│   └── chaos_bot.py
├── tests/
│   └── Test-Install-LiveChaos.ps1
├── Install-LiveChaos.ps1      ← Instalador automático (mod + servidor + OBS overlay)
├── Makefile                   ← Build system (setup, build, mod-build, server-build, clean)
├── LiveChaos-IV.sln
└── README.md
```

---

## Referência de Build

```bash
make setup          # Baixa IV-SDK .NET v1.9.1, extrai DLLs de referência
make build          # Compila ChaosScript.dll (legado)
make mod-build      # Compila mod/LiveChaos.net.dll (novo)
make server-build   # Compila bin/livechaos-server
make server-run     # Executa o servidor Go em modo dev
make clean          # Remove arquivos compilados
make distclean      # Remove compilados + libs baixadas
```

---

## Instalação Automática no Windows — PowerShell

O script `Install-LiveChaos.ps1` detecta a instalação do GTA IV (Steam ou Rockstar Launcher), copia as DLLs, o servidor Go e opcionalmente instala o overlay no OBS.

```powershell
# Detecção automática completa:
.\Install-LiveChaos.ps1

# Caminho manual do GTA IV:
.\Install-LiveChaos.ps1 -GamePath "D:\Games\GTAIV"

# Com OBS manual:
.\Install-LiveChaos.ps1 -OBSScriptsPath "C:\Users\eu\AppData\Roaming\obs-studio"

# Pular instalação OBS:
.\Install-LiveChaos.ps1 -OBSScriptsPath "none"
```

O script copia:
1. `LiveChaos.net.dll`, `IVSDKDotNetWrapper.dll`, `Newtonsoft.Json.dll` → `<GTAIV>\scripts\`
2. `livechaos-server.exe` + `config.toml` → `<GTAIV>\`
3. `livechaos_overlay.lua` + `sources.json` → `<OBS>\` (se detectado)

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
