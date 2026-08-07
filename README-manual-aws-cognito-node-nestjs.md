# Manual de Implementação - AWS Cognito com Custom UI

## Visão Geral

Este manual detalha a implementação completa do AWS Cognito na aplicação utilizando **Custom UI** (sem Hosted UI), suportando:
- ✅ Login com email e senha
- ✅ Login social (Google, Facebook, Apple)
- ✅ Desenvolvimento e teste local com LocalStack

---

## 1. Dependências e Configuração Inicial

### 1.1 Instalar Dependências

```bash
# AWS Cognito SDK
yarn add @aws-sdk/client-cognito-identity-provider

# Para login social (Google)
yarn add google-auth-library

# Para validação de tokens JWT
yarn add jsonwebtoken jwks-rsa

# Para cookie no login do Bull Dashboard (seção 16)
yarn add cookie-parser

# Para geração de PKCE (se necessário)
yarn add crypto

# Tipos TypeScript
yarn add -D @types/jsonwebtoken @types/node @types/cookie-parser
```

### 1.2 Adicionar Variáveis de Ambiente

Adicionar ao `.env.example` e `.env.development`:

```env
# AWS Cognito - Configuração Básica
AWS_REGION=us-east-1
AWS_COGNITO_USER_POOL_ID=
AWS_COGNITO_CLIENT_ID=
AWS_COGNITO_CLIENT_SECRET=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=

# Para desenvolvimento local (LocalStack)
AWS_ENDPOINT_URL=http://localhost:4566
USE_LOCALSTACK=true

# Social Login - Google
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_REDIRECT_URI=http://localhost:3000/auth/callback/google

# Social Login - Facebook
FACEBOOK_APP_ID=
FACEBOOK_APP_SECRET=
FACEBOOK_REDIRECT_URI=http://localhost:3000/auth/callback/facebook

# Social Login - Apple
APPLE_CLIENT_ID=
APPLE_TEAM_ID=
APPLE_KEY_ID=
APPLE_PRIVATE_KEY=
APPLE_REDIRECT_URI=http://localhost:3000/auth/callback/apple

# URLs de Callback
FRONTEND_URL=http://localhost:3000
BACKEND_URL=http://localhost:3000
```

---

## 2. Configuração Docker Compose para LocalStack

### 2.1 Adicionar Serviço LocalStack ao `docker-compose.yml`

```yaml
localstack:
  image: localstack/localstack:latest
  container_name: localstack
  restart: unless-stopped
  ports:
    - "4566:4566"
    - "4510-4559:4510-4559"
  environment:
    - SERVICES=cognito-idp
    - DEBUG=1
    - DATA_DIR=/tmp/localstack/data
    - DOCKER_HOST=unix:///var/run/docker.sock
  volumes:
    - localstack-data:/tmp/localstack
    - /var/run/docker.sock:/var/run/docker.sock
  networks:
    - commerce_platform_network
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:4566/_localstack/health"]
    interval: 10s
    timeout: 5s
    retries: 5
```

### 2.2 Adicionar Volume no docker-compose.yml

```yaml
volumes:
  # ... volumes existentes
  localstack-data:
    driver: local
```

---

## 3. Estrutura de Módulos e Serviços

### 3.1 Criar Estrutura de Diretórios

```
src/modules/auth/
├── cognito/
│   ├── cognito.module.ts
│   ├── cognito.service.ts
│   └── cognito.service.spec.ts
├── controllers/
│   ├── auth.controller.ts
│   └── social-auth.controller.ts
├── dto/
│   ├── sign-up.dto.ts
│   ├── sign-in.dto.ts
│   ├── confirm-sign-up.dto.ts
│   ├── forgot-password.dto.ts
│   ├── confirm-forgot-password.dto.ts
│   ├── change-password.dto.ts
│   ├── refresh-token.dto.ts
│   └── social-login.dto.ts
├── services/
│   ├── user-sync.service.ts
│   ├── google-auth.service.ts
│   ├── facebook-auth.service.ts
│   └── apple-auth.service.ts
└── auth.module.ts
```

### 3.2 Criar Módulo Cognito

**`src/modules/auth/cognito/cognito.module.ts`**

```typescript
import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { CognitoService } from './cognito.service';
import { CognitoIdentityProviderClient } from '@aws-sdk/client-cognito-identity-provider';

@Module({
  imports: [ConfigModule],
  providers: [
    CognitoService,
    {
      provide: 'COGNITO_CLIENT',
      useFactory: (configService: ConfigService) => {
        const config: any = {
          region: configService.get('AWS_REGION'),
        };

        if (configService.get('USE_LOCALSTACK') === 'true') {
          config.endpoint = configService.get('AWS_ENDPOINT_URL');
        }

        return new CognitoIdentityProviderClient(config);
      },
      inject: [ConfigService],
    },
  ],
  exports: [CognitoService],
})
export class CognitoModule {}
```

### 3.3 Criar Serviço Cognito - Métodos Básicos

**`src/modules/auth/cognito/cognito.service.ts`**

Implementar os seguintes métodos:

#### Métodos de Autenticação com Email/Senha:

1. **`signUp(email: string, password: string, attributes: Record<string, string>)`**
   - Usa `SignUpCommand` do AWS SDK
   - Retorna `UserSub` e `CodeDeliveryDetails`
   - Valida senha antes de enviar ao Cognito

2. **`confirmSignUp(username: string, confirmationCode: string)`**
   - Usa `ConfirmSignUpCommand`
   - Confirma registro do usuário

3. **`signIn(username: string, password: string)`**
   - Usa `InitiateAuthCommand` com `AuthFlow: 'USER_PASSWORD_AUTH'`
   - Retorna `AccessToken`, `IdToken`, `RefreshToken`
   - Trata `NEW_PASSWORD_REQUIRED` challenge se necessário

