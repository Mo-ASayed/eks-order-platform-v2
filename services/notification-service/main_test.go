package main

import "testing"

func TestRenderTemplateSubstitutesOrderID(t *testing.T) {
	// JSON numbers arrive as float64; an order id must render as "42", not "42.00".
	out := renderTemplate("Order Confirmed - #{{.OrderID}}", map[string]interface{}{
		"OrderID": float64(42),
	})
	if out != "Order Confirmed - #42" {
		t.Fatalf("got %q", out)
	}
}

func TestRenderTemplateSubstitutesMultipleFields(t *testing.T) {
	out := renderTemplate(
		"Hi {{.CustomerName}}, order #{{.OrderID}} total {{.Currency}} {{.Total}}",
		map[string]interface{}{
			"CustomerName": "admin@platform.local",
			"OrderID":      float64(7),
			"Currency":     "GBP",
			"Total":        float64(25.5),
		},
	)
	want := "Hi admin@platform.local, order #7 total GBP 25.5"
	if out != want {
		t.Fatalf("got %q, want %q", out, want)
	}
}

func TestRenderTemplateLeavesUnknownPlaceholderUntouched(t *testing.T) {
	out := renderTemplate("Track: {{.TrackingNumber}}", map[string]interface{}{
		"OrderID": float64(1),
	})
	if out != "Track: {{.TrackingNumber}}" {
		t.Fatalf("got %q", out)
	}
}
