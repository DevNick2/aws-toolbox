### ECR

```bash
aws ecr create-repository \
  --repository-name meu_repositorio \
  --region minha-regiao \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256

aws ecr describe-repositories

aws ecr get-login-password --region <your-region> --profile | docker login --username AWS --password-stdin <your-account-id>.dkr.ecr.<your-region>.amazonaws.com

docker build -t image-name:image-tag .
docker tag image-name:image-tag <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/<your-repository>:<image-tag>
docker push <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/<your-repository>:<image-tag>
``

### IAM


### Secrets Manger
```bash
aws secretsmanager get-secret-value --secret-id MyTestSecret
aws secretsmanager create-secret --name MyNewSecret --secret-string "MySecretValue"
aws secretsmanager list-secrets
aws secretsmanager update-secret --secret-id MyTestSecret --secret-string "MyNewValue"
aws secretsmanager describe-secret --secret-id stg/checkout --query 'ARN' --output text
``

### ECS
```bash
aws ecs list-clusters
aws ecs describe-cluster --clusters MyCluster
aws ecs list-services --cluster MyCluster
aws ecs list-container-instances
aws ecs list-tasks
aws ecs describe-services --cluster MyCluster --services "arn:aws:ecs:us-west-2:123456789012:service/MyCluster/MyService"
aws ecs list-task-definitions
aws ecs list-task-definition-families --status ACTIVE
aws ecs describe-task-definition --task-definition  [family] > task-def.json --profile stg
``

./scripts/update-ecs-secrets.sh \
  --family MyFamily \
  --cluster MyCluster \
  --service MyService \
  --file secrets.json