4. **`respondToAuthChallenge(username: string, challengeName: string, session: string, responses: Record<string, string>)`**
   - Usa `RespondToAuthChallengeCommand`
   - Responde a challenges como `NEW_PASSWORD_REQUIRED`, `MFA_SETUP`, etc.

5. **`refreshToken(refreshToken: string)`**
   - Usa `InitiateAuthCommand` com `AuthFlow: 'REFRESH_TOKEN_AUTH'`
   - Retorna novos tokens

6. **`signOut(accessToken: string)`**
   - Usa `GlobalSignOutCommand` ou `AdminUserGlobalSignOutCommand`
   - Invalida todos os tokens do usuário

7. **`forgotPassword(username: string)`**
   - Usa `ForgotPasswordCommand`
   - Envia código de verificação por email/SMS

8. **`confirmForgotPassword(username: string, confirmationCode: string, newPassword: string)`**
   - Usa `ConfirmForgotPasswordCommand`
   - Confirma nova senha

9. **`changePassword(accessToken: string, previousPassword: string, proposedPassword: string)`**
   - Usa `ChangePasswordCommand`
   - Altera senha do usuário autenticado

10. **`getUser(accessToken: string)`**
    - Usa `GetUserCommand`
    - Retorna informações do usuário

11. **`updateUserAttributes(accessToken: string, attributes: Record<string, string>)`**
    - Usa `UpdateUserAttributesCommand`
    - Atualiza atributos do usuário

12. **`adminGetUser(username: string)`**
    - Usa `AdminGetUserCommand`
    - Obtém informações do usuário (requer permissões admin)

13. **`adminCreateUser(email: string, temporaryPassword: string, attributes: Record<string, string>)`**
    - Usa `AdminCreateUserCommand`
    - Cria usuário sem confirmação (útil para login social)

14. **`adminSetUserPassword(username: string, password: string, permanent: boolean)`**
    - Usa `AdminSetUserPasswordCommand`
    - Define senha do usuário (útil após login social)

---

## 4. Login Social - Implementação Custom UI

### 4.1 Configurar OAuth Apps nos Providers

#### Google Cloud Console:
1. Criar projeto no Google Cloud Console
2. Habilitar Google+ API
3. Criar OAuth 2.0 Client ID
4. Configurar authorized redirect URIs: `http://localhost:3000/auth/callback/google`
5. Obter Client ID e Client Secret

#### Facebook Developers:
1. Criar app no Facebook Developers
2. Adicionar Facebook Login product
3. Configurar OAuth Redirect URIs: `http://localhost:3000/auth/callback/facebook`
4. Obter App ID e App Secret

#### Apple Developer:
1. Criar App ID no Apple Developer
2. Configurar Sign in with Apple capability
3. Criar Service ID
4. Configurar Return URLs: `http://localhost:3000/auth/callback/apple`
5. Gerar Private Key e obter Key ID e Team ID

### 4.2 Criar Serviço de Autenticação Google

**`src/modules/auth/services/google-auth.service.ts`**

```typescript
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OAuth2Client } from 'google-auth-library';
import { CognitoService } from '../cognito/cognito.service';

@Injectable()
export class GoogleAuthService {
  private oauth2Client: OAuth2Client;

  constructor(
    private configService: ConfigService,
    private cognitoService: CognitoService,
  ) {
    this.oauth2Client = new OAuth2Client(
      this.configService.get('GOOGLE_CLIENT_ID'),
      this.configService.get('GOOGLE_CLIENT_SECRET'),
      this.configService.get('GOOGLE_REDIRECT_URI'),
    );
  }

  getAuthUrl(state?: string): string {
    const scopes = ['openid', 'email', 'profile'];
    return this.oauth2Client.generateAuthUrl({
      access_type: 'offline',
      scope: scopes,
      state,
      prompt: 'consent',
    });
  }

  async handleCallback(code: string) {
    const { tokens } = await this.oauth2Client.getToken(code);
    const ticket = await this.oauth2Client.verifyIdToken({
      idToken: tokens.id_token,
      audience: this.configService.get('GOOGLE_CLIENT_ID'),
    });

    const payload = ticket.getPayload();
    return {
      email: payload.email,
      name: payload.name,
      picture: payload.picture,
      sub: payload.sub,
      idToken: tokens.id_token,
      accessToken: tokens.access_token,
    };
  }

  async authenticateWithCognito(googleUser: any) {
    // Verificar se usuário existe no Cognito
    let cognitoUser;
    try {
      cognitoUser = await this.cognitoService.adminGetUser(googleUser.email);
    } catch (error) {
      // Usuário não existe, criar
      cognitoUser = await this.cognitoService.adminCreateUser(
        googleUser.email,
        this.generateTemporaryPassword(),
        {
          email: googleUser.email,
          name: googleUser.name,
          picture: googleUser.picture,
          'custom:google_id': googleUser.sub,
        },
      );
    }

    // Autenticar no Cognito usando SRP ou AdminInitiateAuth
    const tokens = await this.cognitoService.adminInitiateAuth(
      cognitoUser.Username,
    );

    return tokens;
  }

  private generateTemporaryPassword(): string {
    return Math.random().toString(36).slice(-12) + 'A1!';
  }
}
```
---

## 5. DTOs de Autenticação

### 5.1 DTOs Básicos

**`src/modules/auth/dto/sign-up.dto.ts`**

```typescript
import { IsEmail, IsString, MinLength, IsOptional } from 'class-validator';

export class SignUpDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(8)
  password: string;

  @IsString()
  @IsOptional()
  name?: string;

  @IsString()
  @IsOptional()
  phone?: string;
}
```

**`src/modules/auth/dto/sign-in.dto.ts`**

