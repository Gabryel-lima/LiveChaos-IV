# ─────────────────────────────────────────────────────────────────────────────
#  LiveChaos-IV — Sistema de Build
#
#  Compilação multiplataforma sem precisar do Visual Studio.
#  Testado em: Ubuntu 22.04+, Debian 12+, Arch Linux
#
#  Requisitos de download (curl + unzip):
#    sudo apt install curl unzip                # Ubuntu/Debian
#
#  Requisitos de compilação (escolha UM):
#    sudo apt install mono-complete             # Ubuntu/Debian (Mono/msbuild)
#    sudo apt install dotnet-sdk-8.0            # Ubuntu/Debian (dotnet msbuild)
#    sudo pacman -S mono curl unzip             # Arch
#    brew install mono                          # macOS
#
#  Uso:
#    make install-deps    Mostra o comando para instalar as dependências
#    make setup           Baixa o IV-SDK .NET e copia as DLLs de referência
#    make build           Compila o ChaosScript.dll (executa setup se necessário)
#    make bot-setup       Instala as dependências do bot Python
#    make clean           Remove os arquivos compilados
#    make distclean       Remove os arquivos compilados + libs baixadas
# ─────────────────────────────────────────────────────────────────────────────

# Auto-detecta msbuild: prefere 'msbuild' (Mono), depois 'xbuild' (Mono Ubuntu), cai em 'dotnet msbuild' (.NET SDK)
_MSBUILD_BIN := $(shell command -v msbuild 2>/dev/null)
_XBUILD_BIN  := $(shell command -v xbuild  2>/dev/null)
_DOTNET_BIN  := $(shell command -v dotnet  2>/dev/null)
ifeq ($(_MSBUILD_BIN),)
  ifneq ($(_XBUILD_BIN),)
    MSBUILD ?= xbuild
  else ifneq ($(_DOTNET_BIN),)
    MSBUILD ?= dotnet msbuild
  endif
endif
MSBUILD    ?= msbuild

IVSDK_VER  ?= 1.9.1
IVSDK_URL  ?= https://github.com/ClonkAndre/IV-SDK-DotNet/releases/download/$(IVSDK_VER)/IV-SDK.NET.v$(IVSDK_VER).zip

IVSDK_ZIP   = libs/IV-SDK.NET.v$(IVSDK_VER).zip
IVSDK_DIR   = libs/IV-SDK-DotNet
REF_DLL     = scripts/IVSDKDotNetWrapper.dll
OUTPUT_DLL  = scripts/LiveChaos.net.dll

.PHONY: all setup build clean distclean bot-setup install-deps check-tools-dl check-tools-build

all: setup build

# ─── Instalar dependências ────────────────────────────────────────────────────
install-deps:
	@echo ""
	@echo "  Execute o comando abaixo para instalar as dependências de compilação:"
	@echo ""
	@echo "    sudo apt install -y mono-complete mono-xbuild curl unzip  # Ubuntu/Debian (recomendado)"
	@echo "    sudo apt install -y dotnet-sdk-8.0 curl unzip  # Ubuntu/Debian (.NET SDK)"
	@echo "    # OU"
	@echo "    sudo apt install -y dotnet-sdk-8.0 curl unzip  # Ubuntu/Debian (.NET SDK)"
	@echo "    sudo pacman -S mono curl unzip                 # Arch Linux"
	@echo "    brew install mono                              # macOS"
	@echo ""
	@echo "  Depois execute: make setup && make build"
	@echo ""

# ─── Verificação de ferramentas de download (apenas curl + unzip) ─────────────
check-tools-dl:
	@command -v curl  >/dev/null 2>&1 || { echo "ERRO: curl não encontrado. Execute: sudo apt install curl"; exit 1; }
	@command -v unzip >/dev/null 2>&1 || { echo "ERRO: unzip não encontrado. Execute: sudo apt install unzip"; exit 1; }

