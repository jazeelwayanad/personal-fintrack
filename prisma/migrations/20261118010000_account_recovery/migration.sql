-- AlterTable
ALTER TABLE "User" ADD COLUMN     "sessionVersion" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "AccountToken" (
    "hash" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "newEmail" TEXT,
    "originalEmail" TEXT NOT NULL,
    "sessionVersion" INTEGER NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AccountToken_pkey" PRIMARY KEY ("hash")
);

-- CreateIndex
CREATE INDEX "AccountToken_userId_kind_idx" ON "AccountToken"("userId", "kind");

-- CreateIndex
CREATE INDEX "AccountToken_expiresAt_idx" ON "AccountToken"("expiresAt");

-- AddForeignKey
ALTER TABLE "AccountToken" ADD CONSTRAINT "AccountToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
