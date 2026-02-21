-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "public"."AuthProvider" AS ENUM ('apple', 'google', 'phone');

-- CreateEnum
CREATE TYPE "public"."HouseholdRole" AS ENUM ('OWNER', 'PARENT', 'FAMILY_VIEWER', 'CAREGIVER');

-- CreateEnum
CREATE TYPE "public"."MemberStatus" AS ENUM ('ACTIVE', 'INVITED', 'REMOVED');

-- CreateEnum
CREATE TYPE "public"."EventType" AS ENUM ('FORMULA', 'BREASTFEED', 'SLEEP', 'PEE', 'POO', 'GROWTH', 'MEMO', 'SYMPTOM', 'MEDICATION');

-- CreateEnum
CREATE TYPE "public"."EventSource" AS ENUM ('VOICE', 'TEXT', 'MANUAL', 'IMPORT');

-- CreateEnum
CREATE TYPE "public"."VoiceClipStatus" AS ENUM ('PARSED', 'CONFIRMED', 'FAILED');

-- CreateEnum
CREATE TYPE "public"."ReportPeriodType" AS ENUM ('DAILY', 'WEEKLY');

-- CreateEnum
CREATE TYPE "public"."AiTone" AS ENUM ('FRIENDLY', 'NEUTRAL', 'FORMAL', 'BRIEF', 'COACH');

-- CreateEnum
CREATE TYPE "public"."PhotoVisibility" AS ENUM ('HOUSEHOLD', 'BABY_SCOPED');

-- CreateEnum
CREATE TYPE "public"."SubscriptionPlan" AS ENUM ('PHOTO_SHARE', 'AI_ONLY', 'AI_PHOTO');

-- CreateEnum
CREATE TYPE "public"."SubscriptionStatus" AS ENUM ('ACTIVE', 'PAST_DUE', 'CANCELED', 'TRIALING');

-- CreateEnum
CREATE TYPE "public"."ConsentType" AS ENUM ('TERMS', 'PRIVACY', 'DATA_PROCESSING', 'COMMUNITY_UPLOAD', 'AD_TARGETING', 'LOCATION_BASED', 'PHOTO_SHARE');

-- CreateEnum
CREATE TYPE "public"."AiBillingMode" AS ENUM ('PAID', 'GRACE');

-- CreateEnum
CREATE TYPE "public"."CreditGrantType" AS ENUM ('SUBSCRIPTION_MONTHLY');

-- CreateEnum
CREATE TYPE "public"."ChatSessionStatus" AS ENUM ('ACTIVE', 'CLOSED');

