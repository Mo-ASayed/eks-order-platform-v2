package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	_ "github.com/lib/pq"
)

var db *sql.DB

// lookup resolves authoritative product pricing/stock from the inventory
// service. It is an interface so tests can substitute an in-memory stub.
var lookup productLookup

type Order struct {
	ID         int             `json:"id"`
	CustomerID string          `json:"customer_id"`
	Status     string          `json:"status"`
	Items      json.RawMessage `json:"items"`
	Total      float64         `json:"total"`
	Currency   string          `json:"currency"`
	Notes      string          `json:"notes,omitempty"`
	CreatedAt  string          `json:"created_at"`
	UpdatedAt  string          `json:"updated_at"`
}

type CreateOrderRequest struct {
	Items    []OrderItem `json:"items"`
	Currency string      `json:"currency"`
	Notes    string      `json:"notes,omitempty"`
}

type OrderItem struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
	// Price is resolved from the inventory service, never trusted from the
	// client. Any price sent in the request body is ignored.
	Price float64 `json:"price"`
}

// productInfo is the subset of a product the order service needs to price and
// validate an order line.
type productInfo struct {
	ID        string
	Price     float64
	Available int
}

// productLookup fetches authoritative product data by ID.
type productLookup interface {
	Get(productID string) (productInfo, error)
}

// errProductNotFound signals the inventory service has no such product.
var errProductNotFound = errors.New("product not found")

// orderValidationError carries the HTTP status the handler should return along
// with a client-facing message, so validation logic stays out of the handler.
type orderValidationError struct {
	status  int
	message string
}

func (e *orderValidationError) Error() string { return e.message }

// resolveOrder looks up the authoritative price and available stock for each
// requested item and returns items stamped with the real price plus the order
// total. The client-supplied price is ignored. It fails fast with an
// *orderValidationError when a product is unknown, out of stock, or inventory
// cannot be reached, so a bad order is never persisted then silently cancelled.
func resolveOrder(lookup productLookup, items []OrderItem) ([]OrderItem, float64, error) {
	resolved := make([]OrderItem, 0, len(items))
	var total float64
	for _, it := range items {
		if it.Quantity <= 0 {
			return nil, 0, &orderValidationError{http.StatusBadRequest,
				fmt.Sprintf("quantity for %q must be positive", it.ProductID)}
		}
		p, err := lookup.Get(it.ProductID)
		if errors.Is(err, errProductNotFound) {
			return nil, 0, &orderValidationError{http.StatusNotFound,
				fmt.Sprintf("unknown product %q", it.ProductID)}
		}
		if err != nil {
			log.Printf("inventory lookup for %q failed: %v", it.ProductID, err)
			return nil, 0, &orderValidationError{http.StatusServiceUnavailable,
				"could not validate order against inventory, please retry"}
		}
		if p.Available < it.Quantity {
			return nil, 0, &orderValidationError{http.StatusConflict,
				fmt.Sprintf("insufficient stock for %s: available %d, requested %d",
					it.ProductID, p.Available, it.Quantity)}
		}
		resolved = append(resolved, OrderItem{
			ProductID: it.ProductID,
			Quantity:  it.Quantity,
			Price:     p.Price,
		})
		total += p.Price * float64(it.Quantity)
	}
	return resolved, total, nil
}

// httpProductLookup resolves products by calling the inventory service.
type httpProductLookup struct {
	client  *http.Client
	baseURL string
}

