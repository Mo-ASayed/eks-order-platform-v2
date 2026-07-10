package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
)

// Event is the SQS message payload.
type Event struct {
	Type      string                 `json:"type"`
	Payload   map[string]interface{} `json:"payload"`
	Timestamp string                 `json:"timestamp"`
}

func main() {
	sqsQueue := os.Getenv("SQS_QUEUE_URL")
	if sqsQueue == "" {
		log.Fatal("SQS_QUEUE_URL is required")
	}

	// Downstream service URLs used by event handlers.
	services := map[string]string{
		"inventory":    getEnv("INVENTORY_SERVICE_URL", "http://inventory-service:8082"),
		"payment":      getEnv("PAYMENT_SERVICE_URL", "http://payment-service:8083"),
		"notification": getEnv("NOTIFICATION_SERVICE_URL", "http://notification-service:8084"),
		"shipping":     getEnv("SHIPPING_SERVICE_URL", "http://shipping-service:8085"),
		"order":        getEnv("ORDER_SERVICE_URL", "http://order-service:8081"),
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Run a health server beside the SQS poller.
	go func() {
		mux := http.NewServeMux()
		mux.HandleFunc("/livez", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
		mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]string{"status": "ok", "service": "worker"})
		})
		port := getEnv("HEALTH_PORT", "8090")
		log.Printf("Worker health check on :%s", port)
		http.ListenAndServe(":"+port, mux)
	}()

	// Stop polling on SIGINT/SIGTERM.
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigChan
		log.Println("Shutting down worker...")
		cancel()
	}()

	log.Println("Worker started, polling SQS for events...")
	pollAndProcess(ctx, sqsQueue, services)
}

func pollAndProcess(ctx context.Context, queueURL string, services map[string]string) {
	client := &http.Client{Timeout: 10 * time.Second}
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(getEnv("AWS_REGION", "eu-west-2")),
	})
	if err != nil {
		log.Fatalf("SQS config error: %v", err)
	}
	sqsClient := sqs.New(sess)

	for {
		select {
		case <-ctx.Done():
			log.Println("Worker stopped")
			return
		default:
			messages := receiveSQSMessages(ctx, sqsClient, queueURL)

			for _, message := range messages {
				if message.Body == nil {
					log.Printf("Skipping SQS message with empty body")
					continue
				}

				var event Event
				if err := json.Unmarshal([]byte(*message.Body), &event); err != nil {
					log.Printf("Failed to parse event: %v", err)
					continue
				}

				log.Printf("Processing event: %s", event.Type)

				if err := handleEvent(client, services, event); err != nil {
					log.Printf("Failed to handle event %s: %v", event.Type, err)
					// Leave failed messages in SQS so retry/DLQ policy handles them.
					continue
				}

				log.Printf("Successfully processed: %s", event.Type)
				if err := deleteSQSMessage(ctx, sqsClient, queueURL, message); err != nil {
					log.Printf("Failed to delete SQS message: %v", err)
				}
			}

			if len(messages) == 0 {
				time.Sleep(5 * time.Second)
			}
		}
	}
}

func handleEvent(client *http.Client, services map[string]string, event Event) error {
	switch event.Type {

	case "order.created":
		return handleOrderCreated(client, services, event.Payload)

	case "order.status_changed":
		return handleOrderStatusChanged(client, services, event.Payload)

	case "payment.completed":
		return handlePaymentCompleted(client, services, event.Payload)

	case "payment.failed":
		return handlePaymentFailed(client, services, event.Payload)

	case "shipment.created":
		// The order is already "processing" (that transition is what created the
		// shipment), so there is nothing to advance here. Just acknowledge it.
		log.Printf("  -> Shipment %v created for order %v",
			event.Payload["shipment_id"], event.Payload["order_id"])

	case "shipment.delivered":
		return handleShipmentDelivered(client, services, event.Payload)

	default:
		log.Printf("  -> Unknown event type: %s (skipping)", event.Type)
	}

	return nil
}

