# Plan: Compose + infra + DB + CI para DriveClone local

Branch: `plan/compose-infra-db-cicd`
Created: 2026-11-28

## Goal

Entregar `docker compose up` + `terraform apply` funcionando con NGINX, API, worker, PostgreSQL y LocalStack; esquema de BD migrado con datos de prueba; bucket/cola en variables de entorno; pipeline lint → tests → E2E → auditoría → build; y runbook de NMAP + Cloudflare Tunnel para la demo.

## Context

- El trabajo de infra/compose/db/CI va en `DriveCloneProject/` (superproyecto con submódulos `backend` y `frontend`). **Regla: nunca editar ni hacer commits dentro de `DriveCloneProject/backend` ni `DriveCloneProject/frontend`**; los cambios de código de esos repos se hacen en los clones independientes `/taller2cloud/backend` y `/taller2cloud/frontend` (ambos limpios, en `main`, con remotes `Cloud-Computing-Taller2/backend.git` y `frontend.git`). En el superproyecto solo se actualiza el gitlink.
- Estado actual: `Docker-compose.yaml` vacío, `nginx.conf` roto, `infra/variables.tf` con `locahost`, `infra/outputs.tf` vacío, estado de Terraform vacío. Hay cambios sin commitear en `infra/` y el submódulo `backend` apunta a `a20140d` (trabajo de D), no al gitlink viejo `798ceeb`.
- El backend ya es NestJS + TypeORM con `POST /files`, worker SQS y SQL de migración/seed en `backend/dev/db/`; no tiene `GET /health`; su Dockerfile copia un `contracts/` inexistente. El frontend usa Vite+ (`vp`), no tiene `dist` y su Dockerfile es una copia inválida del backend.
- La API y el worker comparten `/data/uploads`: hace falta un volumen compartido.
- LocalStack gratis incluye S3, SQS e IAM (tabla oficial de licensing), pero desde mar-2026 la imagen unificada pide token: se fija `localstack/localstack:3`.
- LocalStack por defecto genera URLs SQS tipo `sqs.us-east-1.localhost.localstack.cloud`; hay que usar `SQS_ENDPOINT_STRATEGY=off` (`path` produce URLs `/queue/<region>/...` que el provider AWS 6.x rechaza).
- La política IAM necesita `sqs:ChangeMessageVisibility` para los reintentos del worker, y `s3:HeadObject` no es una acción IAM válida.
- D ya tiene `test/uploads.e2e-spec.ts` con el caso 3 intentos → DLQ (`UPLOADS_E2E=1`); hay que conectarlo a CI, no reescribirlo.
- `nmap` está instalado; `cloudflared` y Docker daemon no están disponibles en este momento (el daemon hay que iniciarlo al ejecutar).

## Approach

1. **Infra (`infra/`)**: corregir `locahost` → `localhost`; añadir `public_app_origin` para el hostname del tunnel; CORS con orígenes base + tunnel; bucket privado + SQS/DLQ (`maxReceiveCount=3`); IAM de mínimo privilegio corrigiendo `s3:HeadObject` y añadiendo `sqs:ChangeMessageVisibility`; completar `outputs.tf` con bucket, URLs de colas y credenciales `sensitive`. Commitear `.terraform.lock.hcl`, ignorar `.terraform/` y `*.tfstate*`.
2. **BD (`db/migrations/`)**: copiar `001_init.sql` y `002_seed.sql` desde `backend/dev/db/` (users, folders, files, shares; username único, nombre único por carpeta, CHECK exactly-one-target, cascadas, índices; 3 usuarios y 5 archivos compartidos). Verificar que el hash bcrypt del seed coincide con `Password123!` (parece el hash canónico de `password`; si no, regenerarlo a cost 10).
3. **Compose (`docker-compose.yml`)**: servicios `nginx`, `api`, `worker`, `db`, `localstack`; volúmenes `db_data`, `localstack_data` y `uploads_data` (montado en `/data/uploads` en api y worker); healthchecks; `SQS_ENDPOINT_STRATEGY=off`, `PERSISTENCE=1`, `SERVICES=s3,sqs,iam`; `AWS_ENDPOINT_URL=http://localstack:4566` internamente y `S3_PUBLIC_ENDPOINT=http://localhost:4566` para URLs firmadas; `env_file: .env`.
4. **NGINX (`nginx/Dockerfile`, `nginx/nginx.conf`)**: build multi-stage que compila el frontend con `pnpm@12` + `vp build` y copia `dist` a la imagen `nginx:alpine`; configuración con `/` → React, `/api/` → API (strip del prefijo), `client_max_body_size 50m`, `limit_req` 5r/m con burst 5 en `/api/auth/login`. Añadir `.dockerignore` para no copiar `node_modules`, `.git` ni estado de Terraform.
5. **Backend (repo propio)**: en `/taller2cloud/backend`, rama nueva desde `a20140d` con dos commits mínimos — `GET /health` en `app.controller.ts` y quitar `COPY contracts` de `DockerFile` — y push a `origin`; después, en `DriveCloneProject/` Actualizar solo el gitlink de `backend` al nuevo SHA (`git -C backend fetch origin && git -C backend checkout <sha>`) y hacer el commit del puntero en la rama `plan/compose-infra-db-cicd`. Coordinar con B/C/D antes de pushear.
6. **Variables y arranque**: `.env.example` raíz con todas las variables (incluidas `UPLOAD_TMP_DIR`, `MAX_UPLOAD_BYTES`, `WORKER_*`, `SQS_*`, `ALLOW_DEV_AUTH`); `.env` en `.gitignore`; README con el orden `cp .env.example .env` → levantar `db`/`localstack` → `terraform init && apply` → volcar outputs a `.env` → `docker compose up -d --build --wait`.
7. **CI**: workflow en `DriveCloneProject/.github/workflows/ci.yml` con `checkout(submodules: recursive)`: lint (sin `--fix`) → unit tests → E2E (compose + Terraform + `UPLOADS_E2E=1 pnpm test:e2e`, incluye el test de DLQ de D) → `pnpm audit --audit-level=high` → build, para backend y frontend; job de `terraform fmt/validate` y `docker compose config`. Los workflows mínimos de cada repo se crean en `/taller2cloud/backend/.github/workflows/ci.yml` y `/taller2cloud/frontend/.github/workflows/ci.yml`, se pushean desde esos clones y luego se actualizan los gitlinks en el superproyecto.
8. **Demo**: `docs/demo.md` + `scripts/tunnel.sh`: NMAP contra el host propio (nunca contra IPs edge de Cloudflare), Cloudflare Tunnel en contenedor con `TUNNEL_TOKEN` desde `.env` e ingress a `nginx:80`, alternativa de quick tunnel; el hostname se añade a `public_app_origin` y se reaplica Terraform para CORS.
9. **Apoyo a D**: permiso IAM de visibility + E2E de reintentos/DLQ en CI; si hay flakiness por visibility 30 s, parametrizar `visibility_timeout_seconds` (default 30, bajar a 2 en CI) sin tocar la lógica del worker.

