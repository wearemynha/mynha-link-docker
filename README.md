# Mynha Link Docker

Imagem Docker do **Mynha Link**, baseada no fork do LinkStack mantido pela Mynha.

A imagem contém Apache, PHP 8.3, as dependências PHP de produção e os arquivos compilados do frontend. O ambiente definido em `docker-compose.yml` utiliza PostgreSQL 17.

## Requisitos

- Docker com o plugin Docker Compose;
- código do `mynha-link` disponível na pasta `linkstack/` deste repositório.

Enquanto os submódulos não forem configurados, o código pode ser clonado diretamente:

```sh
git clone https://github.com/wearemynha/mynha-link.git linkstack
```

A pasta é ignorada pelo Git deste repositório. A vinculação definitiva por submódulo será feita em uma etapa separada.

## Execução local

Crie o arquivo local de configuração:

```sh
cp .env.example .env
```

No PowerShell, use:

```powershell
Copy-Item .env.example .env
```

Substitua `POSTGRES_PASSWORD` em `.env` por uma senha local e inicie o ambiente:

```sh
docker compose up --detach --build
```

Acesse `http://localhost:8080`. Para acompanhar a inicialização:

```sh
docker compose logs --follow linkstack
```

Para encerrar os containers sem apagar os dados:

```sh
docker compose down
```

## Persistência e atualizações

O Compose mantém dois volumes:

- `linkstack_data`: `.env`, uploads, temas, backups, configuração avançada e outros dados mutáveis da aplicação;
- `postgres_data`: banco PostgreSQL.

O código imutável fica em `/opt/linkstack`, dentro da imagem. A cada inicialização ele é sincronizado com `/htdocs`, preservando os dados mutáveis. Dessa forma, uma nova imagem atualiza o código sem recriar a configuração da instalação.

Para aplicar uma nova versão do código:

```sh
docker compose build --pull linkstack
docker compose up --detach --force-recreate linkstack
```

Faça backup dos dois volumes antes de atualizações em produção. Não execute `docker compose down --volumes` em um ambiente que contenha dados que devam ser preservados.

## Configuração

As variáveis disponíveis estão documentadas em `.env.example`. As principais são:

| Variável | Finalidade | Padrão |
| --- | --- | --- |
| `APP_URL` | URL pública da aplicação | `http://localhost:8080` |
| `POSTGRES_DB` | Nome do banco | `linkstack` |
| `POSTGRES_USER` | Usuário do banco | `linkstack` |
| `POSTGRES_PASSWORD` | Senha do banco | sem valor seguro padrão |
| `DB_SSLMODE` | Modo SSL da conexão PostgreSQL | `disable` |
| `HTTP_PORT` | Porta HTTP publicada | `8080` |
| `HTTPS_PORT` | Porta HTTPS publicada | `8443` |
| `PHP_MEMORY_LIMIT` | Limite de memória do PHP | `256M` |
| `UPLOAD_MAX_FILESIZE` | Tamanho máximo de um arquivo | `8M` |
| `POST_MAX_SIZE` | Tamanho máximo da requisição | `16M` |
| `TZ` | Fuso horário do container | `America/Sao_Paulo` |

Em produção, defina uma senha forte, `APP_URL` com o domínio público e `APP_DEBUG=false`. O PostgreSQL não é publicado no host pelo Compose.

O Apache também expõe HTTPS com o certificado autoassinado fornecido pela imagem base. Em produção, prefira terminar o TLS em um proxy reverso com certificado válido e encaminhar as requisições para a porta HTTP interna.

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

O teste cria recursos Docker isolados e temporários, valida PostgreSQL, extensões PHP, assets, instalador, healthcheck e persistência após a recriação do container. Os recursos temporários são removidos ao final, inclusive quando ocorre uma falha.

## Licença

Este projeto mantém a licença AGPL-3.0 do projeto original. Consulte [LICENSE](LICENSE).
