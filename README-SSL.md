# Configuração SSL com Certbot

Scripts para configurar e renovar certificados SSL usando Let's Encrypt (certbot) e configurar o virtual host do nginx.

## Para que serve

O script `setup-ssl.sh` automatiza a configuração completa de SSL para um domínio:
- Gera certificado SSL gratuito usando Let's Encrypt
- Configura nginx com HTTPS e redirecionamento HTTP → HTTPS
- Configura arquivos estáticos usando symlinks (não cópia)
- Suporta front-end estático ou API com proxy reverso
- **Suporta múltiplas aplicações na mesma instância** (não interfere com certificados existentes)
- Trata automaticamente erros de autorização e conflitos de porta

## Pré-requisitos

1. Nginx instalado e rodando
2. Domínio apontando para o IP do servidor
3. Portas 80 e 443 abertas no firewall
4. Acesso root/sudo no servidor

## Como executar

```bash
sudo ./scripts/setup-ssl.sh
```

O script é interativo e solicitará:
- Domínio
- Email para o certificado
- Tipo de configuração (front estático ou API)
- Caminho do diretório de build (para front estático)
- Caminho do diretório estático (STATIC_ROOT)
- Configuração de proxy reverso (se necessário)

## Funcionalidades Avançadas

### Suporte para Múltiplas Aplicações

O script foi projetado para funcionar de forma segura em instâncias com múltiplas aplicações usando certbot:

- **Verifica certificados existentes**: Antes de criar um novo certificado, verifica se já existe um válido para o domínio e o reutiliza
- **Limpeza seletiva**: Remove apenas tentativas pendentes do domínio específico, sem afetar certificados válidos de outras aplicações
- **Modo nginx preferencial**: Tenta primeiro obter o certificado usando o modo nginx (sem parar o servidor)
- **Fallback inteligente**: Se o modo nginx falhar, para o nginx temporariamente apenas para obter o certificado, depois reinicia automaticamente
- **Não interfere com outras aplicações**: Garante que certificados válidos de outras aplicações não sejam afetados

### Tratamento de Erros

O script trata automaticamente os seguintes problemas:

- **"No such authorization"**: Limpa tentativas pendentes que podem causar este erro
- **Porta 80 em uso**: Para o nginx temporariamente quando necessário para o modo standalone
- **Certificados expirados**: Detecta e renova certificados expirados automaticamente
- **Conflitos de autorização**: Remove apenas autorizações pendentes do domínio específico

## Arquivos Estáticos

O script cria **symlinks** do diretório de build para o STATIC_ROOT (padrão: `/var/www/<dominio>`). Isso permite atualizar os arquivos sem precisar copiá-los novamente.

### Atualizar arquivos após novo build

Os symlinks são criados automaticamente durante a configuração e não precisam ser refeitos. Para atualizar os arquivos após um novo build:

1. Navegue até o diretório do projeto onde está o build
2. Execute `sudo rm -rf dist/` para remover o diretório de build antigo
3. Execute `git pull` para baixar as atualizações
4. Faça o build novamente (se necessário)

Os symlinks continuarão funcionando porque apontam para o diretório de build que será atualizado com o novo conteúdo.

## Verificação

```bash
# Verificar certificado
sudo certbot certificates

# Testar SSL
curl -I https://<dominio>

# Ver logs do nginx
sudo tail -f /var/log/nginx/<dominio>-error.log
```

## Renovação

A renovação é automática via cron job do certbot. Para renovar manualmente:

```bash
sudo certbot renew
sudo systemctl reload nginx
```

## Problemas Comuns

### Erro 403 (Permission denied)

**Sintoma**: Nginx retorna erro 403 ao tentar servir arquivos estáticos, mesmo com symlinks criados.

**Causa**: O nginx precisa ter permissão de leitura nos arquivos originais do BUILD_PATH e permissão de execução em todos os diretórios do caminho até o BUILD_PATH.

**Solução manual**:

Execute os seguintes comandos na CLI, substituindo pelos seus caminhos reais:

**1. Identifique os caminhos absolutos:**

```bash
# Navegue até o diretório de build e obtenha o caminho absoluto
cd /caminho/para/build
pwd
# Anote o caminho retornado (ex: /home/usuario/projeto/dist)
```

**2. Corrija permissões em todos os diretórios do caminho até o BUILD_PATH:**

Execute `chmod 755` em cada diretório do caminho, começando da raiz. Por exemplo, se o BUILD_PATH for `/home/usuario/projeto/dist`:

```bash
sudo chmod 755 /home
sudo chmod 755 /home/usuario
sudo chmod 755 /home/usuario/projeto
sudo chmod 755 /home/usuario/projeto/dist
```

**3. Corrija permissões dos arquivos e diretórios dentro do BUILD_PATH:**

```bash
# Substitua pelo caminho absoluto do seu BUILD_PATH
sudo find /caminho/absoluto/do/build -type f -exec chmod 644 {} \;
sudo find /caminho/absoluto/do/build -type d -exec chmod 755 {} \;
```

**4. Corrija permissões do diretório pai do STATIC_ROOT:**

```bash
# Se o STATIC_ROOT for /var/www/meu.site, o pai é /var/www
sudo chmod 755 /var/www
```

**5. Corrija permissões do STATIC_ROOT:**

```bash
# Substitua pelo seu STATIC_ROOT
sudo chmod 755 /var/www/<dominio>
sudo chown -R www-data:www-data /var/www/<dominio>
```

**6. Teste e recarregue o nginx:**

```bash
sudo nginx -t
sudo systemctl reload nginx
```

### Erro: "Domain not pointing to this server"

- Verifique se o DNS está configurado corretamente
- Use `dig <dominio>` ou `nslookup <dominio>` para verificar

