# Build e Empacotamento de Front-end

Script para executar build de aplicações front-end e empacotar o resultado em arquivo ZIP.

## Para que serve

O script `build-and-package.sh` automatiza o processo de:
- Executar build de aplicações front-end (React, Vue, Angular, etc.)
- Empacotar o resultado em um arquivo ZIP
- Detectar automaticamente o gerenciador de pacotes (npm ou yarn)
- Validar se o build foi criado corretamente

## Pré-requisitos

1. **Node.js** instalado (npm ou yarn)
2. **zip** instalado (`sudo apt-get install -y zip`)
3. Projeto com `package.json` e script de build configurado

### Verificar instalação

```bash
# Verificar Node.js
node --version
npm --version

# Verificar Yarn (opcional)
yarn --version

# Instalar zip se necessário
sudo apt-get install -y zip
```

## Uso Básico

### Build e empacotamento simples

```bash
# No diretório do projeto
cd /caminho/do/projeto
./scripts/build-and-package.sh
```

O script irá:
1. Detectar automaticamente se usa npm ou yarn
2. Executar o build (`npm run build` ou `yarn build`)
3. Criar um arquivo ZIP com o conteúdo do diretório `dist`
4. Nomear o arquivo automaticamente: `projeto-build-YYYYMMDD-HHMMSS.zip`

### Especificar diretório e nome do arquivo

```bash
./scripts/build-and-package.sh -d ./meu-projeto -o build.zip
```

### Forçar uso de yarn ou npm

```bash
# Forçar uso de yarn
./scripts/build-and-package.sh -m yarn

# Forçar uso de npm
./scripts/build-and-package.sh -m npm
```

## Opções Disponíveis

| Opção | Descrição |
|-------|-----------|
| `-d, --dir <diretorio>` | Diretório do projeto (padrão: diretório atual) |
| `-b, --build-dir <dir>` | Diretório de build (padrão: `dist`) |
| `-o, --output <arquivo>` | Nome do arquivo ZIP de saída |
| `-m, --manager <npm\|yarn>` | Força uso de npm ou yarn (padrão: auto-detecta) |
| `--skip-build` | Pula o build e apenas empacota o diretório existente |
| `--no-clean` | Não limpa o diretório de build antes de construir |
| `--keep-build-dir` | Mantém o diretório de build após criar o ZIP |
| `-h, --help` | Mostra a ajuda |

## Exemplos de Uso

### Exemplo 1: Build básico

```bash
cd /home/user/meu-projeto
./scripts/build-and-package.sh
```

**Saída esperada:**
```
🔨 Build e Empacotamento de Front-end
======================================

📁 Diretório do projeto: /home/user/meu-projeto
📁 Diretório de build: dist

✓ Gerenciador detectado: npm

📦 Executando build com npm...
✓ Build concluído com sucesso

📦 Criando arquivo ZIP...
✓ Arquivo ZIP criado: /home/user/meu-projeto-build-20240128-180530.zip
   Tamanho: 2.5M

📄 Arquivos incluídos (primeiros 10):
   dist/index.html
   dist/assets/index-abc123.js
   ...
   ... total de 45 arquivos

✅ Processo concluído com sucesso!
```

### Exemplo 2: Build com nome específico

```bash
./scripts/build-and-package.sh -o app-production-v1.0.0.zip
```

### Exemplo 3: Build de outro diretório

```bash
./scripts/build-and-package.sh -d ../outro-projeto -o outro-build.zip
```

### Exemplo 4: Apenas empacotar build existente

```bash
# Útil quando você já executou o build manualmente
./scripts/build-and-package.sh --skip-build -o backup-build.zip
```

### Exemplo 5: Build sem limpar diretório anterior

```bash
# Útil para builds incrementais
./scripts/build-and-package.sh --no-clean
```

### Exemplo 6: Manter diretório de build após criar ZIP

```bash
# Útil quando você precisa do diretório de build após empacotar
./scripts/build-and-package.sh --keep-build-dir -o build.zip
```

### Exemplo 7: Build com diretório customizado

```bash
# Se o projeto usa 'build' ao invés de 'dist'
./scripts/build-and-package.sh --build-dir build -o build.zip
```

## Detecção Automática de Gerenciador

O script detecta automaticamente qual gerenciador usar na seguinte ordem:

1. **yarn.lock** presente → usa `yarn`
2. **package-lock.json** presente → usa `npm`
3. Comando disponível → usa o primeiro encontrado (`yarn` ou `npm`)

### Forçar uso manual

Se quiser forçar o uso de um gerenciador específico:

```bash
./scripts/build-and-package.sh -m yarn
# ou
./scripts/build-and-package.sh -m npm
```

## Configuração do package.json

O script espera que o `package.json` tenha um script de build configurado:

```json
{
  "name": "meu-projeto",
  "scripts": {
    "build": "vite build"
    // ou
    "build": "react-scripts build"
    // ou
    "build": "ng build --prod"
  }
}
```

### Verificar script de build

```bash
# Ver scripts disponíveis
npm run
# ou
yarn run
```

## Fluxos de Trabalho Comuns

### 1. Build para produção

```bash
# No diretório do projeto
cd /caminho/do/projeto

# Executar build e empacotar
./scripts/build-and-package.sh -o producao-$(date +%Y%m%d).zip
```

### 2. Build para deploy em servidor

```bash
# Build e empacotar
./scripts/build-and-package.sh -o deploy.zip

# Transferir para servidor
scp deploy.zip user@servidor:/tmp/

# No servidor, extrair e atualizar
ssh user@servidor
cd /tmp
unzip -o /tmp/deploy.zip -d /tmp/build-extracted
cd /var/www/app
# Os arquivos estarão em /tmp/build-extracted/ (index.html, assets/, etc.)
# ou usar update-build-symlinks.sh se configurado
```

