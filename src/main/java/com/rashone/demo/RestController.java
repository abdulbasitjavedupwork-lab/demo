package com.rashone.demo;

import org.springframework.web.bind.annotation.GetMapping;

import java.util.Map;

/**
 * JSON API endpoints.
 *
 * The root path "/" is intentionally NOT mapped here — it is served by
 * {@link HomeController}, which forwards to the static landing page
 * (src/main/resources/static/index.html).
 */
@org.springframework.web.bind.annotation.RestController
public class RestController {

    @GetMapping("/api/greeting")
    public Map<String, String> greeting() {
        return Map.of(
                "message", "Hello Rashone 225, Good Morning",
                "service", "demo",
                "platform", "AWS ECS Fargate",
                "status", "UP"
        );
    }
}
