package com.rashone.demo;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

/**
 * Serves the static landing page at the root path.
 *
 * Using an explicit forward (rather than relying on Spring Boot's welcome-page
 * handler) guarantees that GET "/" returns 200 text/html for ANY Accept header,
 * including the ALB health checker — keeping the target healthy.
 */
@Controller
public class HomeController {

    @GetMapping("/")
    public String home() {
        return "forward:/index.html";
    }
}
