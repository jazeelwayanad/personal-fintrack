-- CreateTable
CREATE TABLE "McpIdentity" (
    "issuer" TEXT NOT NULL,
    "subject" TEXT NOT NULL,
    "userId" TEXT NOT NULL,

    CONSTRAINT "McpIdentity_pkey" PRIMARY KEY ("issuer","subject")
);

-- CreateTable
CREATE TABLE "McpGrant" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "issuer" TEXT NOT NULL,
    "subject" TEXT NOT NULL,
    "clientId" TEXT NOT NULL,
    "scopes" TEXT[],
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "McpGrant_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "McpAuditEvent" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "grantId" TEXT NOT NULL,
    "clientId" TEXT NOT NULL,
    "operation" TEXT NOT NULL,
    "objectId" TEXT,
    "outcome" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "McpAuditEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UpiPaymentAttempt" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "createKey" TEXT NOT NULL,
    "requestHash" TEXT NOT NULL,
    "payeeVpa" TEXT NOT NULL,
    "payeeName" TEXT,
    "amountMode" TEXT NOT NULL,
    "amountPaise" BIGINT NOT NULL,
    "categoryId" TEXT NOT NULL,
    "purpose" TEXT NOT NULL,
    "reference" TEXT,
    "occurrenceId" TEXT,
    "status" TEXT NOT NULL DEFAULT 'ready',
    "reportedOutcome" TEXT,
    "evidenceStatus" TEXT NOT NULL DEFAULT 'unverified',
    "ledgerId" TEXT,
    "recordedLedgerRevision" INTEGER,
    "revision" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "UpiPaymentAttempt_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UpiPaymentEvidence" (
    "id" TEXT NOT NULL,
    "attemptId" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "requestKey" TEXT NOT NULL,
    "requestHash" TEXT NOT NULL,
    "result" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UpiPaymentEvidence_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "McpIdentity_userId_issuer_key" ON "McpIdentity"("userId", "issuer");

-- CreateIndex
CREATE INDEX "McpGrant_issuer_subject_clientId_revokedAt_idx" ON "McpGrant"("issuer", "subject", "clientId", "revokedAt");

-- CreateIndex
CREATE INDEX "McpGrant_userId_idx" ON "McpGrant"("userId");

-- CreateIndex
CREATE INDEX "McpAuditEvent_userId_createdAt_idx" ON "McpAuditEvent"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "UpiPaymentAttempt_userId_createdAt_id_idx" ON "UpiPaymentAttempt"("userId", "createdAt", "id");

-- CreateIndex
CREATE UNIQUE INDEX "UpiPaymentAttempt_userId_createKey_key" ON "UpiPaymentAttempt"("userId", "createKey");

-- CreateIndex
CREATE UNIQUE INDEX "UpiPaymentAttempt_userId_ledgerId_key" ON "UpiPaymentAttempt"("userId", "ledgerId");

-- CreateIndex
CREATE UNIQUE INDEX "UpiPaymentEvidence_attemptId_source_requestKey_key" ON "UpiPaymentEvidence"("attemptId", "source", "requestKey");

-- CreateIndex
CREATE INDEX "AuthAttempt_expiresAt_idx" ON "AuthAttempt"("expiresAt");

-- AddForeignKey
ALTER TABLE "McpIdentity" ADD CONSTRAINT "McpIdentity_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "McpGrant" ADD CONSTRAINT "McpGrant_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "McpAuditEvent" ADD CONSTRAINT "McpAuditEvent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UpiPaymentAttempt" ADD CONSTRAINT "UpiPaymentAttempt_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UpiPaymentEvidence" ADD CONSTRAINT "UpiPaymentEvidence_attemptId_fkey" FOREIGN KEY ("attemptId") REFERENCES "UpiPaymentAttempt"("id") ON DELETE CASCADE ON UPDATE CASCADE;
