package server

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type chatSessionRecord struct {
	ID                     string
	UserID                 string
	HouseholdID            string
	ChildID                *string
	Status                 string
	StartedAt              time.Time
	EndedAt                *time.Time
	MemorySummary          *string
	MemorySummarizedCount  int
	MemorySummaryUpdatedAt *time.Time
}

type chatSessionListItem struct {
	SessionID      string
	ChildID        *string
	Status         string
	StartedAt      time.Time
	UpdatedAt      time.Time
	EndedAt        *time.Time
	FirstUserInput *string
	LastPreview    *string
	LastMessageAt  time.Time
	MessageCount   int
}

type chatContextResult struct {
	Meta    map[string]any
	Summary string
}

type creditSnapshot struct {
	Balance    int
	GraceUsed  int
	GraceLimit int
}

type chatExecutionResult struct {
	SessionID          string
	AssistantMessageID string
	Intent             aiIntent
	Answer             string
	Model              string
	Usage              AIUsage
	Credit             billingResult
	ContextMeta        map[string]any
	ReferenceText      string
}

type chatHTTPError struct {
	Status int
	Detail string
	Credit *creditSnapshot
}

type aiIntent string

const (
	aiIntentMedicalRelated aiIntent = "medical_related"
	aiIntentDataQuery      aiIntent = "data_query"
	aiIntentCareRoutine    aiIntent = "care_routine"
	aiIntentSmalltalk      aiIntent = "smalltalk"
)

const (
	chatConversationTurnLimit = 30
	chatMemorySummaryCharMax  = 3200
	chatMemoryLineCharMax     = 180
)

func (e *chatHTTPError) Error() string {
	return e.Detail
}

func classifyAIIntent(question string) aiIntent {
	normalized := strings.ToLower(strings.Join(strings.Fields(strings.TrimSpace(question)), " "))
	if normalized == "" {
		return aiIntentSmalltalk
	}

	medicalKeywords := []string{
		"fever", "temp", "temperature", "diarrhea", "vomit", "rash", "cough", "blood",
		"medication", "medicine", "antibiotic", "emergency", "hospital", "pediatric",
	}
	if containsAnyKeyword(normalized, medicalKeywords) {
		return aiIntentMedicalRelated
	}

	dataKeywords := []string{
		"how many", "count", "total", "last", "when", "eta", "summary", "trend",
		"record", "history", "stats", "average", "interval",
	}
	if containsAnyKeyword(normalized, dataKeywords) {
		return aiIntentDataQuery
	}

	careKeywords := []string{
		"sleep", "nap", "night sleep", "routine", "schedule", "pattern", "feeding plan",
		"bedtime", "wake", "soothe", "care plan",
	}
	if containsAnyKeyword(normalized, careKeywords) {
		return aiIntentCareRoutine
	}

	casualKeywords := []string{
		"thanks", "thank you", "ok", "okay", "got it", "hello", "hi", "tired", "hungry",
	}
	if containsAnyKeyword(normalized, casualKeywords) {
		return aiIntentSmalltalk
	}
	if len([]rune(normalized)) <= 8 {
		return aiIntentSmalltalk
	}

	return aiIntentSmalltalk
}

func (a *App) createChatSession(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload chatSessionCreateRequest
	if !mustJSON(c, &payload) {
		return
	}

	childID := strings.TrimSpace(payload.ChildID)
	var childRef any
	householdID := ""
	if childID != "" {
		baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, childID, readRoles)
		if err != nil {
			writeError(c, statusCode, err.Error())
			return
		}
		childRef = baby.ID
		householdID = baby.HouseholdID
	} else {
		resolvedHouseholdID, err := a.resolveDefaultHouseholdForUser(c.Request.Context(), user.ID)
		if err != nil {
			writeError(c, http.StatusBadRequest, "No accessible household found. Complete onboarding first.")
			return
		}
		householdID = resolvedHouseholdID
		childRef = nil
	}

	sessionID := uuid.NewString()
	var startedAt time.Time
	err := a.db.QueryRow(
		c.Request.Context(),
		`INSERT INTO "ChatSession" (
			id, "userId", "householdId", "childId", status, "startedAt", "updatedAt"
		) VALUES ($1, $2, $3, $4, 'ACTIVE', NOW(), NOW())
		RETURNING "startedAt"`,
		sessionID,
		user.ID,
		householdID,
		childRef,
	).Scan(&startedAt)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to create chat session")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"session_id":   sessionID,
		"title":        "New conversation",
		"status":       "active",
		"started_at":   startedAt.UTC(),
		"child_id":     nullableString(childRef),
		"household_id": householdID,
	})
}

func (a *App) listChatSessions(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	childID := strings.TrimSpace(c.Query("child_id"))
	limit := 50
	if rawLimit := strings.TrimSpace(c.Query("limit")); rawLimit != "" {
		if parsed, err := strconv.Atoi(rawLimit); err == nil && parsed > 0 {
			if parsed > 100 {
				parsed = 100
			}
			limit = parsed
		}
	}

	var childFilter any
	if childID == "" {
		childFilter = nil
	} else {
		baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, childID, readRoles)
		if err != nil {
			writeError(c, statusCode, err.Error())
			return
		}
		childFilter = baby.ID
	}

	rows, err := a.db.Query(
		c.Request.Context(),
		`SELECT
			s.id,
			s."childId",
			s.status::text,
			s."startedAt",
			s."updatedAt",
			s."endedAt",
			(
				SELECT m.content
				FROM "ChatMessage" m
				WHERE m."sessionId" = s.id
				  AND m.role = 'user'
				ORDER BY m."createdAt" ASC
				LIMIT 1
			) AS first_user_input,
			(
				SELECT m.content
				FROM "ChatMessage" m
				WHERE m."sessionId" = s.id
				ORDER BY m."createdAt" DESC
				LIMIT 1
			) AS last_preview,
			COALESCE(
				(
					SELECT m."createdAt"
					FROM "ChatMessage" m
					WHERE m."sessionId" = s.id
					ORDER BY m."createdAt" DESC
					LIMIT 1
				),
				s."updatedAt"
			) AS last_message_at,
			(
				SELECT COUNT(*)::int
				FROM "ChatMessage" m
				WHERE m."sessionId" = s.id
			) AS message_count
		 FROM "ChatSession" s
		 WHERE s."userId" = $1
		   AND ($2::text IS NULL OR s."childId" = $2)
		 ORDER BY last_message_at DESC
		 LIMIT $3`,
		user.ID,
		childFilter,
		limit,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load chat sessions")
		return
	}
	defer rows.Close()

	items := make([]gin.H, 0, 24)
	for rows.Next() {
		record := chatSessionListItem{}
		if err := rows.Scan(
			&record.SessionID,
			&record.ChildID,
			&record.Status,
			&record.StartedAt,
			&record.UpdatedAt,
			&record.EndedAt,
			&record.FirstUserInput,
			&record.LastPreview,
			&record.LastMessageAt,
			&record.MessageCount,
		); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to parse chat sessions")
			return
		}
		title := deriveSessionTitle(record.FirstUserInput)
		preview := normalizeSessionPreview(record.LastPreview)
		items = append(items, gin.H{
			"session_id":      record.SessionID,
			"title":           title,
			"preview":         preview,
			"status":          strings.ToLower(strings.TrimSpace(record.Status)),
			"started_at":      record.StartedAt.UTC(),
			"updated_at":      record.UpdatedAt.UTC(),
			"last_message_at": record.LastMessageAt.UTC(),
			"ended_at":        record.EndedAt,
			"child_id":        record.ChildID,
			"message_count":   record.MessageCount,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"sessions": items,
	})
}

