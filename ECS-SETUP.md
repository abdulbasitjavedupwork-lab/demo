# ECS Fargate Setup — Console Click-Through

Region **us-east-1** · default VPC · ties back to the ALB from `ALB-SETUP.md`.

Build order:
```
[0] Prereqs: image in ECR (:latest) + ecsTaskExecutionRole
[1] Cluster:        demo-cluster   (Fargate)
[2] Task definition: demo-task     (container demo :8080, exec role, logs)
[3] Service:        demo-service   (1 task, attaches to demo-tg + demo-task-sg)
```

ECR repo URI: `535181393425.dkr.ecr.us-east-1.amazonaws.com/demo`

---

## 0. Prerequisites (check before you start)

**a) An image must already be in ECR tagged `latest`.** The task definition points at
`.../demo:latest`; if the repo is empty the task can't pull and will crash-loop.
- ECR → Repositories → `demo` → confirm at least one image (tag `latest`).
- If empty, seed it once (push to `main` runs the pipeline's *Push to ECR* job, or push
  manually per `AWS-DEPLOYMENT.md` Phase 2).

**b) Task execution role** `ecsTaskExecutionRole` (ECR pull + CloudWatch logs).
- The task-definition wizard creates it automatically if missing. To pre-create:
  IAM → Roles → Create role → AWS service → **Elastic Container Service Task** →
  attach **`AmazonECSTaskExecutionRolePolicy`** → name `ecsTaskExecutionRole`.

---

## 1. Cluster — `demo-cluster`
**ECS → Clusters → Create cluster**
- Cluster name: `demo-cluster`
- Infrastructure: **AWS Fargate (serverless)** — leave checked
- **Create**

---

## 2. Task definition — `demo-task`
**ECS → Task definitions → Create new task definition** (the form, not "with JSON")

- **Task definition family:** `demo-task`
- **Launch type:** AWS Fargate
- **OS/Architecture:** Linux/X86_64
- **CPU:** `.25 vCPU` · **Memory:** `.5 GB`  (smallest — fine for the demo)
- **Task role:** `None`
- **Task execution role:** `ecsTaskExecutionRole`  (or "Create new role")

**Container - 1**
- **Name:** `demo`   ← must equal pipeline var `CONTAINER_NAME`
- **Image URI:** `535181393425.dkr.ecr.us-east-1.amazonaws.com/demo:latest`
- **Essential container:** Yes
- **Port mappings:** Container port `8080` · Protocol `TCP` · App protocol `HTTP`
- **Logging:** leave **Use log collection** on → creates log group `/ecs/demo-task`
- (Optional) **Health check** — leave empty; the ALB target group already health-checks `/`

- **Create**

---

## 3. Service — `demo-service`  (connects ECS ↔ ALB)
**ECS → Clusters → `demo-cluster` → Services tab → Create**

**Environment / Compute**
- Compute options: **Launch type**
- Launch type: **FARGATE** · Platform version: `LATEST`

**Deployment configuration**
- Application type: **Service**
- Family: `demo-task` · Revision: `LATEST`
- Service name: `demo-service`
- Desired tasks: `1`

**Networking**
- VPC: **default**
- Subnets: select the **public subnets** (same AZs you gave the ALB)
- Security group: **Use an existing security group → `demo-task-sg`**
  (remove any auto-created default)
- **Public IP: Turned ON**   ← required so the task can pull from ECR

**Load balancing**
- Load balancer type: **Application Load Balancer**
- **Use an existing load balancer → `demo-alb`**
- Listener: **Use an existing listener → `80 : HTTP`**
- Target group: **Use an existing target group → `demo-tg`**
- Health check grace period: **`60`** seconds (Spring Boot ~60s start; avoids early kills)

- **Create**

---

## 4. Verify
1. ECS → `demo-cluster` → `demo-service` → **Tasks** → task goes `PROVISIONING → RUNNING`.
2. EC2 → Target Groups → `demo-tg` → **Targets** → status flips `initial → healthy`
   (~30–90s after the task is RUNNING).
3. Open `http://<demo-alb-dns>/` → you should see **`Good Morning`**.
   (The earlier **503** disappears once one target is healthy.)

---

## Troubleshooting
| Symptom | Likely cause |
|---------|--------------|
| Task `STOPPED`, "CannotPullContainerError" | No `:latest` image in ECR, or exec role missing ECR perms |
| Task `STOPPED`, exit before running | Wrong image / app crash — check `/ecs/demo-task` logs |
| Target stuck `unhealthy` | Health path ≠ `/`, port ≠ 8080, or `demo-task-sg` doesn't allow 8080 from `demo-alb-sg` |
| Target stuck `initial`, task RUNNING | Grace period too short — app still booting |
| ALB still returns 503 | No healthy targets yet (wait), or service didn't attach to `demo-tg` |
| Task can't reach ECR | Public IP not enabled on the service |

---

## After it's green — wire the pipeline (`AWS-DEPLOYMENT.md` Phase 4)
Add GitHub **Variables**:
```
ECS_CLUSTER        = demo-cluster
ECS_SERVICE        = demo-service
ECS_TASK_DEFINITION= demo-task
CONTAINER_NAME     = demo
APP_URL            = http://<demo-alb-dns>
```
Create the **`production`** GitHub environment (or remove `environment: production` from
`devsecops.yml`). Then a push to `main` does ECR → ECS rolling update → smoke test.
