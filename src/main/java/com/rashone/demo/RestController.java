package com.rashone.demo;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;

@org.springframework.web.bind.annotation.RestController
public class RestController {
    @GetMapping("/")
    public ResponseEntity<String> sayGi()
    {
        return ResponseEntity.ok("Hello Rashone 222, Good Morning");
    }
}