func (a *App) createChatMessage(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload chatMessageCreateRequest
	if !mustJSON(c, &payload) {
		return
	}

	sessionID := strings.TrimSpace(c.Param("session_id"))
	if sessionID == "" {
		writeError(c, http.StatusBadRequest, "session_id is required")
		return
	}
	session, err := a.loadChatSessionForUser(c.Request.Context(), user.ID, sessionID)
	if err != nil {
		a.writeChatExecutionError(c, err)
		return
	}

	role := strings.ToLower(strings.TrimSpace(payload.Role))
	if role != "user" && role != "assistant" && role != "system" {
		writeError(c, http.StatusBadRequest, "role must be one of: user, assistant, system")
		return
	}
	content := strings.TrimSpace(payload.Content)
	if content == "" {
		writeError(c, http.StatusBadRequest, "content is required")
		return
	}

	var childID *string
	if strings.TrimSpace(payload.ChildID) != "" {
		baby, statusCode, babyErr := a.getBabyWithAccess(c.Request.Context(), user.ID, strings.TrimSpace(payload.ChildID), readRoles)
		if babyErr != nil {
			writeError(c, statusCode, babyErr.Error())
			return
		}
		if baby.HouseholdID != session.HouseholdID {
			writeError(c, http.StatusBadRequest, "child_id does not belong to this chat session household")
			return
		}
		childID = &baby.ID
	} else {
		childID = session.ChildID
	}

	messageID, createdAt, err := a.insertChatMessage(
		c.Request.Context(),
		session.ID,
		user.ID,
		session.HouseholdID,
		childID,
		role,
		content,
		strings.TrimSpace(payload.Intent),
		payload.Context,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to create chat message")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message_id":   messageID,
		"session_id":   session.ID,
		"created_at":   createdAt.UTC(),
		"role":         role,
		"household_id": session.HouseholdID,
	})
}

func (a *App) getChatMessages(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	sessionID := strings.TrimSpace(c.Param("session_id"))
	if sessionID == "" {
		writeError(c, http.StatusBadRequest, "session_id is required")
		return
	}
	session, err := a.loadChatSessionForUser(c.Request.Context(), user.ID, sessionID)
	if err != nil {
		a.writeChatExecutionError(c, err)
		return
	}

	rows, err := a.db.Query(
		c.Request.Context(),
		`SELECT id, role, content, intent, "contextJson", "createdAt"
		 FROM "ChatMessage"
		 WHERE "sessionId" = $1
		 ORDER BY "createdAt" ASC`,
		session.ID,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load chat messages")
		return
	}
	defer rows.Close()

	items := make([]gin.H, 0)
	var firstUserInput *string
	for rows.Next() {
		var messageID, role, content string
		var intent *string
		var contextRaw []byte
		var createdAt time.Time
		if err := rows.Scan(&messageID, &role, &content, &intent, &contextRaw, &createdAt); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to parse chat messages")
			return
		}
		item := gin.H{
			"message_id": messageID,
			"role":       strings.ToLower(strings.TrimSpace(role)),
			"content":    content,
			"created_at": createdAt.UTC(),
		}
		if firstUserInput == nil && strings.EqualFold(strings.TrimSpace(role), "user") {
			candidate := strings.TrimSpace(content)
			if candidate != "" {
				firstUserInput = &candidate
			}
		}
		if intent != nil && strings.TrimSpace(*intent) != "" {
			item["intent"] = strings.TrimSpace(*intent)
		}
		if len(contextRaw) > 0 {
			item["context_json"] = parseJSONStringMap(contextRaw)
		}
		items = append(items, item)
	}

	c.JSON(http.StatusOK, gin.H{
		"session_id":   session.ID,
		"title":        deriveSessionTitle(firstUserInput),
		"status":       strings.ToLower(strings.TrimSpace(session.Status)),
		"started_at":   session.StartedAt.UTC(),
		"ended_at":     session.EndedAt,
		"household_id": session.HouseholdID,
		"child_id":     session.ChildID,
		"messages":     items,
	})
}

func (a *App) chatQuery(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload chatQueryRequest
	if !mustJSON(c, &payload) {
		return
	}

	result, err := a.runChatQuery(c.Request.Context(), user, payload, "")
	if err != nil {
		a.writeChatExecutionError(c, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"session_id":     result.SessionID,
		"message_id":     result.AssistantMessageID,
		"answer":         result.Answer,
		"intent":         string(result.Intent),
		"model":          result.Model,
		"usage":          usageMap(result.Usage),
		"credit":         creditMap(result.Credit),
		"context":        result.ContextMeta,
		"reference_text": result.ReferenceText,
	})
}

func (a *App) runChatQuery(
	ctx context.Context,
	user AuthUser,
	payload chatQueryRequest,
	fallbackChildID string,
) (chatExecutionResult, error) {
	sessionID := strings.TrimSpace(payload.SessionID)
	if sessionID == "" {
		return chatExecutionResult{}, &chatHTTPError{Status: http.StatusBadRequest, Detail: "session_id is required"}
	}
	question := strings.TrimSpace(payload.Query)
	if question == "" {
		return chatExecutionResult{}, &chatHTTPError{Status: http.StatusBadRequest, Detail: "query is required"}
	}
	tone := normalizeTone(payload.Tone)

	session, err := a.loadChatSessionForUser(ctx, user.ID, sessionID)
	if err != nil {
		return chatExecutionResult{}, err
	}

	childID := strings.TrimSpace(payload.ChildID)
	if childID == "" {
		childID = strings.TrimSpace(fallbackChildID)
	}
	if childID == "" && session.ChildID != nil {
		childID = strings.TrimSpace(*session.ChildID)
	}
	if payload.UsePersonalData && childID == "" {
		return chatExecutionResult{}, &chatHTTPError{Status: http.StatusBadRequest, Detail: "child_id is required when use_personal_data is true"}
	}

	var childRef *string
	if childID != "" {
		baby, statusCode, babyErr := a.getBabyWithAccess(ctx, user.ID, childID, readRoles)
		if babyErr != nil {
			return chatExecutionResult{}, &chatHTTPError{Status: statusCode, Detail: babyErr.Error()}
		}
		if baby.HouseholdID != session.HouseholdID {
			return chatExecutionResult{}, &chatHTTPError{Status: http.StatusBadRequest, Detail: "child_id does not belong to this chat session household"}
		}
		childRef = &baby.ID
		if session.ChildID == nil || strings.TrimSpace(*session.ChildID) != baby.ID {
			if _, err := a.db.Exec(
				ctx,
				`UPDATE "ChatSession" SET "childId" = $2, "updatedAt" = NOW() WHERE id = $1`,
				session.ID,
				baby.ID,
			); err != nil {
				return chatExecutionResult{}, err
			}
		}
	} else {
		childRef = nil
	}

	now := time.Now().UTC()
	preflight, err := a.preflightBilling(ctx, user.ID, session.HouseholdID, now)
	if err != nil {
		return chatExecutionResult{}, err
	}
	if preflight.Mode == "" {
		balance, berr := a.getWalletBalance(ctx, a.db, user.ID)
		if berr != nil {
			return chatExecutionResult{}, berr
		}
		graceUsed, gerr := a.countGraceUsedToday(ctx, a.db, user.ID, now)
		if gerr != nil {
			return chatExecutionResult{}, gerr
		}
		return chatExecutionResult{}, &chatHTTPError{
			Status: http.StatusPaymentRequired,
			Detail: "Insufficient AI credits",
			Credit: &creditSnapshot{
				Balance:    balance,
				GraceUsed:  graceUsed,
				GraceLimit: graceLimitPerDay,
			},
		}
	}

	turns, sessionMemorySummary, memorySummarizedCount, err := a.prepareSessionMemory(ctx, session)
	if err != nil {
		_ = a.releaseReservedCredits(ctx, user.ID, preflight.Reserved)
		return chatExecutionResult{}, err
	}

	firstUserMessage, err := a.loadFirstUserMessage(ctx, session.ID)
	if err != nil {
		_ = a.releaseReservedCredits(ctx, user.ID, preflight.Reserved)
		return chatExecutionResult{}, err
	}

	intent := a.resolveAIIntentWithSessionByModel(ctx, question, turns, firstUserMessage)
	smalltalkStyleHint := ""
	if intent == aiIntentSmalltalk {
		smalltalkStyleHint = deriveSmalltalkStyleHint(turns, question)
	}

	chatContext, err := a.buildChatContext(ctx, childID, intent, question, now, payload.UsePersonalData)
	if err != nil {
		_ = a.releaseReservedCredits(ctx, user.ID, preflight.Reserved)
		return chatExecutionResult{}, err
	}

	aiResponse, err := a.ai.Query(ctx, AIModelRequest{
		SystemPrompt: buildChatSystemPrompt(
			intent,
			tone,
			chatContext,
			payload.UsePersonalData,
			sessionMemorySummary,
			smalltalkStyleHint,
		),
		Conversation: turns,
		UserPrompt:   question,
	})
	if err != nil {
		log.Printf("ai query failed session_id=%s user_id=%s child_id=%s intent=%s err=%v", session.ID, user.ID, childID, intent, err)
		_ = a.releaseReservedCredits(ctx, user.ID, preflight.Reserved)
		return chatExecutionResult{}, err
	}
	if aiResponse.Usage.TotalTokens <= 0 {
		log.Printf("ai usage missing session_id=%s user_id=%s child_id=%s intent=%s model=%s", session.ID, user.ID, childID, intent, aiResponse.Model)
		_ = a.releaseReservedCredits(ctx, user.ID, preflight.Reserved)
		return chatExecutionResult{}, errors.New("AI response missing usage tokens")
	}

	userContext := cloneMap(chatContext.Meta)
	userContext["tone"] = tone
	userContext["use_personal_data"] = payload.UsePersonalData
	userContext["session_memory_used"] = strings.TrimSpace(sessionMemorySummary) != ""
	userContext["session_memory_summarized_count"] = memorySummarizedCount

	userMessageID, _, err := a.insertChatMessage(
		ctx,
		session.ID,
		user.ID,
		session.HouseholdID,
		childRef,
		"user",
		question,
		string(intent),
		userContext,
	)
	if err != nil {
		_ = a.releaseReservedCredits(ctx, user.ID, preflight.Reserved)
		return chatExecutionResult{}, err
	}

	assistantContext := cloneMap(chatContext.Meta)
	assistantContext["model"] = aiResponse.Model
	assistantContext["usage"] = usageMap(aiResponse.Usage)

	assistantMessageID, _, err := a.insertChatMessage(
		ctx,
		session.ID,
		user.ID,
		session.HouseholdID,
		childRef,
		"assistant",
		aiResponse.Answer,
		string(intent),
		assistantContext,
	)
	if err != nil {
		_, _ = a.db.Exec(ctx, `DELETE FROM "ChatMessage" WHERE id = $1`, userMessageID)
		_ = a.releaseReservedCredits(ctx, user.ID, preflight.Reserved)
		return chatExecutionResult{}, err
	}

	billing, err := a.finalizeBillingAndLog(
		ctx,
		user.ID,
		session.HouseholdID,
		childID,
		question,
		aiResponse.Model,
		aiResponse.Usage,
		preflight,
		now,
	)
	if err != nil {
		_, _ = a.db.Exec(ctx, `DELETE FROM "ChatMessage" WHERE id = $1`, assistantMessageID)
		_, _ = a.db.Exec(ctx, `DELETE FROM "ChatMessage" WHERE id = $1`, userMessageID)
		_ = a.releaseReservedCredits(ctx, user.ID, preflight.Reserved)
		return chatExecutionResult{}, err
	}

	assistantContext["credit"] = creditMap(billing)
	_, _ = a.db.Exec(
		ctx,
		`UPDATE "ChatMessage" SET "contextJson" = $2 WHERE id = $1`,
		assistantMessageID,
		mustMarshalJSON(assistantContext),
	)

	return chatExecutionResult{
		SessionID:          session.ID,
		AssistantMessageID: assistantMessageID,
		Intent:             intent,
		Answer:             aiResponse.Answer,
		Model:              aiResponse.Model,
		Usage:              aiResponse.Usage,
		Credit:             billing,
		ContextMeta:        chatContext.Meta,
		ReferenceText:      chatContext.Summary,
	}, nil
}

