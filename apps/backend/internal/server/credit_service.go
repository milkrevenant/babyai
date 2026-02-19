package server

import (
	"context"
	"errors"
	"math"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const (
	graceLimitPerDay = 3
	reserveCredits   = 2
)

type billingMode string

const (
	billingModePaid  billingMode = "paid"
	billingModeGrace billingMode = "grace"
)

type preflightResult struct {
	Mode          billingMode
	Reserved      int
	Plan          *string
	BalanceBefore int
	GraceUsed     int
}

type billingResult struct {
	Charged      int
	BalanceAfter int
	BillingMode  billingMode
	GraceUsed    int
	GraceLimit   int
	Plan         *string
}

func creditsForPlan(plan string) int {
	switch strings.ToUpper(strings.TrimSpace(plan)) {
	case "AI_ONLY":
		return 300
	case "AI_PHOTO":
		return 500
	default:
		return 0
	}
}

func (a *App) ensureUserWallet(ctx context.Context, q dbQuerier, userID string) error {
	_, err := q.Exec(
		ctx,
		`INSERT INTO "UserCreditWallet" (id, "userId", "balanceCredits", "lifetimeGrantedCredits", "lifetimeSpentCredits", "createdAt", "updatedAt")
		 VALUES ($1, $2, 0, 0, 0, NOW(), NOW())
		 ON CONFLICT ("userId") DO NOTHING`,
		uuid.NewString(),
		userID,
	)
	return err
}

func (a *App) ensureMonthlyGrant(ctx context.Context, q dbQuerier, userID, householdID string, now time.Time) (*string, error) {
	if forcedPlan, forcedStatus, ok := a.localForcedSubscription(); ok {
		if isEnabledSubscriptionStatus(forcedStatus) && creditsForPlan(forcedPlan) > 0 {
			plan := forcedPlan
			return &plan, nil
		}
		return nil, nil
	}

	var subscriptionID, plan, status string
	err := q.QueryRow(
		ctx,
		`SELECT id, plan::text, status::text FROM "Subscription" WHERE "householdId" = $1 LIMIT 1`,
		householdID,
	).Scan(&subscriptionID, &plan, &status)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	planValue := strings.ToUpper(strings.TrimSpace(plan))
	statusValue := strings.ToUpper(strings.TrimSpace(status))
	planPtr := &planValue

	if statusValue != "ACTIVE" && statusValue != "TRIALING" {
		return planPtr, nil
	}
	credits := creditsForPlan(planValue)
	if credits <= 0 {
		return planPtr, nil
	}
	periodKey := now.UTC().Format("2006-01")

	var insertedID string
	insertErr := q.QueryRow(
		ctx,
		`INSERT INTO "UserCreditGrantLedger" (id, "userId", "householdId", "subscriptionId", "grantType", "periodKey", credits, "createdAt")
		 VALUES ($1, $2, $3, $4, 'SUBSCRIPTION_MONTHLY', $5, $6, NOW())
		 ON CONFLICT ("userId", "householdId", "grantType", "periodKey")
		 DO NOTHING
		 RETURNING id`,
		uuid.NewString(),
		userID,
		householdID,
		subscriptionID,
		periodKey,
		credits,
	).Scan(&insertedID)
	if insertErr != nil && !errors.Is(insertErr, pgx.ErrNoRows) {
		return nil, insertErr
	}
	if insertedID == "" {
		return planPtr, nil
	}

	if err := a.ensureUserWallet(ctx, q, userID); err != nil {
		return nil, err
	}
	_, err = q.Exec(
		ctx,
		`UPDATE "UserCreditWallet"
		 SET "balanceCredits" = "balanceCredits" + $2,
		     "lifetimeGrantedCredits" = "lifetimeGrantedCredits" + $2,
		     "updatedAt" = NOW()
		 WHERE "userId" = $1`,
		userID,
		credits,
	)
	if err != nil {
		return nil, err
	}
	return planPtr, nil
}

func (a *App) countGraceUsedToday(ctx context.Context, q dbQuerier, userID string, now time.Time) (int, error) {
	start := startOfUTCDay(now.UTC())
	end := start.Add(24 * time.Hour)
	var count int
	err := q.QueryRow(
		ctx,
		`SELECT COUNT(*)::int
		 FROM "AiUsageLog"
		 WHERE "userId" = $1
		   AND "billingMode" = 'GRACE'
		   AND "createdAt" >= $2
		   AND "createdAt" < $3`,
		userID,
		start,
		end,
	).Scan(&count)
	return count, err
}

func (a *App) getWalletBalance(ctx context.Context, q dbQuerier, userID string) (int, error) {
	if err := a.ensureUserWallet(ctx, q, userID); err != nil {
		return 0, err
	}
	var balance int
	err := q.QueryRow(
		ctx,
		`SELECT "balanceCredits" FROM "UserCreditWallet" WHERE "userId" = $1`,
		userID,
	).Scan(&balance)
	return balance, err
}

func (a *App) preflightBilling(ctx context.Context, userID, householdID string, now time.Time) (preflightResult, error) {
	if forcedPlan, forcedStatus, ok := a.localForcedSubscription(); ok {
		if isEnabledSubscriptionStatus(forcedStatus) && planSupportsFeature(forcedPlan, subscriptionFeatureAI) {
			plan := forcedPlan
			return preflightResult{
				Mode:          billingModeGrace,
				Reserved:      0,
				Plan:          &plan,
				BalanceBefore: 0,
				GraceUsed:     0,
			}, nil
		}
	}

	tx, err := a.db.Begin(ctx)
	if err != nil {
		return preflightResult{}, err
	}
	defer tx.Rollback(ctx)

	plan, err := a.ensureMonthlyGrant(ctx, tx, userID, householdID, now)
	if err != nil {
		return preflightResult{}, err
	}
	if err := a.ensureUserWallet(ctx, tx, userID); err != nil {
		return preflightResult{}, err
	}

	var balance int
	err = tx.QueryRow(
		ctx,
		`SELECT "balanceCredits" FROM "UserCreditWallet" WHERE "userId" = $1 FOR UPDATE`,
		userID,
	).Scan(&balance)
	if err != nil {
		return preflightResult{}, err
	}

	graceUsed, err := a.countGraceUsedToday(ctx, tx, userID, now)
	if err != nil {
		return preflightResult{}, err
	}

	result := preflightResult{
		Plan:          plan,
		BalanceBefore: balance,
		GraceUsed:     graceUsed,
	}
	if balance >= reserveCredits {
		if _, err := tx.Exec(
			ctx,
			`UPDATE "UserCreditWallet" SET "balanceCredits" = "balanceCredits" - $2, "updatedAt" = NOW() WHERE "userId" = $1`,
			userID,
			reserveCredits,
		); err != nil {
			return preflightResult{}, err
		}
		result.Mode = billingModePaid
		result.Reserved = reserveCredits
	} else if graceUsed < graceLimitPerDay {
		result.Mode = billingModeGrace
		result.Reserved = 0
	} else {
		result.Mode = ""
		result.Reserved = 0
	}

	if err := tx.Commit(ctx); err != nil {
		return preflightResult{}, err
	}
	return result, nil
}

func creditsFromTokens(totalTokens int) int {
	if totalTokens <= 0 {
		return 0
	}
	return int(math.Ceil(float64(totalTokens) / 1000.0))
}

func (a *App) releaseReservedCredits(ctx context.Context, userID string, reserved int) error {
	if reserved <= 0 {
		return nil
	}
	_, err := a.db.Exec(
		ctx,
		`UPDATE "UserCreditWallet"
		 SET "balanceCredits" = "balanceCredits" + $2,
		     "updatedAt" = NOW()
		 WHERE "userId" = $1`,
		userID,
		reserved,
	)
	return err
}

func (a *App) finalizeBillingAndLog(
	ctx context.Context,
	userID, householdID, childID, question, model string,
	usage AIUsage,
	preflight preflightResult,
	now time.Time,
) (billingResult, error) {
	tx, err := a.db.Begin(ctx)
	if err != nil {
		return billingResult{}, err
	}
	defer tx.Rollback(ctx)

	charged := 0
	if preflight.Mode == billingModePaid {
		charged = creditsFromTokens(usage.TotalTokens)
		delta := preflight.Reserved - charged
		if delta != 0 {
			_, err := tx.Exec(
				ctx,
				`UPDATE "UserCreditWallet"
				 SET "balanceCredits" = "balanceCredits" + $2,
				     "updatedAt" = NOW()
				 WHERE "userId" = $1`,
				userID,
				delta,
			)
			if err != nil {
				return billingResult{}, err
			}
		}
		_, err = tx.Exec(
			ctx,
			`UPDATE "UserCreditWallet"
			 SET "lifetimeSpentCredits" = "lifetimeSpentCredits" + $2,
			     "updatedAt" = NOW()
			 WHERE "userId" = $1`,
			userID,
			charged,
		)
		if err != nil {
			return billingResult{}, err
		}
	}

	questionChars := len([]rune(strings.TrimSpace(question)))
	_, err = tx.Exec(
		ctx,
		`INSERT INTO "AiUsageLog" (
			id, "userId", "householdId", "childId", model,
			"promptTokens", "completionTokens", "totalTokens",
			"chargedCredits", "billingMode", "questionChars", "createdAt"
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::"AiBillingMode", $11, NOW())`,
		uuid.NewString(),
		userID,
		householdID,
		childID,
		model,
		usage.PromptTokens,
		usage.CompletionTokens,
		usage.TotalTokens,
		charged,
		strings.ToUpper(string(preflight.Mode)),
		questionChars,
	)
	if err != nil {
		return billingResult{}, err
	}

	balanceAfter, err := a.getWalletBalance(ctx, tx, userID)
	if err != nil {
		return billingResult{}, err
	}
	graceUsed, err := a.countGraceUsedToday(ctx, tx, userID, now)
	if err != nil {
		return billingResult{}, err
	}

	if err := tx.Commit(ctx); err != nil {
		return billingResult{}, err
	}
	return billingResult{
		Charged:      charged,
		BalanceAfter: balanceAfter,
		BillingMode:  preflight.Mode,
		GraceUsed:    graceUsed,
		GraceLimit:   graceLimitPerDay,
		Plan:         preflight.Plan,
	}, nil
}