// handleOrderCreated drives the start of the fulfillment flow: reserve stock,
// then charge payment. The payment service publishes payment.completed or
// payment.failed, which advance the order from there.
func handleOrderCreated(client *http.Client, services map[string]string, p map[string]interface{}) error {
	orderID := payloadInt(p, "order_id")
	customerID := payloadString(p, "customer_id")
	total := payloadFloat(p, "total")
	currency := payloadString(p, "currency")
	if currency == "" {
		currency = "GBP"
	}

	// 1. Reserve inventory.
	reserveItems := []map[string]interface{}{}
	for _, it := range payloadItems(p) {
		reserveItems = append(reserveItems, map[string]interface{}{
			"product_id": it["product_id"],
			"quantity":   it["quantity"],
		})
	}
	log.Printf("  -> Reserving inventory for order %d", orderID)
	status, err := doPost(client, services["inventory"]+"/reserve", map[string]interface{}{
		"order_id": orderID,
		"items":    reserveItems,
	})
	if err != nil {
		return fmt.Errorf("reserve inventory: %w", err) // transient, allow retry/DLQ
	}
	if status == http.StatusConflict || status == http.StatusNotFound {
		// Out of stock / unknown product: a business outcome, not a transient
		// fault. Cancel the order and stop (do not charge).
		log.Printf("  -> Reservation rejected (%d), cancelling order %d", status, orderID)
		return updateOrderStatus(client, services, orderID, "cancelled")
	}
	if status >= 500 {
		return fmt.Errorf("reserve inventory returned %d", status)
	}

	// 2. Charge payment. A declined card comes back as 402 and the payment
	// service still emits payment.failed, so only treat 5xx/transport as errors.
	log.Printf("  -> Charging payment for order %d (%.2f %s)", orderID, total, currency)
	status, err = doPost(client, services["payment"]+"/charge", map[string]interface{}{
		"order_id":    orderID,
		"customer_id": customerID,
		"amount":      total,
		"currency":    currency,
		"method":      "card",
	})
	if err != nil {
		return fmt.Errorf("charge payment: %w", err)
	}
	if status >= 500 {
		return fmt.Errorf("charge payment returned %d", status)
	}
	return nil
}

// handlePaymentCompleted confirms the order and sends the confirmation message.
func handlePaymentCompleted(client *http.Client, services map[string]string, p map[string]interface{}) error {
	orderID := payloadInt(p, "order_id")
	customerID := payloadString(p, "customer_id")
	log.Printf("  -> Payment completed, confirming order %d", orderID)
	if err := updateOrderStatus(client, services, orderID, "confirmed"); err != nil {
		return err
	}
	sendNotification(client, services, customerID, "order_confirmed", map[string]interface{}{
		"OrderID":      orderID,
		"CustomerName": customerID,
		"Total":        payloadFloat(p, "amount"),
		"Currency":     payloadString(p, "currency"),
	})
	return nil
}

// handlePaymentFailed cancels the order and notifies the customer. Cancelling
// emits order.status_changed=cancelled, which releases the reservation.
func handlePaymentFailed(client *http.Client, services map[string]string, p map[string]interface{}) error {
	orderID := payloadInt(p, "order_id")
	customerID := payloadString(p, "customer_id")
	log.Printf("  -> Payment failed, cancelling order %d", orderID)
	if err := updateOrderStatus(client, services, orderID, "cancelled"); err != nil {
		return err
	}
	sendNotification(client, services, customerID, "payment_failed", map[string]interface{}{
		"OrderID": orderID,
	})
	return nil
}

// handleOrderStatusChanged reacts to manual/automatic order transitions made
// through the dashboard or by this worker.
func handleOrderStatusChanged(client *http.Client, services map[string]string, p map[string]interface{}) error {
	orderID := payloadInt(p, "order_id")
	newStatus := payloadString(p, "new_status")

	switch newStatus {
	case "processing":
		// Create a shipment. Look up the order for the recipient identity.
		recipient := payloadString(p, "customer_id")
		if order, err := fetchOrder(client, services, orderID); err == nil {
			if c := payloadString(order, "customer_id"); c != "" {
				recipient = c
			}
		}
		log.Printf("  -> Creating shipment for order %d", orderID)
		status, err := doPost(client, services["shipping"]+"/shipments", map[string]interface{}{
			"order_id":       orderID,
			"carrier":        "royal_mail",
			"recipient_name": recipient,
		})
		if err != nil {
			return fmt.Errorf("create shipment: %w", err)
		}
		if status >= 500 {
			return fmt.Errorf("create shipment returned %d", status)
		}

	case "shipped":
		sendNotification(client, services, orderCustomer(client, services, orderID),
			"order_shipped", map[string]interface{}{"OrderID": orderID})

	case "delivered":
		sendNotification(client, services, orderCustomer(client, services, orderID),
			"order_delivered", map[string]interface{}{"OrderID": orderID})

	case "cancelled":
		// Release any inventory reservation held for this order.
		log.Printf("  -> Releasing inventory reservation for order %d", orderID)
		if _, err := doPost(client, services["inventory"]+"/release", map[string]interface{}{
			"order_id": orderID,
		}); err != nil {
			return fmt.Errorf("release inventory: %w", err)
		}
	}
	return nil
}

