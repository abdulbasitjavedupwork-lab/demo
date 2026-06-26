# ALB Setup — Console Click-Through (default VPC)

Region **us-east-1** · default VPC · target container port **8080** · ALB listener **80**.

Create in this order. The target group is **type IP** (required for Fargate `awsvpc`
networking) and stays **empty** until the ECS service registers tasks into it — that's
expected.

```
[1] SG: demo-alb-sg   (inbound 80 from internet)
[2] SG: demo-task-sg  (inbound 8080 from demo-alb-sg)   ← used later by ECS
[3] Target group: demo-tg  (IP, HTTP:8080, health check /)
[4] ALB: demo-alb  (internet-facing, :80 → demo-tg)
```

---

## 1. Security group — `demo-alb-sg`
**EC2 → Security Groups → Create security group**
- Name: `demo-alb-sg`  · Description: `ALB inbound 80` · VPC: **default**
- **Inbound rules → Add rule:**
  - Type `HTTP` · Port `80` · Source `Anywhere-IPv4` (`0.0.0.0/0`)
- Outbound: leave default (all traffic) → **Create security group**

## 2. Security group — `demo-task-sg`  (create now, ECS uses it later)
**EC2 → Security Groups → Create security group**
- Name: `demo-task-sg` · Description: `Fargate task 8080 from ALB` · VPC: **default**
- **Inbound rules → Add rule:**
  - Type `Custom TCP` · Port `8080` · Source: **Custom → pick `demo-alb-sg`**
    (only the ALB can reach the container, not the internet)
- Outbound: leave default → **Create security group**

## 3. Target group — `demo-tg`
**EC2 → Target Groups → Create target group**
- Choose a target type: **IP addresses**  ← important for Fargate
- Target group name: `demo-tg`
- Protocol `HTTP` · Port `8080`
- VPC: **default** · Protocol version: `HTTP1`
- **Health checks:** Protocol `HTTP` · Path `/`
  - (Advanced, optional) Healthy threshold `2`, Interval `30s` — fine to leave defaults
- **Next** → on the "Register targets" page register **nothing** → **Create target group**

## 4. Application Load Balancer — `demo-alb`
**EC2 → Load Balancers → Create load balancer → Application Load Balancer → Create**
- Load balancer name: `demo-alb`
- Scheme: **Internet-facing** · IP address type: `IPv4`
- **Network mapping:** VPC **default** → select **at least 2 Availability Zones**, each
  with a **public subnet** (an ALB requires 2+ AZs)
- **Security groups:** remove the default SG, add **`demo-alb-sg`**
- **Listeners and routing:** Protocol `HTTP` · Port `80` → Default action: **Forward to
  `demo-tg`**
- **Create load balancer** → wait until **State: Active**

## 5. Grab the DNS name
Open `demo-alb` → copy the **DNS name**
(`demo-alb-xxxxxxxxx.us-east-1.elb.amazonaws.com`).

This becomes the pipeline variable:
```
APP_URL = http://demo-alb-xxxxxxxxx.us-east-1.elb.amazonaws.com
```

> Until ECS is created, the target group has no targets, so hitting the DNS now returns
> **503 Service Unavailable**. That's normal — it resolves once the ECS service registers
> a healthy task (next step).

---

## What ECS will need from this step (next phase)
| Value | Where it came from |
|-------|--------------------|
| Target group `demo-tg` (ARN) | step 3 — ECS service "Load balancing" attaches to it |
| `demo-task-sg` | step 2 — assigned to the Fargate task |
| Container port `8080` | matches `demo-tg` and the Dockerfile `EXPOSE 8080` |
| `APP_URL` | step 5 — pipeline variable + smoke test |