```typescript
import { IsEmail, IsString } from 'class-validator';

export class SignInDto {
  @IsEmail()
  email: string;

  @IsString()
  password: string;
}
```

**`src/modules/auth/dto/confirm-sign-up.dto.ts`**

```typescript
import { IsEmail, IsString } from 'class-validator';

export class ConfirmSignUpDto {
  @IsEmail()
  email: string;

  @IsString()
  confirmationCode: string;
}
```

**`src/modules/auth/dto/forgot-password.dto.ts`**

```typescript
import { IsEmail } from 'class-validator';

export class ForgotPasswordDto {
  @IsEmail()
  email: string;
}
```

**`src/modules/auth/dto/confirm-forgot-password.dto.ts`**

```typescript
import { IsEmail, IsString, MinLength } from 'class-validator';

export class ConfirmForgotPasswordDto {
  @IsEmail()
  email: string;

  @IsString()
  confirmationCode: string;

  @IsString()
  @MinLength(8)
  newPassword: string;
}
```

**`src/modules/auth/dto/change-password.dto.ts`**

```typescript
import { IsString, MinLength } from 'class-validator';

export class ChangePasswordDto {
  @IsString()
  previousPassword: string;

  @IsString()
  @MinLength(8)
  proposedPassword: string;
}
```

**`src/modules/auth/dto/refresh-token.dto.ts`**

```typescript
import { IsString } from 'class-validator';

export class RefreshTokenDto {
  @IsString()
  refreshToken: string;
}
```

**`src/modules/auth/dto/social-login.dto.ts`**

```typescript
import { IsEnum, IsString, IsOptional } from 'class-validator';

export enum SocialProvider {
  GOOGLE = 'google',
}

export class SocialLoginDto {
  @IsEnum(SocialProvider)
  provider: SocialProvider;

  @IsString()
  @IsOptional()
  state?: string;
}
```

---

## 6. Controllers de Autenticação

### 6.1 Controller de Autenticação Básica

**`src/modules/auth/controllers/auth.controller.ts`**

```typescript
import {
  Controller,
  Post,
  Get,
  Body,
  UseGuards,
  Request,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { CognitoService } from '../cognito/cognito.service';
import { SignUpDto } from '../dto/sign-up.dto';
import { SignInDto } from '../dto/sign-in.dto';
import { ConfirmSignUpDto } from '../dto/confirm-sign-up.dto';
import { ForgotPasswordDto } from '../dto/forgot-password.dto';
import { ConfirmForgotPasswordDto } from '../dto/confirm-forgot-password.dto';
import { ChangePasswordDto } from '../dto/change-password.dto';
import { RefreshTokenDto } from '../dto/refresh-token.dto';
import { AuthGuard } from 'src/shared/guard/auth.guard';

@ApiTags('Authentication')
@Controller('auth')
export class AuthController {
  constructor(private cognitoService: CognitoService) {}

  @Post('sign-up')
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @ApiOperation({ summary: 'Registrar novo usuário' })
  async signUp(@Body() signUpDto: SignUpDto) {
    return this.cognitoService.signUp(
      signUpDto.email,
      signUpDto.password,
      {
        email: signUpDto.email,
        name: signUpDto.name,
        phone_number: signUpDto.phone,
      },
    );
  }

  @Post('confirm-sign-up')
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @ApiOperation({ summary: 'Confirmar registro com código' })
  async confirmSignUp(@Body() confirmSignUpDto: ConfirmSignUpDto) {
    return this.cognitoService.confirmSignUp(
      confirmSignUpDto.email,
      confirmSignUpDto.confirmationCode,
    );
  }

  @Post('sign-in')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @ApiOperation({ summary: 'Login com email e senha' })
  async signIn(@Body() signInDto: SignInDto) {
    return this.cognitoService.signIn(signInDto.email, signInDto.password);
  }

  @Post('refresh-token')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Renovar tokens de acesso' })
  async refreshToken(@Body() refreshTokenDto: RefreshTokenDto) {
    return this.cognitoService.refreshToken(refreshTokenDto.refreshToken);
  }

  @Post('sign-out')
  @UseGuards(AuthGuard)
  @ApiBearerAuth()
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Logout' })
  async signOut(@Request() req) {
    const accessToken = req.headers.authorization?.replace('Bearer ', '');
    return this.cognitoService.signOut(accessToken);
  }

  @Post('forgot-password')
  @Throttle({ default: { limit: 3, ttl: 60000 } })
  @ApiOperation({ summary: 'Solicitar recuperação de senha' })
  async forgotPassword(@Body() forgotPasswordDto: ForgotPasswordDto) {
    return this.cognitoService.forgotPassword(forgotPasswordDto.email);
  }

  @Post('confirm-forgot-password')
  @Throttle({ default: { limit: 3, ttl: 60000 } })
  @ApiOperation({ summary: 'Confirmar nova senha' })
  async confirmForgotPassword(
    @Body() confirmForgotPasswordDto: ConfirmForgotPasswordDto,
  ) {
    return this.cognitoService.confirmForgotPassword(
      confirmForgotPasswordDto.email,
      confirmForgotPasswordDto.confirmationCode,
      confirmForgotPasswordDto.newPassword,
    );
  }

  @Post('change-password')
  @UseGuards(AuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Alterar senha' })
  async changePassword(
    @Request() req,
    @Body() changePasswordDto: ChangePasswordDto,
  ) {
    const accessToken = req.headers.authorization?.replace('Bearer ', '');
    return this.cognitoService.changePassword(
      accessToken,
      changePasswordDto.previousPassword,
      changePasswordDto.proposedPassword,
    );
  }

  @Get('me')
  @UseGuards(AuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Obter dados do usuário autenticado' })
  async getMe(@Request() req) {
    const accessToken = req.headers.authorization?.replace('Bearer ', '');
    return this.cognitoService.getUser(accessToken);
  }
}
```

