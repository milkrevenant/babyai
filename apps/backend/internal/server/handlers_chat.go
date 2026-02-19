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

type childProfileSnapshot struct {
	Name             string
	BirthDate        time.Time
	AgeDays          int
	AgeMonths        int
	WeightKg         *float64
	WeightSource     string
	HeightCm         *float64
	HeightSource     string
	GrowthMeasuredAt *time.Time
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

const (
	chatConversationTurnLimit = 30
	chatMemorySummaryCharMax  = 3200
	chatMemoryLineCharMax     = 180
	smalltalkReplyRuneMax     = 90
)

func (e *chatHTTPError) Error() string {
	return e.Detail
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
		defaultChildID, err := a.resolvePrimaryChildForHousehold(c.Request.Context(), householdID)
		if err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to resolve default child profile")
			return
		}
		if defaultChildID == "" {
			childRef = nil
		} else {
			childRef = defaultChildID
		}
	}

	sessionID := uuid.NewString()
	if _, err := a.db.Exec(
		c.Request.Context(),
		`UPDATE "ChatSession"
		 SET status = 'CLOSED',
		     "endedAt" = COALESCE("endedAt", NOW()),
		     "updatedAt" = NOW()
		 WHERE "userId" = $1
		   AND "householdId" = $2
		   AND COALESCE("childId", '') = COALESCE($3::text, '')
		   AND status = 'ACTIVE'`,
		user.ID,
		householdID,
		childRef,
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to rotate previous chat session")
		return
	}

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