func (a *App) resolveDefaultHouseholdForUser(ctx context.Context, userID string) (string, error) {
	var householdID string
	err := a.db.QueryRow(
		ctx,
		`SELECT household_id
		 FROM (
			SELECT id AS household_id, 0 AS priority, "createdAt" AS created_at
			FROM "Household"
			WHERE "ownerUserId" = $1
			UNION ALL
			SELECT "householdId" AS household_id, 1 AS priority, "createdAt" AS created_at
			FROM "HouseholdMember"
			WHERE "userId" = $1 AND status = 'ACTIVE'
		 ) candidates
		 ORDER BY priority ASC, created_at ASC
		 LIMIT 1`,
		userID,
	).Scan(&householdID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", errors.New("no household")
	}
	if err != nil {
		return "", err
	}
	return householdID, nil
}

func (a *App) getOrCreateCompatChatSession(
	ctx context.Context,
	userID, householdID, childID string,
) (string, error) {
	childValue := strings.TrimSpace(childID)
	if childValue == "" {
		childValue = ""
	}

	var sessionID string
	err := a.db.QueryRow(
		ctx,
		`SELECT id
		 FROM "ChatSession"
		 WHERE "userId" = $1
		   AND "householdId" = $2
		   AND COALESCE("childId", '') = COALESCE($3::text, '')
		   AND status = 'ACTIVE'
		 ORDER BY "updatedAt" DESC
		 LIMIT 1`,
		userID,
		householdID,
		childValue,
	).Scan(&sessionID)
	if err == nil {
		return sessionID, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return "", err
	}

	newSessionID := uuid.NewString()
	var childRef any
	if childValue != "" {
		childRef = childValue
	} else {
		childRef = nil
	}
	_, err = a.db.Exec(
		ctx,
		`INSERT INTO "ChatSession" (
			id, "userId", "householdId", "childId", status, "startedAt", "updatedAt"
		) VALUES ($1, $2, $3, $4, 'ACTIVE', NOW(), NOW())`,
		newSessionID,
		userID,
		householdID,
		childRef,
	)
	if err != nil {
		return "", err
	}
	return newSessionID, nil
}

func (a *App) loadChatSessionForUser(ctx context.Context, userID, sessionID string) (chatSessionRecord, error) {
	record := chatSessionRecord{}
	queryWithMemory := `SELECT id, "userId", "householdId", "childId", status::text, "startedAt", "endedAt",
	        "memorySummary", COALESCE("memorySummarizedCount", 0), "memorySummaryUpdatedAt"
	 FROM "ChatSession"
	 WHERE id = $1 AND "userId" = $2`
	scanWithMemory := func() error {
		return a.db.QueryRow(
			ctx,
			queryWithMemory,
			sessionID,
			userID,
		).Scan(
			&record.ID,
			&record.UserID,
			&record.HouseholdID,
			&record.ChildID,
			&record.Status,
			&record.StartedAt,
			&record.EndedAt,
			&record.MemorySummary,
			&record.MemorySummarizedCount,
			&record.MemorySummaryUpdatedAt,
		)
	}

	err := scanWithMemory()
	if err != nil && isMissingChatMemoryColumnErr(err) {
		if ensureErr := a.ensureChatSessionMemoryColumns(ctx); ensureErr == nil {
			err = scanWithMemory()
		} else {
			return chatSessionRecord{}, ensureErr
		}
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return chatSessionRecord{}, &chatHTTPError{Status: http.StatusNotFound, Detail: "Chat session not found"}
	}
	if err != nil {
		return chatSessionRecord{}, err
	}

	if _, statusCode, accessErr := a.assertHouseholdAccess(ctx, userID, record.HouseholdID, readRoles); accessErr != nil {
		return chatSessionRecord{}, &chatHTTPError{Status: statusCode, Detail: accessErr.Error()}
	}
	return record, nil
}

