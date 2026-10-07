-- Retain the legacy binary field for existing photos; all new uploads use Cloudinary.
ALTER TABLE "UserProfile" ADD COLUMN "photoPublicId" TEXT, ADD COLUMN "photoFormat" TEXT;
