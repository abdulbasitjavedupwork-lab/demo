# =============================================================================
# Stage 1 — Dependency cache
#   Copies only the POM and wrapper so this layer rebuilds only when
#   dependencies change, not on every source edit.
# =============================================================================
FROM eclipse-temurin:17-jdk-alpine AS deps

WORKDIR /build

COPY mvnw mvnw
COPY .mvn/ .mvn/
COPY pom.xml pom.xml

RUN chmod +x mvnw \
    && ./mvnw dependency:go-offline -B --no-transfer-progress

# =============================================================================
# Stage 2 — Build & package
#   Source is copied after deps so the expensive download layer stays cached.
# =============================================================================
FROM deps AS builder

COPY src/ src/

RUN ./mvnw package -DskipTests -B --no-transfer-progress

# =============================================================================
# Stage 3 — Minimal runtime image
#   JRE-only Alpine image; no compiler, no shell tools, minimal attack surface.
# =============================================================================
FROM eclipse-temurin:17-jre-alpine AS runtime

# OCI standard labels — consumed by ECR, Trivy, and audit tooling
LABEL org.opencontainers.image.title="demo" \
      org.opencontainers.image.description="Spring Boot Demo – rashone" \
      org.opencontainers.image.vendor="com.rashone" \
      org.opencontainers.image.base.name="eclipse-temurin:17-jre-alpine"

# Create a dedicated non-root user/group; never run as root
RUN addgroup -S appgroup \
    && adduser -S appuser -G appgroup

WORKDIR /app

# Copy only the repackaged fat JAR from the builder stage
COPY --from=builder --chown=appuser:appgroup \
     /build/target/demo-0.0.1-SNAPSHOT.jar app.jar

# Drop all privileges
USER appuser

# Document the port; actual binding is done by ECS task definition
EXPOSE 8080

# Container-aware JVM: honours cgroup memory limits and uses /dev/urandom
# so the JVM doesn't block waiting for entropy inside a container.
ENTRYPOINT ["java", \
  "-XX:+UseContainerSupport", \
  "-XX:MaxRAMPercentage=75.0", \
  "-Djava.security.egd=file:/dev/./urandom", \
  "-Dspring.backgroundpreinitializer.ignore=true", \
  "-jar", "app.jar"]

# Lightweight health check using wget (busybox, already in Alpine)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD wget -qO- http://localhost:8080/ || exit 1