func (a *App) insertChatMessage(
	ctx context.Context,
	sessionID, userID, householdID string,
	childID *string,
	role, content, intent string,
	contextMap map[string]any,
) (string, time.Time, error) {
	messageID := uuid.NewString()
	trimmedIntent := strings.TrimSpace(intent)
	trimmedRole := strings.ToLower(strings.TrimSpace(role))
	trimmedContent := strings.TrimSpace(content)

	var childValue any
	if childID == nil || strings.TrimSpace(*childID) == "" {
		childValue = nil
	} else {
		childValue = strings.TrimSpace(*childID)
	}

	var intentValue any
	if trimmedIntent == "" {
		intentValue = nil
	} else {
		intentValue = trimmedIntent
	}

	var contextValue any
	if contextMap == nil {
		contextValue = nil
	} else {
		contextValue = mustMarshalJSON(contextMap)
	}

	var createdAt time.Time
	err := a.db.QueryRow(
		ctx,
		`INSERT INTO "ChatMessage" (
			id, "sessionId", "userId", "householdId", "childId", role, content, intent, "contextJson", "createdAt"
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
		RETURNING "createdAt"`,
		messageID,
		sessionID,
		userID,
		householdID,
		childValue,
		trimmedRole,
		trimmedContent,
		intentValue,
		contextValue,
	).Scan(&createdAt)
	if err != nil {
		return "", time.Time{}, err
	}

	_, _ = a.db.Exec(ctx, `UPDATE "ChatSession" SET "updatedAt" = NOW() WHERE id = $1`, sessionID)
	return messageID, createdAt, nil
}