### 3. Backup de build

```bash
# Criar backup antes de fazer alterações
./scripts/build-and-package.sh --skip-build -o backup-$(date +%Y%m%d).zip
```

### 4. Build em CI/CD

```bash
# Em pipeline CI/CD
npm ci  # ou yarn install --frozen-lockfile
./scripts/build-and-package.sh -o build-artifact.zip

# Fazer upload do artifact
# (depende da plataforma: GitHub Actions, GitLab CI, etc.)
```

### 5. Build múltiplos projetos

```bash
#!/bin/bash
# Script para buildar múltiplos projetos

PROJECTS=("projeto1" "projeto2" "projeto3")

for project in "${PROJECTS[@]}"; do
    echo "Building $project..."
    ./scripts/build-and-package.sh -d "./$project" -o "${project}-build.zip"
done
```

## Integração com Outros Scripts

### Após build, atualizar symlinks no servidor

```bash
# 1. Build e empacotar
./scripts/build-and-package.sh -o build.zip

# 2. Transferir para servidor
scp build.zip user@servidor:/tmp/

# 3. No servidor: extrair e atualizar symlinks
ssh user@servidor
cd /tmp
unzip -o /tmp/build.zip -d /tmp/build-extracted
./scripts/update-build-symlinks.sh /tmp/build-extracted /var/www/app

### Build e deploy completo

```bash
#!/bin/bash
# Script de deploy completo

# Build e empacotar
./scripts/build-and-package.sh -o deploy.zip

# Transferir para servidor
scp deploy.zip user@servidor:/tmp/deploy.zip

# No servidor: extrair e atualizar
# No servidor: extrair e atualizar
ssh user@servidor << 'EOF'
cd /tmp
unzip -o /tmp/deploy.zip -d /tmp/build-extracted
./scripts/update-build-symlinks.sh /tmp/build-extracted /var/www/app
sudo systemctl reload nginx
EOF

## Solução de Problemas

### Erro: "package.json não encontrado"

**Causa**: O script não encontrou o `package.json` no diretório especificado.

**Solução**:
```bash
# Verificar se está no diretório correto
pwd
ls -la package.json

# Especificar o diretório correto
./scripts/build-and-package.sh -d /caminho/correto/do/projeto
```

### Erro: "Nenhum gerenciador de pacotes encontrado"

**Causa**: Nem npm nem yarn estão instalados.

**Solução**:
```bash
# Instalar Node.js e npm
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Ou instalar yarn
npm install -g yarn
```

### Erro: "Diretório de build não foi criado"

**Causa**: O script de build não está configurado corretamente no `package.json`.

**Solução**:
```bash
# Verificar scripts disponíveis
cat package.json | grep -A 5 '"scripts"'

# Verificar se o script de build existe
npm run build
# ou
yarn build
```

### Erro: "Diretório de build está vazio"

**Causa**: O build foi executado mas não gerou arquivos.

**Solução**:
- Verificar logs do build para erros
- Verificar configuração do bundler (Vite, Webpack, etc.)
- Verificar se há erros de compilação

### Erro: "zip: command not found"

**Causa**: O comando `zip` não está instalado.

**Solução**:
```bash
sudo apt-get install -y zip
```

### Build muito lento

**Dicas**:
- Use `--no-clean` para builds incrementais (se suportado pelo bundler)
- Verifique se há muitas dependências desnecessárias
- Considere usar cache de dependências em CI/CD

## Boas Práticas

### 1. Versionamento de builds

```bash
# Incluir versão no nome do arquivo
VERSION=$(node -p "require('./package.json').version")
./scripts/build-and-package.sh -o "app-v${VERSION}.zip"
```

### 2. Builds com timestamp

```bash
# O script já adiciona timestamp automaticamente
# Mas você pode customizar:
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
./scripts/build-and-package.sh -o "build-${TIMESTAMP}.zip"
```

### 3. Verificar tamanho do build

```bash
# Após criar o ZIP, verificar tamanho
./scripts/build-and-package.sh -o build.zip
du -h build.zip
```

### 4. Validar conteúdo do ZIP

```bash
# Listar conteúdo do ZIP
unzip -l build.zip

# Testar extração
unzip -t build.zip
```

### 5. Limpar builds antigos

```bash
# Remover builds antigos (manter apenas últimos 5)
ls -t *.zip | tail -n +6 | xargs rm -f
```

## Estrutura do Arquivo ZIP

O arquivo ZIP criado contém o **conteúdo** do diretório de build diretamente na raiz:

```
build.zip
├── index.html
├── assets/
│   ├── index-abc123.js
│   ├── index-def456.css
│   └── ...
└── ...
```

**Importante**: O ZIP contém os arquivos diretamente na raiz, não dentro de um diretório `dist/`. Isso facilita a extração e deploy.

Para extrair:

```bash
unzip build.zip
# Isso extrairá os arquivos diretamente no diretório atual
# index.html, assets/, etc. estarão na raiz
```

Para extrair em um diretório específico:

```bash
unzip build.zip -d /var/www/app
# Isso extrairá os arquivos em /var/www/app/
```

## Referências

- [npm Documentation](https://docs.npmjs.com/)
- [Yarn Documentation](https://yarnpkg.com/docs)
- [Vite Build](https://vitejs.dev/guide/build.html)
- [Create React App Build](https://create-react-app.dev/docs/production-build/)

