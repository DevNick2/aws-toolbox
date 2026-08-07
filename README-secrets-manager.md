# Gerenciamento de Secrets no AWS Secrets Manager

Scripts para buscar e atualizar secrets no AWS Secrets Manager usando o AWS CLI.

## Para que servem

- `get-secrets.sh` — Busca secrets do Secrets Manager e salva em formato JSON ou .env
- `update-secrets.sh` — Atualiza secrets no Secrets Manager usando um arquivo JSON como entrada

## Pré-requisitos

1. AWS CLI instalado e configurado
2. `jq` instalado (`sudo apt-get install -y jq`)
3. Permissões IAM adequadas para acessar o Secrets Manager

### Permissões IAM necessárias

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:PutSecretValue",
        "secretsmanager:CreateSecret"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:*"
    }
  ]
}
```

## Buscar Secrets (get-secrets.sh)

Busca secrets do AWS Secrets Manager e exibe/salva em formato JSON ou .env.

### Uso básico

```bash
# Exibir secrets (valores mascarados)
./scripts/get-secrets.sh meu-app/producao

# Exibir secrets com valores completos
./scripts/get-secrets.sh meu-app/producao --show-values

# Salvar em arquivo JSON
./scripts/get-secrets.sh meu-app/producao -o secrets.json

# Salvar em formato .env
./scripts/get-secrets.sh meu-app/producao --env -o .env

# Especificar região e perfil AWS
./scripts/get-secrets.sh meu-app/producao --region us-east-1 --profile meu-perfil

# Modo silencioso (apenas output, sem mensagens)
./scripts/get-secrets.sh meu-app/producao -q -o secrets.json
```

### Opções

| Opção | Descrição |
|-------|-----------|
| `-o, --output <file>` | Salva o resultado no arquivo especificado |
| `--region <regiao>` | Região AWS (padrão: usa configuração do CLI) |
| `--profile <profile>` | Perfil AWS a ser usado |
| `--show-values` | Mostra os valores completos (padrão: mascara valores) |
| `--env` | Formato .env ao invés de JSON (VARIAVEL=valor) |
| `-q, --quiet` | Não exibe mensagens de status |
| `-h, --help` | Mostra a ajuda |

### Exemplos de saída

**Formato JSON (padrão):**
```json
{
  "DATABASE_URL": "postgres://user:pass@host:5432/db",
  "API_KEY": "abc123xyz",
  "DEBUG": "false"
}
```

**Formato .env (--env):**
```
DATABASE_URL=postgres://user:pass@host:5432/db
API_KEY=abc123xyz
DEBUG=false
```

## Atualizar Secrets (update-secrets.sh)

Atualiza secrets no AWS Secrets Manager usando um arquivo JSON como entrada.

### Uso básico

```bash
# Atualizar secrets (substitui todos os valores)
./scripts/update-secrets.sh meu-app/producao secrets.json

# Mesclar com valores existentes (não substitui tudo)
./scripts/update-secrets.sh meu-app/producao secrets.json --merge

# Verificar o que seria alterado sem executar
./scripts/update-secrets.sh meu-app/producao secrets.json --dry-run

# Especificar região e perfil AWS
./scripts/update-secrets.sh meu-app/producao secrets.json --region us-east-1 --profile meu-perfil
```

### Opções

| Opção | Descrição |
|-------|-----------|
| `--region <regiao>` | Região AWS (padrão: usa configuração do CLI) |
| `--profile <profile>` | Perfil AWS a ser usado |
| `--merge` | Mescla com valores existentes (não substitui tudo) |
| `--dry-run` | Mostra o que seria atualizado sem executar |
| `-h, --help` | Mostra a ajuda |

### Formato do arquivo JSON de entrada

```json
{
  "DATABASE_URL": "postgres://user:pass@host:5432/db",
  "API_KEY": "abc123xyz",
  "DEBUG": "false"
}
```

### Modos de atualização

**Substituição (padrão):**
- Remove todos os valores existentes e substitui pelo conteúdo do arquivo JSON
- Use quando quiser garantir que o secret tenha exatamente as variáveis do arquivo

**Merge (--merge):**
- Mantém valores existentes e adiciona/atualiza os valores do arquivo JSON
- Use quando quiser atualizar apenas algumas variáveis sem perder as outras

## Fluxos de trabalho comuns

### 1. Exportar secrets para backup

```bash
# Exportar para JSON
./scripts/get-secrets.sh meu-app/producao --show-values -o backup-secrets-$(date +%Y%m%d).json

# Proteger o arquivo
chmod 600 backup-secrets-*.json
```

### 2. Migrar secrets entre ambientes

```bash
# Exportar do ambiente de staging
./scripts/get-secrets.sh meu-app/staging --show-values -o staging-secrets.json

# Editar o arquivo se necessário
nano staging-secrets.json

# Importar para produção
./scripts/update-secrets.sh meu-app/producao staging-secrets.json
```

### 3. Atualizar uma variável específica

```bash
# Criar arquivo com apenas a variável a ser atualizada
echo '{"API_KEY": "novo-valor"}' > update.json

# Atualizar usando merge para não perder outras variáveis
./scripts/update-secrets.sh meu-app/producao update.json --merge

# Limpar
rm update.json
```

### 4. Verificar alterações antes de aplicar

```bash
# Ver o que seria alterado
./scripts/update-secrets.sh meu-app/producao novos-secrets.json --dry-run

# Se estiver correto, aplicar
./scripts/update-secrets.sh meu-app/producao novos-secrets.json
```

### 5. Gerar .env para desenvolvimento local

```bash
# Baixar secrets e salvar como .env
./scripts/get-secrets.sh meu-app/desenvolvimento --env -o .env

# Usar com Docker
docker run --env-file .env minha-imagem
```

## Integração com ECS

Após atualizar os secrets no Secrets Manager, você pode precisar reiniciar os serviços ECS para que eles busquem os novos valores.

```bash
# Atualizar secrets
./scripts/update-secrets.sh meu-app/producao secrets.json

# Reiniciar serviço ECS para aplicar as alterações
./scripts/restart-ecs-service.sh meu-cluster meu-servico --region us-east-1
```

## Segurança

### Boas práticas

1. **Nunca commite arquivos com secrets**: Adicione `*.json` e `.env` ao `.gitignore`
2. **Use --dry-run**: Sempre verifique antes de aplicar alterações em produção
3. **Permissões de arquivo**: Os scripts ajustam automaticamente permissões para 600
4. **Valores mascarados**: Por padrão, valores são mascarados na exibição
5. **Use perfis AWS**: Separe credenciais por ambiente usando `--profile`

### Exemplo de .gitignore

```gitignore
# Arquivos de secrets
*.secrets.json
secrets.json
.env
.env.*
```

## Solução de problemas

### Erro: "Unable to locate credentials"

Configure as credenciais AWS:
```bash
aws configure
# ou
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
```

### Erro: "Secret not found"

Verifique se o nome do secret está correto:
```bash
# Listar todos os secrets
aws secretsmanager list-secrets --query 'SecretList[*].Name' --output table
```

### Erro: "Access denied"

Verifique as permissões IAM do usuário/role.

### Erro: "jq: command not found"

Instale o jq:
```bash
sudo apt-get install -y jq
```

## Referências

- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html)
- [AWS CLI - secretsmanager](https://docs.aws.amazon.com/cli/latest/reference/secretsmanager/)