func (a *App) loadSessionTurns(ctx context.Context, sessionID string, limit int) ([]ChatTurn, error) {
	if limit <= 0 {
		limit = 20
	}
	rows, err := a.db.Query(
		ctx,
		`SELECT role, content
		 FROM "ChatMessage"
		 WHERE "sessionId" = $1
		 ORDER BY "createdAt" DESC
		 LIMIT $2`,
		sessionID,
		limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	turns := make([]ChatTurn, 0, limit)
	for rows.Next() {
		var role, content string
		if err := rows.Scan(&role, &content); err != nil {
			return nil, err
		}
		turns = append(turns, ChatTurn{Role: strings.ToLower(strings.TrimSpace(role)), Content: strings.TrimSpace(content)})
	}

	for i, j := 0, len(turns)-1; i < j; i, j = i+1, j-1 {
		turns[i], turns[j] = turns[j], turns[i]
	}
	return turns, nil
}

func (a *App) loadSessionTurnSlice(ctx context.Context, sessionID string, offset, limit int) ([]ChatTurn, error) {
	if limit <= 0 {
		return []ChatTurn{}, nil
	}
	if offset < 0 {
		offset = 0
	}

	rows, err := a.db.Query(
		ctx,
		`SELECT role, content
		 FROM "ChatMessage"
		 WHERE "sessionId" = $1
		 ORDER BY "createdAt" ASC
		 OFFSET $2
		 LIMIT $3`,
		sessionID,
		offset,
		limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	turns := make([]ChatTurn, 0, limit)
	for rows.Next() {
		var role, content string
		if err := rows.Scan(&role, &content); err != nil {
			return nil, err
		}
		turns = append(turns, ChatTurn{
			Role:    strings.ToLower(strings.TrimSpace(role)),
			Content: strings.TrimSpace(content),
		})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return turns, nil
}

func (a *App) loadSessionMessageCount(ctx context.Context, sessionID string) (int, error) {
	var count int
	if err := a.db.QueryRow(
		ctx,
		`SELECT COUNT(*)::int
		 FROM "ChatMessage"
		 WHERE "sessionId" = $1`,
		sessionID,
	).Scan(&count); err != nil {
		return 0, err
	}
	return count, nil
}

func (a *App) loadFirstUserMessage(ctx context.Context, sessionID string) (string, error) {
	var content string
	err := a.db.QueryRow(
		ctx,
		`SELECT content
		 FROM "ChatMessage"
		 WHERE "sessionId" = $1 AND role = 'user'
		 ORDER BY "createdAt" ASC
		 LIMIT 1`,
		sessionID,
	).Scan(&content)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(content), nil
}

func (a *App) saveSessionMemorySummary(
	ctx context.Context,
	sessionID, summary string,
	summarizedCount int,
) error {
	if summarizedCount <= 0 || strings.TrimSpace(summary) == "" {
		err := a.execChatMemoryUpdateWithRetry(
			ctx,
			`UPDATE "ChatSession"
			 SET "memorySummary" = NULL,
			     "memorySummarizedCount" = 0,
			     "memorySummaryUpdatedAt" = NULL
			 WHERE id = $1`,
			sessionID,
		)
		return err
	}

	err := a.execChatMemoryUpdateWithRetry(
		ctx,
		`UPDATE "ChatSession"
		 SET "memorySummary" = $2,
		     "memorySummarizedCount" = $3,
		     "memorySummaryUpdatedAt" = NOW()
		 WHERE id = $1`,
		sessionID,
		strings.TrimSpace(summary),
		summarizedCount,
	)
	return err
}

func (a *App) execChatMemoryUpdateWithRetry(ctx context.Context, query string, args ...any) error {
	_, err := a.db.Exec(ctx, query, args...)
	if err == nil {
		return nil
	}
	if !isMissingChatMemoryColumnErr(err) {
		return err
	}
	if ensureErr := a.ensureChatSessionMemoryColumns(ctx); ensureErr != nil {
		return ensureErr
	}
	_, retryErr := a.db.Exec(ctx, query, args...)
	return retryErr
}

func (a *App) ensureChatSessionMemoryColumns(ctx context.Context) error {
	statements := []string{
		`ALTER TABLE "ChatSession" ADD COLUMN IF NOT EXISTS "memorySummary" TEXT`,
		`ALTER TABLE "ChatSession" ADD COLUMN IF NOT EXISTS "memorySummarizedCount" INTEGER NOT NULL DEFAULT 0`,
		`ALTER TABLE "ChatSession" ADD COLUMN IF NOT EXISTS "memorySummaryUpdatedAt" TIMESTAMP(3)`,
	}
	for _, stmt := range statements {
		if _, err := a.db.Exec(ctx, stmt); err != nil {
			return err
		}
	}
	return nil
}

func isMissingChatMemoryColumnErr(err error) bool {
	if err == nil {
		return false
	}
	lowered := strings.ToLower(strings.TrimSpace(err.Error()))
	if !strings.Contains(lowered, "column") {
		return false
	}
	return strings.Contains(lowered, "memorysummary") ||
		strings.Contains(lowered, "memorysummarizedcount") ||
		strings.Contains(lowered, "memorysummaryupdatedat")
}

func (a *App) prepareSessionMemory(
	ctx context.Context,
	session chatSessionRecord,
) ([]ChatTurn, string, int, error) {
	totalCount, err := a.loadSessionMessageCount(ctx, session.ID)
	if err != nil {
		return nil, "", 0, err
	}

	targetSummarizedCount := totalCount - chatConversationTurnLimit
	if targetSummarizedCount < 0 {
		targetSummarizedCount = 0
	}

	currentSummarizedCount := session.MemorySummarizedCount
	if currentSummarizedCount < 0 {
		currentSummarizedCount = 0
	}
	if currentSummarizedCount > totalCount {
		currentSummarizedCount = totalCount
	}

	summary := ""
	if session.MemorySummary != nil {
		summary = strings.TrimSpace(*session.MemorySummary)
	}

	switch {
	case targetSummarizedCount == 0:
		if currentSummarizedCount > 0 || summary != "" {
			if err := a.saveSessionMemorySummary(ctx, session.ID, "", 0); err != nil {
				return nil, "", 0, err
			}
			currentSummarizedCount = 0
			summary = ""
		}
	case currentSummarizedCount > targetSummarizedCount:
		rebuildTurns, err := a.loadSessionTurnSlice(ctx, session.ID, 0, targetSummarizedCount)
		if err != nil {
			return nil, "", 0, err
		}
		summary = buildSessionMemorySummary("", rebuildTurns)
		currentSummarizedCount = targetSummarizedCount
		if err := a.saveSessionMemorySummary(ctx, session.ID, summary, currentSummarizedCount); err != nil {
			return nil, "", 0, err
		}
	case currentSummarizedCount < targetSummarizedCount:
		delta := targetSummarizedCount - currentSummarizedCount
		newTurns, err := a.loadSessionTurnSlice(ctx, session.ID, currentSummarizedCount, delta)
		if err != nil {
			return nil, "", 0, err
		}
		summary = buildSessionMemorySummary(summary, newTurns)
		currentSummarizedCount = targetSummarizedCount
		if err := a.saveSessionMemorySummary(ctx, session.ID, summary, currentSummarizedCount); err != nil {
			return nil, "", 0, err
		}
	}

	turns, err := a.loadSessionTurns(ctx, session.ID, chatConversationTurnLimit)
	if err != nil {
		return nil, "", 0, err
	}
	return turns, summary, currentSummarizedCount, nil
}

func (a *App) resolveAIIntentWithSessionByModel(
	ctx context.Context,
	question string,
	turns []ChatTurn,
	firstUserMessage string,
) aiIntent {
	fallback := resolveAIIntentWithSession(question, turns)

	firstMessage := strings.TrimSpace(firstUserMessage)
	if firstMessage == "" {
		firstMessage = firstUserMessageFromTurns(turns)
	}
	if firstMessage == "" {
		firstMessage = strings.TrimSpace(question)
	}
	if firstMessage == "" {
		return fallback
	}

	intent, err := a.resolveAIIntentByFirstMessage(ctx, firstMessage, question)
	if err != nil || intent == "" {
		return fallback
	}
	return intent
}

func (a *App) resolveAIIntentByFirstMessage(ctx context.Context, firstMessage, latestQuestion string) (aiIntent, error) {
	systemPrompt := strings.Join([]string{
		"You are an intent router for a parenting assistant.",
		"Classify the conversation intent using the first user message as the primary signal.",
		"Allowed intents are only: smalltalk, data_query, medical_related, care_routine.",
		"Return ONLY a strict JSON object.",
		`JSON schema: {"intent":"smalltalk|data_query|medical_related|care_routine","confidence":0.0,"reason":"short reason"}`,
		"No markdown, no code fence, no extra text.",
	}, "\n")
	userPrompt := strings.Join([]string{
		"first_user_message: " + strings.TrimSpace(firstMessage),
		"latest_user_message: " + strings.TrimSpace(latestQuestion),
		"Select exactly one intent.",
	}, "\n")

	resp, err := a.ai.Query(ctx, AIModelRequest{
		SystemPrompt: systemPrompt,
		UserPrompt:   userPrompt,
	})
	if err != nil {
		return "", err
	}

	intent, ok := parseAIIntentRouterJSON(resp.Answer)
	if !ok {
		return "", errors.New("intent router returned invalid JSON")
	}
	return intent, nil
}

func firstUserMessageFromTurns(turns []ChatTurn) string {
	for _, turn := range turns {
		if strings.ToLower(strings.TrimSpace(turn.Role)) != "user" {
			continue
		}
		content := strings.TrimSpace(turn.Content)
		if content != "" {
			return content
		}
	}
	return ""
}

func parseAIIntentRouterJSON(answer string) (aiIntent, bool) {
	candidate := strings.TrimSpace(answer)
	if candidate == "" {
		return "", false
	}
	if !strings.HasPrefix(candidate, "{") {
		start := strings.Index(candidate, "{")
		end := strings.LastIndex(candidate, "}")
		if start >= 0 && end > start {
			candidate = strings.TrimSpace(candidate[start : end+1])
		}
	}
	if strings.HasPrefix(candidate, "```") {
		candidate = strings.TrimSpace(strings.TrimPrefix(candidate, "```json"))
		candidate = strings.TrimSpace(strings.TrimPrefix(candidate, "```"))
		candidate = strings.TrimSpace(strings.TrimSuffix(candidate, "```"))
	}
	parsed := parseJSONStringMap([]byte(candidate))
	intent := normalizeAIIntentLabel(toString(parsed["intent"]))
	if intent == "" {
		return "", false
	}
	return intent, true
}

func normalizeAIIntentLabel(value string) aiIntent {
	normalized := strings.ToLower(strings.TrimSpace(value))
	switch normalized {
	case string(aiIntentSmalltalk):
		return aiIntentSmalltalk
	case string(aiIntentDataQuery):
		return aiIntentDataQuery
	case string(aiIntentMedicalRelated):
		return aiIntentMedicalRelated
	case string(aiIntentCareRoutine):
		return aiIntentCareRoutine
	default:
		return ""
	}
}

func resolveAIIntentWithSession(question string, turns []ChatTurn) aiIntent {
	base := classifyAIIntent(question)
	firstIntent := firstUserIntentFromTurns(turns)
	latestIntent := latestUserIntentFromTurns(turns)

	if base != aiIntentSmalltalk {
		return base
	}
	if isShortCasualFollowUp(question) {
		return aiIntentSmalltalk
	}
	if isVagueFollowUp(question) {
		if latestIntent != "" && latestIntent != aiIntentSmalltalk {
			return latestIntent
		}
		if firstIntent != "" {
			return firstIntent
		}
	}
	if firstIntent != "" {
		return firstIntent
	}
	return aiIntentSmalltalk
}

func latestUserIntentFromTurns(turns []ChatTurn) aiIntent {
	for idx := len(turns) - 1; idx >= 0; idx-- {
		turn := turns[idx]
		if strings.ToLower(strings.TrimSpace(turn.Role)) != "user" {
			continue
		}
		intent := classifyAIIntent(turn.Content)
		if intent == aiIntentSmalltalk {
			continue
		}
		return intent
	}
	return aiIntentSmalltalk
}

func firstUserIntentFromTurns(turns []ChatTurn) aiIntent {
	for idx := 0; idx < len(turns); idx++ {
		turn := turns[idx]
		if strings.ToLower(strings.TrimSpace(turn.Role)) != "user" {
			continue
		}
		intent := classifyAIIntent(turn.Content)
		if intent == "" {
			continue
		}
		return intent
	}
	return aiIntentSmalltalk
}

func isShortCasualFollowUp(question string) bool {
	normalized := strings.ToLower(strings.TrimSpace(question))
	if normalized == "" {
		return true
	}
	casual := []string{
		"thanks", "thank you", "ok", "okay", "got it", "sure", "sounds good",
		"yes", "yeah", "yep", "nope", "cool",
	}
	if containsAnyKeyword(normalized, casual) {
		return true
	}
	return len([]rune(normalized)) <= 8
}

func isVagueFollowUp(question string) bool {
	normalized := strings.ToLower(strings.TrimSpace(question))
	if normalized == "" {
		return false
	}
	candidates := []string{
		"then", "why", "how", "more", "details", "what about", "explain", "again",
	}
	return containsAnyKeyword(normalized, candidates)
}
func (a *App) buildChatContext(
	ctx context.Context,
	childID string,
	intent aiIntent,
	question string,
	now time.Time,
	usePersonalData bool,
) (chatContextResult, error) {
	if !usePersonalData || strings.TrimSpace(childID) == "" {
		meta := map[string]any{
			"child_id":             nil,
			"time_range":           "none",
			"evidence_event_ids":   []string{},
			"has_estimated_values": false,
			"has_missing_data":     true,
		}
		return chatContextResult{
			Meta:    meta,
			Summary: "Personal data context is disabled for this query.",
		}, nil
	}

	nowUTC := now.UTC()
	if intent == aiIntentSmalltalk {
		meta := map[string]any{
			"child_id":             childID,
			"time_range":           "smalltalk_minimal",
			"evidence_event_ids":   []string{},
			"has_estimated_values": false,
			"has_missing_data":     false,
		}
		return chatContextResult{
			Meta: meta,
			Summary: strings.Join([]string{
				fmt.Sprintf("Smalltalk mode for child_id=%s.", childID),
				"Keep conversation warm and natural.",
				"Do not inject raw records unless the user explicitly asks for data details.",
			}, "\n"),
		}, nil
	}

	rawStart, rawEnd, requestedDate := resolveRawWindow(question, nowUTC)
	monthlyStart := nowUTC.Add(-30 * 24 * time.Hour)
	if monthlyStart.After(rawStart) {
		monthlyStart = rawStart.Add(-30 * 24 * time.Hour)
	}
	monthlyEnd := rawStart
	if monthlyEnd.Before(monthlyStart) {
		monthlyStart = monthlyEnd
	}

	rawRows, err := a.db.Query(
		ctx,
		`SELECT id, type::text, "startTime", "endTime", "valueJson"::text, COALESCE("metadataJson", '{}'::jsonb)::text
		 FROM "Event"
		 WHERE "babyId" = $1
		   AND "startTime" >= $2
		   AND "startTime" < $3
		 ORDER BY "startTime" DESC`,
		childID,
		rawStart,
		rawEnd,
	)
	if err != nil {
		return chatContextResult{}, err
	}
	defer rawRows.Close()

	rawLines := make([]string, 0, 128)
	evidenceIDs := make([]string, 0, 200)
	rawCountByType := map[string]int{}
	for rawRows.Next() {
		var eventID, eventType, valueText, metadataText string
		var startAt time.Time
		var endAt *time.Time
		if err := rawRows.Scan(&eventID, &eventType, &startAt, &endAt, &valueText, &metadataText); err != nil {
			return chatContextResult{}, err
		}
		eventType = strings.TrimSpace(eventType)
		rawCountByType[eventType]++
		evidenceIDs = append(evidenceIDs, eventID)

		details := []string{
			fmt.Sprintf("event_id=%s", strings.TrimSpace(eventID)),
			fmt.Sprintf("type=%s", strings.ToUpper(eventType)),
			fmt.Sprintf("start=%s", startAt.UTC().Format(time.RFC3339)),
		}
		if endAt != nil {
			details = append(details, fmt.Sprintf("end=%s", endAt.UTC().Format(time.RFC3339)))
		}
		if v := strings.TrimSpace(valueText); v != "" && v != "{}" && v != "null" {
			details = append(details, "value="+v)
		}
		if m := strings.TrimSpace(metadataText); m != "" && m != "{}" && m != "null" {
			details = append(details, "meta="+m)
		}
		rawLines = append(rawLines, "- "+strings.Join(details, " | "))
	}
	if err := rawRows.Err(); err != nil {
		return chatContextResult{}, err
	}

	monthlyCountByType := map[string]int{}
	if monthlyStart.Before(monthlyEnd) {
		monthlyTypeRows, err := a.db.Query(
			ctx,
			`SELECT type::text, COUNT(*)::int
			 FROM "Event"
			 WHERE "babyId" = $1
			   AND "startTime" >= $2
			   AND "startTime" < $3
			 GROUP BY type`,
			childID,
			monthlyStart,
			monthlyEnd,
		)
		if err != nil {
			return chatContextResult{}, err
		}
		for monthlyTypeRows.Next() {
			var eventType string
			var count int
			if err := monthlyTypeRows.Scan(&eventType, &count); err != nil {
				monthlyTypeRows.Close()
				return chatContextResult{}, err
			}
			monthlyCountByType[strings.TrimSpace(eventType)] = count
		}
		if err := monthlyTypeRows.Err(); err != nil {
			monthlyTypeRows.Close()
			return chatContextResult{}, err
		}
		monthlyTypeRows.Close()
	}

	dailyOverviewLines := make([]string, 0, 40)
	if monthlyStart.Before(monthlyEnd) {
		dailyRows, err := a.db.Query(
			ctx,
			`SELECT TO_CHAR(DATE_TRUNC('day', "startTime" AT TIME ZONE 'UTC'), 'YYYY-MM-DD') AS day, COUNT(*)::int
			 FROM "Event"
			 WHERE "babyId" = $1
			   AND "startTime" >= $2
			   AND "startTime" < $3
			 GROUP BY day
			 ORDER BY day DESC`,
			childID,
			monthlyStart,
			monthlyEnd,
		)
		if err != nil {
			return chatContextResult{}, err
		}
		for dailyRows.Next() {
			var day string
			var count int
			if err := dailyRows.Scan(&day, &count); err != nil {
				dailyRows.Close()
				return chatContextResult{}, err
			}
			dailyOverviewLines = append(dailyOverviewLines, fmt.Sprintf("- %s: %d events", strings.TrimSpace(day), count))
		}
		if err := dailyRows.Err(); err != nil {
			dailyRows.Close()
			return chatContextResult{}, err
		}
		dailyRows.Close()
	}

	rawRangeLabel := "last_7d_raw"
	if requestedDate != nil {
		rawRangeLabel = "requested_date_raw"
	}
	hasMissingData := len(rawLines) == 0
	meta := map[string]any{
		"child_id":             childID,
		"time_range":           rawRangeLabel,
		"evidence_event_ids":   evidenceIDs,
		"has_estimated_values": false,
		"has_missing_data":     hasMissingData,
		"raw_since_utc":        rawStart.Format(time.RFC3339),
		"raw_until_utc":        rawEnd.Format(time.RFC3339),
		"monthly_since_utc":    monthlyStart.Format(time.RFC3339),
		"monthly_until_utc":    monthlyEnd.Format(time.RFC3339),
	}
	if requestedDate != nil {
		meta["requested_date_utc"] = requestedDate.Format("2006-01-02")
	}

	summaryLines := make([]string, 0, len(rawLines)+80)
	summaryLines = append(summaryLines, fmt.Sprintf("Child-specific context for child_id=%s.", childID))
	if requestedDate != nil {
		summaryLines = append(summaryLines,
			fmt.Sprintf("User requested raw records for specific date (UTC): %s.", requestedDate.Format("2006-01-02")),
		)
	}
	summaryLines = append(summaryLines,
		fmt.Sprintf("Raw records window (UTC): %s to %s.", rawStart.Format(time.RFC3339), rawEnd.Format(time.RFC3339)),
		"Raw event lines below are direct stored payloads (value/meta) from user-entered records.",
	)
	if len(rawLines) == 0 {
		summaryLines = append(summaryLines, "- No raw events found in the selected raw window.")
	} else {
		summaryLines = append(summaryLines, rawLines...)
		rawTypes := make([]string, 0, len(rawCountByType))
		for eventType := range rawCountByType {
			rawTypes = append(rawTypes, eventType)
		}
		sort.Strings(rawTypes)
		summaryLines = append(summaryLines, "Raw window counts by type:")
		for _, eventType := range rawTypes {
			summaryLines = append(summaryLines,
				fmt.Sprintf("- %s: %d events", strings.ToUpper(strings.TrimSpace(eventType)), rawCountByType[eventType]),
			)
		}
	}

	summaryLines = append(summaryLines,
		"Monthly summary overview (older than the raw window, up to 30 days):",
		fmt.Sprintf("Period (UTC): %s to %s.", monthlyStart.Format(time.RFC3339), monthlyEnd.Format(time.RFC3339)),
	)
	if len(monthlyCountByType) == 0 {
		summaryLines = append(summaryLines, "- No monthly summary events found in the configured period.")
	} else {
		types := make([]string, 0, len(monthlyCountByType))
		for eventType := range monthlyCountByType {
			types = append(types, eventType)
		}
		sort.Strings(types)
		for _, eventType := range types {
			summaryLines = append(summaryLines,
				fmt.Sprintf("- %s: %d events", strings.ToUpper(strings.TrimSpace(eventType)), monthlyCountByType[eventType]),
			)
		}
	}
	if len(dailyOverviewLines) == 0 {
		summaryLines = append(summaryLines, "- No daily overview rows in the monthly summary period.")
	} else {
		summaryLines = append(summaryLines, "Daily counts in monthly period:")
		summaryLines = append(summaryLines, dailyOverviewLines...)
	}

	return chatContextResult{
		Meta:    meta,
		Summary: strings.Join(summaryLines, "\n"),
	}, nil
}

var (
	isoDatePattern    = regexp.MustCompile(`\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b`)
	koreanDatePattern = regexp.MustCompile(`(?:(20\d{2})\s*년\s*)?(\d{1,2})\s*월\s*(\d{1,2})\s*일`)
)

func resolveRawWindow(question string, nowUTC time.Time) (time.Time, time.Time, *time.Time) {
	if specificDate, ok := extractRequestedDate(question, nowUTC); ok {
		start := startOfUTCDay(specificDate.UTC())
		return start, start.Add(24 * time.Hour), &start
	}
	return nowUTC.Add(-7 * 24 * time.Hour), nowUTC, nil
}

func extractRequestedDate(question string, nowUTC time.Time) (time.Time, bool) {
	normalized := strings.TrimSpace(question)
	lowered := strings.ToLower(normalized)
	if normalized == "" {
		return time.Time{}, false
	}

	switch {
	case strings.Contains(normalized, "오늘") || strings.Contains(lowered, "today"):
		return startOfUTCDay(nowUTC), true
	case strings.Contains(normalized, "어제") || strings.Contains(lowered, "yesterday"):
		return startOfUTCDay(nowUTC.Add(-24 * time.Hour)), true
	}

	if match := isoDatePattern.FindStringSubmatch(normalized); len(match) == 4 {
		year, yErr := strconv.Atoi(strings.TrimSpace(match[1]))
		month, mErr := strconv.Atoi(strings.TrimSpace(match[2]))
		day, dErr := strconv.Atoi(strings.TrimSpace(match[3]))
		if yErr == nil && mErr == nil && dErr == nil {
			if dateValue, ok := buildUTCDate(year, month, day); ok {
				return dateValue, true
			}
		}
	}

	if match := koreanDatePattern.FindStringSubmatch(normalized); len(match) == 4 {
		year := nowUTC.Year()
		if strings.TrimSpace(match[1]) != "" {
			parsedYear, err := strconv.Atoi(strings.TrimSpace(match[1]))
			if err == nil {
				year = parsedYear
			}
		}
		month, mErr := strconv.Atoi(strings.TrimSpace(match[2]))
		day, dErr := strconv.Atoi(strings.TrimSpace(match[3]))
		if mErr == nil && dErr == nil {
			if dateValue, ok := buildUTCDate(year, month, day); ok {
				return dateValue, true
			}
		}
	}

	return time.Time{}, false
}

func buildUTCDate(year, month, day int) (time.Time, bool) {
	if year < 2000 || year > 2100 {
		return time.Time{}, false
	}
	if month < 1 || month > 12 {
		return time.Time{}, false
	}
	if day < 1 || day > 31 {
		return time.Time{}, false
	}
	value := time.Date(year, time.Month(month), day, 0, 0, 0, 0, time.UTC)
	if value.Year() != year || int(value.Month()) != month || value.Day() != day {
		return time.Time{}, false
	}
	return value, true
}
func buildChatSystemPrompt(
	intent aiIntent,
	tone string,
	context chatContextResult,
	usePersonalData bool,
	sessionMemorySummary string,
	smalltalkStyleHint string,
) string {
	toneValue := strings.TrimSpace(tone)
	if toneValue == "" {
		toneValue = "neutral"
	}

	lines := []string{
		"You are BabyAI, a warm and practical parenting assistant.",
		"The user is a caregiver using a parenting AI chatbot.",
		"Speak naturally like a daily conversation with a caregiver.",
		"Do not mention technical terms such as database, logs, API, JSON, schema, token, model, or system prompt.",
		"Do not expose internal field names or key-value strings to the user.",
		"If data is missing or estimated, explain that in simple everyday language.",
		"Never claim diagnosis or prescription certainty; describe possibilities and safe next actions.",
		"Always answer in Markdown.",
		"Format guideline: choose Markdown structure based on context so the answer is easy to scan.",
		"Format guideline: for record-based summaries, prefer a compact Markdown table first.",
		"Format guideline: if summary and guidance are both present, put analysis/advice below a horizontal rule (`---`).",
		"Format guideline: use clear headings with `#`/`##` and bold key labels for readability.",
		"Format guideline: checklists or checkboxes (`- [ ]`, `- [x]`) are allowed when action tracking helps.",
		"Format guideline: avoid excessive bullet points; use bullets only for true multi-item lists.",
		"Format guideline: emojis are welcome when they improve warmth/readability; do not artificially limit them.",
		"Format guideline: keep paragraphs short and scannable.",
		"Answer tone: " + toneValue + ".",
	}

	if usePersonalData {
		if intent == aiIntentSmalltalk {
			lines = append(lines,
				"Smalltalk mode: avoid unsolicited raw data dump unless user asks for record details.",
				"Context summary: "+context.Summary,
			)
		} else {
			lines = append(lines,
				"Use only the supplied data context for factual claims.",
				"When context is requested_date_raw, prioritize that specific date raw records.",
				"When context is last_7d_raw, use raw records for the recent 7-day window and use monthly summary for older trends.",
				"Context summary: "+context.Summary,
			)
		}
	} else {
		lines = append(lines, "Personal data is disabled for this query. Provide general guidance only.")
	}
	if summary := strings.TrimSpace(sessionMemorySummary); summary != "" {
		lines = append(lines,
			"Conversation memory from older turns (compressed summary):",
			summary,
		)
	}
	if intent == aiIntentSmalltalk {
		if hint := strings.TrimSpace(smalltalkStyleHint); hint != "" {
			lines = append(lines, "Smalltalk style hint: "+hint)
		}
	}

	switch intent {
	case aiIntentSmalltalk:
		lines = append(lines,
			"Persona for smalltalk:",
			"- Be kind, warm, and encouraging.",
			"- Match the user's speaking style naturally (polite/casual, sentence length, emoji usage).",
			"- Do not start with statistics unless user explicitly asks for numbers or records.",
			"- Keep responses short and human, like a supportive caregiver friend.",
			"- If useful, add one gentle practical tip related to childcare.",
		)
	case aiIntentMedicalRelated:
		lines = append(lines,
			"Persona for medical conversation:",
			"- Be calm, precise, and safety-focused.",
			"- Use the user's recorded data to explain the current situation.",
			"- Never diagnose definitively; present possibilities only.",
			"- Start with a clear record-based summary table when data is available.",
			"- Then use `---` and provide cause analysis and practical medical guidance below it.",
			"- Cover: current summary, possible explanations, what to do now, where to go, and red flags.",
		)
	case aiIntentDataQuery:
		lines = append(lines,
			"Persona for data-based conversation:",
			"- Be exact and evidence-based using only user-entered records.",
			"- Give concrete numbers with clear period labels.",
			"- If details are missing (for example dose ml), say so plainly.",
			"- Present the record summary in a compact Markdown table for readability.",
			"- If interpretation is needed, add `---` and place analysis/next action below the table.",
			"- Use concise Markdown formatting and natural, helpful emojis when appropriate.",
		)
	case aiIntentCareRoutine:
		lines = append(lines,
			"Persona for routine coaching:",
			"- Friendly and practical.",
			"- Combine recent pattern observation with next-step suggestions.",
			"- Keep guidance actionable and easy to follow.",
		)
	default:
		lines = append(lines, "If records are insufficient, ask one focused follow-up question.")
	}

	return strings.Join(lines, "\n")
}

func usageMap(usage AIUsage) gin.H {
	return gin.H{
		"prompt_tokens":     usage.PromptTokens,
		"completion_tokens": usage.CompletionTokens,
		"total_tokens":      usage.TotalTokens,
	}
}

func creditMap(result billingResult) gin.H {
	return gin.H{
		"charged":          result.Charged,
		"balance_after":    result.BalanceAfter,
		"billing_mode":     string(result.BillingMode),
		"grace_used_today": result.GraceUsed,
		"grace_limit":      result.GraceLimit,
	}
}

func (a *App) writeChatExecutionError(c *gin.Context, err error) {
	if err == nil {
		return
	}
	var httpErr *chatHTTPError
	if errors.As(err, &httpErr) {
		if httpErr.Credit != nil {
			c.AbortWithStatusJSON(httpErr.Status, gin.H{
				"detail": httpErr.Detail,
				"credit": gin.H{
					"balance":          httpErr.Credit.Balance,
					"grace_used_today": httpErr.Credit.GraceUsed,
					"grace_limit":      httpErr.Credit.GraceLimit,
				},
			})
			return
		}
		writeError(c, httpErr.Status, httpErr.Detail)
		return
	}
	lowered := strings.ToLower(strings.TrimSpace(err.Error()))
	switch {
	case strings.Contains(lowered, "openai_api_key is not configured"):
		writeError(c, http.StatusServiceUnavailable, "AI provider is not configured: set OPENAI_API_KEY")
		return
	case strings.Contains(lowered, "openai responses error"):
		writeError(c, http.StatusBadGateway, "AI provider request failed")
		return
	case strings.Contains(lowered, "context deadline exceeded"):
		writeError(c, http.StatusBadGateway, "AI provider request timed out")
		return
	case strings.Contains(lowered, "openai response answer is empty"):
		writeError(c, http.StatusBadGateway, "AI provider returned empty answer")
		return
	case strings.Contains(lowered, "openai response incomplete due max_output_tokens"):
		writeError(c, http.StatusBadGateway, "AI provider response incomplete; increase AI_MAX_OUTPUT_TOKENS")
		return
	case strings.Contains(lowered, "ai response missing usage tokens"):
		writeError(c, http.StatusBadGateway, "AI provider returned incomplete usage metadata")
		return
	}
	log.Printf("chat query failed unclassified err=%v", err)
	writeError(c, http.StatusInternalServerError, "Failed to execute chat query")
}

func buildSessionMemorySummary(existing string, turns []ChatTurn) string {
	lines := make([]string, 0, len(turns)+8)
	if trimmed := strings.TrimSpace(existing); trimmed != "" {
		lines = append(lines, splitNonEmptyLines(trimmed)...)
	}
	for _, turn := range turns {
		role := strings.ToLower(strings.TrimSpace(turn.Role))
		if role != "user" && role != "assistant" {
			continue
		}
		content := normalizeMemoryContent(turn.Content)
		if content == "" {
			continue
		}
		speaker := "User"
		if role == "assistant" {
			speaker = "Assistant"
		}
		lines = append(lines, "- "+speaker+": "+content)
	}
	if len(lines) == 0 {
		return ""
	}
	return trimToRuneLimit(strings.Join(lines, "\n"), chatMemorySummaryCharMax)
}

func normalizeMemoryContent(content string) string {
	compact := strings.Join(strings.Fields(strings.TrimSpace(content)), " ")
	if compact == "" {
		return ""
	}
	return truncateRunes(compact, chatMemoryLineCharMax)
}

func trimToRuneLimit(value string, limit int) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" || limit <= 0 {
		return trimmed
	}
	runes := []rune(trimmed)
	if len(runes) <= limit {
		return trimmed
	}

	const prefix = "(older memory compressed)\n"
	keep := limit - len([]rune(prefix))
	if keep < 64 {
		keep = limit
	}
	if keep > len(runes) {
		keep = len(runes)
	}
	tail := strings.TrimSpace(string(runes[len(runes)-keep:]))
	if keep == limit {
		return tail
	}
	return prefix + tail
}

func truncateRunes(value string, max int) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" || max <= 0 {
		return ""
	}
	runes := []rune(trimmed)
	if len(runes) <= max {
		return trimmed
	}
	return strings.TrimSpace(string(runes[:max])) + "..."
}

