# LiveChaos-IV — TODO

Roadmap de melhorias e funcionalidades a implementar.
Marque com `[x]` quando concluído.

---

## Concluídos

- [x] **`mono-complete` não instalado** — Makefile auto-detecta `msbuild`, `xbuild` e `dotnet msbuild`.
- [x] **`twitchio` v3 quebrou a API** — Bot Python aposentado; servidor Go usa `go-twitch-irc/v4` diretamente.
- [x] **`_pending` guarda apenas 1 efeito** — `PipeClient.cs` agora usa `Queue<string>`.
- [x] **CI release.yml .NET 4.5 targeting pack** — Retargetado para .NET 4.8 (disponível no runner windows-latest).
- [x] **Bot Python aposentado** — Substituído pelo servidor Go (`server/`). Twitch IRC e YouTube Live Chat agora em Go.
- [x] **Arquitetura 3 componentes** — Servidor Go + Mod C# + Overlay OBS Lua implementados.
- [x] **CI/CD release.yml** — Compila C# (ChaosScript + mod), Go server, e publica artefatos + GitHub Release.
- [x] **Overlay OBS** — Script Lua que faz polling HTTP e atualiza fontes de texto/timer no OBS.
- [x] **Named pipe IPC** — Comunicação tipada JSON entre servidor Go e mod C# via named pipe.
- [x] **HUD in-game** — Barra de timer com color lerp, nome do efeito e votos desenhados via natives.
- [x] **Install-LiveChaos.ps1 atualizado** — Agora copia mod DLLs + servidor Go + overlay OBS.

---

## 🔴 Bugs / Bloqueantes

- [ ] **Testar em GTA IV real** — Todos os efeitos compilam, mas precisam de validação in-game.
  - Verificar se os model hashes (`RHINO = 0x6D6F1DC8`, `PED_MODEL = 0xF6C4AA6`) funcionam corretamente.
  - Testar `APPLY_FORCE_TO_CAR` no `FLIP_CARS` (substituiu `SET_CAR_QUATERNION` que não existe).

---

## 🟡 Compilação Windows

### Status atual
- `.csproj` retargetados para `.NET Framework 4.8` (compatível com IV-SDK .NET, disponível no runner CI).
- Platform: `x86` (Release) — necessário para IV-SDK .NET.
- CI compila ambos `ChaosScript/` (legado) e `mod/` (novo) + servidor Go.

### Passos para compilar no Windows
1. Instale **Visual Studio 2022** (Community) com workload `.NET desktop development` **ou** [Build Tools](https://aka.ms/vs/17/release/vs_BuildTools.exe).
2. Abra o **Developer Command Prompt**:
   ```bat
   cd mod
   msbuild LiveChaos.csproj /p:Configuration=Release /p:Platform=x86
   ```
3. `scripts\LiveChaos.net.dll` será gerado.
4. Copie para `<GTAIV>\scripts\`.

---

## 🟢 Menu In-Game

> Prioridade alta — permite ao streamer ativar/desativar efeitos e configurar o mod sem sair do jogo.

- [ ] **Classe `ChaosMenu`** — desenhar e navegar menu com `DRAW_RECT` + texto nativo.
- [ ] **Tecla de atalho F8** — capturar `KeyDown` para abrir/fechar.
- [ ] **Navegação** — toggles, ajuste de inteiros com `←/→`.
- [ ] **Arquivo de config** (`scripts/LiveChaos.ini`) — persistir preferências.

---

## 🟢 Melhorias Futuras

- [ ] **Mais efeitos** — Ampliar o pool (weather change, teleport, spawn helicopters, etc.).
- [ ] **Pipe bidirecional** — Mod envia estado de volta para o servidor (saúde, posição, etc.).
- [ ] **Dashboard web** — Interface web para gerenciar efeitos em tempo real via WebSocket.
- [ ] **go.sum no repositório** — Executar `go mod tidy` e commitar `go.sum` para builds reproduzíveis.
- [ ] **Testes unitários Go** — Cobrir `vote/aggregator.go` e `state/state.go`.
- [ ] **Remover ChaosScript/ legado** — Após validação in-game do novo `mod/`, remover código antigo.
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