### 6.2 Controller de Login Social

**`src/modules/auth/controllers/social-auth.controller.ts`**

```typescript
import {
  Controller,
  Get,
  Post,
  Query,
  Body,
  Param,
  Res,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import { Response } from 'express';
import { GoogleAuthService } from '../services/google-auth.service';
import { FacebookAuthService } from '../services/facebook-auth.service';
import { AppleAuthService } from '../services/apple-auth.service';
import { SocialProvider } from '../dto/social-login.dto';
import { UserSyncService } from '../services/user-sync.service';

@ApiTags('Social Authentication')
@Controller('auth/social')
export class SocialAuthController {
  constructor(
    private googleAuthService: GoogleAuthService,
    private facebookAuthService: FacebookAuthService,
    private appleAuthService: AppleAuthService,
    private userSyncService: UserSyncService,
  ) {}

  @Get(':provider')
  @ApiOperation({ summary: 'Iniciar login social' })
  async initiateSocialLogin(
    @Param('provider') provider: SocialProvider,
    @Query('state') state?: string,
    @Res() res?: Response,
  ) {
    let authUrl: string;

    switch (provider) {
      case SocialProvider.GOOGLE:
        authUrl = this.googleAuthService.getAuthUrl(state);
        break;
      default:
        throw new Error('Provider não suportado');
    }

    return res.redirect(authUrl);
  }

  @Get('callback/google')
  @ApiOperation({ summary: 'Callback do Google OAuth' })
  async handleGoogleCallback(
    @Query('code') code: string,
    @Query('state') state: string,
    @Res() res: Response,
  ) {
    try {
      const googleUser = await this.googleAuthService.handleCallback(code);
      const cognitoTokens = await this.googleAuthService.authenticateWithCognito(
        googleUser,
      );

      // Sincronizar com Customer entity
      await this.userSyncService.syncUserFromCognito(
        cognitoTokens.IdToken,
      );

      // Redirecionar para frontend com tokens
      const frontendUrl = process.env.FRONTEND_URL;
      return res.redirect(
        `${frontendUrl}/auth/callback?access_token=${cognitoTokens.AccessToken}&id_token=${cognitoTokens.IdToken}&refresh_token=${cognitoTokens.RefreshToken}`,
      );
    } catch (error) {
      return res.redirect(
        `${process.env.FRONTEND_URL}/auth/error?message=${error.message}`,
      );
    }
  }
}
```

---

## 7. Atualizar AuthGuard para Cognito

### 7.1 Criar Serviço de Validação de Token Cognito

**`src/shared/services/cognito-jwt-validator.service.ts`**

```typescript
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import jwt from 'jsonwebtoken';
import jwksClient from 'jwks-rsa';
import { CacheService } from '../services/cache/cache.service';

@Injectable()
export class CognitoJwtValidatorService {
  private jwksClient: jwksClient.JwksClient;
  private userPoolId: string;
  private region: string;

  constructor(
    private configService: ConfigService,
    private cacheService: CacheService,
  ) {
    this.userPoolId = this.configService.get('AWS_COGNITO_USER_POOL_ID');
    this.region = this.configService.get('AWS_REGION');

    const jwksUri = `https://cognito-idp.${this.region}.amazonaws.com/${this.userPoolId}/.well-known/jwks.json`;

    this.jwksClient = jwksClient({
      jwksUri,
      cache: true,
      cacheMaxAge: 86400000, // 24 horas
    });
  }

  async validateToken(token: string): Promise<any> {
    // Verificar cache de blacklist
    const isBlacklisted = await this.cacheService.get(
      `blacklist_token:${token}`,
    );
    if (isBlacklisted) {
      throw new Error('Token inválido');
    }

    // Decodificar token sem verificar
    const decoded = jwt.decode(token, { complete: true });
    if (!decoded) {
      throw new Error('Token inválido');
    }

    // Obter chave pública
    const kid = decoded.header.kid;
    const key = await this.jwksClient.getSigningKey(kid);
    const signingKey = key.getPublicKey();

    // Verificar token
    const verified = jwt.verify(token, signingKey, {
      audience: this.configService.get('AWS_COGNITO_CLIENT_ID'),
      issuer: `https://cognito-idp.${this.region}.amazonaws.com/${this.userPoolId}`,
    });

    return verified;
  }
}
```

### 7.2 Modificar AuthGuard

**`src/shared/guard/auth.guard.ts`**

Atualizar para usar `CognitoJwtValidatorService` em vez de `JwtService`:

```typescript
// ... imports existentes
import { CognitoJwtValidatorService } from '../services/cognito-jwt-validator.service';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private cognitoJwtValidator: CognitoJwtValidatorService,
    private configService: ConfigService,
    private reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    // ... lógica de rotas públicas, purchase, onboarding, webhook

    const token = this.extractTokenFromHeader(request);
    if (!token) {
      throw new UnauthorizedException('Token não fornecido');
    }

    try {
      const payload = await this.cognitoJwtValidator.validateToken(token);
      request['user'] = payload;
      return true;
    } catch (e) {
      throw new UnauthorizedException('Token inválido');
    }
  }
}
```

---

## 8. Integração com Entidade Customer

### 8.1 Atualizar Customer Entity

**`src/entities/customer.entity.ts`**

Adicionar campos:

```typescript
@Column({
  type: 'varchar',
  nullable: true,
  unique: true,
  comment: 'Sub do usuário no Cognito',
})
cognito_sub?: string;

@Column({
  type: 'varchar',
  nullable: true,
  comment: 'Username no Cognito',
})
cognito_username?: string;

