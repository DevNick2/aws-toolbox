# Reiniciar Serviço ECS

Script para reiniciar um serviço no Amazon ECS forçando um novo deployment.

## Para que serve

O script `restart-ecs-service.sh` automatiza o processo de:
- Forçar um novo deployment de um serviço ECS
- Aguardar a estabilização do serviço após o restart
- Exibir informações sobre o status do serviço

## Pré-requisitos

1. **AWS CLI** instalado e configurado
2. **Permissões IAM** adequadas para:
   - `ecs:UpdateService`
   - `ecs:DescribeServices`
   - `ecs:DescribeTaskDefinition`

### Permissões IAM necessárias

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateService",
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition"
      ],
      "Resource": "*"
    }
  ]
}
```

## Uso Básico

### Uso simples (com valores padrão)

```bash
./scripts/restart-ecs-service.sh
```

O script usa valores padrão:
- Cluster: `my-cluster`
- Service: `my-app-service`
- Family: `my-app`
- Region: `us-east-1`
- Profile: `stg`

### Uso com parâmetros

```bash
./scripts/restart-ecs-service.sh <cluster> <service> <family> <region> <profile>
```

### Exemplos práticos

```bash

# Reiniciar serviço em staging
./scripts/restart-ecs-service.sh \
  staging-cluster \
  app-service-abc123 \
  app-family \
  us-east-1 \
  stg

# Usando apenas cluster e service (outros valores padrão)
./scripts/restart-ecs-service.sh meu-cluster meu-servico
```

## Parâmetros

| Posição | Parâmetro | Obrigatório | Descrição | Padrão |
|---------|-----------|-------------|-----------|--------|
| 1 | `cluster` | Não | Nome do cluster ECS | `my-cluster` |
| 2 | `service` | Não | Nome do serviço ECS | `my-app-service` |
| 3 | `family` | Não | Nome da família da Task Definition | `my-app` |
| 4 | `region` | Não | Região AWS | `us-east-1` |
| 5 | `profile` | Não | Perfil AWS CLI | `stg` |

## Como Funciona

### 1. Forçar Novo Deployment

O script executa `aws ecs update-service` com a flag `--force-new-deployment`:

```bash
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition $FAMILY \
  --force-new-deployment \
  --region "$REGION" \
  --profile $PROFILE
```

**O que acontece:**
- ECS força um novo deployment do serviço
- Novas tasks são criadas com a mesma Task Definition
- Tasks antigas são gradualmente substituídas
- O serviço mantém disponibilidade durante o processo

### 2. Aguardar Estabilização

O script usa `aws ecs wait services-stable` para aguardar:

```bash
aws ecs wait services-stable \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --region "$REGION" \
  --profile $PROFILE
```

**O que acontece:**
- Aguarda até que todas as tasks estejam rodando
- Verifica que o número de tasks desejadas = tasks rodando
- Timeout padrão: 10 minutos (pode ser configurado)

## Saída do Script

### Durante a execução

```
🔄 Reiniciando serviço ECS...
Cluster: my-prod-cluster
Service: my-app-service
Family: my-app
Region: us-east-1
Profile: prd

------------------------------------------------------------------
|                    UpdateService                               |
+------------------+---------------------------------------------+
|  DesiredCount    |  2                                          |
|  RunningCount    |  2                                          |
|  ServiceName     |  my-app-service                             |
|  Status          |  ACTIVE                                     |
+------------------+---------------------------------------------+

✅ Novo deployment iniciado!
⏳ Aguardando estabilização do serviço...
✅ Serviço reiniciado com sucesso!
```

## Casos de Uso

### 1. Reiniciar após atualização de secrets

```bash
# 1. Atualizar secrets
./scripts/update-ecs-secrets.sh \
  --family my-app \
  --cluster my-cluster \
  --service my-app-service \
  --file secrets.json

# 2. Reiniciar para aplicar mudanças
./scripts/restart-ecs-service.sh \
  my-cluster \
  my-app-service \
  my-app \
  us-east-1 \
  stg
```

### 2. Reiniciar após deploy de nova imagem

```bash
# Após fazer push de nova imagem Docker
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/app:v1.2.0

# Reiniciar serviço para usar nova imagem
./scripts/restart-ecs-service.sh \
  meu-cluster \
  meu-servico \
  minha-family \
  us-east-1 \
  prd
```

### 3. Reiniciar para resolver problemas

```bash
# Se o serviço estiver com problemas, reiniciar pode ajudar
./scripts/restart-ecs-service.sh \
  cluster-producao \
  app-service \
  app-family \
  us-east-1 \
  prd
```

### 4. Reiniciar múltiplos serviços

```bash
#!/bin/bash
# Script para reiniciar múltiplos serviços

SERVICES=(
  "cluster1:service1:family1"
  "cluster2:service2:family2"
  "cluster3:service3:family3"
)

for service_info in "${SERVICES[@]}"; do
  IFS=':' read -r cluster service family <<< "$service_info"
  echo "Reiniciando $service no cluster $cluster..."
  ./scripts/restart-ecs-service.sh "$cluster" "$service" "$family" us-east-1 prd
