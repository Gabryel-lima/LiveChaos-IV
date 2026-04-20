# LiveChaos-IV — TODO

Roadmap de melhorias e funcionalidades a implementar.
Marque com `[x]` quando concluído.

---

## 🔴 Bugs / Bloqueantes

- [x] **`mono-complete` não instalado** — `make build` falha no Linux sem Mono. ✅ **Resolvido.**
  - Makefile agora auto-detecta `msbuild`, `xbuild` e `dotnet msbuild`.
  - Solução para o usuário: `sudo apt install mono-complete` (Ubuntu/Debian) ou `sudo pacman -S mono` (Arch).

- [ ] **`twitchio` v3 quebrou a API** — A versão 3.x do twitchio alterou a interface de `Bot`.
  - O `chaos_bot.py` usa a API do twitchio v2 (`twitchio_commands.Bot`, `event_message`).
  - `bot/requirements.txt` já tem `twitchio>=2.6.0` mas **falta o limite superior `<3.0`**.
  - Solução pendente: adicionar `twitchio>=2.6.0,<3.0` no `requirements.txt` **ou** migrar para a API v3.

- [ ] **`_pending` guarda apenas 1 efeito** — Se dois efeitos chegarem no mesmo tick o segundo sobrescreve o primeiro.
  - Solução: trocar `_pending: string` por uma `Queue<string>` e despachar um por tick.

---

## 🟡 Compilação Windows