## Files / Areas

- `DriveCloneProject/infra/{variables.tf,main.tf,outputs.tf,.gitignore}`
- `DriveCloneProject/db/migrations/{001_init.sql,002_seed.sql}`
- `DriveCloneProject/docker-compose.yml`, `.dockerignore`, `.env.example`, `README.md`
- `DriveCloneProject/nginx/{Dockerfile,nginx.conf}`
- `/taller2cloud/backend/`: `src/app.controller.ts`, `DockerFile`, `.github/workflows/ci.yml` (se commitea aquí, nunca en `DriveCloneProject/backend`)
- `/taller2cloud/frontend/.github/workflows/ci.yml` (ídem, nunca en `DriveCloneProject/frontend`)
- `DriveCloneProject/backend` y `DriveCloneProject/frontend`: solo gitlinks apuntando a los commits ya pusheados
- `DriveCloneProject/.github/workflows/ci.yml`, `docs/demo.md`, `scripts/tunnel.sh`

## Verification

- `docker compose config` y `docker compose up -d --build --wait`: todos los contenedores healthy.
- `curl localhost/` sirve React; `curl localhost/api/health` → `{"status":"ok"}`; 6 `POST /api/auth/login` rápidos → 429; upload > 50 MB → 413.
- `awslocal s3 ls`, `awslocal sqs list-queues`, `awslocal iam list-users`; `terraform plan` sin diff y outputs no vacíos.
- `psql` (o `docker compose exec db psql`): 4 tablas, constraints y `setval` correcto; 3 usuarios / 6 carpetas / 5 archivos / 4 shares.
- `UPLOADS_E2E=1 pnpm test:e2e -- uploads` en `backend`: pasa el caso de 3 reintentos y mensaje en la DLQ (en CI; localmente el `node_modules` de este checkout está corrupto y `app.e2e-spec.ts` falla al cargar `@nestjs/config` como ESM).
- CI completa: lint → tests → E2E → audit → build, tanto en el superproyecto como en los submódulos.

## Validation (2026-11-28)

- `docker compose up -d --build --wait`: los 5 servicios healthy. Correcciones necesarias durante el build: instalar `git` para el hook `prepare` de Vite+, copiar `nginx.conf` desde la raíz del contexto, publicar el puerto de host como `${HTTP_PORT:-80}` (Docker rootless no puede enlazar 80) y escuchar también en IPv6 en NGINX.
- `terraform apply`: 8 recursos creados; cola con `maxReceiveCount=3`, visibility 30 s y bucket privado con CORS. `terraform plan -detailed-exitcode` → 0 (sin diff).
- HTTP: `/` → 200, `/api/health` → `{"status":"ok"}`, rate limit de login → 429 tras 5 req, upload de 51 MB → 413.
- Flujo real de carga: `POST /api/files?folderId=2` → 202 `queued`; el worker la dejó `ready` y el objeto apareció en S3 con clave `users/1/folders/2/<uuid>-manual-upload.png`.
- Seed: 3 usuarios / 6 carpetas / 5 archivos / 4 shares. El hash bcrypt original no coincidía con `Password123!`; se regeneró a cost 10.
- No se ejecutó la suite Jest de uploads en este host (dependencias corruptas); queda cubierta por el job E2E de CI.

## Open Questions

- Verificado: el hash original del seed no coincidía con `Password123!`; se regeneró a cost 10 en `002_seed.sql` (tanto en el repo backend como en el superproyecto).
- Hostname definitivo del Cloudflare Tunnel para `public_app_origin` / CORS (se puede dejar `null` hasta la demo).
- Sincronizar con B/C/D el push desde los clones independientes y los bumps de gitlinks; no pisar la rama de D ni hacer commits dentro de los submódulos de `DriveCloneProject/`.
- `pnpm audit --audit-level=high` puede reportar vulnerabilidades base en dependencias; decidir si se aplica un allowlist documentado en vez de actualizar dependencias ajenas.
