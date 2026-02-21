# AWS Deployment (ECS Fargate + ECR)

This guide deploys the backend API container to Amazon ECS Fargate and runs Prisma migrations as a one-off ECS task before service rollout.

## Official references
- Amazon ECS Developer Guide (getting started): https://docs.aws.amazon.com/AmazonECS/latest/developerguide/getting-started-fargate.html
- ECS task definition parameters (`runtimePlatform`, CPU/memory): https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html
- ECS + Secrets Manager env injection: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/secrets-envvar-secrets-manager.html
- ECS `run-task` API (one-off task execution): https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_RunTask.html
- ECR image push: https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html
- Docker Buildx (`--platform`): https://docs.docker.com/reference/cli/docker/buildx/build/
- Prisma migrate deploy (production): https://www.prisma.io/docs/orm/prisma-client/deployment/deploy-database-changes-with-prisma-migrate

## Why this path
- Keeps build/runtime deterministic with Docker.
- Supports one-off migration execution (`npm run prisma:migrate:deploy`) before app rollout.
- Works well for macOS local development + Linux production targets.

## 1) Create ECR repository
```bash
AWS_REGION=ap-northeast-2
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

aws ecr create-repository \
  --repository-name babyai-api \
  --region "$AWS_REGION"
```

## 2) Build and push image
If `docker buildx` is not available on macOS, install it first:
https://docs.docker.com/build/buildx/install/

```bash
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/babyai-api:$(date +%Y%m%d%H%M%S)"

aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker buildx build \
  --platform linux/amd64 \
  -t "$IMAGE_URI" \
  -f Dockerfile \
  --push \
  .
```

## 3) Store runtime secrets
Store at minimum:
- `DATABASE_URL`
- `JWT_SECRET`
- `OPENAI_API_KEY` (if AI routes are enabled in production)

Example:
```bash
aws secretsmanager create-secret --name babyai/database-url --secret-string "$DATABASE_URL" --region "$AWS_REGION"
aws secretsmanager create-secret --name babyai/jwt-secret --secret-string "$JWT_SECRET" --region "$AWS_REGION"
```

## 4) Task definitions
Create two task definitions from the same image:
1. `babyai-api` service task
2. `babyai-migrate` one-off task (`command: ["npm","run","prisma:migrate:deploy"]`)

Required points:
- `requiresCompatibilities`: `FARGATE`
- `networkMode`: `awsvpc`
- `runtimePlatform.cpuArchitecture`: `X86_64` (or `ARM64` if you intentionally build ARM images)
- secrets via ECS `secrets` field (Secrets Manager ARNs)
- service container port: `8080`

## 5) Run migration task before service deploy
```bash
aws ecs run-task \
  --region "$AWS_REGION" \
  --cluster babyai-cluster \
  --launch-type FARGATE \
  --task-definition babyai-migrate \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-aaa,subnet-bbb],securityGroups=[sg-aaa],assignPublicIp=ENABLED}" \
  --count 1
```

Wait for task stop and confirm exit code `0` in ECS task details/CloudWatch logs.

## 6) Deploy/update API service
Update ECS service to new task definition/image after migration succeeds.

## 7) Self-check before every deploy
1. `./apps/backend/scripts/self_check_env_parity.sh`
2. Confirm image architecture matches ECS task `runtimePlatform.cpuArchitecture`.
3. Confirm Secrets Manager values are current.
4. Confirm service health endpoint responds after rollout: `GET /health`.
