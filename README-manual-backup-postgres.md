# Backup manual do PostgreSQL (`scripts/backup-postgres.sh`)

Este guia descreve como gerar um arquivo **ZIP** com um backup lógico de um banco PostgreSQL, usando os clientes oficiais instalados na máquina onde o script roda.

## O que o script faz

1. Conecta ao servidor informado (**host**, **porta**, **usuário**, **banco**).
2. Executa **`pg_dump`** para gerar um único arquivo SQL com estrutura e dados (`--clean`, `--if-exists`, `--create`, sem dono/privilégios globais, UTF-8).
3. Compacta esse SQL em **`postgres_backup_<data_hora>.zip`** no diretório de saída (por padrão `./backups`).

**Nota:** backups lógicos são feitos com **`pg_dump`**. O **`psql`** é o cliente interativo e serve para **executar** ou **restaurar** scripts SQL; faz parte do mesmo pacote de ferramentas (por exemplo `postgresql-client` no Debian/Ubuntu).

## Pré-requisitos

- **`pg_dump`** e **`psql`** no `PATH` (instale o pacote de cliente PostgreSQL adequado ao seu sistema).
- **`zip`** no `PATH`.
- Rede até o servidor (firewall/security group liberado na porta PostgreSQL).

## Parâmetros obrigatórios

| Opção           | Descrição                          |
|----------------|-------------------------------------|
| `--host`       | Hostname ou IP do servidor         |
| `--port`       | Porta TCP (opcional; padrão: `5432`) |
| `--user`       | Usuário PostgreSQL                 |
| `--database`   | Nome do banco a ser dumpado       |

Opcional:

| Opção           | Descrição                                    |
|----------------|-----------------------------------------------|
| `--output-dir` | Pasta onde será criado o `.zip` (default: `./backups`) |

`-h` / `--help` mostra o resumo de uso.

## Senha

- Recomendado: exportar **`PGPASSWORD`** apenas para a execução (evita deixar a senha no histórico de argumentos):

  ```bash
  export PGPASSWORD='sua_senha'
  ./scripts/backup-postgres.sh --host db.exemplo.com --port 5432 --user app --database appdb
  unset PGPASSWORD
  ```

- Se **`PGPASSWORD`** não estiver definida, o script pede a senha de forma **silenciosa** (sem eco).

## TLS / provedores cloud

Para instâncias que exigem SSL, use variáveis padrão do libpq, por exemplo:

```bash
export PGSSLMODE=require
```

Ajuste conforme a política do provedor (RDS, AlloyDB, Azure, etc.).

## Exemplos

Dentro do repositório (ajuste caminhos se necessário):

```bash
chmod +x scripts/backup-postgres.sh

PGPASSWORD='***' ./scripts/backup-postgres.sh \
  --host localhost \
  --port 5432 \
  --user postgres \
  --database meu_banco \
  --output-dir ./backups
```

Saída típica: `./backups/postgres_backup_YYYYMMDD_HHMMSS.zip`.

## Restaurar o backup

O ZIP contém **um arquivo `.sql`**. Você pode descompactar e enviar ao `psql`, ou usar pipe:

```bash
# Exemplo: restaurar direto do ZIP (streaming para psql)
unzip -p ./backups/postgres_backup_20260101_120000.zip | \
  psql -h HOST_DESTINO -p 5432 -U USUARIO -d postgres
```

O dump inclui `CREATE DATABASE` quando gerado com `--create`; em muitos casos você apontará o `-d` para um banco existente onde o comando de criar/atualizar o banco faz sentido, ou use `postgres` como banco inicial conforme sua política de restauração.

Para grandes volumes ou formato customizado no futuro, considere `pg_dump -Fc` e `pg_restore`; este script visa um único artefato **ZIP + SQL** simples para arquivo e troca manual.

## Falhas comuns

- **`pg_dump: error: connection refused`**: host/porta incorretos ou serviço inacessível na rede.
- **Autenticação**: usuário/senha ou `pg_hba.conf` do servidor.
- **Comando não encontrado**: instale cliente PostgreSQL e `zip`.
