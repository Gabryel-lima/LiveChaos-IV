"""
LiveChaos-IV  |  bot/chaos_bot.py
==================================
Servidor socket TCP que:
  1. Escuta chat do Twitch via IRC (twitchio) ou YouTube Live Chat (polling)
  2. Recebe votos da audiência
  3. A cada VOTE_DURATION segundos envia o efeito vencedor para o GTA IV

Requisitos:
    pip install -r requirements.txt

Configuração:
    Copie .env.example → .env e preencha os valores antes de rodar.
    Para YouTube você precisa de uma API Key em:
    https://console.cloud.google.com/
"""

import asyncio
import os
import socket
import threading
import time
import random
from collections import Counter, defaultdict
from dotenv import load_dotenv

# Carrega variáveis do arquivo .env (ignora silenciosamente se não existir)
load_dotenv()

# ── CONFIG ────────────────────────────────────────────────────────────────────
TWITCH_ENABLED   = os.getenv("TWITCH_ENABLED",  "true").lower()  == "true"
YOUTUBE_ENABLED  = os.getenv("YOUTUBE_ENABLED", "false").lower() == "true"

TWITCH_TOKEN     = os.getenv("TWITCH_TOKEN",   "")
TWITCH_CHANNEL   = os.getenv("TWITCH_CHANNEL", "")

YOUTUBE_API_KEY  = os.getenv("YOUTUBE_API_KEY", "")
YOUTUBE_LIVE_ID  = os.getenv("YOUTUBE_LIVE_ID", "")

GTA_HOST         = os.getenv("GTA_HOST", "127.0.0.1")
GTA_PORT         = int(os.getenv("GTA_PORT",  "9999"))

VOTE_DURATION    = int(os.getenv("VOTE_DURATION", "30"))
VOTE_OPTIONS     = int(os.getenv("VOTE_OPTIONS",  "3"))

# Todos os efeitos disponíveis (devem bater com o switch em ChaosScript.cs)
ALL_EFFECTS = [
    "turbo",
    "explode_player",
    "elevate_peds",
    "wanted_up",
    "wanted_clear",
    "heal_player",
    "ragdoll_peds",
    "explode_cars",
    "give_weapon",
]
# ── FIM CONFIG ────────────────────────────────────────────────────────────────


# ── Comunicação com o GTA IV ──────────────────────────────────────────────────
class GTASocket:
    """Servidor TCP que o mod C# se conecta (mod = client, bot = server)."""

    def __init__(self, host: str, port: int):
        self.host  = host
        self.port  = port
        self._conn = None
        self._lock = threading.Lock()
        self._server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server.bind((host, port))
        self._server.listen(1)
        print(f"[GTA Socket] Aguardando conexão do mod em {host}:{port}...")

        accept_thread = threading.Thread(target=self._accept_loop, daemon=True)
        accept_thread.start()

    def _accept_loop(self):
        while True:
            conn, addr = self._server.accept()
            print(f"[GTA Socket] Mod conectado: {addr}")
            with self._lock:
                if self._conn:
                    try:
                        self._conn.close()
                    except Exception:
                        pass
                self._conn = conn

    def send_effect(self, effect: str):
        with self._lock:
            if self._conn is None:
                print(f"[GTA Socket] Sem conexão com o mod. Efeito '{effect}' descartado.")
                return
            try:
                self._conn.sendall((effect + "\n").encode("utf-8"))
                print(f"[GTA Socket] Efeito enviado: {effect}")
            except Exception as e:
                print(f"[GTA Socket] Erro ao enviar: {e}")
                self._conn = None


