# AWS Deployment Guide — Spring Boot Demo

On-screen reference so you don't have to scroll the chat. This walks the **manual AWS
Console route** for a throwaway 1-day demo: `git push` → GitHub Actions →
SAST/SCA/build/scan → **ECR** → **ECS (Fargate)** behind an **ALB**.

> **Account / region used in this guide**
> - Account ID: `535181393425`
> - Region: `us-east-1`
> - ECR repo URI: `535181393425.dkr.ecr.us-east-1.amazonaws.com/demo`

---

## ⚠️ Do these two things first

1. **Rotate the leaked IAM key.** The access key `AKIAXZG2L7YIYNWPA3FK` and its secret
   were pasted into chat, so treat them as compromised.
   - IAM → Users → *your user* → Security credentials → delete that access key.
   - Create a fresh access key and use the new pair in GitHub Secrets (below).
   - Never paste the new secret anywhere except the GitHub Secrets form.

2. **The `pom.xml` fix is already applied** in this repo (see below). Without it the
   Maven build fails and no image ever reaches ECR.

---

## What's already done ✅

| Item | Status |
|------|--------|
| ECR repository `demo` | ✅ created |
| IAM access key | ⚠️ created but **must be rotated** (leaked in chat) |
| `Dockerfile` (multi-stage, non-root, healthcheck) | ✅ in repo |
| `.github/workflows/devsecops.yml` pipeline | ✅ in repo |
| `pom.xml` dependency fix | ✅ applied this session |

---

## The `pom.xml` fix (applied)

The original `pom.xml` declared 6 web starters plus `-test` variants. Several are **not
real Spring Boot artifacts** (`spring-boot-starter-webmvc`, `-restclient`, `-webclient`,
`-webservices`), so Maven could not resolve them and the build job died before any image
was produced.

The app (`RestController.java`) only uses basic Spring MVC (`@RestController`,
`@GetMapping`, `ResponseEntity`), so the dependencies were trimmed to:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-test</artifactId>
    <scope>test</scope>
</dependency>
```

---

## Pipeline overview

The workflow triggers on push/PR to `main`. Jobs:

1. **SAST** — Semgrep → HTML artifact (informational)
2. **Build & Test** — Maven `verify` + JUnit → HTML artifact + JAR (**hard gate**)
3. **Container Scan** — Trivy image scan → HTML artifact (**informational** — runs in
   parallel, never blocks the push)
4. **Push to ECR** — only on push to `main`, after build completes
5. **Deploy to ECS** — rolling update, waits for service stability
6. **Post-Deploy Validation** — smoke test hits `APP_URL/`, expects `200` + body
   containing `Good Morning`

> SCA (OWASP Dependency Check) was **removed** — without an `NVD_API_KEY` its NVD
> download burned free Actions minutes for little value on a 1-day demo.
> Jobs 4–6 run **only** on `push` to `main` (not on PRs).
> Job 5 uses a GitHub environment named **`production`** — create it (or remove the
> `environment: production` line) or the deploy job won't run.

---

## GitHub configuration

**Settings → Secrets and variables → Actions**

> **Config is read from Secrets, not Variables.** The workflow uses `secrets.*` for all
> config values (region/registry/repo/ECS), because they were stored in the Secrets tab.
> The single exception is `DEPLOY_ENABLED`, which must be a **Variable** — GitHub doesn't
> allow `secrets.*` inside a job-level `if:`.

### Secrets (tab: *Secrets*)
| Name | Value |
|------|-------|
| `AWS_ACCESS_KEY_ID` | your **rotated** IAM access key |
| `AWS_SECRET_ACCESS_KEY` | matching secret |
| `AWS_REGION` | `us-east-1` |
| `ECR_REGISTRY` | `535181393425.dkr.ecr.us-east-1.amazonaws.com` |
| `ECR_REPOSITORY` | `demo` |
| `ECS_CLUSTER` | `demo-cluster` |
| `ECS_SERVICE` | `demo-service` |
| `ECS_TASK_DEFINITION` | `demo-task` |
| `CONTAINER_NAME` | `demo` (must match the container name in the task def) |
| `APP_URL` | `http://<your-alb-dns>.us-east-1.elb.amazonaws.com` |

### Variables (tab: *Variables*)
| Name | Value | When |
|------|-------|------|
| `DEPLOY_ENABLED` | *(leave unset)* → set to `true` | Set to `true` **only after** ECS exists (Phase 3). Until then, Deploy/Validate skip and a push only seeds ECR. |

> The ECS-related secrets (`ECS_*`, `CONTAINER_NAME`, `APP_URL`) only matter once the ECS
> resources exist — see Phase 3/4. The image seed needs just the two AWS keys plus
> `AWS_REGION`, `ECR_REGISTRY`, `ECR_REPOSITORY`.

