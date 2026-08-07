# Update ECS Task Definition — Secrets e Environment

Dois scripts automatizam a sincronização de **`secrets`** (referências ao Secrets Manager) e **`environment`** (valores literais) em `containerDefinitions[0]` da Task Definition ativa do serviço.

| Script | Campo na TD | Conteúdo do `--file` |
|--------|-------------|-------------------------|
| **`scripts/update-ecs-secrets.sh`** | `secrets` | ARNs `valueFrom` → Secrets Manager |
| **`scripts/update-ecs-env.sh`** | `environment` | Pares `name` / `value` em texto |

Comportamento comum aos dois:

- Usa a Task Definition **ativa** do serviço (via `describe-services`)
- **Substitui por completo** o array correspondente — não faz merge
- Registra nova revisão, faz `update-service` e opcionalmente aguarda estabilização (`--wait`)

---

## Pré-requisitos

- AWS CLI com credenciais válidas
- `jq` (`sudo apt-get install jq`)
- Permissões IAM: `ecs:DescribeServices`, `ecs:DescribeTaskDefinition`, `ecs:RegisterTaskDefinition`, `ecs:UpdateService`
- Para **secrets**: permissão de leitura aos secrets referenciados (`secretsmanager:GetSecretValue`)

---

## `update-ecs-secrets.sh`

### Uso

```bash
./scripts/update-ecs-secrets.sh \
  --family <family> \
  --cluster <cluster> \
  --service <service> \
  --file <arquivo.json> \
  [--region <region>] \
  [--profile <profile>] \
  [--wait]
```

### Parâmetros

| Parâmetro | Obrigatório | Descrição | Padrão |
|-----------|-------------|-----------|--------|
| `--family` | Sim | Família da Task Definition | — |
| `--cluster` | Sim | Cluster ECS | — |
| `--service` | Sim | Serviço ECS | — |
| `--file` | Sim | JSON com secrets | — |
| `--region` | Não | Região AWS | `us-east-1` |
| `--profile` | Não | Perfil AWS CLI | `stg` |
| `--wait` | Não | Aguardar estabilização | `true` |

### Formato do JSON (secrets)

**Objeto:**

```json
{
  "DATABASE_URL": "arn:aws:secretsmanager:us-east-1:123456789012:secret:app/db-AbCdEf:DATABASE_URL::",
  "API_KEY": "arn:aws:secretsmanager:us-east-1:123456789012:secret:app/api-GhIjKl:API_KEY::"
}
```

**Array (formato ECS):**

```json
[
  {
    "name": "DATABASE_URL",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:app/db-AbCdEf:DATABASE_URL::"
  }
]
```

ARN esperado: `arn:aws:secretsmanager:<region>:<account>:secret:...`

### Exemplo

```bash
./scripts/update-ecs-secrets.sh \
  --family my-app \
  --cluster my-cluster \
  --service my-service \
  --file secrets.json \
  --profile stg
```

---

## `update-ecs-env.sh`

### Uso

```bash
./scripts/update-ecs-env.sh \
  --family <family> \
  --cluster <cluster> \
  --service <service> \
  --file <arquivo.json> \
  [--region <region>] \
  [--profile <profile>] \
  [--wait]
```

Os parâmetros são os mesmos do script de secrets; a diferença é o formato do arquivo e o campo atualizado na Task Definition (`environment`).

### Formato do JSON (environment)

**Objeto:**

```json
{
  "NODE_ENV": "production",
  "LOG_LEVEL": "info",
  "PORT": "8080"
}
```

**Array (formato ECS):**

```json
[
  { "name": "NODE_ENV", "value": "production" },
  { "name": "LOG_LEVEL", "value": "info" }
]
```

Valores são convertidos para string. **Não use este script para senhas ou tokens** — prefira `update-ecs-secrets.sh`; valores literais aparecem na definição da task (API/Console).

### Exemplo

```bash
./scripts/update-ecs-env.sh \
  --family my-app \
  --cluster my-cluster \
  --service my-service \
  --file env.json \
  --region us-east-1 \
  --profile stg
```

---

## Fluxo de execução (ambos os scripts)

1. Lê e valida o JSON (`jq`)
2. Obtém a Task Definition ativa do serviço
3. Substitui `secrets` **ou** `environment` em `containerDefinitions[0]`
4. Registra nova revisão preservando `networkMode`, `executionRoleArn`, `requiresCompatibilities`, `cpu`, `memory`
5. Atualiza o serviço e opcionalmente espera `services-stable`

---

## Comportamento importante

### Substituição completa

Inclua no arquivo todas as variáveis que devem permanecer; entradas omitidas são removidas na nova revisão.

### Task Definition ativa

A base é sempre a revisão **em uso pelo serviço**, não necessariamente a última revisão registrada na família.

---

## Troubleshooting

### `jq não está instalado`

```bash
sudo apt-get install jq
```

### Secrets: `ARN inválido`

Use apenas ARNs `arn:aws:secretsmanager:...`

### `Task Definition ativa não encontrada`

Confira cluster, serviço e perfil AWS.

### `networkMode` / `executionRoleArn` ausentes

Revise a Task Definition atual no console AWS.