# ── Votação ───────────────────────────────────────────────────────────────────
class VoteManager:
    def __init__(self, gta: GTASocket):
        self.gta     = gta
        self.votes   = defaultdict(int)   # {"1": 10, "2": 3, "3": 7}
        self.options = []                 # efeitos da rodada atual
        self.voters  = set()              # um voto por usuário
        self._lock   = threading.Lock()
        self._running = True
        self._thread  = threading.Thread(target=self._vote_loop, daemon=True)
        self._thread.start()

    def _new_round(self):
        with self._lock:
            self.options = random.sample(ALL_EFFECTS, min(VOTE_OPTIONS, len(ALL_EFFECTS)))
            self.votes   = defaultdict(int)
            self.voters  = set()
        print("\n" + "="*50)
        print("NOVA RODADA DE VOTAÇÃO:")
        for i, eff in enumerate(self.options, 1):
            print(f"  Digite {i} → {eff}")
        print("="*50)

    def register_vote(self, user: str, msg: str):
        msg = msg.strip()
        if msg not in ("1", "2", "3"):
            return
        idx = int(msg) - 1
        with self._lock:
            if not self.options or idx >= len(self.options):
                return
            if user in self.voters:
                return   # já votou
            self.voters.add(user)
            self.votes[msg] += 1

    def _vote_loop(self):
        while self._running:
            self._new_round()
            time.sleep(VOTE_DURATION)

            with self._lock:
                if not self.votes:
                    print("[Voto] Nenhum voto recebido. Efeito aleatório.")
                    winner = random.choice(self.options) if self.options else None
                else:
                    winner_key = max(self.votes, key=lambda k: self.votes[k])
                    winner = self.options[int(winner_key) - 1]

            if winner:
                print(f"[Voto] Efeito vencedor: {winner}")
                self.gta.send_effect(winner)
            time.sleep(1)   # pausa breve antes da próxima rodada


# ── Twitch (twitchio) ─────────────────────────────────────────────────────────
def start_twitch_bot(vote_manager: VoteManager):
    try:
        import twitchio
        from twitchio.ext import commands as twitchio_commands

        class TwitchBot(twitchio_commands.Bot):
            def __init__(self):
                super().__init__(
                    token=TWITCH_TOKEN,
                    prefix="",
                    initial_channels=[TWITCH_CHANNEL],
                )
                self.vote = vote_manager

            async def event_message(self, message):
                if message.echo:
                    return
                self.vote.register_vote(message.author.name, message.content)

        bot = TwitchBot()
        print("[Twitch] Conectando...")
        bot.run()

    except ImportError:
        print("[Twitch] twitchio não instalado. Execute: pip install twitchio")
    except Exception as e:
        print(f"[Twitch] Erro: {e}")


# ── YouTube (polling) ─────────────────────────────────────────────────────────
def start_youtube_bot(vote_manager: VoteManager):
    try:
        from googleapiclient.discovery import build

        youtube = build("youtube", "v3", developerKey=YOUTUBE_API_KEY)

        def get_live_chat_id():
            r = youtube.videos().list(part="liveStreamingDetails", id=YOUTUBE_LIVE_ID).execute()
            return r["items"][0]["liveStreamingDetails"]["activeLiveChatId"]

        def poll(chat_id):
            page_token = None
            while True:
                params = dict(liveChatId=chat_id, part="snippet,authorDetails", maxResults=200)
                if page_token:
                    params["pageToken"] = page_token
                r = youtube.liveChatMessages().list(**params).execute()
                for item in r.get("items", []):
                    user = item["authorDetails"]["displayName"]
                    text = item["snippet"]["displayMessage"]
                    vote_manager.register_vote(user, text)
                page_token = r.get("nextPageToken")
                interval  = r.get("pollingIntervalMillis", 10000) / 1000
                time.sleep(interval)

        print("[YouTube] Obtendo Live Chat ID...")
        chat_id = get_live_chat_id()
        print(f"[YouTube] Chat ID: {chat_id}")
        poll(chat_id)

    except ImportError:
        print("[YouTube] google-api-python-client não instalado.")
        print("Execute: pip install google-api-python-client")
    except Exception as e:
        print(f"[YouTube] Erro: {e}")


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    gta = GTASocket(GTA_HOST, GTA_PORT)
    mgr = VoteManager(gta)

    threads = []

    if TWITCH_ENABLED:
        t = threading.Thread(target=start_twitch_bot, args=(mgr,), daemon=True)
        t.start()
        threads.append(t)

    if YOUTUBE_ENABLED:
        t = threading.Thread(target=start_youtube_bot, args=(mgr,), daemon=True)
        t.start()
        threads.append(t)

    if not threads:
        print("[AVISO] Nenhuma fonte de chat ativada. Defina TWITCH_ENABLED ou YOUTUBE_ENABLED.")

    # Mantém o processo vivo
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nBot encerrado.")