@Column({
  type: 'varchar',
  nullable: true,
  comment: 'Provider social vinculado (google, facebook, apple)',
})
social_provider?: string;
```

### 8.2 Criar Migration

**`db/migrations/XXXXXX-add-cognito-fields-to-customer.ts`**

```typescript
import { MigrationInterface, QueryRunner, TableColumn } from 'typeorm';

export class AddCognitoFieldsToCustomer1234567890 implements MigrationInterface {
  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.addColumn(
      'customer',
      new TableColumn({
        name: 'cognito_sub',
        type: 'varchar',
        isNullable: true,
        isUnique: true,
      }),
    );

    await queryRunner.addColumn(
      'customer',
      new TableColumn({
        name: 'cognito_username',
        type: 'varchar',
        isNullable: true,
      }),
    );

    await queryRunner.addColumn(
      'customer',
      new TableColumn({
        name: 'social_provider',
        type: 'varchar',
        isNullable: true,
      }),
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.dropColumn('customer', 'social_provider');
    await queryRunner.dropColumn('customer', 'cognito_username');
    await queryRunner.dropColumn('customer', 'cognito_sub');
  }
}
```

### 8.3 Criar Serviço de Sincronização

**`src/modules/auth/services/user-sync.service.ts`**

```typescript
import { Injectable } from '@nestjs/common';
import { CognitoService } from '../cognito/cognito.service';
import { CustomerRepository } from 'src/modules/v1/customer/repositories/customer.repository';
import jwt from 'jsonwebtoken';

@Injectable()
export class UserSyncService {
  constructor(
    private cognitoService: CognitoService,
    private customerRepository: CustomerRepository,
  ) {}

  async syncUserFromCognito(idToken: string) {
    const decoded = jwt.decode(idToken) as any;
    const sub = decoded.sub;
    const email = decoded.email;
    const name = decoded.name || decoded['cognito:username'];

    // Verificar se Customer já existe
    let customer = await this.customerRepository.findOne({
      where: { cognito_sub: sub },
    });

    if (!customer) {
      // Verificar por email
      customer = await this.customerRepository.findOne({
        where: { email },
      });
    }

    if (customer) {
      // Atualizar campos do Cognito
      customer.cognito_sub = sub;
      customer.cognito_username = decoded['cognito:username'];
      customer.email = email;
      if (name && !customer.name) {
        customer.name = name;
      }
      await this.customerRepository.save(customer);
    } else {
      // Criar novo Customer
      // Nota: Pode precisar de mais informações (endereço, etc.)
      customer = this.customerRepository.create({
        cognito_sub: sub,
        cognito_username: decoded['cognito:username'],
        email,
        name,
      });
      await this.customerRepository.save(customer);
    }

    return customer;
  }
}
```

---

## 9. Tratamento de Erros

### 9.1 Criar Exceções Customizadas

**`src/shared/exceptions/cognito.exception.ts`**

```typescript
import {
  BadRequestException,
  UnauthorizedException,
  ConflictException,
  ForbiddenException,
} from '@nestjs/common';

export class CognitoException extends Error {
  static handle(error: any) {
    const errorCode = error.code || error.name;

    switch (errorCode) {
      case 'UsernameExistsException':
        throw new ConflictException('Usuário já existe');
      case 'UserNotFoundException':
        throw new UnauthorizedException('Usuário não encontrado');
      case 'NotAuthorizedException':
        throw new UnauthorizedException('Credenciais inválidas');
      case 'InvalidPasswordException':
        throw new BadRequestException('Senha inválida');
      case 'CodeMismatchException':
        throw new BadRequestException('Código de verificação inválido');
      case 'ExpiredCodeException':
        throw new BadRequestException('Código de verificação expirado');
      case 'LimitExceededException':
        throw new ForbiddenException('Limite de tentativas excedido');
      case 'TooManyRequestsException':
        throw new ForbiddenException('Muitas requisições. Tente novamente mais tarde');
      default:
        throw new BadRequestException(error.message || 'Erro ao processar requisição');
    }
  }
}
```

### 9.2 Atualizar Exception Filter

**`src/shared/filters/http-exception.filter.ts`**

Adicionar tratamento para erros do Cognito:

```typescript
import { CognitoException } from '../exceptions/cognito.exception';

// No método catch
if (exception instanceof Error && exception.name.includes('Cognito')) {
  CognitoException.handle(exception);
}
```

---

## 10. Scripts de Setup para Desenvolvimento Local

### 10.1 Script de Setup do Cognito no LocalStack

**`scripts/setup-localstack-cognito.sh`**

```bash
#!/bin/bash

ENDPOINT_URL="http://localhost:4566"
REGION="us-east-1"
USER_POOL_NAME="commerce-platform-pool"

echo "Criando User Pool no LocalStack..."

# Criar User Pool
aws cognito-idp create-user-pool \
  --endpoint-url $ENDPOINT_URL \
  --region $REGION \
  --pool-name $USER_POOL_NAME \
  --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=true}" \
  --auto-verified-attributes email \
  --schema \
    Name=email,AttributeDataType=String,Required=true \
    Name=name,AttributeDataType=String,Required=false \
    Name=phone_number,AttributeDataType=String,Required=false

echo "User Pool criado com sucesso!"
```

### 10.2 Script de Seed de Usuários de Teste

**`scripts/seed-cognito-users.sh`**

```bash
#!/bin/bash

ENDPOINT_URL="http://localhost:4566"
REGION="us-east-1"
USER_POOL_ID="your-pool-id"
EMAIL="test@example.com"
PASSWORD="Test123!"

echo "Criando usuário de teste..."