func (h *httpProductLookup) Get(productID string) (productInfo, error) {
	resp, err := h.client.Get(h.baseURL + "/products/" + url.PathEscape(productID))
	if err != nil {
		return productInfo{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return productInfo{}, errProductNotFound
	}
	if resp.StatusCode != http.StatusOK {
		return productInfo{}, fmt.Errorf("inventory returned %d", resp.StatusCode)
	}
	var p struct {
		Price     float64 `json:"price"`
		Available int     `json:"available"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&p); err != nil {
		return productInfo{}, err
	}
	return productInfo{ID: productID, Price: p.Price, Available: p.Available}, nil
}

// Valid state transitions
var validTransitions = map[string][]string{
	"pending":    {"confirmed", "cancelled"},
	"confirmed":  {"processing", "cancelled"},
	"processing": {"shipped", "cancelled"},
	"shipped":    {"delivered"},
	"delivered":  {},
	"cancelled":  {},
}

func main() {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL is required")
	}

	var err error
	db, err = sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	waitForDB()
	migrate()

	lookup = &httpProductLookup{
		client:  &http.Client{Timeout: 5 * time.Second},
		baseURL: strings.TrimRight(getEnv("INVENTORY_SERVICE_URL", "http://inventory-service:8082"), "/"),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/livez", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("/healthz", handleHealth)
	mux.HandleFunc("/", handleOrders)
	mux.HandleFunc("/status", handleUpdateStatus)

	port := getEnv("PORT", "8081")
	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	go func() {
		log.Printf("Order service listening on :%s", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server error: %v", err)
		}
	}()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	log.Println("Shutting down...")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Printf("graceful shutdown error: %v", err)
	}
}

func migrate() {
	migrations := []string{
		`CREATE TABLE IF NOT EXISTS orders (
			id SERIAL PRIMARY KEY,
			customer_id VARCHAR(255) NOT NULL,
			status VARCHAR(20) NOT NULL DEFAULT 'pending',
			items JSONB NOT NULL,
			total DECIMAL(12,2) NOT NULL DEFAULT 0,
			currency VARCHAR(3) NOT NULL DEFAULT 'GBP',
			notes TEXT,
			created_at TIMESTAMP DEFAULT NOW(),
			updated_at TIMESTAMP DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id)`,
		`CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)`,
		`CREATE TABLE IF NOT EXISTS order_events (
			id SERIAL PRIMARY KEY,
			order_id INTEGER NOT NULL REFERENCES orders(id),
			event_type VARCHAR(50) NOT NULL,
			old_status VARCHAR(20),
			new_status VARCHAR(20),
			metadata JSONB,
			created_at TIMESTAMP DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_order_events_order ON order_events(order_id)`,
	}
	for _, m := range migrations {
		if _, err := db.Exec(m); err != nil {
			log.Fatalf("Migration failed: %v", err)
		}
	}
	log.Println("Order service migrations complete")
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	status := "ok"
	if err := db.Ping(); err != nil {
		status = "unhealthy"
		w.WriteHeader(http.StatusServiceUnavailable)
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": status, "service": "order-service"})
}

func handleOrders(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		// GET / - list orders (filtered by customer from header)
		// GET /{id} - get specific order
		path := strings.TrimPrefix(r.URL.Path, "/")
		if path != "" && path != "/" {
			getOrder(w, r, path)
		} else {
			listOrders(w, r)
		}
	case http.MethodPost:
		createOrder(w, r)
	default:
		httpError(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func createOrder(w http.ResponseWriter, r *http.Request) {
	customerID := r.Header.Get("X-User-Email")
	if customerID == "" {
		httpError(w, "missing customer identity", http.StatusBadRequest)
		return
	}

	var req CreateOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpError(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if len(req.Items) == 0 {
		httpError(w, "order must have at least one item", http.StatusBadRequest)
		return
	}

	// Resolve authoritative prices and validate stock against inventory. This
	// ignores any client-supplied price and rejects unknown / out-of-stock
	// products up front instead of creating an order that gets cancelled later.
	resolvedItems, total, err := resolveOrder(lookup, req.Items)
	if err != nil {
		var ve *orderValidationError
		if errors.As(err, &ve) {
			httpError(w, ve.message, ve.status)
			return
		}
		httpError(w, "failed to validate order", http.StatusInternalServerError)
		return
	}

	currency := req.Currency
	if currency == "" {
		currency = "GBP"
	}

	itemsJSON, _ := json.Marshal(resolvedItems)

	var orderID int
	err = db.QueryRow(
		`INSERT INTO orders (customer_id, status, items, total, currency, notes)
		 VALUES ($1, 'pending', $2, $3, $4, $5) RETURNING id`,
		customerID, itemsJSON, total, currency, req.Notes,
	).Scan(&orderID)

	if err != nil {
		log.Printf("Create order error: %v", err)
		httpError(w, "failed to create order", http.StatusInternalServerError)
		return
	}

	// Record event
	db.Exec(
		`INSERT INTO order_events (order_id, event_type, new_status)
		 VALUES ($1, 'order_created', 'pending')`,
		orderID,
	)

	// Publish to SQS for downstream services (inventory reservation, etc.)
	publishEvent("order.created", map[string]interface{}{
		"order_id":    orderID,
		"customer_id": customerID,
		"items":       resolvedItems,
		"total":       total,
		"currency":    currency,
	})

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"id":     orderID,
		"status": "pending",
		"total":  total,
	})
}

func listOrders(w http.ResponseWriter, r *http.Request) {
	customerID := r.Header.Get("X-User-Email")
	status := r.URL.Query().Get("status")

	query := "SELECT id, customer_id, status, items, total, currency, notes, created_at, updated_at FROM orders WHERE 1=1"
	args := []interface{}{}
	argN := 1

	if customerID != "" {
		query += fmt.Sprintf(" AND customer_id = $%d", argN)
		args = append(args, customerID)
		argN++
	}
	if status != "" {
		query += fmt.Sprintf(" AND status = $%d", argN)
		args = append(args, status)
		argN++
	}
	query += " ORDER BY created_at DESC LIMIT 100"

	rows, err := db.Query(query, args...)
	if err != nil {
		httpError(w, "query failed", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	orders := []Order{}
	for rows.Next() {
		var o Order
		if err := rows.Scan(&o.ID, &o.CustomerID, &o.Status, &o.Items, &o.Total, &o.Currency, &o.Notes, &o.CreatedAt, &o.UpdatedAt); err != nil {
			httpError(w, "scan failed", http.StatusInternalServerError)
			return
		}
		orders = append(orders, o)
	}
	if err := rows.Err(); err != nil {
		httpError(w, "iteration failed", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(orders)
}

func getOrder(w http.ResponseWriter, r *http.Request, id string) {
	var o Order
	err := db.QueryRow(
		"SELECT id, customer_id, status, items, total, currency, notes, created_at, updated_at FROM orders WHERE id = $1",
		id,
	).Scan(&o.ID, &o.CustomerID, &o.Status, &o.Items, &o.Total, &o.Currency, &o.Notes, &o.CreatedAt, &o.UpdatedAt)

	if err != nil {
		httpError(w, "order not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(o)
}

func handleUpdateStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPut {
		httpError(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		OrderID   int    `json:"order_id"`
		NewStatus string `json:"new_status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httpError(w, "invalid request body", http.StatusBadRequest)
		return
	}

	// Get current status
	var currentStatus string
	err := db.QueryRow("SELECT status FROM orders WHERE id = $1", req.OrderID).Scan(&currentStatus)
	if err != nil {
		httpError(w, "order not found", http.StatusNotFound)
		return
	}

	// Validate transition
	allowed, ok := validTransitions[currentStatus]
	if !ok {
		httpError(w, "invalid current status", http.StatusBadRequest)
		return
	}

	valid := false
	for _, s := range allowed {
		if s == req.NewStatus {
			valid = true
			break
		}
	}
	if !valid {
		httpError(w, fmt.Sprintf("cannot transition from %s to %s", currentStatus, req.NewStatus), http.StatusConflict)
		return
	}

	_, err = db.Exec(
		"UPDATE orders SET status = $1, updated_at = NOW() WHERE id = $2",
		req.NewStatus, req.OrderID,
	)
	if err != nil {
		httpError(w, "failed to update order", http.StatusInternalServerError)
		return
	}

	// Record event
	db.Exec(
		`INSERT INTO order_events (order_id, event_type, old_status, new_status)
		 VALUES ($1, 'status_changed', $2, $3)`,
		req.OrderID, currentStatus, req.NewStatus,
	)

	// Publish event
	publishEvent("order.status_changed", map[string]interface{}{
		"order_id":   req.OrderID,
		"old_status": currentStatus,
		"new_status": req.NewStatus,
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"order_id":   req.OrderID,
		"old_status": currentStatus,
		"new_status": req.NewStatus,
	})
}

func publishEvent(eventType string, payload map[string]interface{}) {
	sqsQueue := os.Getenv("SQS_QUEUE_URL")
	if sqsQueue == "" {
		log.Printf("Event (no SQS): %s %v", eventType, payload)
		return
	}

	event := map[string]interface{}{
		"type":      eventType,
		"payload":   payload,
		"timestamp": time.Now().UTC().Format(time.RFC3339),
	}
	data, _ := json.Marshal(event)
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(getEnv("AWS_REGION", "eu-west-2")),
	})
	if err != nil {
		log.Printf("SQS config error: %v", err)
		return
	}
	client := sqs.New(sess)
	if _, err := client.SendMessageWithContext(context.Background(), &sqs.SendMessageInput{
		QueueUrl:    aws.String(sqsQueue),
		MessageBody: aws.String(string(data)),
	}); err != nil {
		log.Printf("SQS send error: %v", err)
		return
	}
	log.Printf("Event sent to SQS: %s", eventType)
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

func waitForDB() {
	for i := 0; i < 120; i++ {
		if err := db.Ping(); err == nil {
			return
		}
		log.Printf("Waiting for database... (%d/120)", i+1)
		time.Sleep(time.Second)
	}
	log.Fatal("Database not ready after 120s")
}
