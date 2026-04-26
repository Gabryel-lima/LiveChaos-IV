# MyLoader - Código Fonte

Este diretório contém o código fonte C++ do loader customizado que garante o carregamento seguro do ScriptHookDotNet no GTA IV.

## 📋 Descrição

O MyLoader é um arquivo ASI (ASI Loader Script) desenvolvido em C++ que resolve um problema comum ao carregar o ScriptHookDotNet diretamente: crashes na inicialização do jogo. 

### Problema Resolvido

Quando o ScriptHookDotNet é carregado muito cedo durante a inicialização do jogo, pode causar crashes. O MyLoader resolve isso:

1. Aguarda 5 segundos após o jogo iniciar
2. Carrega o ScriptHookDotNet de forma segura em uma thread separada
3. Exibe mensagens de sucesso/erro para feedback

## 📁 Estrutura dos Arquivos

```
MyLoader/
├── MyLoader.cpp          # Código fonte principal
├── MyLoader.h            # Cabeçalho (atualmente vazio, pode ser usado para futuras expansões)
├── MyLoader.sln          # Solução Visual Studio
├── MyLoader.vcxproj      # Projeto Visual Studio
├── MyLoader.vcxproj.filters
├── MyLoader.vcxproj.user
└── Release/              # Arquivos compilados (gerados após build)
    └── MyLoader.asi      # Arquivo final compilado
```

## 🔧 Como Compilar

### Requisitos

- **Visual Studio 2019 ou superior** (com componentes C++)
- **Windows SDK 10.0** ou superior
- **Platform Toolset v142** (Visual Studio 2019) ou superior

### Passos para Compilar

1. **Abrir o Projeto**
   - Abra `MyLoader.sln` no Visual Studio

2. **Configurar a Build**
   - Selecione a configuração **Release**
   - Selecione a plataforma **Win32** (GTA IV é 32-bit)
   - **Nota**: A configuração Release|Win32 compila como DLL (DynamicLibrary) e gera um arquivo `.asi`

3. **Compilar**
   - Pressione `F7` ou vá em **Build** → **Build Solution**
   - O arquivo `MyLoader.asi` será gerado na pasta `Release/`

4. **Copiar o Resultado**
   - Copie `Release/MyLoader.asi` para o diretório principal do GTA IV

### Configurações Importantes

- **Configuration Type**: `DynamicLibrary` (para gerar .asi)
- **Target Extension**: `.asi` (definido no projeto Release|Win32)
- **Platform**: Win32 (GTA IV é 32-bit)

## 📝 Explicação do Código

### MyLoader.cpp

O código principal implementa:

```cpp
void LoadScripts()
{
    // Espera 5 segundos para o jogo carregar tudo (evita crash)
    Sleep(5000);
    
    // Carrega o ScriptHookDotNet com segurança
    HMODULE h = LoadLibraryA("ScriptHookDotNet.asi");
    // ... tratamento de sucesso/erro
}

BOOL APIENTRY DllMain(...)
{
    // Cria thread separada para carregar o ScriptHookDotNet
    std::thread(LoadScripts).detach();
}
```

### Funcionalidades

1. **DllMain**: Ponto de entrada da DLL, chamado quando o ASI é carregado
2. **DisableThreadLibraryCalls**: Previne chamadas recursivas que podem causar deadlocks
3. **Thread Separada**: Carrega o ScriptHookDotNet em uma thread separada para não bloquear o jogo
4. **Delay de 5 segundos**: Aguarda o jogo inicializar completamente antes de carregar scripts
5. **Feedback Visual**: Exibe MessageBox para indicar sucesso ou erro

## 🔍 Detalhes Técnicos

### Por que uma Thread Separada?

Carregar DLLs diretamente no `DllMain` pode causar deadlocks e crashes. Usar uma thread separada garante que o carregamento aconteça de forma assíncrona e segura.

### Por que 5 segundos?

Este valor foi escolhido empiricamente para dar tempo suficiente ao jogo inicializar todos os seus sistemas antes de carregar scripts .NET. Você pode ajustar este valor se necessário, mas valores menores podem causar instabilidade.

### Dependências

- **Windows.h**: Para funções da API do Windows (LoadLibrary, Sleep, MessageBox)
- **thread**: Para criar threads (C++11)

## 🛠️ Modificações Possíveis

### Ajustar o Tempo de Espera

Se você quiser mudar o tempo de espera, modifique a linha:

```cpp
Sleep(5000);  // Mude 5000 para o valor desejado (em milissegundos)
```

### Remover Mensagens de Feedback

Se você não quiser as MessageBox, remova ou comente as linhas:

```cpp
MessageBoxA(0, "ScriptHookDotNet carregado com sucesso!", "MeuLoader", MB_ICONINFORMATION);
```

### Adicionar Logging

Você pode adicionar logging em arquivo para debug:

```cpp
// Exemplo de logging
FILE* f = fopen("MyLoader.log", "a");
fprintf(f, "ScriptHookDotNet carregado\n");
fclose(f);
```

## ⚠️ Notas Importantes

- Este loader é específico para **GTA IV 32-bit**
- O arquivo `ScriptHookDotNet.asi` deve estar no mesmo diretório que `MyLoader.asi`
- O loader assume que o Ultimate ASI Loader (`dinput8.dll`) já está instalado
- Não modifique o `DllMain` de forma que possa bloquear ou causar deadlocks

## 🐛 Troubleshooting de Compilação

### Erro: "Cannot open include file"

- Certifique-se de ter o Windows SDK instalado
- Verifique se o Visual Studio está configurado corretamente

### Erro: "Unresolved external symbol"

- Verifique se todas as bibliotecas necessárias estão linkadas
- Para este projeto, apenas as bibliotecas padrão do Windows são necessárias

### O arquivo .asi não é gerado

- Certifique-se de estar usando a configuração **Release|Win32**
- Verifique se o `ConfigurationType` está definido como `DynamicLibrary`
- Verifique se o `TargetExt` está definido como `.asi`

## 📄 Licença

Este código é parte do projeto TurboTraffic-IV e é fornecido "como está" para uso pessoal e educacional.