-- CreateTable
CREATE TABLE "public"."User" (
    "id" TEXT NOT NULL,
    "provider" "public"."AuthProvider" NOT NULL,
    "providerUid" TEXT,
    "phone" TEXT,
    "name" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Household" (
    "id" TEXT NOT NULL,
    "ownerUserId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Household_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."HouseholdMember" (
    "id" TEXT NOT NULL,
    "householdId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "role" "public"."HouseholdRole" NOT NULL,
    "status" "public"."MemberStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "HouseholdMember_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Baby" (
    "id" TEXT NOT NULL,
    "householdId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "birthDate" TIMESTAMP(3) NOT NULL,
    "sex" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Baby_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Event" (
    "id" TEXT NOT NULL,
    "babyId" TEXT NOT NULL,
    "type" "public"."EventType" NOT NULL,
    "startTime" TIMESTAMP(3) NOT NULL,
    "endTime" TIMESTAMP(3),
    "valueJson" JSONB NOT NULL,
    "metadataJson" JSONB,
    "source" "public"."EventSource" NOT NULL,
    "createdBy" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Event_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."VoiceClip" (
    "id" TEXT NOT NULL,
    "householdId" TEXT NOT NULL,
    "babyId" TEXT NOT NULL,
    "audioUrl" TEXT NOT NULL,
    "transcript" TEXT,
    "parsedEventsJson" JSONB,
    "confidenceJson" JSONB,
    "status" "public"."VoiceClipStatus" NOT NULL DEFAULT 'PARSED',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "VoiceClip_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Report" (
    "id" TEXT NOT NULL,
    "householdId" TEXT NOT NULL,
    "babyId" TEXT NOT NULL,
    "periodType" "public"."ReportPeriodType" NOT NULL,
    "periodStart" TIMESTAMP(3) NOT NULL,
    "periodEnd" TIMESTAMP(3) NOT NULL,
    "metricsJson" JSONB NOT NULL,
    "summaryText" TEXT NOT NULL,
    "modelVersion" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Report_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."PersonaProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "personaJson" JSONB NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PersonaProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."AiToneProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tone" "public"."AiTone" NOT NULL DEFAULT 'NEUTRAL',
    "verbosityLevel" INTEGER NOT NULL DEFAULT 2,
    "safetyStrictness" INTEGER NOT NULL DEFAULT 2,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AiToneProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Album" (
    "id" TEXT NOT NULL,
    "householdId" TEXT NOT NULL,
    "babyId" TEXT,
    "title" TEXT NOT NULL,
    "monthKey" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Album_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."PhotoAsset" (
    "id" TEXT NOT NULL,
    "albumId" TEXT NOT NULL,
    "uploaderUserId" TEXT NOT NULL,
    "variantsJson" JSONB NOT NULL,
    "visibility" "public"."PhotoVisibility" NOT NULL DEFAULT 'HOUSEHOLD',
    "downloadable" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PhotoAsset_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Invite" (
    "id" TEXT NOT NULL,
    "householdId" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "role" "public"."HouseholdRole" NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "invitedBy" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "usedAt" TIMESTAMP(3),

    CONSTRAINT "Invite_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Subscription" (
    "id" TEXT NOT NULL,
    "householdId" TEXT NOT NULL,
    "plan" "public"."SubscriptionPlan" NOT NULL,
    "status" "public"."SubscriptionStatus" NOT NULL DEFAULT 'ACTIVE',
    "renewAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Subscription_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Consent" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" "public"."ConsentType" NOT NULL,
    "granted" BOOLEAN NOT NULL,
    "grantedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Consent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."AuditLog" (
    "id" TEXT NOT NULL,
    "householdId" TEXT NOT NULL,
    "actorUserId" TEXT,
    "action" TEXT NOT NULL,
    "targetType" TEXT NOT NULL,
    "targetId" TEXT,
    "payloadJson" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."UserCreditWallet" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "balanceCredits" INTEGER NOT NULL DEFAULT 0,
    "lifetimeGrantedCredits" INTEGER NOT NULL DEFAULT 0,
    "lifetimeSpentCredits" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "UserCreditWallet_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."AiUsageLog" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "householdId" TEXT NOT NULL,
    "childId" TEXT NOT NULL,
    "model" TEXT NOT NULL,
    "promptTokens" INTEGER NOT NULL,
    "completionTokens" INTEGER NOT NULL,
    "totalTokens" INTEGER NOT NULL,
    "chargedCredits" INTEGER NOT NULL,
    "billingMode" "public"."AiBillingMode" NOT NULL,
    "questionChars" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AiUsageLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."UserCreditGrantLedger" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "householdId" TEXT NOT NULL,
    "subscriptionId" TEXT,
    "grantType" "public"."CreditGrantType" NOT NULL,
    "periodKey" TEXT NOT NULL,
    "credits" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserCreditGrantLedger_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ChatSession" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "householdId" TEXT NOT NULL,
    "childId" TEXT,
    "status" "public"."ChatSessionStatus" NOT NULL DEFAULT 'ACTIVE',
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMP(3),
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "memorySummary" TEXT,
    "memorySummarizedCount" INTEGER NOT NULL DEFAULT 0,
    "memorySummaryUpdatedAt" TIMESTAMP(3),

    CONSTRAINT "ChatSession_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ChatMessage" (
    "id" TEXT NOT NULL,
    "sessionId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "householdId" TEXT NOT NULL,
    "childId" TEXT,
    "role" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "intent" TEXT,
    "contextJson" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ChatMessage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."SleepEvent" (
    "id" TEXT NOT NULL,
    "childId" TEXT NOT NULL,
    "startAt" TIMESTAMP(3) NOT NULL,
    "endAt" TIMESTAMP(3),
    "note" TEXT,
    "endIsEstimated" BOOLEAN NOT NULL DEFAULT false,
    "estimationMethod" TEXT,
    "estimationConfidence" INTEGER,
    "sleepType" TEXT NOT NULL DEFAULT 'unknown',
    "sleepTypeSource" TEXT NOT NULL DEFAULT 'auto',
    "qualityScore" INTEGER,
    "wakeCount" INTEGER,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SleepEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."IntakeEvent" (
    "id" TEXT NOT NULL,
    "childId" TEXT NOT NULL,
    "startAt" TIMESTAMP(3) NOT NULL,
    "endAt" TIMESTAMP(3),
    "note" TEXT,
    "endIsEstimated" BOOLEAN NOT NULL DEFAULT false,
    "estimationMethod" TEXT,
    "estimationConfidence" INTEGER,
    "intakeType" TEXT NOT NULL,
    "amountMl" INTEGER,
    "amountText" TEXT,
    "side" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "IntakeEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."TemperatureEvent" (
    "id" TEXT NOT NULL,
    "childId" TEXT NOT NULL,
    "measuredAt" TIMESTAMP(3) NOT NULL,
    "tempC" DECIMAL(4,1) NOT NULL,
    "method" TEXT NOT NULL DEFAULT 'ear',
    "methodSource" TEXT NOT NULL DEFAULT 'default',
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TemperatureEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."DiaperEvent" (
    "id" TEXT NOT NULL,
    "childId" TEXT NOT NULL,
    "at" TIMESTAMP(3) NOT NULL,
    "pee" BOOLEAN,
    "poo" BOOLEAN,
    "pooType" TEXT,
    "color" TEXT,
    "texture" TEXT,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DiaperEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."MedicationEvent" (
    "id" TEXT NOT NULL,
    "childId" TEXT NOT NULL,
    "at" TIMESTAMP(3) NOT NULL,
    "medName" TEXT NOT NULL,
    "doseText" TEXT,
    "route" TEXT,
    "isPrescribed" BOOLEAN,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MedicationEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."VisitEvent" (
    "id" TEXT NOT NULL,
    "childId" TEXT NOT NULL,
    "at" TIMESTAMP(3) NOT NULL,
    "facilityType" TEXT,
    "reason" TEXT,
    "diagnosisText" TEXT,
    "treatmentText" TEXT,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "VisitEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ActivityEvent" (
    "id" TEXT NOT NULL,
    "childId" TEXT NOT NULL,
    "activityType" TEXT NOT NULL,
    "startAt" TIMESTAMP(3) NOT NULL,
    "endAt" TIMESTAMP(3),
    "durationSec" INTEGER,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ActivityEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."NoteEvent" (
    "id" TEXT NOT NULL,
    "childId" TEXT NOT NULL,
    "at" TIMESTAMP(3) NOT NULL,
    "content" TEXT NOT NULL,
    "tagsJson" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "NoteEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."DailySummary" (
    "id" TEXT NOT NULL,
    "childId" TEXT NOT NULL,
    "date" TIMESTAMP(3) NOT NULL,
    "sleepTotalMin" INTEGER,
    "sleepLongestMin" INTEGER,
    "sleepNightMin" INTEGER,
    "sleepNapMin" INTEGER,
    "intakeCount" INTEGER,
    "formulaTotalMl" INTEGER,
    "intakeTotalMl" INTEGER,
    "diaperPeeCount" INTEGER,
    "diaperPooCount" INTEGER,
    "diarrheaCount" INTEGER,
    "tempMaxC" DECIMAL(4,1),
    "tempMinC" DECIMAL(4,1),
    "activityTotalMin" INTEGER,
    "missingnessJson" JSONB,
    "estimatedFieldsJson" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DailySummary_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."WeeklySummary" (
    "id" TEXT NOT NULL,
    "childId" TEXT NOT NULL,
    "weekStartDate" TIMESTAMP(3) NOT NULL,
    "metricsJson" JSONB,
    "missingnessJson" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "WeeklySummary_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."MonthlyMedicalSummary" (
    "id" TEXT NOT NULL,
    "childId" TEXT NOT NULL,
    "month" TIMESTAMP(3) NOT NULL,
    "medicalTimelineJson" JSONB,
    "missingnessJson" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MonthlyMedicalSummary_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_provider_providerUid_key" ON "public"."User"("provider", "providerUid");

-- CreateIndex
CREATE UNIQUE INDEX "User_phone_key" ON "public"."User"("phone");

-- CreateIndex
CREATE INDEX "Household_ownerUserId_idx" ON "public"."Household"("ownerUserId");

-- CreateIndex
CREATE INDEX "HouseholdMember_householdId_idx" ON "public"."HouseholdMember"("householdId");

-- CreateIndex
CREATE INDEX "HouseholdMember_userId_idx" ON "public"."HouseholdMember"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "HouseholdMember_householdId_userId_key" ON "public"."HouseholdMember"("householdId", "userId");

-- CreateIndex
CREATE INDEX "Baby_householdId_idx" ON "public"."Baby"("householdId");

-- CreateIndex
CREATE INDEX "Event_babyId_startTime_idx" ON "public"."Event"("babyId", "startTime" DESC);

-- CreateIndex
CREATE INDEX "Event_babyId_type_startTime_idx" ON "public"."Event"("babyId", "type", "startTime" DESC);

-- CreateIndex
CREATE INDEX "VoiceClip_householdId_createdAt_idx" ON "public"."VoiceClip"("householdId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "Report_householdId_babyId_periodType_periodStart_idx" ON "public"."Report"("householdId", "babyId", "periodType", "periodStart");

-- CreateIndex
CREATE UNIQUE INDEX "PersonaProfile_userId_key" ON "public"."PersonaProfile"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "AiToneProfile_userId_key" ON "public"."AiToneProfile"("userId");

-- CreateIndex
CREATE INDEX "Album_householdId_monthKey_idx" ON "public"."Album"("householdId", "monthKey");

-- CreateIndex
CREATE INDEX "PhotoAsset_albumId_createdAt_idx" ON "public"."PhotoAsset"("albumId", "createdAt" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "Invite_token_key" ON "public"."Invite"("token");

-- CreateIndex
CREATE INDEX "Invite_householdId_expiresAt_idx" ON "public"."Invite"("householdId", "expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "Subscription_householdId_key" ON "public"."Subscription"("householdId");

-- CreateIndex
CREATE INDEX "Consent_userId_type_idx" ON "public"."Consent"("userId", "type");

-- CreateIndex
CREATE INDEX "AuditLog_householdId_createdAt_idx" ON "public"."AuditLog"("householdId", "createdAt" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "UserCreditWallet_userId_key" ON "public"."UserCreditWallet"("userId");

-- CreateIndex
CREATE INDEX "AiUsageLog_userId_createdAt_idx" ON "public"."AiUsageLog"("userId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "AiUsageLog_householdId_createdAt_idx" ON "public"."AiUsageLog"("householdId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "AiUsageLog_childId_createdAt_idx" ON "public"."AiUsageLog"("childId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "UserCreditGrantLedger_userId_createdAt_idx" ON "public"."UserCreditGrantLedger"("userId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "UserCreditGrantLedger_householdId_createdAt_idx" ON "public"."UserCreditGrantLedger"("householdId", "createdAt" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "UserCreditGrantLedger_userId_householdId_grantType_periodKe_key" ON "public"."UserCreditGrantLedger"("userId", "householdId", "grantType", "periodKey");

-- CreateIndex
CREATE INDEX "ChatSession_userId_startedAt_idx" ON "public"."ChatSession"("userId", "startedAt" DESC);

-- CreateIndex
CREATE INDEX "ChatSession_householdId_startedAt_idx" ON "public"."ChatSession"("householdId", "startedAt" DESC);

-- CreateIndex
CREATE INDEX "ChatSession_childId_startedAt_idx" ON "public"."ChatSession"("childId", "startedAt" DESC);

-- CreateIndex
CREATE INDEX "ChatMessage_sessionId_createdAt_idx" ON "public"."ChatMessage"("sessionId", "createdAt");

-- CreateIndex
CREATE INDEX "ChatMessage_userId_createdAt_idx" ON "public"."ChatMessage"("userId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "SleepEvent_childId_startAt_idx" ON "public"."SleepEvent"("childId", "startAt" DESC);

-- CreateIndex
CREATE INDEX "IntakeEvent_childId_startAt_idx" ON "public"."IntakeEvent"("childId", "startAt" DESC);

-- CreateIndex
CREATE INDEX "TemperatureEvent_childId_measuredAt_idx" ON "public"."TemperatureEvent"("childId", "measuredAt" DESC);

-- CreateIndex
CREATE INDEX "DiaperEvent_childId_at_idx" ON "public"."DiaperEvent"("childId", "at" DESC);

-- CreateIndex
CREATE INDEX "MedicationEvent_childId_at_idx" ON "public"."MedicationEvent"("childId", "at" DESC);

-- CreateIndex
CREATE INDEX "VisitEvent_childId_at_idx" ON "public"."VisitEvent"("childId", "at" DESC);

-- CreateIndex
CREATE INDEX "ActivityEvent_childId_startAt_idx" ON "public"."ActivityEvent"("childId", "startAt" DESC);

-- CreateIndex
CREATE INDEX "NoteEvent_childId_at_idx" ON "public"."NoteEvent"("childId", "at" DESC);

-- CreateIndex
CREATE INDEX "DailySummary_childId_date_idx" ON "public"."DailySummary"("childId", "date" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "DailySummary_childId_date_key" ON "public"."DailySummary"("childId", "date");

-- CreateIndex
CREATE INDEX "WeeklySummary_childId_weekStartDate_idx" ON "public"."WeeklySummary"("childId", "weekStartDate" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "WeeklySummary_childId_weekStartDate_key" ON "public"."WeeklySummary"("childId", "weekStartDate");

-- CreateIndex
CREATE INDEX "MonthlyMedicalSummary_childId_month_idx" ON "public"."MonthlyMedicalSummary"("childId", "month" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "MonthlyMedicalSummary_childId_month_key" ON "public"."MonthlyMedicalSummary"("childId", "month");

-- AddForeignKey
ALTER TABLE "public"."Household" ADD CONSTRAINT "Household_ownerUserId_fkey" FOREIGN KEY ("ownerUserId") REFERENCES "public"."User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."HouseholdMember" ADD CONSTRAINT "HouseholdMember_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "public"."Household"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."HouseholdMember" ADD CONSTRAINT "HouseholdMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Baby" ADD CONSTRAINT "Baby_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "public"."Household"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Event" ADD CONSTRAINT "Event_babyId_fkey" FOREIGN KEY ("babyId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Event" ADD CONSTRAINT "Event_createdBy_fkey" FOREIGN KEY ("createdBy") REFERENCES "public"."User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."VoiceClip" ADD CONSTRAINT "VoiceClip_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "public"."Household"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."VoiceClip" ADD CONSTRAINT "VoiceClip_babyId_fkey" FOREIGN KEY ("babyId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Report" ADD CONSTRAINT "Report_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "public"."Household"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Report" ADD CONSTRAINT "Report_babyId_fkey" FOREIGN KEY ("babyId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."PersonaProfile" ADD CONSTRAINT "PersonaProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."AiToneProfile" ADD CONSTRAINT "AiToneProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Album" ADD CONSTRAINT "Album_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "public"."Household"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Album" ADD CONSTRAINT "Album_babyId_fkey" FOREIGN KEY ("babyId") REFERENCES "public"."Baby"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."PhotoAsset" ADD CONSTRAINT "PhotoAsset_albumId_fkey" FOREIGN KEY ("albumId") REFERENCES "public"."Album"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."PhotoAsset" ADD CONSTRAINT "PhotoAsset_uploaderUserId_fkey" FOREIGN KEY ("uploaderUserId") REFERENCES "public"."User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Invite" ADD CONSTRAINT "Invite_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "public"."Household"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Invite" ADD CONSTRAINT "Invite_invitedBy_fkey" FOREIGN KEY ("invitedBy") REFERENCES "public"."User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Subscription" ADD CONSTRAINT "Subscription_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "public"."Household"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Consent" ADD CONSTRAINT "Consent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."AuditLog" ADD CONSTRAINT "AuditLog_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "public"."Household"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."AuditLog" ADD CONSTRAINT "AuditLog_actorUserId_fkey" FOREIGN KEY ("actorUserId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."UserCreditWallet" ADD CONSTRAINT "UserCreditWallet_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."AiUsageLog" ADD CONSTRAINT "AiUsageLog_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."AiUsageLog" ADD CONSTRAINT "AiUsageLog_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "public"."Household"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."AiUsageLog" ADD CONSTRAINT "AiUsageLog_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."UserCreditGrantLedger" ADD CONSTRAINT "UserCreditGrantLedger_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."UserCreditGrantLedger" ADD CONSTRAINT "UserCreditGrantLedger_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "public"."Household"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."UserCreditGrantLedger" ADD CONSTRAINT "UserCreditGrantLedger_subscriptionId_fkey" FOREIGN KEY ("subscriptionId") REFERENCES "public"."Subscription"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ChatSession" ADD CONSTRAINT "ChatSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ChatSession" ADD CONSTRAINT "ChatSession_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "public"."Household"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ChatSession" ADD CONSTRAINT "ChatSession_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ChatMessage" ADD CONSTRAINT "ChatMessage_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "public"."ChatSession"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ChatMessage" ADD CONSTRAINT "ChatMessage_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ChatMessage" ADD CONSTRAINT "ChatMessage_householdId_fkey" FOREIGN KEY ("householdId") REFERENCES "public"."Household"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ChatMessage" ADD CONSTRAINT "ChatMessage_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."SleepEvent" ADD CONSTRAINT "SleepEvent_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."IntakeEvent" ADD CONSTRAINT "IntakeEvent_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."TemperatureEvent" ADD CONSTRAINT "TemperatureEvent_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DiaperEvent" ADD CONSTRAINT "DiaperEvent_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."MedicationEvent" ADD CONSTRAINT "MedicationEvent_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."VisitEvent" ADD CONSTRAINT "VisitEvent_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ActivityEvent" ADD CONSTRAINT "ActivityEvent_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."NoteEvent" ADD CONSTRAINT "NoteEvent_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DailySummary" ADD CONSTRAINT "DailySummary_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."WeeklySummary" ADD CONSTRAINT "WeeklySummary_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."MonthlyMedicalSummary" ADD CONSTRAINT "MonthlyMedicalSummary_childId_fkey" FOREIGN KEY ("childId") REFERENCES "public"."Baby"("id") ON DELETE CASCADE ON UPDATE CASCADE;