aws cognito-idp admin-create-user \
  --endpoint-url $ENDPOINT_URL \
  --region $REGION \
  --user-pool-id $USER_POOL_ID \
  --username $EMAIL \
  --user-attributes Name=email,Value=$EMAIL Name=email_verified,Value=true \
  --message-action SUPPRESS

aws cognito-idp admin-set-user-password \
  --endpoint-url $ENDPOINT_URL \
  --region $REGION \
  --user-pool-id $USER_POOL_ID \
  --username $EMAIL \
  --password $PASSWORD \
  --permanent

echo "Usuário criado com sucesso!"
```

---

## 11. Configuração do Módulo Auth

### 11.1 Criar Auth Module

**`src/modules/auth/auth.module.ts`**

```typescript
import { Module } from '@nestjs/common';
import { CognitoModule } from './cognito/cognito.module';
import { AuthController } from './controllers/auth.controller';
import { SocialAuthController } from './controllers/social-auth.controller';
import { GoogleAuthService } from './services/google-auth.service';
import { FacebookAuthService } from './services/facebook-auth.service';
import { AppleAuthService } from './services/apple-auth.service';
import { UserSyncService } from './services/user-sync.service';
import { CustomerModule } from '../v1/customer/customer.module';

@Module({
  imports: [CognitoModule, CustomerModule],
  controllers: [AuthController, SocialAuthController],
  providers: [
    GoogleAuthService,
    FacebookAuthService,
    AppleAuthService,
    UserSyncService,
  ],
  exports: [CognitoModule],
})
export class AuthModule {}
```

### 11.2 Atualizar App Module

**`src/app.module.ts`**

```typescript
// ... imports existentes
import { AuthModule } from './modules/auth/auth.module';

@Global()
@Module({
  imports: [
    // ... outros imports
    AuthModule, // Adicionar aqui
  ],
  // ...
})
export class AppModule {}
```

---

## 12. Segurança e Boas Práticas

### 12.1 Rate Limiting

Aplicar throttling nos endpoints de autenticação usando `@nestjs/throttler`:

```typescript
@Throttle({ default: { limit: 5, ttl: 60000 } }) // 5 requisições por minuto
```

### 12.2 Validação de Senha

Criar helper para validar senha antes de enviar ao Cognito:

```typescript
export class PasswordValidator {
  static validate(password: string): boolean {
    // Mínimo 8 caracteres
    if (password.length < 8) return false;
    
    // Pelo menos uma maiúscula
    if (!/[A-Z]/.test(password)) return false;
    
    // Pelo menos uma minúscula
    if (!/[a-z]/.test(password)) return false;
    
    // Pelo menos um número
    if (!/[0-9]/.test(password)) return false;
    
    // Pelo menos um símbolo
    if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) return false;
    
    return true;
  }
}
```

### 12.3 Logs e Auditoria

```typescript
// Logar tentativas de login (sem senha/token)
this.logger.log(`Login attempt: ${email} - ${success ? 'SUCCESS' : 'FAILED'}`);
```

---

## 13. Testes

### 13.1 Testes Unitários

**`src/modules/auth/cognito/cognito.service.spec.ts`**

```typescript
import { Test, TestingModule } from '@nestjs/testing';
import { CognitoService } from './cognito.service';
import { CognitoIdentityProviderClient } from '@aws-sdk/client-cognito-identity-provider';

describe('CognitoService', () => {
  let service: CognitoService;
  let mockClient: jest.Mocked<CognitoIdentityProviderClient>;

  beforeEach(async () => {
    mockClient = {
      send: jest.fn(),
    } as any;

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        CognitoService,
        {
          provide: 'COGNITO_CLIENT',
          useValue: mockClient,
        },
      ],
    }).compile();

    service = module.get<CognitoService>(CognitoService);
  });

  it('should sign up user', async () => {
    // Mock implementation
  });
});
```

### 13.2 Testes de Integração

Usar LocalStack para testes E2E dos endpoints de autenticação.

---

## 14. Health Check

### 14.1 Adicionar Verificação de Saúde do Cognito

**`src/modules/health/health.controller.ts`**

```typescript
@Get('cognito')
async checkCognito() {
  try {
    await this.cognitoService.getUserPool();
    return { status: 'up' };
  } catch (error) {
    return { status: 'down', error: error.message };
  }
}
```

---

## 15. Ordem de Implementação Sugerida

1. **Dependências e variáveis de ambiente** (1.1, 1.2)
2. **Docker Compose com LocalStack** (2.1, 2.2)
3. **Módulo e serviço Cognito básico** (3.1, 3.2, 3.3)
   - Implementar métodos de email/senha primeiro
4. **DTOs de autenticação** (5.1)
5. **Controller de autenticação básica** (6.1)
6. **Serviço de validação JWT Cognito** (7.1) — necessário para o Bull Dashboard e para o AuthGuard
7. **Proteção do Bull Dashboard com Cognito** (16) — opcional: implementar primeiro se quiser proteger `/admin/queues` antes do resto da API
8. **AuthGuard atualizado** (7.2)
9. **Serviços de login social** (4.2, 4.3, 4.4)
10. **Controller de login social** (6.2)
11. **Integração com Customer** (8.1, 8.2, 8.3)
12. **Tratamento de erros** (9.1, 9.2)
13. **Scripts de setup local** (10.1, 10.2)
14. **Testes e documentação** (13, 11)

---

## 16. Proteção do Bull Dashboard com Cognito

O endpoint `/admin/queues` (Bull Dashboard) pode ser protegido com login via Cognito. **Acesso apenas por usuário (email) e senha** — esta implementação não utiliza login social (Google, Facebook, Apple); é exclusiva para o Bull Dashboard. O mesmo **CognitoService** e **CognitoJwtValidatorService** configurados aqui poderão ser reutilizados depois no AuthGuard (seção 7.2) e no restante da API.

### 16.1 Visão geral do fluxo

1. Usuário acessa `GET /admin/queues` → middleware verifica token (cookie ou `Authorization: Bearer`).
2. Se não houver token ou for inválido → redireciona para `GET /admin/queues/login` (página de login).
3. Usuário envia email e senha em `POST /admin/queues/login` → backend chama `CognitoService.signIn()`.
4. Se login OK → define cookie HTTP-only com o access token e redireciona para `/admin/queues`.
5. Requisições seguintes ao dashboard enviam o cookie; o middleware valida o JWT com **CognitoJwtValidatorService** e libera o acesso.

O token é armazenado em **cookie** para que o frontend do Bull Board (que não controlamos) continue fazendo requisições ao mesmo domínio sem precisar enviar `Authorization` manualmente.

### 16.2 Dependência adicional

```bash
yarn add cookie-parser
yarn add -D @types/cookie-parser
```

### 16.3 Variáveis de ambiente

Adicionar ao `.env.example` e ao `.env` usado na aplicação:

```env
# Bull Dashboard - Login com Cognito
BULL_BOARD_COOKIE_NAME=admin_queues_token
BULL_BOARD_LOGIN_PATH=/admin/queues/login
```

### 16.4 Middleware de autenticação para o Bull Board

O projeto já contém o middleware e as rotas de login em:

- **`src/shared/middleware/bull-board-cognito.middleware.ts`** — middleware que valida JWT (cookie ou Bearer) e redireciona para login.
- **`src/shared/middleware/bull-board-login.routes.ts`** — registro de GET (página de login) e POST (login com Cognito).

Eles usam interfaces (`BullBoardCognitoJwtValidator`, `BullBoardCognitoLoginService`) para não depender do módulo de auth até você implementá-lo. Quando o **CognitoService** e o **CognitoJwtValidatorService** existirem, eles são compatíveis com essas interfaces.

Código de referência do middleware (já presente no repositório):

```typescript
import { Request, Response, NextFunction } from 'express';
import { CognitoJwtValidatorService } from '../services/cognito-jwt-validator.service';