# ─── Verificação de ferramentas de build (msbuild, xbuild ou dotnet) ────────
check-tools-build:
	@command -v msbuild >/dev/null 2>&1 || command -v xbuild >/dev/null 2>&1 || command -v dotnet >/dev/null 2>&1 || \
		{ echo ""; \
		  echo "  ERRO: nenhum compilador .NET encontrado (msbuild / xbuild / dotnet)."; \
		  echo "  Execute: make install-deps   para ver as opções de instalação."; \
		  echo ""; exit 1; }

# ─── Download do SDK ─────────────────────────────────────────────────────────
# O pipe (|) torna check-tools-dl um "order-only prerequisite":
# a verificação roda antes, mas não marca o zip como desatualizado,
# portanto o Make só re-baixa se o arquivo ainda não existir.
$(IVSDK_ZIP): | check-tools-dl
	@echo "==> Baixando IV-SDK .NET $(IVSDK_VER)..."
	@mkdir -p libs
	curl -fL "$(IVSDK_URL)" -o "$(IVSDK_ZIP)"
	@echo "==> Download concluído."

# ─── Extrair e copiar DLLs de referência ─────────────────────────────────────
# Make só re-executa esta regra se $(IVSDK_ZIP) for mais novo que $(REF_DLL)
# (ou seja, se a DLL ainda não existir ou o zip tiver sido atualizado).
$(REF_DLL): $(IVSDK_ZIP)
	@echo "==> Extraindo IV-SDK .NET..."
	@mkdir -p "$(IVSDK_DIR)"
	@chmod -Rf u+w "$(IVSDK_DIR)" 2>/dev/null || true
	unzip -oq "$(IVSDK_ZIP)" -d "$(IVSDK_DIR)"
	@echo "==> Copiando DLLs de referência para scripts/..."
	@mkdir -p scripts
	cp "$(IVSDK_DIR)/IVSDKDotNetWrapper.dll"            scripts/
	cp "$(IVSDK_DIR)/IVSDKDotNet/bin/Newtonsoft.Json.dll" scripts/
	@echo "==> DLLs de referência prontas."

setup: $(REF_DLL)
	@echo "==> Setup concluído. Execute 'make build' para compilar."

# ─── Compilação ──────────────────────────────────────────────────────────────
build: check-tools-build $(REF_DLL)
	@echo "==> Compilando ChaosScript.dll (Release|x86)..."
	cd ChaosScript && $(MSBUILD) ChaosScript.csproj \
		/p:Configuration=Release \
		/p:Platform=x86 \
		/p:OutputPath=../scripts/ \
		/verbosity:minimal
	@echo ""
	@echo "  Build concluído!"
	@echo "  Saída  : $(OUTPUT_DLL)"
	@echo "  Próximo: copie scripts/LiveChaos.net.dll para a pasta scripts/ do GTA IV."
	@echo ""

# ─── Bot Python ──────────────────────────────────────────────────────────────
bot-setup:
	@echo "==> Criando ambiente virtual Python (bot/.venv)..."
	python3 -m venv bot/.venv
	@echo "==> Instalando dependências do bot Python..."
	bot/.venv/bin/pip install --upgrade pip -q
	bot/.venv/bin/pip install -r bot/requirements.txt
	@echo "==> Pronto. Copie .env.example → .env e preencha seus tokens."
	@echo "   Para rodar o bot: bot/.venv/bin/python bot/chaos_bot.py"

# ─── Limpeza ─────────────────────────────────────────────────────────────────
clean:
	@echo "==> Removendo arquivos compilados..."
	rm -rf ChaosScript/bin ChaosScript/obj
	rm -f  scripts/*.dll scripts/*.pdb
	@echo "==> Pronto."

distclean: clean
	@echo "==> Removendo libs baixadas..."
	chmod -Rf u+w libs/ 2>/dev/null || true
	rm -rf libs/
	@echo "==> Pronto."