func deriveSmalltalkStyleHint(turns []ChatTurn, latestQuestion string) string {
	samples := collectUserToneSamples(turns, latestQuestion, 8)
	if len(samples) == 0 {
		return ""
	}

	formalScore := 0
	casualScore := 0
	emojiLike := 0
	totalRunes := 0
	hasHangul := false

	for _, sample := range samples {
		text := strings.TrimSpace(sample)
		if text == "" {
			continue
		}
		totalRunes += len([]rune(text))
		lowered := strings.ToLower(text)

		if containsAnyKeyword(lowered, []string{
			"합니다", "습니다", "요", "해주세요", "부탁", "괜찮을까요", "인가요",
			"please", "could you", "would you",
		}) {
			formalScore++
		}
		if containsAnyKeyword(lowered, []string{
			"해줘", "줘", "ㅋㅋ", "ㅎㅎ", "ㅠㅠ", "ㅜㅜ", "~",
			"lol", "haha", "pls", "thx",
		}) {
			casualScore++
		}
		if containsEmojiHint(text) {
			emojiLike++
		}
		if hasHangulText(text) {
			hasHangul = true
		}
	}

	avgLen := 0
	if len(samples) > 0 {
		avgLen = totalRunes / len(samples)
	}

	hints := []string{
		"Mirror the user's speaking style naturally and keep it warm.",
	}
	if hasHangul {
		switch {
		case formalScore >= casualScore+1:
			hints = append(hints, "Use polite Korean endings.")
		case casualScore >= formalScore+1:
			hints = append(hints, "Use conversational Korean similar to the user while staying respectful.")
		default:
			hints = append(hints, "Use friendly everyday Korean with balanced politeness.")
		}
	} else {
		if formalScore >= casualScore+1 {
			hints = append(hints, "Keep wording polite and considerate.")
		} else {
			hints = append(hints, "Keep wording casual and friendly.")
		}
	}
	if avgLen > 0 && avgLen <= 30 {
		hints = append(hints, "Prefer short sentences.")
	}
	if emojiLike > 0 {
		hints = append(hints, "A light emoji can be used when it fits.")
	}
	return strings.Join(hints, " ")
}