func (a *App) aiQuery(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload aiQueryRequest
	if !mustJSON(c, &payload) {
		return
	}
	payload.Tone = normalizeTone(payload.Tone)
	payload.BabyID = strings.TrimSpace(payload.BabyID)
	if payload.BabyID == "" {
		writeError(c, http.StatusBadRequest, "baby_id is required")
		return
	}
	if strings.TrimSpace(payload.Question) == "" {
		writeError(c, http.StatusBadRequest, "question is required")
		return
	}

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, payload.BabyID, readRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}
	hasFeature, plan, statusValue, err := a.hasSubscriptionFeature(
		c.Request.Context(),
		baby.HouseholdID,
		subscriptionFeatureAI,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load subscription")
		return
	}
	if !hasFeature {
		a.writeSubscriptionRequired(c, subscriptionFeatureAI, plan, statusValue)
		return
	}

	sessionID, err := a.getOrCreateCompatChatSession(c.Request.Context(), user.ID, baby.HouseholdID, baby.ID)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to prepare chat session")
		return
	}

	result, err := a.runChatQuery(
		c.Request.Context(),
		user,
		chatQueryRequest{
			SessionID:       sessionID,
			ChildID:         baby.ID,
			Query:           payload.Question,
			Tone:            payload.Tone,
			UsePersonalData: payload.UsePersonalData,
		},
		baby.ID,
	)
	if err != nil {
		a.writeChatExecutionError(c, err)
		return
	}

	labels := []string{"general_information"}
	if payload.UsePersonalData {
		labels = []string{"record_based"}
	}

	c.JSON(http.StatusOK, gin.H{
		"answer":            result.Answer,
		"labels":            labels,
		"tone":              payload.Tone,
		"use_personal_data": payload.UsePersonalData,
		"intent":            string(result.Intent),
		"session_id":        result.SessionID,
		"message_id":        result.AssistantMessageID,
		"model":             result.Model,
		"usage":             usageMap(result.Usage),
		"credit":            creditMap(result.Credit),
		"reference_text":    result.ReferenceText,
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
	hasFeature, _, _, err := a.hasSubscriptionFeature(
		ctx,
		session.HouseholdID,
		subscriptionFeatureAI,
	)
	if err != nil {
		return chatExecutionResult{}, err
	}
	if !hasFeature {
		return chatExecutionResult{}, &chatHTTPError{
			Status: http.StatusPaymentRequired,
			Detail: subscriptionFeatureDetail(subscriptionFeatureAI),
		}
	}

	childID := strings.TrimSpace(payload.ChildID)
	if childID == "" {
		childID = strings.TrimSpace(fallbackChildID)
	}
	if childID == "" && session.ChildID != nil {
		childID = strings.TrimSpace(*session.ChildID)
	}
	if payload.UsePersonalData && childID == "" {
		resolvedChildID, resolveErr := a.resolvePrimaryChildForHousehold(ctx, session.HouseholdID)
		if resolveErr != nil {
			return chatExecutionResult{}, resolveErr
		}
		childID = strings.TrimSpace(resolvedChildID)
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

	firstUserMessageID, firstUserMessage, fixedIntent, err := a.loadFirstUserMessageIntent(ctx, session.ID)
	if err != nil {
		_ = a.releaseReservedCredits(ctx, user.ID, preflight.Reserved)
		return chatExecutionResult{}, err
	}

	intent := a.resolveSessionIntentFromFirstUserMessage(
		ctx,
		session.ID,
		question,
		turns,
		firstUserMessageID,
		firstUserMessage,
		fixedIntent,
	)
	smalltalkStyleHint := ""
	if intent == aiIntentSmalltalk {
		smalltalkStyleHint = deriveSmalltalkStyleHint(turns, question)
	}

	chatContext, err := a.buildChatContext(ctx, user.ID, childID, intent, question, now, payload.UsePersonalData)
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
	finalAnswer := strings.TrimSpace(aiResponse.Answer)
	finalAnswer = sanitizeUserFacingAnswer(finalAnswer)
	if intent == aiIntentSmalltalk {
		finalAnswer = sanitizeSmalltalkAnswer(finalAnswer)
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
		finalAnswer,
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
		Answer:             finalAnswer,
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

func (a *App) resolvePrimaryChildForHousehold(ctx context.Context, householdID string) (string, error) {
	householdValue := strings.TrimSpace(householdID)
	if householdValue == "" {
		return "", nil
	}

	var childID string
	err := a.db.QueryRow(
		ctx,
		`SELECT id
		 FROM "Baby"
		 WHERE "householdId" = $1
		 ORDER BY "createdAt" ASC, id ASC
		 LIMIT 1`,
		householdValue,
	).Scan(&childID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(childID), nil
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

func (a *App) loadFirstUserMessageIntent(ctx context.Context, sessionID string) (string, string, aiIntent, error) {
	var messageID, content string
	var intent *string
	err := a.db.QueryRow(
		ctx,
		`SELECT id, content, intent
		 FROM "ChatMessage"
		 WHERE "sessionId" = $1 AND role = 'user'
		 ORDER BY "createdAt" ASC
		 LIMIT 1`,
		sessionID,
	).Scan(&messageID, &content, &intent)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", "", nil
	}
	if err != nil {
		return "", "", "", err
	}
	normalizedIntent := aiIntent("")
	if intent != nil {
		normalizedIntent = normalizeAIIntentLabel(*intent)
	}
	return strings.TrimSpace(messageID), strings.TrimSpace(content), normalizedIntent, nil
}

func (a *App) saveFirstUserIntent(ctx context.Context, messageID string, intent aiIntent) error {
	trimmedMessageID := strings.TrimSpace(messageID)
	if trimmedMessageID == "" || strings.TrimSpace(string(intent)) == "" {
		return nil
	}
	_, err := a.db.Exec(
		ctx,
		`UPDATE "ChatMessage"
		 SET intent = $2
		 WHERE id = $1 AND role = 'user'`,
		trimmedMessageID,
		string(intent),
	)
	return err
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

func (a *App) resolveSessionIntentFromFirstUserMessage(
	ctx context.Context,
	sessionID string,
	question string,
	turns []ChatTurn,
	firstUserMessageID string,
	firstUserMessage string,
	fixedIntent aiIntent,
) aiIntent {
	fallback := resolveAIIntentWithSession(question, turns)
	if fixedIntent != "" {
		return fixedIntent
	}

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
	// Guardrail: caregiver self-state utterances should stay in smalltalk.
	if isLikelyCaregiverSelfTalk(firstMessage) {
		if strings.TrimSpace(firstUserMessageID) != "" {
			if saveErr := a.saveFirstUserIntent(ctx, firstUserMessageID, aiIntentSmalltalk); saveErr != nil {
				log.Printf("failed to persist caregiver-self smalltalk intent session_id=%s message_id=%s err=%v", sessionID, firstUserMessageID, saveErr)
			}
		}
		return aiIntentSmalltalk
	}

	intent, err := a.resolveAIIntentByFirstMessage(ctx, firstMessage, question)
	if err != nil || intent == "" {
		return fallback
	}
	if strings.TrimSpace(firstUserMessageID) != "" {
		if saveErr := a.saveFirstUserIntent(ctx, firstUserMessageID, intent); saveErr != nil {
			log.Printf("failed to persist first-user intent session_id=%s message_id=%s intent=%s err=%v", sessionID, firstUserMessageID, intent, saveErr)
		}
	}
	return intent
}

func (a *App) resolveAIIntentByFirstMessage(ctx context.Context, firstMessage, latestQuestion string) (aiIntent, error) {
	systemPrompt := strings.Join([]string{
		"너는 육아 도우미의 의도 분류 라우터다.",
		"화자는 기본적으로 아이가 아닌 보호자로 가정한다.",
		"첫 사용자 메시지를 가장 중요한 신호로 사용해 대화 의도를 분류한다.",
		"허용 의도는 smalltalk, data_query, medical_related, care_routine 네 가지뿐이다.",
		"메시지가 보호자 본인 상태(예: 배고픔/피곤함/스트레스)이고 아이 주어가 명시되지 않으면 smalltalk로 분류한다.",
		"모호한 1인칭 표현을 아이 상태로 과추론하지 않는다.",
		"반드시 JSON 객체만 반환한다.",
		`JSON schema: {"intent":"smalltalk|data_query|medical_related|care_routine","confidence":0.0,"reason":"short reason"}`,
		"마크다운, 코드펜스, 부가 설명 텍스트는 금지한다.",
	}, "\n")
	userPrompt := strings.Join([]string{
		"첫 사용자 메시지: " + strings.TrimSpace(firstMessage),
		"최신 사용자 메시지: " + strings.TrimSpace(latestQuestion),
		"의도는 정확히 1개만 선택한다.",
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

func isLikelyCaregiverSelfTalk(message string) bool {
	normalized := strings.ToLower(strings.Join(strings.Fields(strings.TrimSpace(message)), " "))
	if normalized == "" {
		return false
	}

	childSubjectMarkers := []string{
		"아기", "아이", "애기", "우리애", "우리 아이", "아들", "딸",
		"baby", "child", "kid", "infant", "newborn", "toddler",
	}
	if containsAnyKeyword(normalized, childSubjectMarkers) {
		return false
	}

	parentingDomainMarkers := []string{
		"수유", "분유", "모유", "기저귀", "이유식", "수면", "낮잠", "밤잠", "체온", "열", "기침", "구토", "설사",
		"feeding", "formula", "breastfeed", "diaper", "nap", "sleep", "fever", "cough", "vomit", "diarrhea",
	}
	if containsAnyKeyword(normalized, parentingDomainMarkers) {
		return false
	}

	caregiverStateMarkers := []string{
		"배고프", "배가 고파", "피곤", "졸리", "지치", "힘들", "우울", "불안", "스트레스", "멘붕",
		"hungry", "starving", "tired", "sleepy", "exhausted", "stressed", "overwhelmed", "burned out", "burnt out", "anxious",
	}
	return containsAnyKeyword(normalized, caregiverStateMarkers)
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
	userID string,
	childID string,
	intent aiIntent,
	question string,
	now time.Time,
	usePersonalData bool,
) (chatContextResult, error) {
	if !usePersonalData || strings.TrimSpace(childID) == "" {
		timeRange := "none"
		summary := "이번 질의는 개인 기록 컨텍스트가 비활성화되어 있습니다."
		if intent == aiIntentSmalltalk {
			timeRange = "smalltalk_chat_only"
			summary = strings.Join([]string{
				"일상대화 전용 모드입니다.",
				"이 모드에서는 개인 DB 컨텍스트가 비활성화되어 세션 대화 맥락만 활용합니다.",
			}, "\n")
		}
		meta := map[string]any{
			"child_id":             nil,
			"time_range":           timeRange,
			"evidence_event_ids":   []string{},
			"has_estimated_values": false,
			"has_missing_data":     true,
		}
		return chatContextResult{
			Meta:    meta,
			Summary: summary,
		}, nil
	}

	nowUTC := now.UTC()
	profileSnapshot, err := a.loadChildProfileSnapshot(ctx, userID, childID)
	if err != nil {
		return chatContextResult{}, err
	}
	birthDateText := ""
	if !profileSnapshot.BirthDate.IsZero() {
		birthDateText = profileSnapshot.BirthDate.UTC().Format("2006-01-02")
	}
	if intent == aiIntentSmalltalk {
		meta := map[string]any{
			"child_id":                       childID,
			"time_range":                     "smalltalk_profile_snapshot",
			"evidence_event_ids":             []string{},
			"has_estimated_values":           false,
			"has_missing_data":               false,
			"profile_name":                   profileSnapshot.Name,
			"profile_birth_date_utc":         birthDateText,
			"profile_age_days":               profileSnapshot.AgeDays,
			"profile_age_months":             profileSnapshot.AgeMonths,
			"profile_age_months_basis":       "calendar_from_birth_date",
			"profile_weight_kg":              profileSnapshot.WeightKg,
			"profile_weight_source":          profileSnapshot.WeightSource,
			"profile_height_cm":              profileSnapshot.HeightCm,
			"profile_height_source":          profileSnapshot.HeightSource,
			"profile_growth_measured_at_utc": formatNullableTimeRFC3339(profileSnapshot.GrowthMeasuredAt),
		}
		summaryLines := []string{
			fmt.Sprintf("일상대화용 아동 프로필 DB 스냅샷 (child_id=%s).", childID),
			fmt.Sprintf("- 이름=%s", profileSnapshot.Name),
			fmt.Sprintf("- 생년월일=%s", birthDateText),
			fmt.Sprintf("- 나이=%d일 (만 %d개월, 생년월일 기준)", profileSnapshot.AgeDays, profileSnapshot.AgeMonths),
		}
		if profileSnapshot.WeightKg != nil {
			summaryLines = append(summaryLines, fmt.Sprintf("- 몸무게=%.1fkg (출처=%s)", *profileSnapshot.WeightKg, profileSnapshot.WeightSource))
		} else {
			summaryLines = append(summaryLines, "- 몸무게=없음")
		}
		if profileSnapshot.HeightCm != nil {
			line := fmt.Sprintf("- 키=%.1fcm (출처=%s)", *profileSnapshot.HeightCm, profileSnapshot.HeightSource)
			if profileSnapshot.GrowthMeasuredAt != nil {
				line = line + fmt.Sprintf(", 측정시각=%s", formatContextTime(*profileSnapshot.GrowthMeasuredAt))
			}
			summaryLines = append(summaryLines, line)
		} else {
			summaryLines = append(summaryLines, "- 키=없음")
		}
		return chatContextResult{
			Meta:    meta,
			Summary: strings.Join(summaryLines, "\n"),
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
			fmt.Sprintf("이벤트ID=%s", strings.TrimSpace(eventID)),
			fmt.Sprintf("유형=%s", strings.ToUpper(eventType)),
			fmt.Sprintf("시작시각=%s", formatContextTime(startAt)),
		}
		if endAt != nil {
			details = append(details, fmt.Sprintf("종료시각=%s", formatContextTime(*endAt)))
		}
		if v := strings.TrimSpace(valueText); v != "" && v != "{}" && v != "null" {
			details = append(details, "값="+v)
		}
		if m := strings.TrimSpace(metadataText); m != "" && m != "{}" && m != "null" {
			details = append(details, "메타="+m)
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
			dailyOverviewLines = append(dailyOverviewLines, fmt.Sprintf("- %s: %d건", strings.TrimSpace(day), count))
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
		"child_id":                       childID,
		"time_range":                     rawRangeLabel,
		"evidence_event_ids":             evidenceIDs,
		"has_estimated_values":           false,
		"has_missing_data":               hasMissingData,
		"reference_now_utc":              nowUTC.Format(time.RFC3339),
		"raw_since_utc":                  rawStart.Format(time.RFC3339),
		"raw_until_utc":                  rawEnd.Format(time.RFC3339),
		"monthly_since_utc":              monthlyStart.Format(time.RFC3339),
		"monthly_until_utc":              monthlyEnd.Format(time.RFC3339),
		"profile_name":                   profileSnapshot.Name,
		"profile_birth_date_utc":         birthDateText,
		"profile_age_days":               profileSnapshot.AgeDays,
		"profile_age_months":             profileSnapshot.AgeMonths,
		"profile_age_months_basis":       "calendar_from_birth_date",
		"profile_weight_kg":              profileSnapshot.WeightKg,
		"profile_weight_source":          profileSnapshot.WeightSource,
		"profile_height_cm":              profileSnapshot.HeightCm,
		"profile_height_source":          profileSnapshot.HeightSource,
		"profile_growth_measured_at_utc": formatNullableTimeRFC3339(profileSnapshot.GrowthMeasuredAt),
	}
	if requestedDate != nil {
		meta["requested_date_utc"] = requestedDate.Format("2006-01-02")
	}

	summaryLines := make([]string, 0, len(rawLines)+96)
	summaryLines = append(summaryLines, fmt.Sprintf("아동 기준 참고 컨텍스트 (child_id=%s).", childID))
	summaryLines = append(summaryLines,
		"아동 프로필 스냅샷:",
		fmt.Sprintf("- 이름=%s", profileSnapshot.Name),
		fmt.Sprintf("- 생년월일=%s", birthDateText),
		fmt.Sprintf("- 나이=%d일 (만 %d개월, 생년월일 기준)", profileSnapshot.AgeDays, profileSnapshot.AgeMonths),
		fmt.Sprintf("- 현재 기준 시각=%s", formatContextTime(nowUTC)),
	)
	if profileSnapshot.WeightKg != nil {
		summaryLines = append(summaryLines,
			fmt.Sprintf("- 몸무게=%.1fkg (출처=%s)", *profileSnapshot.WeightKg, profileSnapshot.WeightSource),
		)
	} else {
		summaryLines = append(summaryLines, "- 몸무게=없음")
	}
	if profileSnapshot.HeightCm != nil {
		line := fmt.Sprintf("- 키=%.1fcm (출처=%s)", *profileSnapshot.HeightCm, profileSnapshot.HeightSource)
		if profileSnapshot.GrowthMeasuredAt != nil {
			line = line + fmt.Sprintf(", 측정시각=%s", formatContextTime(*profileSnapshot.GrowthMeasuredAt))
		}
		summaryLines = append(summaryLines, line)
	} else {
		summaryLines = append(summaryLines, "- 키=없음")
	}
	if requestedDate != nil {
		summaryLines = append(summaryLines,
			fmt.Sprintf("사용자가 특정 날짜 원시 기록을 요청함: %s.", requestedDate.Format("2006-01-02")),
		)
	}
	summaryLines = append(summaryLines,
		fmt.Sprintf("원시 기록 조회 구간: %s ~ %s.", formatContextTime(rawStart), formatContextTime(rawEnd)),
		"아래 원시 이벤트는 사용자가 입력한 기록의 저장 원본(값/메타)입니다.",
	)
	if len(rawLines) == 0 {
		summaryLines = append(summaryLines, "- 선택한 원시 구간에 기록이 없습니다.")
	} else {
		summaryLines = append(summaryLines, rawLines...)
		rawTypes := make([]string, 0, len(rawCountByType))
		for eventType := range rawCountByType {
			rawTypes = append(rawTypes, eventType)
		}
		sort.Strings(rawTypes)
		summaryLines = append(summaryLines, "원시 구간 유형별 건수:")
		for _, eventType := range rawTypes {
			summaryLines = append(summaryLines,
				fmt.Sprintf("- %s: %d건", strings.ToUpper(strings.TrimSpace(eventType)), rawCountByType[eventType]),
			)
		}
	}

	summaryLines = append(summaryLines,
		"월간 요약(원시 구간 이전 최대 30일):",
		fmt.Sprintf("월간 요약 구간: %s ~ %s.", formatContextTime(monthlyStart), formatContextTime(monthlyEnd)),
	)
	if len(monthlyCountByType) == 0 {
		summaryLines = append(summaryLines, "- 설정된 월간 구간에 요약할 기록이 없습니다.")
	} else {
		types := make([]string, 0, len(monthlyCountByType))
		for eventType := range monthlyCountByType {
			types = append(types, eventType)
		}
		sort.Strings(types)
		for _, eventType := range types {
			summaryLines = append(summaryLines,
				fmt.Sprintf("- %s: %d건", strings.ToUpper(strings.TrimSpace(eventType)), monthlyCountByType[eventType]),
			)
		}
	}
	if len(dailyOverviewLines) == 0 {
		summaryLines = append(summaryLines, "- 월간 구간 일자별 집계가 없습니다.")
	} else {
		summaryLines = append(summaryLines, "월간 구간 일자별 건수:")
		summaryLines = append(summaryLines, dailyOverviewLines...)
	}

	return chatContextResult{
		Meta:    meta,
		Summary: strings.Join(summaryLines, "\n"),
	}, nil
}

func (a *App) loadChildProfileSnapshot(ctx context.Context, userID, childID string) (childProfileSnapshot, error) {
	profile, _, err := a.resolveBabyProfile(ctx, userID, childID, readRoles)
	if err != nil {
		return childProfileSnapshot{}, err
	}

	snapshot := childProfileSnapshot{
		Name:         strings.TrimSpace(profile.Name),
		BirthDate:    startOfUTCDay(profile.BirthDate.UTC()),
		AgeDays:      profile.AgeDays,
		AgeMonths:    ageMonthsFromBirthDate(profile.BirthDate.UTC(), time.Now().UTC()),
		WeightKg:     profile.WeightKg,
		WeightSource: "profile_settings",
		HeightCm:     nil,
		HeightSource: "not_available",
	}
	if snapshot.AgeMonths < 0 {
		snapshot.AgeMonths = 0
	}
	if snapshot.WeightKg == nil {
		snapshot.WeightSource = "not_available"
	}

	var growthStartAt time.Time
	var growthValueRaw []byte
	growthErr := a.db.QueryRow(
		ctx,
		`SELECT "startTime", "valueJson"::text
		 FROM "Event"
		 WHERE "babyId" = $1
		   AND type = 'GROWTH'
		 ORDER BY "startTime" DESC
		 LIMIT 1`,
		childID,
	).Scan(&growthStartAt, &growthValueRaw)
	if growthErr != nil && !errors.Is(growthErr, pgx.ErrNoRows) {
		return childProfileSnapshot{}, growthErr
	}
	if growthErr == nil {
		valueMap := parseJSONStringMap(growthValueRaw)
		if snapshot.WeightKg == nil {
			if weight := extractNumberFromMap(valueMap, "weight_kg", "weightKg", "weight"); weight > 0 {
				rounded := roundToOneDecimal(weight)
				snapshot.WeightKg = &rounded
				snapshot.WeightSource = "latest_growth_event"
			}
		}
		if height := extractNumberFromMap(
			valueMap,
			"height_cm",
			"length_cm",
			"stature_cm",
			"heightCm",
			"lengthCm",
			"height",
			"length",
		); height > 0 {
			rounded := roundToOneDecimal(height)
			snapshot.HeightCm = &rounded
			snapshot.HeightSource = "latest_growth_event"
			measuredAt := growthStartAt.UTC()
			snapshot.GrowthMeasuredAt = &measuredAt
		}
	}

	if snapshot.Name == "" {
		snapshot.Name = "child"
	}
	return snapshot, nil
}

func ageMonthsFromBirthDate(birthDate, now time.Time) int {
	if birthDate.IsZero() {
		return 0
	}
	birthUTC := startOfUTCDay(birthDate.UTC())
	nowUTC := startOfUTCDay(now.UTC())
	if nowUTC.Before(birthUTC) {
		return 0
	}
	months := (nowUTC.Year()-birthUTC.Year())*12 + int(nowUTC.Month()) - int(birthUTC.Month())
	if nowUTC.Day() < birthUTC.Day() {
		months--
	}
	if months < 0 {
		return 0
	}
	return months
}

var (
	htmlBreakTagPattern    = regexp.MustCompile(`(?i)<br\s*/?>`)
	utcParenPattern        = regexp.MustCompile(`(?i)\(\s*UTC\s*\)`)
	utcWordPattern         = regexp.MustCompile(`(?i)\bUTC\b`)
	rfc3339DateTimePattern = regexp.MustCompile(`\b20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\b`)
	timeWithZSuffixPattern = regexp.MustCompile(`\b(20\d{2}-\d{2}-\d{2}\s+\d{2}:\d{2})(?::\d{2})?Z\b`)
	isoDatePattern         = regexp.MustCompile(`\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b`)
	koreanDatePattern      = regexp.MustCompile(`(?:(20\d{2})\s*년\s*)?(\d{1,2})\s*월\s*(\d{1,2})\s*일`)
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
		"너는 BabyAI이며, 보호자와 대화하는 따뜻하고 실용적인 육아 도우미다.",
		"모든 답변의 기본 언어는 한국어다. 사용자가 다른 언어를 명시적으로 요청할 때만 해당 언어를 사용한다.",
		"같은 세션의 이전 대화를 이어서 답하고, 단발성 답변처럼 끊지 않는다.",
		"필요하면 직전 대화 맥락을 짧게 연결해 연속성을 유지한다.",
		"사용자 노출 답변에서 UTC 같은 시간대 용어를 쓰지 않는다.",
		"날짜/시간 표기는 `YYYY-MM-DD HH:MM` 형식으로 통일한다.",
		"데이터베이스, 로그, API, JSON, 스키마, 토큰, 모델, 시스템 프롬프트 같은 내부 기술 용어를 사용자에게 말하지 않는다.",
		"내부 필드명과 key-value 원문을 그대로 노출하지 않는다.",
		"공지문/정책문/병원 게시문처럼 딱딱한 문체를 피하고 자연스러운 한국어 대화체를 사용한다.",
		"최종 답변에 HTML 태그(`<br>` 등)를 사용하지 않는다.",
		"데이터가 누락되거나 추정치가 섞이면 쉬운 한국어로 짧고 명확하게 설명한다.",
		"진단/처방을 단정하지 말고 가능성과 안전한 다음 행동을 제시한다.",
		"시간 예측 질문(예: 다음 수유 ETA)은 컨텍스트에 제공된 현재 기준 시각을 기준으로 계산한다.",
		"smalltalk가 아닌 의도에서는 Markdown으로 답한다.",
		"모바일 화면에서 읽기 쉽도록 짧은 문단과 짧은 줄바꿈 중심으로 작성한다.",
		"핵심 결론은 첫 줄 1문장으로 제시한다.",
		"문단은 1~2문장으로 유지하고 긴 문장은 여러 줄로 나눈다.",
		"중요 정보(날짜, 시간, ml, 횟수, 퍼센트, 체온/체중 등 수치)는 값과 단위를 함께 Markdown 굵게(`**...**`)로 표시한다.",
		"강조 예시: **2026-02-15 14:30**, **120ml**, **3회**.",
		"중요 수치가 2개 이상이면 한 줄에 몰아쓰지 말고 줄을 나눠 제시한다.",
		"강조는 핵심 정보 위주로만 사용하고 문장 전체를 굵게 처리하지 않는다.",
		"불릿은 필요한 경우에만 사용하고 항목 수를 과도하게 늘리지 않는다.",
		"데이터 항목이 많거나 비교 포인트가 3개 이상이면 Markdown 표를 우선 사용한다.",
		"데이터 항목 수가 적으면 표보다 짧은 요약 문단/불릿을 우선한다.",
		"표를 쓸 때는 2열(`항목`, `요약`) 중심으로 구성하고 `항목`은 짧게, `요약`은 상대적으로 자세히 작성한다.",
		"요약에는 가능하면 항목별 `횟수`, `시간(범위/마지막 시각)`, `ml 용량(총량/마지막 또는 회당)`을 함께 제시한다.",
		"모바일 가독성을 위해 표의 열 이름과 셀 텍스트는 짧게 유지하고, 꼭 필요한 열만 남긴다.",
		"표 셀은 1~2줄 중심으로 작성하고, 긴 문장은 나눠 셀 높이가 과도하게 커지지 않게 한다.",
		"표 셀 내부 줄바꿈은 Markdown 기본 줄바꿈에 맞게 처리하고 `<br>` 같은 HTML 태그는 쓰지 않는다.",
		"표 셀 값은 공백, 쉼표, 슬래시(`/`), 하이픈(`-`) 단위로 자연 줄바꿈 가능하게 짧은 표현을 사용한다.",
		"기본 응답에서는 메모(원문 노트)를 본문에 넣지 않고, 사용자가 요청할 때만 별도 섹션으로 제공한다.",
		"요약과 가이드를 함께 제시할 때는 필요 시 구분선(`---`)을 사용한다.",
		"응답 톤: " + toneValue + ".",
	}

	if intent == aiIntentSmalltalk {
		lines = append(lines,
			"일상대화 모드: 이 세션은 기록 분석보다 대화 중심으로 운영한다.",
			"일상대화 모드: 필요하면 아동 프로필 DB 정보(생년월일 기준 월령/일령, 몸무게/키)를 1문장으로 자연스럽게 반영한다.",
			"일상대화 모드: 이벤트 통계/표/과도한 분석은 기본적으로 생략하고, 사용자가 원할 때만 간단히 언급한다.",
			"일상대화 모드: 해결책 제시보다 짧은 대화 왕복을 우선한다.",
			"일상대화 모드: 과한 공감/감정 과장은 피하고 담백하게 위로한다.",
			"일상대화 모드: 답변은 기본 1~2문장으로 짧게 유지한다.",
			"일상대화 모드: 필요하면 한 번에 질문 1개만 던져 자연스럽게 주고받는다.",
			"일상대화 모드: 사용자가 조언을 명시적으로 요청하기 전에는 해결책/팁/체크리스트를 먼저 제시하지 않는다.",
			"일상대화 모드 형식: 일반 채팅 문장만 출력한다. 제목(`#`), 불릿(`-`, `*`), 번호 목록은 사용하지 않는다.",
			"일상대화 모드 형식: 장식용 기호 나열을 피한다.",
			"일상대화 모드 이모지: 필요할 때만 가볍게 사용하고 반복 장식은 피한다.",
			"참고 컨텍스트: "+context.Summary,
		)
	} else if usePersonalData {
		lines = append(lines,
			"기록 기반 모드: 보호자가 아이 관련 내용을 묻는 상황으로 보고 제공된 아이 기록을 사실 근거로 사용한다.",
			"사실 판단은 제공된 데이터 컨텍스트 안에서만 수행한다.",
			"필요하면 아이 프로필(월령/일령, 몸무게, 키)을 함께 반영한다.",
			"context.time_range가 requested_date_raw이면 해당 날짜 원시 기록을 우선한다.",
			"context.time_range가 last_7d_raw이면 최근 7일 원시 기록을 우선하고, 그 이전 추세는 월간 요약으로 보완한다.",
			"참고 컨텍스트: "+context.Summary,
		)
	} else {
		lines = append(lines, "개인 기록이 비활성화된 질의이므로 일반 가이드만 제공한다.")
	}
	if summary := strings.TrimSpace(sessionMemorySummary); summary != "" {
		lines = append(lines,
			"이전 대화 메모(압축 요약):",
			summary,
		)
	}
	if intent == aiIntentSmalltalk {
		if hint := strings.TrimSpace(smalltalkStyleHint); hint != "" {
			lines = append(lines, "일상대화 스타일 힌트: "+hint)
		}
	}

	switch intent {
	case aiIntentSmalltalk:
		lines = append(lines,
			"일상대화 페르소나:",
			"- 보호자의 감정, 피로, 일상 상태에 초점을 둔다.",
			"- 친절하지만 과장되지 않은 안정된 톤을 유지한다.",
			"- 설명문/강의체보다 자연스러운 대화체를 사용한다.",
			"- 사용자 말투(존댓말/캐주얼, 문장 길이, 이모지 정도)를 자연스럽게 맞춘다.",
			"- 세션 내 핵심 맥락과 분위기를 기억해 짧게 연결한다.",
			"- 기본은 짧게 답하고, 필요 시 가벼운 후속 질문 1개로 대화를 이어간다.",
			"- 사용자가 불안하거나 지쳐 보이면 먼저 짧게 안정감을 주는 한마디를 건넨다.",
			"- 사용자가 요청하기 전에는 해결책/셀프케어 팁을 먼저 제안하지 않는다.",
		)
	case aiIntentMedicalRelated:
		lines = append(lines,
			"의료 대화 페르소나:",
			"- 침착하고 정확하며 안전 중심으로 답한다.",
			"- 이전 턴 맥락을 짧게 이어 보호자가 이미 공유한 내용을 반영한다.",
			"- 즉시 행동이 필요한 상황이면 첫 줄에 바로 해야 할 행동 1가지를 먼저 제시한다.",
			"- 확정 진단처럼 단정하지 않고 가능성 중심으로 설명한다.",
			"- 문단은 1~3개의 짧은 문장으로 유지해 모바일에서 읽기 쉽게 만든다.",
			"- 중요한 행동은 줄을 분리해 제시하고, 순서가 필요하면 1., 2., 3. 형식을 사용한다.",
			"- 설명보다 현재 해야 할 행동, 관찰 포인트, 병원/응급실 기준을 우선한다.",
			"- 마지막에는 필요 시 짧은 확인 질문 1개를 둔다.",
		)
	case aiIntentDataQuery:
		lines = append(lines,
			"기록 분석 페르소나:",
			"- 사용자 입력 기록만 근거로 정확하게 답한다.",
			"- 매 턴 같은 기초 요약을 반복하지 말고 이전 대화 맥락을 이어간다.",
			"- 차가운 리포트 문체보다 친절한 코치 톤을 유지한다.",
			"- 기간 라벨과 수치를 명확히 제시하되 문장은 짧고 자연스럽게 유지한다.",
			"- 가장 중요한 요점은 첫 줄 1문장으로 먼저 제시한다.",
			"- 요약은 `횟수`, `시간`, `ml 용량` 중심으로 먼저 제시한다.",
			"- 항목별로 총횟수, 마지막 시각(또는 시간 범위), 총 ml(또는 회당 ml)를 우선 정리한다.",
			"- 문단은 1~3개의 짧은 문장으로 유지해 모바일 가독성을 높인다.",
			"- 데이터 항목이 많거나 비교가 필요한 경우 표를 우선 사용하고, 2열(`항목`, `요약`)만 유지한다.",
			"- 메모/원문 노트는 사용자가 요청할 때만 제공한다.",
			"- 핵심 행동은 줄을 분리하고 순서가 필요하면 1., 2., 3. 형식을 사용한다.",
			"- 값이 비어 있으면 한 줄로 명확히 부족 정보를 알린다.",
			"- 마지막에 현실적인 다음 단계 1가지를 제안한다.",
		)
	case aiIntentCareRoutine:
		lines = append(lines,
			"루틴 코칭 페르소나:",
			"- 친근하고 실용적으로 안내한다.",
			"- 최근 패턴 관찰과 다음 행동 제안을 함께 제시한다.",
			"- 바로 실행 가능한 짧은 단계 위주로 설명한다.",
			"- 모바일에서 빠르게 읽히도록 간결한 블록 구조를 유지한다.",
		)
	default:
		lines = append(lines, "기록이 부족하면 초점이 분명한 후속 질문 1개를 한다.")
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

func sanitizeUserFacingAnswer(answer string) string {
	normalized := strings.TrimSpace(answer)
	if normalized == "" {
		return ""
	}

	normalized = htmlBreakTagPattern.ReplaceAllString(normalized, "\n")
	normalized = normalizeUserFacingDateTimes(normalized)
	normalized = timeWithZSuffixPattern.ReplaceAllString(normalized, "$1")

	normalized = strings.ReplaceAll(normalized, "시간(UTC)", "시간")
	normalized = strings.ReplaceAll(normalized, "기간(UTC)", "기간")
	normalized = strings.ReplaceAll(normalized, "날짜(UTC)", "날짜")
	normalized = strings.ReplaceAll(normalized, "(UTC):", ":")
	normalized = strings.ReplaceAll(normalized, "(utc):", ":")
	normalized = strings.ReplaceAll(normalized, "(UTC)", "")
	normalized = strings.ReplaceAll(normalized, "(utc)", "")
	normalized = utcWordPattern.ReplaceAllString(normalized, "")
	normalized = strings.ReplaceAll(normalized, "()", "")
	normalized = utcParenPattern.ReplaceAllString(normalized, "")
	normalized = strings.ReplaceAll(normalized, "UTC:", "")
	normalized = strings.ReplaceAll(normalized, "utc:", "")
	normalized = strings.ReplaceAll(normalized, "UTC 기준", "")
	normalized = strings.ReplaceAll(normalized, "utc 기준", "")
	normalized = strings.ReplaceAll(normalized, "( )", "")

	for strings.Contains(normalized, "  ") {
		normalized = strings.ReplaceAll(normalized, "  ", " ")
	}
	normalized = strings.ReplaceAll(normalized, " / / ", " / ")
	normalized = strings.ReplaceAll(normalized, " : ", ": ")
	return strings.TrimSpace(normalized)
}

func normalizeUserFacingDateTimes(input string) string {
	return rfc3339DateTimePattern.ReplaceAllStringFunc(input, func(raw string) string {
		if parsed, ok := parseRFC3339DateTime(raw); ok {
			return parsed.Format("2006-01-02 15:04")
		}
		return raw
	})
}

func parseRFC3339DateTime(raw string) (time.Time, bool) {
	candidate := strings.TrimSpace(raw)
	if candidate == "" {
		return time.Time{}, false
	}
	layouts := []string{
		time.RFC3339Nano,
		time.RFC3339,
		"2006-01-02T15:04:05Z07:00",
		"2006-01-02T15:04Z07:00",
	}
	for _, layout := range layouts {
		parsed, err := time.Parse(layout, candidate)
		if err == nil {
			return parsed, true
		}
	}
	return time.Time{}, false
}

func sanitizeSmalltalkAnswer(answer string) string {
	trimmed := strings.TrimSpace(answer)
	if trimmed == "" {
		return ""
	}

	lines := splitNonEmptyLines(trimmed)
	cleaned := make([]string, 0, len(lines))
	for _, line := range lines {
		item := strings.TrimSpace(line)
		if item == "" || item == "---" {
			continue
		}
		item = strings.TrimSpace(strings.TrimLeft(item, "#"))
		item = stripSmalltalkListPrefix(item)
		item = strings.TrimSpace(strings.Trim(item, "`"))
		if item == "" {
			continue
		}
		cleaned = append(cleaned, item)
	}

	merged := strings.Join(cleaned, " ")
	merged = strings.Join(strings.Fields(strings.TrimSpace(merged)), " ")
	if merged == "" {
		merged = strings.Join(strings.Fields(trimmed), " ")
	}
	return truncateRunes(merged, smalltalkReplyRuneMax)
}

func stripSmalltalkListPrefix(line string) string {
	trimmed := strings.TrimSpace(line)
	prefixes := []string{
		"- [ ] ",
		"- [x] ",
		"- ",
		"* ",
		"+ ",
	}
	for _, prefix := range prefixes {
		if strings.HasPrefix(trimmed, prefix) {
			return strings.TrimSpace(trimmed[len(prefix):])
		}
	}

	digitEnd := 0
	for digitEnd < len(trimmed) {
		ch := trimmed[digitEnd]
		if ch < '0' || ch > '9' {
			break
		}
		digitEnd++
	}
	if digitEnd > 0 && digitEnd+1 < len(trimmed) {
		marker := trimmed[digitEnd]
		next := trimmed[digitEnd+1]
		if (marker == '.' || marker == ')') && next == ' ' {
			return strings.TrimSpace(trimmed[digitEnd+2:])
		}
	}
	return trimmed
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
		"사용자 말투를 자연스럽게 맞추고 따뜻한 톤을 유지하세요.",
	}
	if hasHangul {
		switch {
		case formalScore >= casualScore+1:
			hints = append(hints, "존댓말 어미를 안정적으로 사용하세요.")
		case casualScore >= formalScore+1:
			hints = append(hints, "사용자와 비슷한 구어체 한국어를 쓰되 예의는 유지하세요.")
		default:
			hints = append(hints, "친근하지만 균형 잡힌 한국어 톤을 사용하세요.")
		}
	} else {
		if formalScore >= casualScore+1 {
			hints = append(hints, "정중하고 배려 있는 표현을 사용하세요.")
		} else {
			hints = append(hints, "가볍고 친근한 표현을 사용하세요.")
		}
	}
	if avgLen > 0 && avgLen <= 30 {
		hints = append(hints, "짧은 문장을 우선하세요.")
	}
	if emojiLike > 0 {
		hints = append(hints, "맥락에 맞으면 이모지는 가볍게만 사용하세요.")
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
