CREATE TABLE "UserProfile" (
    "userId" TEXT NOT NULL,
    "phone" TEXT,
    "photo" BYTEA,
    "photoType" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "UserProfile_pkey" PRIMARY KEY ("userId"),
    CONSTRAINT "UserProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