### Status atual
O `.csproj` já está configurado para compilar com MSBuild nativo no Windows:
- Target: `.NET Framework 4.5` (compatível com GTA IV / IV-SDK .NET)
- Platform: `x86` (Release) — necessário para o ScriptHookDotNet
- OutputPath Release: `..\scripts\` — saída direta na pasta correta

### Passos para compilar no Windows
1. Instale **Visual Studio 2022** (Community gratuito) com workload `.NET desktop development` **ou**
   instale apenas o [Build Tools for Visual Studio](https://aka.ms/vs/17/release/vs_BuildTools.exe).
2. Abra o **Developer Command Prompt** e rode:
   ```bat
   cd ChaosScript
   msbuild ChaosScript.csproj /p:Configuration=Release /p:Platform=x86
   ```
3. O arquivo `scripts\LiveChaos.net.dll` será gerado automaticamente.
4. Copie `scripts\LiveChaos.net.dll` para `<GTAIV>\scripts\`.

### Automação (CI/CD GitHub Actions)
- [x] Adicionar workflow `.github/workflows/release.yml` que compila no Windows runner e faz upload do artifact `LiveChaos.net.dll`. ✅ **Resolvido.**
  - CI em push para `main` e PRs; GitHub Release com DLLs em tags `v*.*.*`.

---

## 🟢 Menu In-Game

> Prioridade alta — permite ao streamer ativar/desativar efeitos e configurar o mod sem sair do jogo.

### Design proposto
Menu ativado pela tecla `F8` (configurável). Navegação com `↑ ↓` e confirmação com `Enter`. Tecla `Backspace` / `F8` fecha.

```
┌─────────────────────────────┐
│      LiveChaos-IV  v1.0     │
├─────────────────────────────┤
│  [ON]  Mod ativo            │
│  [ON]  Turbo NPC            │
│  [30s] Duração da votação   │
│  [3]   Opções por rodada    │
├─────────────────────────────┤
│  Efeitos habilitados:       │
│   ✔ turbo                   │
│   ✔ explode_player          │
│   ✔ elevate_peds            │
│   ✔ wanted_up               │
│   ✔ wanted_clear            │
│   ✔ heal_player             │
│   ✔ ragdoll_peds            │
│   ✔ explode_cars            │
│   ✔ give_weapon             │
├─────────────────────────────┤
│  [Testar efeito aleatório]  │
│  [Salvar configuração]      │
└─────────────────────────────┘
```

### Implementação (ChaosScript.cs)

- [ ] **Classe `ChaosMenu`** — responsável por desenhar e navegar no menu.
  - Usar `DRAW_RECT` + `PRINT_STRING_WITH_LITERAL_STRING_NOW` da API nativa para desenhar fundo e texto.
  - Alternativamente, usar `IVGame.ShowSubtitleMessage` para feedback rápido.
- [ ] **Tecla de atalho** — capturar `KeyDown` (evento do SDK) para abrir/fechar o menu.
- [ ] **Navegação** — estado de item selecionado, toggle de booleanos, ajuste de inteiros com `←/→`.
- [ ] **Arquivo de config** (`scripts/LiveChaos.ini`) — persistir preferências entre sessões.
  - Usar `System.IO.File` + `System.Configuration` ou parser INI manual simples.

### Itens do menu

| Item | Tipo | Valor padrão | Descrição |
|------|------|--------------|-----------|
| Mod ativo | Toggle | `true` | Liga/desliga recepção de efeitos |
| Turbo NPC | Toggle | `true` | Aplica turbo contínuo aos NPCs |
| Duração votação | Int (s) | `30` | Enviado ao bot via socket |
| Opções por rodada | Int | `3` | Sorteio de efeitos |
| Lista de efeitos | Checklist | todos ON | Quais efeitos entram no sorteio |
| Testar efeito | Ação | — | Dispara efeito aleatório imediatamente |
| Salvar config | Ação | — | Escreve `LiveChaos.ini` |

---

## 🟢 HUD / Overlay In-Game

- [ ] **Barra de progresso da votação** — timer visual no canto da tela mostrando tempo restante até o próximo efeito.
- [ ] **Notificação de efeito ativo** — mensagem tipo "Efeito: EXPLODE CARS!" aparecendo por ~3 segundos.
  - Usar `IVGame.ShowSubtitleMessage` ou `PRINT_HELP_FOREVER_NOWITH_NUMBER` nativos.
- [ ] **Placar de votos** — exibir as 3 opções da rodada com contagem de votos ao vivo (requer o bot enviar dados de votação além do efeito vencedor).

---

## 🟢 Novos Efeitos

- [ ] `spawn_tank` — Spawna um Rhino próximo ao player.
- [ ] `invert_controls` — Inverte os controles por 10 segundos (usando wrapper de input).
- [ ] `drunk_mode` — Aplica efeito de embriaguez ao player (`SET_PLAYER_DRUNKNESS`).
- [ ] `slow_motion` — Altera `SET_TIME_SCALE` para 0.5 por 5 segundos.
- [ ] `super_speed` — Aplica velocidade extrema ao player a pé.
- [ ] `random_teleport` — Teleporta o player para um waypoint aleatório no mapa.
- [ ] `weather_change` — Muda o clima aleatoriamente (neblina, chuva, tempestade).
- [ ] `remove_all_weapons` — Remove todas as armas do player.
- [ ] `full_armor` — Dá armadura máxima ao player.
- [ ] `spawn_peds_army` — Spawna 5 NPCs agressivos próximos.

---

## 🟢 Comunicação Bot ↔ Mod (melhorias de protocolo)

- [ ] **Protocolo bidirecional** — O mod envia dados de estado (posição do player, efeito ativo, tempo restante) ao bot para exibição no overlay do stream.
- [ ] **Heartbeat** — O bot envia `PING\n` a cada 5s; o mod responde `PONG\n`. Se o mod não responder em 15s, o bot avisa no chat.
- [ ] **Confirmação de efeito** — Após executar, o mod envia `OK:<effect>\n` ao bot para log/stats.
- [ ] **Configuração remota** — O bot pode enviar `CONFIG:vote_duration=60\n` para alterar parâmetros sem reiniciar o mod.

---

## 🟢 Bot Python (melhorias)

- [ ] **Dashboard web simples** — Flask/FastAPI servindo uma página com placar de votos ao vivo via WebSocket.
- [ ] **Cooldown por efeito** — Evitar que o mesmo efeito vença rodadas consecutivas.
- [ ] **Lista negra de efeitos** — Configurar via `.env` quais efeitos nunca entram no sorteio.
- [ ] **Kick/veto de usuário** — Ignorar votos de usuários banidos da lista.
- [ ] **Suporte a Kick.com** — Adicionar integração com o chat do Kick além de Twitch e YouTube.

---

## 🟢 Documentação

- [ ] Adicionar seção no README explicando como compilar no Windows com Visual Studio.
- [ ] Adicionar GIF/vídeo demonstrativo no README.
- [ ] Documentar o protocolo de socket (formato das mensagens, porta padrão).
- [ ] Criar `CONTRIBUTING.md` com guia para adicionar novos efeitos.

---

## 🔵 Qualidade / Testes

- [ ] Adicionar testes unitários para `VoteManager` (Python, `pytest`).
- [ ] Adicionar script `tools/test_socket.py` para simular o mod C# e testar o bot em isolamento.
- [ ] Adicionar script `tools/send_effect.py <efeito>` para injetar efeitos manualmente sem o bot.
- [ ] Validar que todos os handles `playerHandle` são válidos antes de chamar nativos (evita crash).

---

## Resumo de status dos comandos

| Comando | Status | Observação |
|---------|--------|------------|
| `make install-deps` | ✅ Funciona | Imprime o comando sudo para o usuário instalar mono/dotnet |
| `make check-tools-dl` | ✅ Funciona | Verifica curl + unzip (disponíveis) |
| `make check-tools-build` | ✅ Funciona | Falha com mensagem clara se nenhum compilador estiver instalado |
| `make setup` | ✅ Funciona | Baixa IV-SDK .NET 1.9.1 e copia DLLs para `scripts/` |
| `make build` | ✅ Funciona | Requer `mono-complete` instalado; auto-detecta `xbuild`/`msbuild`/`dotnet` |
| `make bot-setup` | ✅ Funciona | Cria venv em `bot/.venv` e instala todas as dependências |
| `make clean` | ✅ Funciona | Remove artefatos compilados |
| `make distclean` | ✅ Funciona | Remove libs também (corrigido permissão read-only) |

### Para compilar: instale o compilador .NET

```bash
# Ubuntu 24.04 — opção 1: Mono (recomendado para GTA IV mods)
sudo apt install -y mono-complete

# Ubuntu 24.04 — opção 2: .NET SDK 8 (alternativa moderna)
sudo apt install -y dotnet-sdk-8.0

# Depois compile:
make setup && make build
```

O Makefile auto-detecta qual está disponível (`msbuild` do Mono ou `dotnet msbuild` do .NET SDK).