done
```

## Integração com Outros Scripts

### Fluxo completo: Atualizar secrets e reiniciar

```bash
#!/bin/bash
# Script completo de atualização

CLUSTER="my-cluster"
SERVICE="my-app-service"
FAMILY="my-app"
REGION="us-east-1"
PROFILE="stg"

# 1. Buscar secrets atualizados
./scripts/get-secrets.sh stg/vault -o secrets.json --profile "$PROFILE"

# 2. Atualizar Task Definition
./scripts/update-ecs-secrets.sh \
  --family "$FAMILY" \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --file secrets.json \
  --region "$REGION" \
  --profile "$PROFILE"

# 3. Reiniciar serviço
./scripts/restart-ecs-service.sh \
  "$CLUSTER" \
  "$SERVICE" \
  "$FAMILY" \
  "$REGION" \
  "$PROFILE"
```

## Solução de Problemas

### Erro: "Service not found"

**Causa**: O nome do serviço ou cluster está incorreto.

**Solução**:
```bash
# Listar serviços do cluster
aws ecs list-services --cluster meu-cluster --profile meu-perfil

# Verificar nome exato do serviço
aws ecs describe-services \
  --cluster meu-cluster \
  --services meu-servico \
  --profile meu-perfil
```

### Erro: "Access Denied"

**Causa**: Permissões IAM insuficientes.

**Solução**: Verificar e adicionar as permissões necessárias:
- `ecs:UpdateService`
- `ecs:DescribeServices`
- `ecs:DescribeTaskDefinition`

### Erro: "Task Definition not found"

**Causa**: O nome da família da Task Definition está incorreto.

**Solução**:
```bash
# Listar famílias de Task Definitions
aws ecs list-task-definition-families --profile meu-perfil

# Verificar Task Definition ativa do serviço
aws ecs describe-services \
  --cluster meu-cluster \
  --services meu-servico \
  --query 'services[0].taskDefinition' \
  --output text \
  --profile meu-perfil
```

### Timeout ao aguardar estabilização

**Causa**: O serviço está demorando muito para estabilizar.

**Solução**:
- Verificar logs das tasks: `aws ecs describe-tasks`
- Verificar eventos do serviço: `aws ecs describe-services`
- Verificar se há problemas de saúde nas tasks
- Considerar aumentar o timeout (modificar script se necessário)

### Serviço não reinicia

**Causa**: Possíveis problemas:
- Task Definition não existe
- Imagem Docker não encontrada
- Problemas de configuração

**Solução**:
```bash
# Verificar eventos do serviço
aws ecs describe-services \
  --cluster meu-cluster \
  --services meu-servico \
  --query 'services[0].events[:5]' \
  --output table \
  --profile meu-perfil

# Verificar tasks falhando
aws ecs list-tasks \
  --cluster meu-cluster \
  --service-name meu-servico \
  --desired-status STOPPED \
  --profile meu-perfil
```

## Boas Práticas

### 1. Verificar status antes de reiniciar

```bash
# Verificar status atual
aws ecs describe-services \
  --cluster meu-cluster \
  --services meu-servico \
  --query 'services[0].{Status:status,Desired:desiredCount,Running:runningCount}' \
  --output table \
  --profile meu-perfil
```

### 2. Usar em horários de baixo tráfego

Reiniciar serviços pode causar breve indisponibilidade. Prefira horários de menor tráfego.

### 3. Monitorar após reiniciar

```bash
# Monitorar logs após reiniciar
aws logs tail /aws/ecs/meu-servico --follow --profile meu-perfil
```

### 4. Verificar health checks

Após reiniciar, verificar se os health checks estão passando:

```bash
# Verificar health das tasks
aws ecs describe-tasks \
  --cluster meu-cluster \
  --tasks $(aws ecs list-tasks --cluster meu-cluster --service-name meu-servico --query 'taskArns[0]' --output text) \
  --query 'tasks[0].healthStatus' \
  --output text \
  --profile meu-perfil
```

## Diferenças entre Restart e Update

| Ação | Comando | Quando Usar |
|------|---------|-------------|
| **Restart** | `--force-new-deployment` | Reiniciar com mesma configuração |
| **Update (secrets)** | `update-ecs-secrets.sh` | Referências Secrets Manager na Task Definition |
| **Update (environment)** | `update-ecs-env.sh` | Variáveis literais (`environment`) na Task Definition |

**Restart** é útil quando:
- Aplicar mudanças de secrets já atualizadas
- Resolver problemas de aplicação
- Forçar recriação de tasks

**Update** é necessário quando:
- Mudar variáveis de ambiente literais (`scripts/update-ecs-env.sh`)
- Atualizar secrets referenciados na Task Definition (`scripts/update-ecs-secrets.sh`)
- Mudar outros campos da Task Definition (fora do escopo destes scripts)

## Referências

- [AWS ECS Update Service](https://docs.aws.amazon.com/cli/latest/reference/ecs/update-service.html)
- [AWS ECS Wait Services Stable](https://docs.aws.amazon.com/cli/latest/reference/ecs/wait/services-stable.html)
- [ECS Service Deployment](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-deployments.html)

