# DriveClone local stack

NGINX + React, NestJS API, SQS worker, PostgreSQL and LocalStack (S3/SQS/IAM), all with healthchecks and persistent volumes.

## Prerequisites

Docker with Compose v2, Terraform >= 1.5. LocalStack `3` is pinned so no auth token is required; S3, SQS and IAM are in the free tier.

## Run

```bash
cp .env.example .env
docker compose up -d db localstack --wait
cd infra && terraform init && terraform apply -auto-approve && cd ..
# Paste terraform outputs into .env (S3_BUCKET_NAME, SQS_QUEUE_URL, SQS_DLQ_URL,
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY). Use `terraform -chdir=infra output -raw <name>`.
docker compose up -d --build --wait
```

React is at `http://localhost`, API at `http://localhost/api/health`. With rootless Docker set `HTTP_PORT=8080` in `.env` and use `http://localhost:8080`.
Demo users: `alice`, `bob`, `carol` (see `db/migrations/002_seed.sql`; confirm the bcrypt password with C before the demo).

Terraform runs from the host against `http://localhost:4566`; API and worker reach LocalStack via `http://localstack:4566`. Presigned URLs for the browser are signed with `S3_PUBLIC_ENDPOINT` (`SQS_ENDPOINT_STRATEGY=path` keeps queue URLs browser-resolvable).

## Data and resets

Migrations in `db/migrations/` run on the **first** creation of `db_data` only. For an existing volume apply them manually:

```bash
docker compose exec -T db psql -U drive -d driveclone -f /dev/stdin < db/migrations/001_init.sql
```

`docker compose down -v` deletes DB, LocalStack state and uploaded files.

## Checks

```bash
docker compose ps
curl -fsS http://localhost/api/health
curl -fsS http://localhost/ | head -5
awslocal s3 ls && awslocal sqs list-queues && awslocal iam list-users
terraform -chdir=infra plan -detailed-exitcode
```

## CI

The superproject workflow (`.github/workflows/ci.yml`) checks out both submodules and runs lint, unit tests, E2E, dependency audit and build. The E2E job starts PostgreSQL and LocalStack, applies Terraform and enables D's retry/DLQ suite with `UPLOADS_E2E=1`. Each submodule repo also has its own workflow so direct pushes there are checked: `backend` on `infra/compose-support`, `frontend` on `infra/ci`; this repo records those commits as gitlinks.

## Notes

- IAM policy is least privilege; `sqs:ChangeMessageVisibility` is required by the worker retries and DLQ redrive.
- Bucket CORS allows `frontend_origins` plus `public_app_origin` (the Cloudflare Tunnel hostname). Re-run `terraform apply` after changing it.
- Submodule code is edited only in the standalone `backend` and `frontend` repos; this repo only records their commits.
