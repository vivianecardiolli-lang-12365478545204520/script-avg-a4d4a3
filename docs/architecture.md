# Arquitetura do Projeto

## Estrutura

- `main.lua`: único entrypoint do executor; carrega módulos via HTTP.
- `src/app.lua`: orquestração principal do fluxo.
- `src/core/`: base compartilhada (`config`, `logger`).
- `src/systems/`: sistemas de automação por domínio.
- `src/integrations/`: integrações externas (Google Sheets).
- `src/utils/`: utilitários reutilizáveis.

## Fluxo principal

1. `RewardSystem.run()`
2. `Tracker.sendNow()`
3. `Tracker.startLoop()`

## Execução no executor

- Configure `baseUrl` em `main.lua` apontando para a pasta `src/` hospedada.
- Execute `main.lua` no executor.
- Os módulos são carregados via HTTP sob demanda e com cache em memória.

Exemplo de URL base:

```text
https://raw.githubusercontent.com/SEU_USUARIO/SEU_REPO/main/src/
```

## Observações

- Não há geração de bundle.
- A evolução do projeto ocorre mantendo múltiplos arquivos Lua em `src/`.