const LOGIN_PATH = process.env.BULL_BOARD_LOGIN_PATH || '/admin/queues/login';
const COOKIE_NAME = process.env.BULL_BOARD_COOKIE_NAME || 'admin_queues_token';

export function createBullBoardCognitoMiddleware(
  cognitoJwtValidator: CognitoJwtValidatorService,
) {
  return async function bullBoardCognitoMiddleware(
    req: Request,
    res: Response,
    next: NextFunction,
  ): Promise<void> {
    const path = req.path;
    const isLoginPage =
      path === '/login' || path === '/login/' || path.startsWith('/login?');

    if (isLoginPage) {
      return next();
    }

    const token =
      (req.cookies?.[COOKIE_NAME] as string) ||
      (req.headers.authorization?.startsWith('Bearer ')
        ? req.headers.authorization.slice(7)
        : undefined);

    if (!token) {
      res.redirect(LOGIN_PATH);
      return;
    }

    try {
      await cognitoJwtValidator.validateToken(token);
      next();
    } catch {
      res.redirect(LOGIN_PATH);
    }
  };
}
```

### 16.5 Rotas de login (GET página + POST login)

Registrar no Express a página de login e o handler que chama o Cognito e seta o cookie.

**`src/shared/middleware/bull-board-login.routes.ts`**

```typescript
import { Request, Response } from 'express';
import { CognitoService } from 'src/modules/auth/cognito/cognito.service';

const BASE_PATH = '/admin/queues';
const LOGIN_PATH = process.env.BULL_BOARD_LOGIN_PATH || `${BASE_PATH}/login`;
const COOKIE_NAME = process.env.BULL_BOARD_COOKIE_NAME || 'admin_queues_token';
const COOKIE_MAX_AGE_MS = 60 * 60 * 1000; // 1 hora