func collectUserToneSamples(turns []ChatTurn, latestQuestion string, max int) []string {
	if max <= 0 {
		max = 6
	}
	samples := make([]string, 0, max)
	if question := strings.TrimSpace(latestQuestion); question != "" {
		samples = append(samples, question)
	}
	for i := len(turns) - 1; i >= 0 && len(samples) < max; i-- {
		turn := turns[i]
		if strings.ToLower(strings.TrimSpace(turn.Role)) != "user" {
			continue
		}
		content := strings.TrimSpace(turn.Content)
		if content == "" {
			continue
		}
		samples = append(samples, content)
	}
	return samples
}

func containsEmojiHint(text string) bool {
	if strings.ContainsAny(text, "🙂😊😂🤣😅😍😭😢😴😄😉🥹✨🙏👍👶🍼❤💕") {
		return true
	}
	if strings.Contains(text, "ㅋㅋ") || strings.Contains(text, "ㅎㅎ") || strings.Contains(text, "ㅠㅠ") || strings.Contains(text, "ㅜㅜ") {
		return true
	}
	lowered := strings.ToLower(text)
	return strings.Contains(lowered, "lol") || strings.Contains(lowered, "haha")
}

func hasHangulText(text string) bool {
	for _, r := range text {
		if r >= 0xAC00 && r <= 0xD7A3 {
			return true
		}
	}
	return false
}

