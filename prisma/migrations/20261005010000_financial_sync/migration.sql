-- AlterTable
ALTER TABLE "User" ADD COLUMN     "syncImported" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "syncRevision" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "FinancialRecord" (
    "userId" TEXT NOT NULL,
    "id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "data" JSONB NOT NULL,
    "revision" INTEGER NOT NULL,
    "deleted" BOOLEAN NOT NULL DEFAULT false,
    "occurrenceKey" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FinancialRecord_pkey" PRIMARY KEY ("userId","id")
);

-- CreateTable
CREATE TABLE "SyncMutation" (
    "userId" TEXT NOT NULL,
    "id" TEXT NOT NULL,
    "result" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SyncMutation_pkey" PRIMARY KEY ("userId","id")
);

-- CreateTable
CREATE TABLE "MobileSession" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "refreshHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MobileSession_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "NotificationDevice" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "token" TEXT,
    "subscription" JSONB,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "NotificationDevice_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "NotificationDelivery" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "deviceId" TEXT NOT NULL,
    "date" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "lastError" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "NotificationDelivery_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuthAttempt" (
    "key" TEXT NOT NULL,
    "count" INTEGER NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AuthAttempt_pkey" PRIMARY KEY ("key")
);

-- CreateIndex
CREATE INDEX "FinancialRecord_userId_revision_idx" ON "FinancialRecord"("userId", "revision");

-- CreateIndex
CREATE UNIQUE INDEX "FinancialRecord_userId_occurrenceKey_key" ON "FinancialRecord"("userId", "occurrenceKey");

-- CreateIndex
CREATE UNIQUE INDEX "MobileSession_refreshHash_key" ON "MobileSession"("refreshHash");

-- CreateIndex
CREATE UNIQUE INDEX "NotificationDevice_token_key" ON "NotificationDevice"("token");

-- CreateIndex
CREATE INDEX "NotificationDevice_userId_idx" ON "NotificationDevice"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "NotificationDelivery_deviceId_date_key" ON "NotificationDelivery"("deviceId", "date");

-- AddForeignKey
ALTER TABLE "FinancialRecord" ADD CONSTRAINT "FinancialRecord_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SyncMutation" ADD CONSTRAINT "SyncMutation_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MobileSession" ADD CONSTRAINT "MobileSession_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "NotificationDevice" ADD CONSTRAINT "NotificationDevice_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "NotificationDelivery" ADD CONSTRAINT "NotificationDelivery_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
