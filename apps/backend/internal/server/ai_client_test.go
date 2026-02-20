package server

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestOpenAIResponsesClientRetriesOnServerError(t *testing.T) {
	t.Parallel()

	var attempts int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		current := atomic.AddInt32(&attempts, 1)
		w.Header().Set("Content-Type", "application/json")
		if current == 1 {
			w.WriteHeader(http.StatusBadGateway)
			_, _ = w.Write([]byte(`{"error":{"message":"temporary upstream issue"}}`))
			return
		}
		_, _ = w.Write([]byte(`{
			"model":"gpt-5-mini",
			"output":[{"content":[{"type":"output_text","text":"retry ok"}]}],
			"usage":{"input_tokens":10,"output_tokens":4,"total_tokens":14}
		}`))
	}))
	defer server.Close()

	client := &OpenAIResponsesClient{
		apiKey:          "test",
		baseURL:         server.URL,
		model:           "gpt-5-mini",
		maxOutputTokens: 256,
		httpClient: &http.Client{
			Timeout: 2 * time.Second,
		},
	}

	resp, err := client.Query(context.Background(), AIModelRequest{
		Model:      "gpt-5-mini",
		UserPrompt: "hello",
	})
	if err != nil {
		t.Fatalf("expected retry to succeed, got err=%v", err)
	}
	if resp.Answer != "retry ok" {
		t.Fatalf("unexpected answer: %q", resp.Answer)
	}
	if got := atomic.LoadInt32(&attempts); got != 2 {
		t.Fatalf("expected 2 attempts, got %d", got)
	}
}

func TestOpenAIResponsesClientHonorsConfiguredMaxOutputTokens(t *testing.T) {
	t.Parallel()

	var receivedMaxTokens int
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer r.Body.Close()
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("failed to decode request payload: %v", err)
		}
		receivedMaxTokens = int(extractNumber(payload["max_output_tokens"]))
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"model":"gpt-5-mini",
			"output":[{"content":[{"type":"output_text","text":"ok"}]}],
			"usage":{"input_tokens":8,"output_tokens":3,"total_tokens":11}
		}`))
	}))
	defer server.Close()

	client := &OpenAIResponsesClient{
		apiKey:          "test",
		baseURL:         server.URL,
		model:           "gpt-5-mini",
		maxOutputTokens: 320,
		httpClient: &http.Client{
			Timeout: 2 * time.Second,
		},
	}

	_, err := client.Query(context.Background(), AIModelRequest{
		Model:      "gpt-5-mini",
		UserPrompt: "token test",
	})
	if err != nil {
		t.Fatalf("query failed: %v", err)
	}
	if receivedMaxTokens != 320 {
		t.Fatalf("expected max_output_tokens=320, got %d", receivedMaxTokens)
	}
}

func TestOpenAIResponsesClientRetriesWithHigherTokenBudgetOnIncomplete(t *testing.T) {
	t.Parallel()

	var attempts int32
	var firstBudget int
	var secondBudget int

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer r.Body.Close()
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatalf("failed to decode request payload: %v", err)
		}

		current := atomic.AddInt32(&attempts, 1)
		budget := int(extractNumber(payload["max_output_tokens"]))
		if current == 1 {
			firstBudget = budget
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{
				"model":"gpt-5-mini",
				"output":[],
				"incomplete_details":{"reason":"max_output_tokens"}
			}`))
			return
		}

		secondBudget = budget
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"model":"gpt-5-mini",
			"output":[{"content":[{"type":"output_text","text":"retry with larger budget"}]}],
			"usage":{"input_tokens":12,"output_tokens":5,"total_tokens":17}
		}`))
	}))
	defer server.Close()

	client := &OpenAIResponsesClient{
		apiKey:          "test",
		baseURL:         server.URL,
		model:           "gpt-5-mini",
		maxOutputTokens: 600,
		httpClient: &http.Client{
			Timeout: 2 * time.Second,
		},
	}

	resp, err := client.Query(context.Background(), AIModelRequest{
		Model:      "gpt-5-mini",
		UserPrompt: "needs a longer response",
	})
	if err != nil {
		t.Fatalf("query failed: %v", err)
	}
	if resp.Answer != "retry with larger budget" {
		t.Fatalf("unexpected answer: %q", resp.Answer)
	}
	if got := atomic.LoadInt32(&attempts); got != 2 {
		t.Fatalf("expected 2 attempts, got %d", got)
	}
	if firstBudget != 600 {
		t.Fatalf("expected first max_output_tokens=600, got %d", firstBudget)
	}
	if secondBudget <= firstBudget {
		t.Fatalf("expected second token budget to increase (first=%d second=%d)", firstBudget, secondBudget)
	}
}

func extractNumber(value any) float64 {
	switch v := value.(type) {
	case float64:
		return v
	case int:
		return float64(v)
	default:
		return 0
	}
}
