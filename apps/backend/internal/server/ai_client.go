package server

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"babyai/apps/backend/internal/config"
)

type ChatTurn struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type AIUsage struct {
	PromptTokens     int `json:"prompt_tokens"`
	CompletionTokens int `json:"completion_tokens"`
	TotalTokens      int `json:"total_tokens"`
}

type AIModelRequest struct {
	Model        string
	SystemPrompt string
	Conversation []ChatTurn
	UserPrompt   string
}

type AIModelResponse struct {
	Answer string
	Model  string
	Usage  AIUsage
}

type AIClient interface {
	Query(ctx context.Context, req AIModelRequest) (AIModelResponse, error)
}

type OpenAIResponsesClient struct {
	apiKey          string
	baseURL         string
	model           string
	maxOutputTokens int
	httpClient      *http.Client
}

type MockAIClient struct {
	Model string
}

func (m MockAIClient) Query(_ context.Context, req AIModelRequest) (AIModelResponse, error) {
	question := strings.TrimSpace(req.UserPrompt)
	if question == "" {
		question = "No question provided."
	}
	lowered := strings.ToLower(question)

	answer := "Mock response: " + question
	if strings.Contains(lowered, "fever") || strings.Contains(lowered, "diarrhea") || strings.Contains(lowered, "vomit") {
		answer = strings.Join([]string{
			"1) Record summary: recent records suggest symptom monitoring is needed; missing data is possible.",
			"2) Possibilities: viral illness, mild GI upset, feeding intolerance.",
			"3) Before visit: hydrate, track temperature every 4-6h, monitor urine/feeding.",
			"4) Where to go: Pediatrics first; ER if symptoms rapidly worsen.",
			"5) Red flags: breathing trouble, blood in stool/vomit, persistent high fever, low urine output.",
		}, "\n")
	}
	if strings.Contains(lowered, "sleep") && !strings.Contains(lowered, "fever") {
		answer = "Mock response: sleep routine can be adjusted with consistent bedtime and nap windows."
	}

	model := strings.TrimSpace(req.Model)
	if model == "" {
		model = strings.TrimSpace(m.Model)
	}
	if model == "" {
		model = "gpt-5-mini"
	}
	return AIModelResponse{
		Answer: answer,
		Model:  model,
		Usage: AIUsage{
			PromptTokens:     120,
			CompletionTokens: 80,
			TotalTokens:      200,
		},
	}, nil
}

func NewOpenAIResponsesClient(cfg config.Config) *OpenAIResponsesClient {
	timeoutSeconds := cfg.AITimeoutSeconds
	if timeoutSeconds <= 0 {
		timeoutSeconds = 20
	}
	return &OpenAIResponsesClient{
		apiKey:          strings.TrimSpace(cfg.OpenAIAPIKey),
		baseURL:         strings.TrimRight(strings.TrimSpace(cfg.OpenAIBaseURL), "/"),
		model:           strings.TrimSpace(cfg.OpenAIModel),
		maxOutputTokens: cfg.AIMaxOutputTokens,
		httpClient: &http.Client{
			Timeout: time.Duration(timeoutSeconds) * time.Second,
		},
	}
}

