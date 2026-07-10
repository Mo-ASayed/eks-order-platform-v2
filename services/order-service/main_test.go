package main

import (
	"errors"
	"net/http"
	"testing"
)

// stubLookup is an in-memory productLookup for tests. If err is set, every
// lookup fails with it; otherwise unknown IDs return errProductNotFound.
type stubLookup struct {
	products map[string]productInfo
	err      error
}

func (s stubLookup) Get(productID string) (productInfo, error) {
	if s.err != nil {
		return productInfo{}, s.err
	}
	p, ok := s.products[productID]
	if !ok {
		return productInfo{}, errProductNotFound
	}
	return p, nil
}

func TestResolveOrderUsesInventoryPriceNotClientPrice(t *testing.T) {
	lookup := stubLookup{products: map[string]productInfo{
		"kb-001": {ID: "kb-001", Price: 42.50, Available: 10},
	}}
	// Client tries to smuggle in a price of 1.00 - it must be ignored.
	items := []OrderItem{{ProductID: "kb-001", Quantity: 2, Price: 1.00}}

	resolved, total, err := resolveOrder(lookup, items)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(resolved) != 1 {
		t.Fatalf("expected 1 resolved item, got %d", len(resolved))
	}
	if resolved[0].Price != 42.50 {
		t.Fatalf("expected authoritative price 42.50, got %v", resolved[0].Price)
	}
	if total != 85.00 {
		t.Fatalf("expected total 85.00 (2 x 42.50), got %v", total)
	}
}

func TestResolveOrderUnknownProductIsNotFound(t *testing.T) {
	lookup := stubLookup{products: map[string]productInfo{}}
	items := []OrderItem{{ProductID: "does-not-exist", Quantity: 1}}

	_, _, err := resolveOrder(lookup, items)

	var ve *orderValidationError
	if !errors.As(err, &ve) || ve.status != http.StatusNotFound {
		t.Fatalf("expected 404 orderValidationError, got %v", err)
	}
}

func TestResolveOrderInsufficientStockIsConflict(t *testing.T) {
	lookup := stubLookup{products: map[string]productInfo{
		"kb-001": {ID: "kb-001", Price: 10, Available: 3},
	}}
	items := []OrderItem{{ProductID: "kb-001", Quantity: 5}}

	_, _, err := resolveOrder(lookup, items)

	var ve *orderValidationError
	if !errors.As(err, &ve) || ve.status != http.StatusConflict {
		t.Fatalf("expected 409 orderValidationError, got %v", err)
	}
}

func TestResolveOrderInventoryUnavailableIsServiceUnavailable(t *testing.T) {
	lookup := stubLookup{err: errors.New("connection refused")}
	items := []OrderItem{{ProductID: "kb-001", Quantity: 1}}

	_, _, err := resolveOrder(lookup, items)

	var ve *orderValidationError
	if !errors.As(err, &ve) || ve.status != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 orderValidationError, got %v", err)
	}
}

func TestResolveOrderRejectsNonPositiveQuantity(t *testing.T) {
	lookup := stubLookup{products: map[string]productInfo{
		"kb-001": {ID: "kb-001", Price: 10, Available: 3},
	}}
	items := []OrderItem{{ProductID: "kb-001", Quantity: 0}}

	_, _, err := resolveOrder(lookup, items)

	var ve *orderValidationError
	if !errors.As(err, &ve) || ve.status != http.StatusBadRequest {
		t.Fatalf("expected 400 orderValidationError, got %v", err)
	}
}

func TestResolveOrderSumsMultipleItems(t *testing.T) {
	lookup := stubLookup{products: map[string]productInfo{
		"kb-001": {ID: "kb-001", Price: 20, Available: 10},
		"ms-002": {ID: "ms-002", Price: 5, Available: 10},
	}}
	items := []OrderItem{
		{ProductID: "kb-001", Quantity: 2},
		{ProductID: "ms-002", Quantity: 3},
	}

	resolved, total, err := resolveOrder(lookup, items)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(resolved) != 2 {
		t.Fatalf("expected 2 resolved items, got %d", len(resolved))
	}
	if total != 55.00 { // 2*20 + 3*5
		t.Fatalf("expected total 55.00, got %v", total)
	}
}