func normalizeSessionPreview(input *string) string {
	if input == nil {
		return "No messages yet"
	}
	normalized := strings.Join(strings.Fields(strings.TrimSpace(*input)), " ")
	if normalized == "" {
		return "No messages yet"
	}
	const maxLen = 96
	if len(normalized) <= maxLen {
		return normalized
	}
	return strings.TrimSpace(normalized[:maxLen]) + "..."
}

func deriveSessionTitle(firstUserInput *string) string {
	if firstUserInput == nil {
		return "New conversation"
	}
	normalized := strings.Join(strings.Fields(strings.TrimSpace(*firstUserInput)), " ")
	if normalized == "" {
		return "New conversation"
	}
	const maxLen = 38
	if len(normalized) <= maxLen {
		return normalized
	}
	return strings.TrimSpace(normalized[:maxLen]) + "..."
}

func formatContextTime(value time.Time) string {
	return value.UTC().Format("2006-01-02 15:04")
}

func nullableString(value any) *string {
	if value == nil {
		return nil
	}
	switch raw := value.(type) {
	case string:
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" {
			return nil
		}
		return &trimmed
	default:
		parsed := strings.TrimSpace(fmt.Sprintf("%v", value))
		if parsed == "" {
			return nil
		}
		return &parsed
	}
}

func cloneMap(input map[string]any) map[string]any {
	if input == nil {
		return map[string]any{}
	}
	result := make(map[string]any, len(input))
	for key, value := range input {
		result[key] = value
	}
	return result
}