// handleShipmentDelivered marks the order delivered once the carrier confirms.
func handleShipmentDelivered(client *http.Client, services map[string]string, p map[string]interface{}) error {
	orderID := payloadInt(p, "order_id")
	log.Printf("  -> Shipment delivered, marking order %d delivered", orderID)
	return updateOrderStatus(client, services, orderID, "delivered")
}

// orderCustomer best-effort resolves the customer email for an order.
func orderCustomer(client *http.Client, services map[string]string, orderID int) string {
	if order, err := fetchOrder(client, services, orderID); err == nil {
		return payloadString(order, "customer_id")
	}
	return ""
}

// updateOrderStatus PUTs a new status to the order service. A 409 means the
// transition is no longer valid (e.g. already in that state) and is not retried.
func updateOrderStatus(client *http.Client, services map[string]string, orderID int, newStatus string) error {
	status, err := doRequest(client, http.MethodPut, services["order"]+"/status", map[string]interface{}{
		"order_id":   orderID,
		"new_status": newStatus,
	})
	if err != nil {
		return fmt.Errorf("order status -> %s: %w", newStatus, err)
	}
	if status == http.StatusConflict {
		log.Printf("  -> Order %d transition to %s rejected as invalid (%d)", orderID, newStatus, status)
		return nil
	}
	if status >= 500 {
		return fmt.Errorf("order status -> %s returned %d", newStatus, status)
	}
	return nil
}

// sendNotification fires a templated message; failures are logged but do not
// fail the event (a missed email should not block the order flow).
func sendNotification(client *http.Client, services map[string]string, recipient, template string, data map[string]interface{}) {
	if recipient == "" {
		log.Printf("  -> Skipping %s notification: no recipient", template)
		return
	}
	if _, err := doPost(client, services["notification"]+"/send", map[string]interface{}{
		"recipient": recipient,
		"channel":   "email",
		"template":  template,
		"data":      data,
	}); err != nil {
		log.Printf("  -> Notification %s failed: %v", template, err)
	}
}

// fetchOrder retrieves an order from the order service as a generic map.
func fetchOrder(client *http.Client, services map[string]string, orderID int) (map[string]interface{}, error) {
	resp, err := client.Get(fmt.Sprintf("%s/%d", services["order"], orderID))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("order fetch returned %d", resp.StatusCode)
	}
	var order map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&order); err != nil {
		return nil, err
	}
	return order, nil
}

func doPost(client *http.Client, url string, body interface{}) (int, error) {
	return doRequest(client, http.MethodPost, url, body)
}

func doRequest(client *http.Client, method, url string, body interface{}) (int, error) {
	data, err := json.Marshal(body)
	if err != nil {
		return 0, err
	}
	req, err := http.NewRequest(method, url, bytes.NewReader(data))
	if err != nil {
		return 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)
	return resp.StatusCode, nil
}

// --- payload extraction helpers (JSON numbers arrive as float64) ---

func payloadInt(p map[string]interface{}, key string) int {
	switch v := p[key].(type) {
	case float64:
		return int(v)
	case int:
		return v
	case string:
		n, _ := strconv.Atoi(v)
		return n
	}
	return 0
}

func payloadFloat(p map[string]interface{}, key string) float64 {
	switch v := p[key].(type) {
	case float64:
		return v
	case int:
		return float64(v)
	case string:
		f, _ := strconv.ParseFloat(v, 64)
		return f
	}
	return 0
}

func payloadString(p map[string]interface{}, key string) string {
	if v, ok := p[key].(string); ok {
		return v
	}
	return ""
}

func payloadItems(p map[string]interface{}) []map[string]interface{} {
	raw, ok := p["items"].([]interface{})
	if !ok {
		return nil
	}
	items := make([]map[string]interface{}, 0, len(raw))
	for _, it := range raw {
		if m, ok := it.(map[string]interface{}); ok {
			items = append(items, m)
		}
	}
	return items
}

func receiveSQSMessages(ctx context.Context, client *sqs.SQS, queueURL string) []*sqs.Message {
	out, err := client.ReceiveMessageWithContext(ctx, &sqs.ReceiveMessageInput{
		QueueUrl:            aws.String(queueURL),
		MaxNumberOfMessages: aws.Int64(10),
		WaitTimeSeconds:     aws.Int64(20),
	})
	if err != nil {
		log.Printf("SQS receive error: %v", err)
		return nil
	}
	return out.Messages
}

func deleteSQSMessage(ctx context.Context, client *sqs.SQS, queueURL string, message *sqs.Message) error {
	if message == nil {
		return nil
	}
	if message.ReceiptHandle == nil {
		return nil
	}
	_, err := client.DeleteMessageWithContext(ctx, &sqs.DeleteMessageInput{
		QueueUrl:      aws.String(queueURL),
		ReceiptHandle: message.ReceiptHandle,
	})
	return err
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