### Erro: "Port 80 is already in use"

**Sintoma**: Certbot falha ao usar modo standalone porque a porta 80 está em uso.

**Solução**: O script trata isso automaticamente:
1. Tenta primeiro o modo nginx (sem parar o servidor)
2. Se falhar, para o nginx temporariamente apenas para obter o certificado
3. Reinicia o nginx automaticamente após obter o certificado

Se o problema persistir:
- Verifique se há outro serviço usando a porta 80: `sudo netstat -tulpn | grep :80`
- Verifique se o nginx está rodando: `sudo systemctl status nginx`

### Erro: "No such authorization"

**Sintoma**: Certbot retorna erro "The request message was malformed :: No such authorization".

**Causa**: Tentativas anteriores de obter certificado deixaram autorizações pendentes inconsistentes.

**Solução**: O script trata isso automaticamente limpando apenas tentativas pendentes do domínio específico. Se o problema persistir:

```bash
# Limpar manualmente tentativas pendentes (apenas do domínio específico)
sudo rm -rf /var/lib/letsencrypt/archive/<dominio>
sudo rm -rf /var/lib/letsencrypt/live/<dominio>
sudo rm -rf /var/lib/letsencrypt/renewal/<dominio>.conf
```

**⚠️ Atenção**: Não execute `certbot delete` sem especificar o domínio, pois isso pode deletar certificados de outras aplicações.

### Certificado não renova automaticamente

- Verifique os logs: `sudo tail -f /var/log/letsencrypt/letsencrypt.log`
- Verifique o cron job: `sudo crontab -l`
- Execute renovação manual para testar

### Nginx não recarrega após renovação

- Adicione `--deploy-hook "systemctl reload nginx"` ao comando certbot
- Ou configure manualmente o hook no `/etc/letsencrypt/renewal/<dominio>.conf`

### Certificado não é criado mesmo com DNS correto

**Sintoma**: O script falha ao obter o certificado mesmo com DNS apontando corretamente.

**Soluções**:

1. **Verifique os logs detalhados**:
   ```bash
   sudo tail -f /var/log/letsencrypt/letsencrypt.log
   ```

2. **Verifique se a porta 80 está acessível externamente**:
   ```bash
   # De outro servidor ou máquina
   curl -I http://<dominio>/.well-known/acme-challenge/test
   ```

3. **Verifique rate limits do Let's Encrypt**:
   - Let's Encrypt tem limites de tentativas por domínio
   - Se você tentou muitas vezes, pode precisar aguardar algumas horas
   - Verifique: https://letsencrypt.org/docs/rate-limits/

4. **Execute o script com mais verbosidade**:
   ```bash
   sudo certbot certonly --nginx -d <dominio> -v
   ```

## Como o Script Funciona

### Fluxo de Obtenção de Certificado

1. **Verificação de certificado existente**: Verifica se já existe um certificado válido para o domínio
2. **Reutilização**: Se existir e estiver válido, reutiliza o certificado existente
3. **Limpeza seletiva**: Se não existir, limpa apenas tentativas pendentes do domínio específico
4. **Modo nginx**: Tenta primeiro obter o certificado usando o modo nginx (sem parar o servidor)
5. **Modo standalone (fallback)**: Se o modo nginx falhar:
   - Para o nginx temporariamente
   - Verifica se a porta 80 está livre
   - Obtém o certificado usando modo standalone
   - Reinicia o nginx automaticamente
6. **Tratamento de erros**: Em caso de falha, fornece mensagens claras e dicas para resolução

### Segurança para Múltiplas Aplicações

O script garante que:
- ✅ Não deleta certificados válidos de outras aplicações
- ✅ Limpa apenas tentativas pendentes do domínio específico
- ✅ Verifica validade antes de limpar qualquer coisa
- ✅ Para o nginx apenas quando necessário e por tempo mínimo
- ✅ Reinicia o nginx mesmo em caso de erro

## Boas Práticas

### Para Instâncias com Múltiplas Aplicações

1. **Use o script para cada domínio separadamente**: Execute o script uma vez para cada aplicação/domínio
2. **Não delete certificados manualmente**: Deixe o script gerenciar os certificados
3. **Verifique certificados existentes**: Antes de executar o script, veja quais certificados já existem:
   ```bash
   sudo certbot certificates
   ```
4. **Monitore logs**: Em caso de problemas, verifique os logs:
   ```bash
   sudo tail -f /var/log/letsencrypt/letsencrypt.log
   ```

### Renovação Automática

O certbot configura automaticamente um cron job para renovação. Para verificar:

```bash
# Verificar cron job do certbot
sudo systemctl list-timers | grep certbot

# Ou verificar diretamente
sudo cat /etc/cron.d/certbot
```

### Backup de Certificados

Embora os certificados sejam renovados automaticamente, é uma boa prática fazer backup periódico:

```bash
# Criar backup dos certificados
sudo tar -czf /backup/letsencrypt-$(date +%Y%m%d).tar.gz /etc/letsencrypt/live/
```

## Changelog

### Versão Atual (2026)

**Melhorias implementadas**:
- ✅ Suporte seguro para múltiplas aplicações na mesma instância
- ✅ Verificação e reutilização de certificados existentes
- ✅ Limpeza seletiva de tentativas pendentes (sem afetar outros certificados)
- ✅ Tratamento automático do erro "No such authorization"
- ✅ Tratamento automático de conflitos de porta 80
- ✅ Modo nginx preferencial (sem parar o servidor)
- ✅ Fallback inteligente para modo standalone quando necessário
- ✅ Mensagens de erro mais claras e dicas de resolução
- ✅ Verificação de validade de certificados antes de limpar
