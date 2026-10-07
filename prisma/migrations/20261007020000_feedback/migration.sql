CREATE TABLE "Feedback" (
  "userId" TEXT NOT NULL,
  "id" TEXT NOT NULL,
  "topic" TEXT NOT NULL,
  "message" TEXT NOT NULL,
  "appVersion" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "Feedback_pkey" PRIMARY KEY ("userId", "id")
);
CREATE INDEX "Feedback_createdAt_idx" ON "Feedback"("createdAt");
ALTER TABLE "Feedback" ADD CONSTRAINT "Feedback_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
