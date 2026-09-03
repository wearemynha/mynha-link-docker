# Mynha Link Docker

Imagem Docker do **Mynha Link**, baseada no fork do LinkStack mantido pela Mynha.

A imagem contém Apache, PHP 8.3, as dependências PHP de produção e os arquivos compilados do frontend. O ambiente definido em `docker-compose.yml` utiliza PostgreSQL 17.

## Requisitos

- Docker com o plugin Docker Compose;
- código do `mynha-link` disponível na pasta `linkstack/` deste repositório.

Enquanto os submódulos permanecerem como placeholders, o código usado pelo build pode ser clonado diretamente:

```sh
git clone https://github.com/wearemynha/mynha-link.git linkstack
```

A pasta é ignorada pelo Git deste repositório. A vinculação definitiva do build aos submódulos será feita em uma etapa separada.

## Submódulos (placeholders)

O repositório já reserva os seguintes caminhos:

- `sources/mynha-link`: código da aplicação;
- `sources/mynha-link-themes`: repositório de temas, cuja estrutura de temas está em `themes/`.

Os dois submódulos acompanham a branch `main` como referência, mas o repositório Docker sempre registra commits exatos. Eles ainda não são consumidos pelo `Dockerfile` e estão excluídos do contexto de build por `.dockerignore`; portanto, não alteram a imagem atual.

Em um clone novo, inicialize os placeholders com:

```sh
git submodule update --init --recursive
```

Também é possível clonar tudo de uma vez com `git clone --recurse-submodules`. A ativação ocorrerá somente depois que as versões desejadas da aplicação e dos temas estiverem na `main`: nessa etapa, os ponteiros serão atualizados e o `Dockerfile` passará a usar `sources/mynha-link` e `sources/mynha-link-themes/themes`.

## Execução local

Crie o arquivo local de configuração:

```sh
cp .env.local.example .env
```

No PowerShell, use:

```powershell
Copy-Item .env.local.example .env
```

Substitua `POSTGRES_PASSWORD` em `.env` por uma senha local e inicie o ambiente:

```sh
docker compose -f docker-compose.yml -f docker-compose.local.yml up --detach --build
```

O Compose base não publica portas no host. O arquivo `docker-compose.local.yml` adiciona exclusivamente o mapeamento `${HTTP_PORT:-8080}:80` necessário para acessar a aplicação pelo navegador local.

Acesse `http://localhost:8080`. Para acompanhar a inicialização:

```sh
docker compose -f docker-compose.yml -f docker-compose.local.yml logs --follow linkstack
```

Para encerrar os containers sem apagar os dados:

```sh
docker compose -f docker-compose.yml -f docker-compose.local.yml down
```

## Persistência e atualizações

O Compose mantém dois volumes:

- `linkstack_data`: `.env`, uploads, backups, configuração avançada e outros dados mutáveis da aplicação;
- `postgres_data`: banco PostgreSQL.

O código e os temas distribuídos ficam em `/opt/linkstack`, dentro da imagem. A cada inicialização eles são sincronizados com `/htdocs`, preservando os dados mutáveis. A pasta de temas fica somente leitura para o Apache; novos temas devem entrar pelo repositório e pelo processo de build. A sincronização não remove temas já existentes no volume, mesmo quando eles deixam de fazer parte de uma imagem posterior.

Para aplicar uma nova versão do código:

```sh
docker compose build --pull linkstack
docker compose up --detach --force-recreate linkstack
```

Faça backup dos dois volumes antes de atualizações em produção. Não execute `docker compose down --volumes` em um ambiente que contenha dados que devam ser preservados.

## Configuração

O `.env.example` é o modelo canônico e completo de produção. Para execução local, `.env.local.example` contém somente os valores que precisam sobrescrever os padrões locais seguros definidos no Compose. Em cada ambiente continua existindo um único `.env` real. As principais variáveis são:

| Variável | Finalidade | Padrão |
| --- | --- | --- |
| `APP_URL` | URL pública da aplicação | `https://link.example.com` |
| `POSTGRES_DB` | Nome do banco | `mynha_link` |
| `POSTGRES_USER` | Usuário do banco | `mynha_link` |
| `POSTGRES_PASSWORD` | Senha do banco | sem valor seguro padrão |
| `DB_SSLMODE` | Modo SSL da conexão PostgreSQL | `disable` |
| `HTTP_PORT` | Porta HTTP publicada pelo override local | `8080` |
| `PHP_MEMORY_LIMIT` | Limite de memória do PHP | `256M` |
| `UPLOAD_MAX_FILESIZE` | Tamanho máximo de um arquivo | `8M` |
| `POST_MAX_SIZE` | Tamanho máximo da requisição | `16M` |
| `TZ` | Fuso horário do container | `America/Sao_Paulo` |

Os campos de segredo permanecem vazios nos exemplos para que o Compose interrompa a inicialização até que sejam fornecidos pelo ambiente. Em produção, defina uma senha forte, substitua `<version>` por uma tag imutável da imagem, configure `APP_URL` com o domínio público e mantenha `APP_DEBUG=false`. A inicialização é interrompida se `APP_DEBUG=true` for usado com `APP_ENV=production`. O PostgreSQL não é publicado no host pelo Compose.

O arquivo `.env` deste repositório é a fonte de configuração do ambiente Docker. O Compose encaminha apenas uma lista explícita de variáveis de deploy para o container. Na inicialização, essa lista é sincronizada com o `.env` persistente do Mynha Link e o cache do Laravel é reconstruído.

Uma chave controlada pelo deploy que deixar de ser fornecida será removida do ambiente persistente, evitando que um valor antigo continue ativo silenciosamente. A `APP_KEY` é a exceção: quando não é fornecida pelo deploy, a chave gerada e persistida pela aplicação é preservada. Opções pertencentes ao instalador ou painel, como nome da aplicação, idioma ativo, registro e página inicial, também são preservadas.

A raiz `/htdocs` e o diretório `/htdocs/config` pertencem ao usuário `root` e não são graváveis pelo Apache. A aplicação recebe escrita somente no `.env`, no arquivo `config/advanced-config.php` e nos diretórios de dados mutáveis, como `storage`, uploads, caches e backups.

O Apache escuta somente HTTP na porta 80. O Compose base apenas documenta essa porta e não a publica no host. Em produção, o Traefik termina o TLS e encaminha as requisições para essa porta; não há certificado nem listener HTTPS dentro da imagem.

## Build manual

```sh
docker build --tag ghcr.io/wearemynha/mynha-link:local .
```

O build possui três estágios:

1. compilação dos assets com Node.js;
2. instalação das dependências PHP de produção com Composer;
3. criação da imagem final sem `node_modules`, testes ou ferramentas de desenvolvimento.

## Homologação automatizada

Em Linux, WSL ou Git Bash, execute:

```sh
sh ./autotest.sh
```

O teste cria recursos Docker isolados e temporários, valida PostgreSQL, extensões PHP, assets, instalador, healthcheck, permissões, limpeza de configurações antigas e persistência após a recriação do container. Os recursos temporários são removidos ao final, inclusive quando ocorre uma falha.

## Licença

Este projeto mantém a licença AGPL-3.0 do projeto original. Consulte [LICENSE](LICENSE).