func (c *OpenAIResponsesClient) Query(ctx context.Context, req AIModelRequest) (AIModelResponse, error) {
	if strings.TrimSpace(c.apiKey) == "" {
		return AIModelResponse{}, errors.New("OPENAI_API_KEY is not configured")
	}
	if strings.TrimSpace(c.baseURL) == "" {
		return AIModelResponse{}, errors.New("OPENAI_BASE_URL is not configured")
	}
	defaultModel := strings.TrimSpace(c.model)
	if defaultModel == "" {
		return AIModelResponse{}, errors.New("OPENAI_MODEL is not configured")
	}
	requestModel := strings.TrimSpace(req.Model)
	if requestModel == "" {
		requestModel = defaultModel
	}

	type inputText struct {
		Type string `json:"type"`
		Text string `json:"text"`
	}
	type inputBlock struct {
		Role    string      `json:"role"`
		Content []inputText `json:"content"`
	}
	hasAssistantTurn := false
	for _, turn := range req.Conversation {
		if strings.EqualFold(strings.TrimSpace(turn.Role), "assistant") {
			hasAssistantTurn = true
			break
		}
	}

	buildInput := func(includeAssistantTurns bool) []inputBlock {
		input := make([]inputBlock, 0, len(req.Conversation)+2)
		if strings.TrimSpace(req.SystemPrompt) != "" {
			input = append(input, inputBlock{
				Role:    "system",
				Content: []inputText{{Type: "input_text", Text: strings.TrimSpace(req.SystemPrompt)}},
			})
		}
		for _, turn := range req.Conversation {
			role := strings.ToLower(strings.TrimSpace(turn.Role))
			if role != "user" && role != "assistant" {
				continue
			}
			if role == "assistant" && !includeAssistantTurns {
				continue
			}
			content := strings.TrimSpace(turn.Content)
			if content == "" {
				continue
			}
			contentType := "input_text"
			if role == "assistant" {
				contentType = "output_text"
			}
			input = append(input, inputBlock{
				Role:    role,
				Content: []inputText{{Type: contentType, Text: content}},
			})
		}
		userPrompt := strings.TrimSpace(req.UserPrompt)
		if userPrompt != "" {
			input = append(input, inputBlock{
				Role:    "user",
				Content: []inputText{{Type: "input_text", Text: userPrompt}},
			})
		}
		return input
	}

	maxTokens := c.maxOutputTokens
	if maxTokens < 1200 {
		maxTokens = 1200
	}

	callResponses := func(input []inputBlock) (int, []byte, error) {
		if len(input) == 0 {
			return 0, nil, errors.New("AI request input is empty")
		}
		payload := map[string]any{
			"model":             requestModel,
			"input":             input,
			"max_output_tokens": maxTokens,
			"reasoning": map[string]any{
				"effort": "low",
			},
			"text": map[string]any{
				"verbosity": "low",
			},
		}
		bodyRaw, err := json.Marshal(payload)
		if err != nil {
			return 0, nil, err
		}

		request, err := http.NewRequestWithContext(
			ctx,
			http.MethodPost,
			c.baseURL+"/responses",
			bytes.NewReader(bodyRaw),
		)
		if err != nil {
			return 0, nil, err
		}
		request.Header.Set("Authorization", "Bearer "+c.apiKey)
		request.Header.Set("Content-Type", "application/json")

		response, err := c.httpClient.Do(request)
		if err != nil {
			return 0, nil, err
		}
		defer response.Body.Close()

		responseBody, err := io.ReadAll(response.Body)
		if err != nil {
			return 0, nil, err
		}
		return response.StatusCode, responseBody, nil
	}

	input := buildInput(true)
	statusCode, responseBody, err := callResponses(input)
	if err != nil {
		return AIModelResponse{}, err
	}
	if statusCode < 200 || statusCode >= 300 {
		bodyText := strings.TrimSpace(string(responseBody))
		shouldRetryWithoutAssistant := statusCode == http.StatusBadRequest &&
			hasAssistantTurn &&
			strings.Contains(bodyText, "Invalid value: 'input_text'") &&
			strings.Contains(bodyText, "Supported values are: 'output_text' and 'refusal'")
		if shouldRetryWithoutAssistant {
			retryInput := buildInput(false)
			retryStatusCode, retryResponseBody, retryErr := callResponses(retryInput)
			if retryErr == nil && retryStatusCode >= 200 && retryStatusCode < 300 {
				statusCode = retryStatusCode
				responseBody = retryResponseBody
			} else {
				if retryErr != nil {
					return AIModelResponse{}, retryErr
				}
				return AIModelResponse{}, fmt.Errorf("openai responses error (%d): %s", retryStatusCode, strings.TrimSpace(string(retryResponseBody)))
			}
		} else {
			return AIModelResponse{}, fmt.Errorf("openai responses error (%d): %s", statusCode, bodyText)
		}
	}

	parsed := parseJSONStringMap(responseBody)
	answer := extractResponseAnswer(parsed)
	if strings.TrimSpace(answer) == "" {
		if isMaxOutputTokenIncomplete(parsed) {
			return AIModelResponse{}, errors.New("openai response incomplete due max_output_tokens")
		}
		log.Printf("openai response had no extractable answer: %s", truncateForLog(string(responseBody), 1200))
		return AIModelResponse{}, errors.New("openai response answer is empty")
	}

	usageMap, _ := parsed["usage"].(map[string]any)
	promptTokens := int(extractNumberFromMap(usageMap, "input_tokens", "prompt_tokens"))
	completionTokens := int(extractNumberFromMap(usageMap, "output_tokens", "completion_tokens"))
	totalTokens := int(extractNumberFromMap(usageMap, "total_tokens"))
	if totalTokens <= 0 {
		return AIModelResponse{}, errors.New("openai response missing token usage")
	}

	modelName := strings.TrimSpace(toString(parsed["model"]))
	if modelName == "" {
		modelName = requestModel
	}

	return AIModelResponse{
		Answer: answer,
		Model:  modelName,
		Usage: AIUsage{
			PromptTokens:     promptTokens,
			CompletionTokens: completionTokens,
			TotalTokens:      totalTokens,
		},
	}, nil
}

func extractResponseAnswer(data map[string]any) string {
	direct := strings.TrimSpace(toString(data["output_text"]))
	if direct != "" {
		return direct
	}

	outputs, ok := data["output"].([]any)
	if !ok {
		return ""
	}
	parts := make([]string, 0)
	for _, item := range outputs {
		block, ok := item.(map[string]any)
		if !ok {
			continue
		}
		contentList, ok := block["content"].([]any)
		if !ok {
			continue
		}
		for _, contentItem := range contentList {
			contentMap, ok := contentItem.(map[string]any)
			if !ok {
				continue
			}
			contentType := strings.ToLower(strings.TrimSpace(toString(contentMap["type"])))
			if contentType != "output_text" && contentType != "text" {
				continue
			}
			text := strings.TrimSpace(extractResponseTextValue(contentMap))
			if text != "" {
				parts = append(parts, text)
			}
		}
	}
	return strings.TrimSpace(strings.Join(parts, "\n"))
}

func extractResponseTextValue(content map[string]any) string {
	if content == nil {
		return ""
	}
	if text := strings.TrimSpace(toString(content["text"])); text != "" {
		return text
	}
	textMap, ok := content["text"].(map[string]any)
	if ok {
		if value := strings.TrimSpace(toString(textMap["value"])); value != "" {
			return value
		}
	}
	if value := strings.TrimSpace(toString(content["output_text"])); value != "" {
		return value
	}
	return ""
}

func truncateForLog(value string, limit int) string {
	trimmed := strings.TrimSpace(value)
	if limit <= 0 || len(trimmed) <= limit {
		return trimmed
	}
	return trimmed[:limit] + "...(truncated)"
}

func isMaxOutputTokenIncomplete(parsed map[string]any) bool {
	if parsed == nil {
		return false
	}
	details, ok := parsed["incomplete_details"].(map[string]any)
	if !ok {
		return false
	}
	reason := strings.ToLower(strings.TrimSpace(toString(details["reason"])))
	return reason == "max_output_tokens"
}