const LOGIN_HTML = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Admin Queues - Login</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 360px; margin: 80px auto; padding: 24px; }
    h1 { font-size: 1.25rem; margin-bottom: 24px; }
    input { width: 100%; padding: 10px 12px; margin-bottom: 12px; box-sizing: border-box; }
    button { width: 100%; padding: 12px; background: #333; color: #fff; border: 0; cursor: pointer; }
    .error { color: #c00; margin-bottom: 12px; font-size: 0.9rem; }
  </style>
</head>
<body>
  <h1>Admin Queues</h1>
  {{invalidMessage}}
  <form method="post" action="{{loginPath}}">
    <input type="email" name="email" placeholder="Email" required autocomplete="username">
    <input type="password" name="password" placeholder="Senha" required autocomplete="current-password">
    <button type="submit">Entrar</button>
  </form>
</body>
</html>
`;

function getLoginPath(): string {
  return LOGIN_PATH;
}

export function registerBullBoardLoginRoutes(
  app: any,
  cognitoService: CognitoService,
): void {
  const loginPath = getLoginPath();

  app.get(loginPath, (req: Request, res: Response) => {
    const invalid = req.query.invalid === 'true';
    const invalidMessage = invalid
      ? '<p class="error">Credenciais inválidas. Tente novamente.</p>'
      : '';
    const html = LOGIN_HTML.replace('{{loginPath}}', loginPath).replace(
      '{{invalidMessage}}',
      invalidMessage,
    );
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.send(html);
  });

  app.post(loginPath, async (req: Request, res: Response) => {
    const email = (req.body?.email as string)?.trim();
    const password = req.body?.password as string;

    if (!email || !password) {
      res.redirect(`${loginPath}?invalid=true`);
      return;
    }

    try {
      const result = await cognitoService.signIn(email, password);
      const accessToken =
        result?.AuthenticationResult?.AccessToken ?? result?.AccessToken;

      if (!accessToken) {
        res.redirect(`${loginPath}?invalid=true`);
        return;
      }

      res.cookie(COOKIE_NAME, accessToken, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'lax',
        maxAge: COOKIE_MAX_AGE_MS,
        path: BASE_PATH,
      });
      res.redirect(BASE_PATH);
    } catch {
      res.redirect(`${loginPath}?invalid=true`);
    }
  });
}
```

O **CognitoService** do manual (seção 3.3) retorna `AuthenticationResult` com `AccessToken`; o arquivo `bull-board-login.routes.ts` já trata esse formato. No NestJS o body-parser para `application/x-www-form-urlencoded` já está habilitado por padrão, então o POST de login funciona sem configuração extra.

### 16.6 Integração no `main.ts`

Em `src/main.ts` há um comentário com o trecho exato para ativar a proteção após o Cognito estar implementado. É necessário:

1. Importar e usar `cookie-parser` no app.
2. Registrar as rotas de login **antes** de montar o router do Bull Board.
3. Montar o **middleware de autenticação** antes de `serverAdapter.getRouter()`.

**Trecho em `src/main.ts` (após criar o `app` e antes de `app.use('/admin/queues', ...)`):**

```typescript
import cookieParser from 'cookie-parser';
import { createBullBoardCognitoMiddleware } from './shared/middleware/bull-board-cognito.middleware';
import { registerBullBoardLoginRoutes } from './shared/middleware/bull-board-login.routes';

// ... após createBullBoard(...) e antes de app.use('/admin/queues', ...)

app.use(cookieParser());

const cognitoJwtValidator = app.get(CognitoJwtValidatorService);
const cognitoService = app.get(CognitoService);

registerBullBoardLoginRoutes(app, cognitoService);

const bullBoardAuthMiddleware = createBullBoardCognitoMiddleware(cognitoJwtValidator);
app.use('/admin/queues', bullBoardAuthMiddleware, serverAdapter.getRouter());
```

Remover a linha que monta apenas o router:

```typescript
// Remover: app.use('/admin/queues', serverAdapter.getRouter());
```

### 16.7 Módulos necessários

Para o `app.get(CognitoJwtValidatorService)` e `app.get(CognitoService)` funcionarem, o **CognitoModule** (e o serviço de validação JWT) precisam estar disponíveis no **AppModule**. Ou seja:

- Implementar o **CognitoModule** (seção 3.2) e o **CognitoService** com ao menos `signIn` (seção 3.3).
- Implementar o **CognitoJwtValidatorService** (seção 7.1) e registrá-lo em um módulo importado pelo `AppModule` (por exemplo no próprio `CognitoModule` ou em um `AuthModule` que importe o `CognitoModule` e exporte o validator).
- No **AppModule**, importar esse módulo (ex.: `AuthModule` ou `CognitoModule`) para que os providers fiquem disponíveis globalmente ou no escopo do app.

Assim, o mesmo service fica configurado para o Bull Dashboard e pode ser reaproveitado depois no AuthGuard e no restante da aplicação.

### 16.8 Desenvolvimento local (LocalStack)

Com Cognito no LocalStack, a URL JWKS usada no **CognitoJwtValidatorService** (seção 7.1) pode ser diferente da AWS. Ajuste a `jwksUri` no construtor para apontar para o endpoint do LocalStack se necessário, ou use um mecanismo de validação alternativo em ambiente local (por exemplo, validar apenas assinatura/localmente). O login em si (signIn) já pode ser feito contra o LocalStack desde que o User Pool e o app client estejam configurados.

### 16.9 Resumo

| Item | Descrição |
|------|-----------|
| Autenticação | **Apenas usuário (email) e senha** — sem login social, somente para o Bull Dashboard |
| Login | Página em `GET /admin/queues/login`; envio em `POST /admin/queues/login` com email/senha |
| Cookie | Nome em `BULL_BOARD_COOKIE_NAME`, path `/admin/queues`, httpOnly, 1h |
| Middleware | Valida JWT (cookie ou Bearer) com **CognitoJwtValidatorService**; redireciona para login se inválido |
| Serviços | **CognitoService** (signIn) e **CognitoJwtValidatorService** (validateToken) — os mesmos usados depois no AuthGuard e na API |

---

## Notas Importantes

- **LocalStack**: Suporte limitado para OAuth social. Para desenvolvimento, considere usar Cognito AWS real ou mocks.
- **PKCE**: Implementar PKCE para maior segurança no fluxo OAuth (opcional mas recomendado).
- **Tokens**: Sempre validar tokens do Cognito usando JWKS antes de confiar neles.
- **Sincronização**: Garantir que dados do Cognito sejam sincronizados com a entidade Customer.
- **Segurança**: Nunca logar senhas ou tokens completos. Aplicar rate limiting em todos os endpoints de autenticação.

---

## Referências

- [AWS Cognito Documentation](https://docs.aws.amazon.com/cognito/)
- [AWS SDK v3 - Cognito Identity Provider](https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/clients/client-cognito-identity-provider/)
- [Google OAuth 2.0](https://developers.google.com/identity/protocols/oauth2)
- [Facebook Login](https://developers.facebook.com/docs/facebook-login/)
- [Sign in with Apple](https://developer.apple.com/sign-in-with-apple/)
```

Copie o conteúdo acima e cole no arquivo `manual-implementação-cognito`. O documento inclui:

- Custom UI (sem Hosted UI)
- Login com email e senha
- Login social (Google, Facebook, Apple)
- Desenvolvimento local com LocalStack
- Estrutura de código, DTOs, controllers e serviços
- Integração com a entidade Customer
- Tratamento de erros e segurança
- Scripts de setup e testes

Todas as etapas estão detalhadas com exemplos de código.