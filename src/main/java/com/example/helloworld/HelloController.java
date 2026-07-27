package com.example.helloworld;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.LinkedHashMap;
import java.util.Map;

@RestController
public class HelloController {

    @GetMapping("/")
    public Map<String, String> hello() {
        Map<String, String> response = new LinkedHashMap<>();
        response.put("message", "Hello World from AWS!");
        response.put("host", getHostName());
        response.put("deployment", System.getenv().getOrDefault("DEPLOYMENT_TYPE", "local"));
        response.put("version", "1.0.0");
        return response;
    }

    @GetMapping("/hello")
    public String helloText() {
        return "Hello World! Running on: " + getHostName();
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        Map<String, String> response = new LinkedHashMap<>();
        response.put("status", "UP");
        response.put("host", getHostName());
        return response;
    }

    private String getHostName() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            return "unknown";
        }
    }
}
