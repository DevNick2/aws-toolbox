Processo de implantação de uma aplicação saas:

Atributos:

- Repositórios diferentes
- Usa o Github Actions para as CD
- Usa o Secrets Manager para gerenciar os segredos
- A API é em NestJS/Typescript 100% Docker;
- A API é servida em um ECS com Tasks de EC2
- O APP é feito em React com Vite
- O APP é servido em um Amplify
- API Gateway para servir a API
- Cognito para IAM


Processo de deploy Amplify:

1) Implantar o APP com Github
2) Criar as API Keys no API Gateway
3) Configurar as Variaveis de Ambiente
4) Adicionar o dominio customizável

Processo de deploy Amplify: