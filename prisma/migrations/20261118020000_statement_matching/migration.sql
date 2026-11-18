-- AlterTable
ALTER TABLE "UpiPaymentAttempt" ADD COLUMN     "referenceMatchKey" TEXT;

-- AlterTable
ALTER TABLE "UpiPaymentEvidence" ADD COLUMN     "statementKey" TEXT,
ADD COLUMN     "statementOwnerId" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "UpiPaymentEvidence_statementOwnerId_statementKey_key" ON "UpiPaymentEvidence"("statementOwnerId", "statementKey");
