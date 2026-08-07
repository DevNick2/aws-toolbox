# Script de Instalação e Configuração do Nginx e Firewall

Este script automatiza a instalação do nginx e a configuração do firewall (UFW) sincronizando com os grupos de segurança da AWS.

## Arquivo

- `setup-nginx-firewall.sh` - Script principal para instalar nginx e configurar firewall

## Funcionalidades

1. **Instalação do Nginx**
   - Instala o nginx se não estiver instalado
   - Inicia e habilita o serviço automaticamente

2. **Configuração do Firewall (UFW)**
   - Instala e configura o UFW (Uncomplicated Firewall)
   - Sincroniza regras com os Security Groups da AWS
   - Garante que as portas essenciais (22, 80, 443) estão abertas

3. **Sincronização com AWS**
   - Detecta automaticamente a instância EC2
   - Obtém os Security Groups associados
   - Aplica todas as regras de entrada no firewall local

## Pré-requisitos

1. **Executar como root ou com sudo**
   ```bash
   sudo ./scripts/setup-nginx-firewall.sh
   ```

2. **AWS CLI configurado**
   - AWS CLI instalado
   - Credenciais configuradas (`aws configure`)
   - Permissões adequadas para:
     - `ec2:DescribeInstances`
     - `ec2:DescribeSecurityGroups`

3. **Instância EC2**
   - O script detecta automaticamente se está rodando em uma instância EC2
   - Se não conseguir detectar, permite entrada manual do Instance ID

## Como Usar

### Execução Básica

```bash
sudo ./scripts/setup-nginx-firewall.sh
```

### Execução em Instância EC2

O script detecta automaticamente:
- Instance ID via metadata da instância
- Security Groups associados
- Regras de entrada dos Security Groups

### Execução Fora da EC2

Se não estiver em uma instância EC2, o script solicitará:
- Instance ID manual (ou pode pular a sincronização AWS)
- Ainda assim, as portas essenciais (22, 80, 443) serão liberadas

## O que o Script Faz

### 1. Instalação do Nginx
- Atualiza repositórios
- Instala nginx (se necessário)
- Inicia e habilita o serviço

### 2. Configuração do Firewall
- Instala UFW e jq (se necessário)
- Verifica configuração do AWS CLI
- Obtém informações da instância EC2
- Sincroniza regras dos Security Groups
- Garante portas essenciais abertas
- Habilita o firewall

### 3. Portas Garantidas
- **Porta 22** (SSH) - Sempre liberada
- **Porta 80** (HTTP) - Sempre liberada
- **Porta 443** (HTTPS) - Sempre liberada

## Exemplo de Saída

```
🚀 Iniciando instalação e configuração do nginx e firewall...
ℹ️  Instalando nginx...
✅ Nginx instalado com sucesso
✅ Nginx iniciado e habilitado
ℹ️  Configurando firewall (UFW)...
ℹ️  Obtendo informações da instância EC2...
ℹ️  Sincronizando regras dos Security Groups da AWS...
ℹ️  Security Groups encontrados: sg-12345678 sg-87654321
ℹ️  Processando Security Group: sg-12345678
ℹ️  Aplicando: ufw allow 22/tcp comment "SSH"
✅ Porta 22 (SSH) liberada
✅ Porta 80 (HTTP) liberada
✅ Porta 443 (HTTPS) liberada
✅ Regras dos Security Groups sincronizadas
✅ Firewall configurado e ativado
```

## Verificação

### Verificar Status do Firewall

```bash
sudo ufw status verbose
```

### Ver Regras Numeradas

```bash
sudo ufw status numbered
```

### Verificar Nginx

```bash
sudo systemctl status nginx
```

### Testar Nginx

```bash
curl http://localhost
```

## Troubleshooting

### Erro: "AWS CLI não está configurado"

Configure as credenciais da AWS:
```bash
aws configure
```

Ou defina variáveis de ambiente:
```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

### Erro: "Não foi possível obter o Instance ID"

Se não estiver em uma instância EC2:
1. O script solicitará o Instance ID manualmente
2. Ou pressione Enter para pular a sincronização AWS
3. As portas essenciais ainda serão liberadas

### Erro: "Permissões insuficientes"

Certifique-se de que o usuário/IAM role tem permissões:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeSecurityGroups"
      ],
      "Resource": "*"
    }
  ]
}
```

### Firewall Bloqueando Acesso

Se o firewall bloquear seu acesso:
```bash
# Desabilitar temporariamente (CUIDADO!)
sudo ufw disable

# Ou adicionar regra específica
sudo ufw allow from SEU_IP to any port 22
```

## Notas Importantes

⚠️ **CUIDADO**: 
- Certifique-se de que o SSH está acessível antes de fechar a sessão
- O script configura o firewall para negar tráfego de entrada por padrão
- Apenas as regras explicitamente permitidas funcionarão

🔒 **Segurança**:
- O script sincroniza apenas regras de entrada (Ingress)
- Regras de saída (Egress) não são afetadas
- O firewall é configurado para permitir saída por padrão

🔄 **Sincronização**:
- A sincronização é feita uma vez durante a execução do script
- Para atualizar regras após mudanças nos Security Groups, execute o script novamente
- Ou adicione regras manualmente com `ufw allow`

## Comandos Úteis

### Adicionar Regra Manualmente

```bash
# Permitir porta específica
sudo ufw allow 8080/tcp

# Permitir de IP específico
sudo ufw allow from 192.168.1.100 to any port 22

# Permitir range de portas
sudo ufw allow 8000:9000/tcp
```

### Remover Regra

```bash
# Ver regras numeradas
sudo ufw status numbered

# Deletar regra por número
sudo ufw delete 3
```

### Recarregar Firewall

```bash
sudo ufw reload
```

### Ver Logs do Firewall

```bash
sudo tail -f /var/log/ufw.log
```