---

## Phase 1 — ECR + IAM ✅ (done)

- ECR repo `demo` created.
- IAM access key created → **rotate it** (see top of doc).

## Phase 2 — Seed the first image into ECR

ECS needs an existing image before you can create a task definition pointing at it.

1. Add the **Secrets** and these **Variables**: `AWS_REGION`, `ECR_REGISTRY`,
   `ECR_REPOSITORY`. (The `ECS_*`/`APP_URL` ones can wait.)
2. Commit and push to `main`:
   ```bash
   git add pom.xml AWS-DEPLOYMENT.md
   git commit -m "Fix pom.xml dependencies; add deployment guide"
   git push origin main
   ```
3. The **Deploy** and **Validate** jobs **skip** automatically (they're gated on the
   `ECS_CLUSTER` / `APP_URL` variables, which don't exist yet), so the run goes **green**
   once **Push to ECR** succeeds. Confirm in ECR that the `demo` repo now has an image
   tagged with the commit SHA and `latest`.

> Alternatively seed it manually from your machine:
> ```bash
> aws ecr get-login-password --region us-east-1 \
>   | docker login --username AWS --password-stdin 535181393425.dkr.ecr.us-east-1.amazonaws.com
> docker build -t 535181393425.dkr.ecr.us-east-1.amazonaws.com/demo:latest .
> docker push 535181393425.dkr.ecr.us-east-1.amazonaws.com/demo:latest
> ```

## Phase 3 — Create ECS (Fargate) + ALB (Console wizard)

1. **Cluster** — ECS → Create cluster → name `demo-cluster` → Fargate (AWS Fargate
   serverless) → Create.
2. **Task definition** — ECS → Task definitions → Create new (Fargate):
   - Family: `demo-task`
   - Container name: `demo` (must equal `CONTAINER_NAME`)
   - Image URI: `535181393425.dkr.ecr.us-east-1.amazonaws.com/demo:latest`
   - Port mappings: container port **8080** (TCP)
   - CPU/memory: smallest (e.g. 0.25 vCPU / 0.5 GB) is fine for a demo
   - Task role / execution role: let the wizard create
     `ecsTaskExecutionRole` (needs ECR pull + CloudWatch logs).
3. **Service** — from the cluster → Create service:
   - Launch type: Fargate
   - Task definition: `demo-task`
   - Service name: `demo-service`
   - Desired tasks: 1
   - Networking: a VPC with public subnets; **Assign public IP: ENABLED**
   - Load balancer: create an **Application Load Balancer**
     - Listener port 80 → target group port **8080**
     - Health check path: `/`
   - Security groups: ALB allows inbound **80** from anywhere; task SG allows **8080**
     from the ALB SG.
4. Wait until the service is **stable** and the target shows **healthy**, then open the
   ALB DNS name in a browser — you should see the `Good Morning` greeting.

## Phase 4 — Wire ECS back into the pipeline

1. Confirm the ECS **Secrets** hold real values: `ECS_CLUSTER`, `ECS_SERVICE`,
   `ECS_TASK_DEFINITION`, `CONTAINER_NAME`, and `APP_URL` (the ALB DNS, with `http://`
   prefix, no trailing slash). Update `APP_URL` to the actual ALB DNS from Phase 3.
2. Set the **Variable** `DEPLOY_ENABLED` = `true` (Variables tab) to turn on the Deploy
   and Validate jobs.
3. Create the **`production`** GitHub environment (Settings → Environments) — or delete
   the `environment: production` line in the workflow.
4. Push any small change to `main` to prove the full loop:
   `git push` → ECR → ECS rolling update → smoke test passes.

---

## Teardown (it's a 1-day demo — delete to stop charges)

Delete in this order:
1. ECS **service** (set desired count to 0 first, then delete)
2. ECS **cluster**
3. **ALB**, its **target group**, and **listener**
4. **ECR** images / repo (optional)
5. The **IAM access key** (and user, if created just for this)
6. Any **CloudWatch log groups** (`/ecs/demo-task`)

> ALB + Fargate accrue hourly charges even when idle, so don't leave them running
> overnight.

---

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| Build job fails resolving dependencies | `pom.xml` not the fixed version — re-pull |
| Push-to-ECR skipped | Not a `push` to `main` (PRs skip jobs 5–7) |
| Deploy job skipped | `ECS_CLUSTER` variable not set yet (expected before Phase 3) |
| Deploy job never starts | `production` environment missing |
| ECS task keeps restarting | Health check path wrong, or container port ≠ 8080 |
| Target unhealthy | App still booting (start-period 60s) or SG blocks 8080 from ALB |
| Smoke test fails | `APP_URL` wrong, or app not returning `Good Morning` at `/` |
| ECR pull denied in ECS | Task **execution** role lacks ECR permissions |
