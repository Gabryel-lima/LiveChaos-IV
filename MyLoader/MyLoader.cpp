#include <windows.h>
#include <thread>

// Função que vai rodar em uma thread separada
void LoadScripts()
{
    // Espera 5 segundos para o jogo carregar tudo (evita crash)
    Sleep(5000);

    // Agora sim carrega o ScriptHookDotNet com segurança
    HMODULE h = LoadLibraryA("ScriptHookDotNet.asi");
    if (h)
    {
        // Opcional: mostra mensagem no log do ASI Loader
        MessageBoxA(0, "ScriptHookDotNet carregado com sucesso!", "MeuLoader", MB_ICONINFORMATION);
    }
    else
    {
        MessageBoxA(0, "ERRO: ScriptHookDotNet.asi não encontrado ou falhou ao carregar!", "MeuLoader", MB_ICONERROR);
    }
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID lpReserved)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        // Desabilita chamadas recursivas (importante!)
        DisableThreadLibraryCalls(hModule);

        // Cria uma thread separada para carregar o ScriptHookDotNet
        std::thread(LoadScripts).detach();
    }
    return TRUE;
}
