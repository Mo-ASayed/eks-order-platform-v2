package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/golang-jwt/jwt/v5"
)

var (
	redisClient     *redis.Client
	ctx             = context.Background()
	jwtSecret       []byte
	routes          map[string]string
	rateLimitPerMin = 600
)

func main() {
	jwtSecret = []byte(getEnv("JWT_SECRET", "change-me-in-production"))

	if v := os.Getenv("RATE_LIMIT_PER_MIN"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			rateLimitPerMin = n
		} else {
			log.Printf("WARNING: invalid RATE_LIMIT_PER_MIN %q, using default %d", v, rateLimitPerMin)
		}
	}

	// Routes to internal services.
	routes = map[string]string{
		"/api/orders":        getEnv("ORDER_SERVICE_URL", "http://order-service:8081"),
		"/api/inventory":     getEnv("INVENTORY_SERVICE_URL", "http://inventory-service:8082"),
		"/api/payments":      getEnv("PAYMENT_SERVICE_URL", "http://payment-service:8083"),
		"/api/notifications": getEnv("NOTIFICATION_SERVICE_URL", "http://notification-service:8084"),
		"/api/shipping":      getEnv("SHIPPING_SERVICE_URL", "http://shipping-service:8085"),
		"/api/dashboard":     getEnv("DASHBOARD_SERVICE_URL", "http://dashboard-api:8086"),
	}

	// Optional Redis-backed rate limiting.
	redisURL := os.Getenv("REDIS_URL")
	if redisURL != "" {
		opt, err := redis.ParseURL(redisURL)
		if err != nil {
			log.Printf("WARNING: invalid REDIS_URL, rate limiting disabled: %v", err)
		} else {
			redisClient = redis.NewClient(opt)
			if _, err := redisClient.Ping(ctx).Result(); err != nil {
				log.Printf("WARNING: Redis not reachable, rate limiting disabled: %v", err)
				redisClient = nil
			} else {
				log.Println("Redis connected for rate limiting")
			}
		}
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/livez", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("/healthz", handleHealth)
	mux.HandleFunc("/auth/login", handleLogin)
	mux.HandleFunc("/auth/register", handleRegister)
	mux.HandleFunc("/", handleProxy)

	port := getEnv("PORT", "8080")
	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	go gracefulShutdown(server)

	log.Printf("API Gateway listening on :%s", port)
	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "service": "api-gateway"})
}

func handleLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpError(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpError(w, "invalid request body", http.StatusBadRequest)
		return
	}

	// Demo auth accepts any credentials and issues a JWT.
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":  req.Email,
		"role": "customer",
		"exp":  time.Now().Add(24 * time.Hour).Unix(),
		"iat":  time.Now().Unix(),
	})

	tokenString, err := token.SignedString(jwtSecret)
	if err != nil {
		httpError(w, "failed to generate token", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"token": tokenString})
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpError(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
		Name     string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpError(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if req.Email == "" || req.Password == "" {
		httpError(w, "email and password required", http.StatusBadRequest)
		return
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":  req.Email,
		"name": req.Name,
		"role": "customer",
		"exp":  time.Now().Add(24 * time.Hour).Unix(),
		"iat":  time.Now().Unix(),
	})

	tokenString, err := token.SignedString(jwtSecret)
	if err != nil {
		httpError(w, "failed to generate token", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message": "registered",
		"email":   req.Email,
		"token":   tokenString,
	})
}

func handleProxy(w http.ResponseWriter, r *http.Request) {
	// Require auth except for public endpoints. Done before rate limiting so
	// the limiter can key on the authenticated user rather than a shared IP.
	var userEmail string
	if !isPublicPath(r.URL.Path) {
		claims, err := validateToken(r)
		if err != nil {
			httpError(w, "unauthorized: "+err.Error(), http.StatusUnauthorized)
			return
		}
		// Pass identity to downstream services.
		if sub, ok := claims["sub"].(string); ok {
			userEmail = sub
			r.Header.Set("X-User-Email", sub)
		}
		if role, ok := claims["role"].(string); ok {
			r.Header.Set("X-User-Role", role)
		}
	}

	// Apply the rate limit before proxying. Health checks are exempt so the
	// dashboard's frequent polling never starves the budget for real traffic.
	if redisClient != nil && !isHealthCheck(r.URL.Path) {
		// Prefer the authenticated user so multiple tabs behind one NAT/IP
		// are not lumped together; fall back to client IP for public paths.
		subject := userEmail
		if subject == "" {
			subject = "ip:" + clientIP(r)
		}
		key := fmt.Sprintf("rate:%s", subject)
		count, _ := redisClient.Incr(ctx, key).Result()
		if count == 1 {
			redisClient.Expire(ctx, key, time.Minute)
		}
		if count > int64(rateLimitPerMin) {
			httpError(w, "rate limit exceeded", http.StatusTooManyRequests)
			return
		}
	}

	for prefix, targetURL := range routes {
		if strings.HasPrefix(r.URL.Path, prefix) {
			target, err := url.Parse(targetURL)
			if err != nil {
				httpError(w, "bad upstream config", http.StatusInternalServerError)
				return
			}

			proxy := httputil.NewSingleHostReverseProxy(target)
			proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
				log.Printf("Proxy error: %v", err)
				httpError(w, "service unavailable", http.StatusBadGateway)
			}

			// Downstream services receive paths without the gateway prefix.
			r.URL.Path = strings.TrimPrefix(r.URL.Path, prefix)
			if r.URL.Path == "" {
				r.URL.Path = "/"
			}
			r.Header.Set("X-Forwarded-For", r.RemoteAddr)
			r.Header.Set("X-Request-ID", fmt.Sprintf("%d", time.Now().UnixNano()))

			proxy.ServeHTTP(w, r)
			return
		}
	}

	httpError(w, "not found", http.StatusNotFound)
}

func isPublicPath(path string) bool {
	public := []string{"/healthz", "/auth/", "/api/shipping/webhook"}
	for _, p := range public {
		if strings.HasPrefix(path, p) {
			return true
		}
	}
	// Allow downstream health checks without auth.
	if isHealthCheck(path) {
		return true
	}
	return false
}

// isHealthCheck reports whether the path is a liveness/readiness probe. These
// are exempt from rate limiting because the dashboard polls them frequently.
func isHealthCheck(path string) bool {
	return strings.HasSuffix(path, "/healthz") || strings.HasSuffix(path, "/livez")
}

func validateToken(r *http.Request) (jwt.MapClaims, error) {
	auth := r.Header.Get("Authorization")
	if auth == "" {
		return nil, fmt.Errorf("missing Authorization header")
	}

	parts := strings.SplitN(auth, " ", 2)
	if len(parts) != 2 || parts[0] != "Bearer" {
		return nil, fmt.Errorf("invalid Authorization format")
	}

	token, err := jwt.Parse(parts[1], func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method")
		}
		return jwtSecret, nil
	})
	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(jwt.MapClaims); ok && token.Valid {
		return claims, nil
	}
	return nil, fmt.Errorf("invalid token")
}

func httpError(w http.ResponseWriter, msg string, code int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"error": msg})
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		if idx := strings.Index(xff, ","); idx >= 0 {
			return strings.TrimSpace(xff[:idx])
		}
		return strings.TrimSpace(xff)
	}
	if xrip := r.Header.Get("X-Real-IP"); xrip != "" {
		return xrip
	}
	return r.RemoteAddr
}

var shutdownOnce sync.Once

func gracefulShutdown(server *http.Server) {
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan
	shutdownOnce.Do(func() {
		log.Println("Shutting down...")
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		server.Shutdown(ctx)
	})
}
