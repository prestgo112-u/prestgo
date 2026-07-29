-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "public"."DisputeStatus" AS ENUM ('open', 'in_review', 'waiting_client', 'waiting_provider', 'resolved', 'rejected', 'closed');

-- CreateEnum
CREATE TYPE "public"."DocumentStatus" AS ENUM ('pending', 'approved', 'rejected');

-- CreateEnum
CREATE TYPE "public"."FileVisibility" AS ENUM ('public', 'authenticated', 'restricted', 'sensitive');

-- CreateEnum
CREATE TYPE "public"."MissionStatus" AS ENUM ('draft', 'pending_provider', 'confirmed', 'in_progress', 'completed', 'closed', 'cancelled', 'disputed');

-- CreateEnum
CREATE TYPE "public"."ProviderValidationStatus" AS ENUM ('profile_incomplete', 'pending_review', 'approved', 'changes_requested', 'rejected', 'suspended');

-- CreateEnum
CREATE TYPE "public"."ReportStatus" AS ENUM ('pending', 'reviewed', 'dismissed');

-- CreateEnum
CREATE TYPE "public"."RescheduleStatus" AS ENUM ('requested', 'accepted', 'rejected', 'applied');

-- CreateEnum
CREATE TYPE "public"."ReviewStatus" AS ENUM ('published', 'reported', 'hidden', 'rejected');

-- CreateEnum
CREATE TYPE "public"."UserStatus" AS ENUM ('draft', 'pending', 'active', 'rejected', 'suspended', 'deleted');

-- CreateTable
CREATE TABLE "public"."Address" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "label" TEXT,
    "city" TEXT,
    "commune" TEXT,
    "details" TEXT,
    "latitude" DOUBLE PRECISION,
    "longitude" DOUBLE PRECISION,
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Address_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."AdminProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "jobTitle" TEXT,
    "department" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AdminProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."AuditLog" (
    "id" TEXT NOT NULL,
    "actorId" TEXT,
    "action" TEXT NOT NULL,
    "entity" TEXT NOT NULL,
    "entityId" TEXT,
    "oldValue" JSONB,
    "newValue" JSONB,
    "ip" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."CatalogCategory" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "description" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "displayOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "iconFileId" TEXT,

    CONSTRAINT "CatalogCategory_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ChatMessage" (
    "id" TEXT NOT NULL,
    "threadId" TEXT NOT NULL,
    "senderId" TEXT,
    "message" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "readAt" TIMESTAMP(3),

    CONSTRAINT "ChatMessage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ChatMessageFile" (
    "messageId" TEXT NOT NULL,
    "fileId" TEXT NOT NULL,

    CONSTRAINT "ChatMessageFile_pkey" PRIMARY KEY ("messageId","fileId")
);

-- CreateTable
CREATE TABLE "public"."ChatThread" (
    "id" TEXT NOT NULL,
    "missionId" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'open',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ChatThread_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."City" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL DEFAULT 'CI',
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "City_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ClientProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "avatarFileId" TEXT,
    "defaultAddressId" TEXT,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ClientProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Dispute" (
    "id" TEXT NOT NULL,
    "missionId" TEXT NOT NULL,
    "openedBy" TEXT,
    "reason" TEXT NOT NULL,
    "description" TEXT,
    "status" "public"."DisputeStatus" NOT NULL DEFAULT 'open',
    "assignedTo" TEXT,
    "decision" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Dispute_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."DisputeFile" (
    "disputeId" TEXT NOT NULL,
    "fileId" TEXT NOT NULL,

    CONSTRAINT "DisputeFile_pkey" PRIMARY KEY ("disputeId","fileId")
);

-- CreateTable
CREATE TABLE "public"."DisputeMessage" (
    "id" TEXT NOT NULL,
    "disputeId" TEXT NOT NULL,
    "senderId" TEXT,
    "message" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "internalOnly" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "DisputeMessage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ExportJob" (
    "id" TEXT NOT NULL,
    "requestedBy" TEXT,
    "type" TEXT NOT NULL,
    "filters" JSONB,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "fileId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),

    CONSTRAINT "ExportJob_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."File" (
    "id" TEXT NOT NULL,
    "ownerId" TEXT,
    "originalName" TEXT NOT NULL,
    "mimeType" TEXT NOT NULL,
    "size" INTEGER NOT NULL,
    "storageKey" TEXT NOT NULL,
    "visibility" "public"."FileVisibility" NOT NULL DEFAULT 'restricted',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "disabledAt" TIMESTAMP(3),

    CONSTRAINT "File_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Mission" (
    "id" TEXT NOT NULL,
    "clientId" TEXT NOT NULL,
    "providerId" TEXT,
    "scheduledAt" TIMESTAMP(3),
    "status" "public"."MissionStatus" NOT NULL DEFAULT 'draft',
    "instructions" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "addressId" TEXT,
    "packId" TEXT,

    CONSTRAINT "Mission_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."MissionCancellation" (
    "id" TEXT NOT NULL,
    "missionId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "cancelledBy" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "details" TEXT,

    CONSTRAINT "MissionCancellation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."MissionReschedule" (
    "id" TEXT NOT NULL,
    "missionId" TEXT NOT NULL,
    "oldScheduledAt" TIMESTAMP(3),
    "newScheduledAt" TIMESTAMP(3) NOT NULL,
    "reason" TEXT,
    "createdBy" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "status" "public"."RescheduleStatus" NOT NULL DEFAULT 'applied',

    CONSTRAINT "MissionReschedule_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."MissionStatusHistory" (
    "id" TEXT NOT NULL,
    "missionId" TEXT NOT NULL,
    "oldStatus" "public"."MissionStatus",
    "newStatus" "public"."MissionStatus" NOT NULL,
    "changedBy" TEXT,
    "reason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MissionStatusHistory_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Notification" (
    "id" TEXT NOT NULL,
    "userId" TEXT,
    "type" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "channel" TEXT NOT NULL DEFAULT 'in_app',
    "status" TEXT NOT NULL DEFAULT 'queued',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "sentAt" TIMESTAMP(3),

    CONSTRAINT "Notification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."NotificationTemplate" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "titleTemplate" TEXT NOT NULL,
    "bodyTemplate" TEXT NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "NotificationTemplate_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."OtpCode" (
    "id" TEXT NOT NULL,
    "target" TEXT NOT NULL,
    "purpose" TEXT NOT NULL DEFAULT 'phone_verification',
    "codeHash" TEXT NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "usedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OtpCode_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."PasswordResetToken" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "usedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PasswordResetToken_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Permission" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "module" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "description" TEXT,

    CONSTRAINT "Permission_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ProviderAvailability" (
    "id" TEXT NOT NULL,
    "providerId" TEXT NOT NULL,
    "weekday" INTEGER NOT NULL,
    "startTime" TEXT NOT NULL,
    "endTime" TEXT NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProviderAvailability_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ProviderDocument" (
    "id" TEXT NOT NULL,
    "providerId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "fileId" TEXT,
    "status" "public"."DocumentStatus" NOT NULL DEFAULT 'pending',
    "rejectionReason" TEXT,
    "reviewedBy" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProviderDocument_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ProviderInternalNote" (
    "id" TEXT NOT NULL,
    "providerId" TEXT NOT NULL,
    "authorId" TEXT,
    "note" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProviderInternalNote_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ProviderPortfolioItem" (
    "id" TEXT NOT NULL,
    "providerId" TEXT NOT NULL,
    "fileId" TEXT NOT NULL,
    "title" TEXT,
    "description" TEXT,
    "displayOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProviderPortfolioItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ProviderProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "publicName" TEXT NOT NULL,
    "bio" TEXT,
    "experienceYears" INTEGER,
    "validationStatus" "public"."ProviderValidationStatus" NOT NULL DEFAULT 'profile_incomplete',
    "availabilityStatus" TEXT NOT NULL DEFAULT 'unavailable',
    "score" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ProviderProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ProviderService" (
    "id" TEXT NOT NULL,
    "providerId" TEXT NOT NULL,
    "serviceTypeId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProviderService_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ProviderUnavailability" (
    "id" TEXT NOT NULL,
    "providerId" TEXT NOT NULL,
    "startAt" TIMESTAMP(3) NOT NULL,
    "endAt" TIMESTAMP(3) NOT NULL,
    "reason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProviderUnavailability_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ProviderZone" (
    "providerId" TEXT NOT NULL,
    "zoneId" TEXT NOT NULL,

    CONSTRAINT "ProviderZone_pkey" PRIMARY KEY ("providerId","zoneId")
);

-- CreateTable
CREATE TABLE "public"."Review" (
    "id" TEXT NOT NULL,
    "missionId" TEXT NOT NULL,
    "authorId" TEXT,
    "targetId" TEXT,
    "rating" INTEGER NOT NULL,
    "comment" TEXT,
    "status" "public"."ReviewStatus" NOT NULL DEFAULT 'published',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Review_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ReviewReport" (
    "id" TEXT NOT NULL,
    "reviewId" TEXT NOT NULL,
    "reportedBy" TEXT,
    "reason" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "status" "public"."ReportStatus" NOT NULL DEFAULT 'pending',

    CONSTRAINT "ReviewReport_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."Role" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "isSystem" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Role_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."RolePermission" (
    "roleId" TEXT NOT NULL,
    "permissionId" TEXT NOT NULL,

    CONSTRAINT "RolePermission_pkey" PRIMARY KEY ("roleId","permissionId")
);

-- CreateTable
CREATE TABLE "public"."ServicePack" (
    "id" TEXT NOT NULL,
    "providerServiceId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "price" DOUBLE PRECISION NOT NULL,
    "durationMinutes" INTEGER NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ServicePack_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ServicePackOption" (
    "id" TEXT NOT NULL,
    "packId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "price" DOUBLE PRECISION NOT NULL,
    "durationMinutes" INTEGER NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ServicePackOption_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."ServiceType" (
    "id" TEXT NOT NULL,
    "categoryId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "description" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ServiceType_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."SystemSetting" (
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "type" TEXT NOT NULL DEFAULT 'string',
    "description" TEXT,
    "updatedBy" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SystemSetting_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "public"."User" (
    "id" TEXT NOT NULL,
    "firstName" TEXT,
    "lastName" TEXT,
    "phone" TEXT,
    "email" TEXT,
    "passwordHash" TEXT NOT NULL,
    "status" "public"."UserStatus" NOT NULL DEFAULT 'draft',
    "phoneVerifiedAt" TIMESTAMP(3),
    "emailVerifiedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."UserRole" (
    "userId" TEXT NOT NULL,
    "roleId" TEXT NOT NULL,

    CONSTRAINT "UserRole_pkey" PRIMARY KEY ("userId","roleId")
);

-- CreateTable
CREATE TABLE "public"."Zone" (
    "id" TEXT NOT NULL,
    "cityId" TEXT,
    "name" TEXT NOT NULL,
    "latitude" DOUBLE PRECISION,
    "longitude" DOUBLE PRECISION,
    "radiusKm" DOUBLE PRECISION,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Zone_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Address_userId_idx" ON "public"."Address"("userId" ASC);

-- CreateIndex
CREATE INDEX "AdminProfile_isActive_idx" ON "public"."AdminProfile"("isActive" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "AdminProfile_userId_key" ON "public"."AdminProfile"("userId" ASC);

-- CreateIndex
CREATE INDEX "AuditLog_actorId_idx" ON "public"."AuditLog"("actorId" ASC);

-- CreateIndex
CREATE INDEX "AuditLog_createdAt_idx" ON "public"."AuditLog"("createdAt" ASC);

-- CreateIndex
CREATE INDEX "AuditLog_entity_entityId_idx" ON "public"."AuditLog"("entity" ASC, "entityId" ASC);

-- CreateIndex
CREATE INDEX "CatalogCategory_active_idx" ON "public"."CatalogCategory"("active" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "CatalogCategory_slug_key" ON "public"."CatalogCategory"("slug" ASC);

-- CreateIndex
CREATE INDEX "ChatMessage_createdAt_idx" ON "public"."ChatMessage"("createdAt" ASC);

-- CreateIndex
CREATE INDEX "ChatMessage_threadId_idx" ON "public"."ChatMessage"("threadId" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "ChatThread_missionId_key" ON "public"."ChatThread"("missionId" ASC);

-- CreateIndex
CREATE INDEX "City_active_idx" ON "public"."City"("active" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "City_slug_key" ON "public"."City"("slug" ASC);

-- CreateIndex
CREATE INDEX "ClientProfile_avatarFileId_idx" ON "public"."ClientProfile"("avatarFileId" ASC);

-- CreateIndex
CREATE INDEX "ClientProfile_defaultAddressId_idx" ON "public"."ClientProfile"("defaultAddressId" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "ClientProfile_userId_key" ON "public"."ClientProfile"("userId" ASC);

-- CreateIndex
CREATE INDEX "Dispute_assignedTo_idx" ON "public"."Dispute"("assignedTo" ASC);

-- CreateIndex
CREATE INDEX "Dispute_missionId_idx" ON "public"."Dispute"("missionId" ASC);

-- CreateIndex
CREATE INDEX "Dispute_status_idx" ON "public"."Dispute"("status" ASC);

-- CreateIndex
CREATE INDEX "DisputeMessage_disputeId_idx" ON "public"."DisputeMessage"("disputeId" ASC);

-- CreateIndex
CREATE INDEX "DisputeMessage_internalOnly_idx" ON "public"."DisputeMessage"("internalOnly" ASC);

-- CreateIndex
CREATE INDEX "ExportJob_requestedBy_idx" ON "public"."ExportJob"("requestedBy" ASC);

-- CreateIndex
CREATE INDEX "ExportJob_status_idx" ON "public"."ExportJob"("status" ASC);

-- CreateIndex
CREATE INDEX "File_ownerId_idx" ON "public"."File"("ownerId" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "File_storageKey_key" ON "public"."File"("storageKey" ASC);

-- CreateIndex
CREATE INDEX "File_visibility_idx" ON "public"."File"("visibility" ASC);

-- CreateIndex
CREATE INDEX "Mission_addressId_idx" ON "public"."Mission"("addressId" ASC);

-- CreateIndex
CREATE INDEX "Mission_clientId_idx" ON "public"."Mission"("clientId" ASC);

-- CreateIndex
CREATE INDEX "Mission_packId_idx" ON "public"."Mission"("packId" ASC);

-- CreateIndex
CREATE INDEX "Mission_providerId_idx" ON "public"."Mission"("providerId" ASC);

-- CreateIndex
CREATE INDEX "Mission_scheduledAt_idx" ON "public"."Mission"("scheduledAt" ASC);

-- CreateIndex
CREATE INDEX "Mission_status_idx" ON "public"."Mission"("status" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "MissionCancellation_missionId_key" ON "public"."MissionCancellation"("missionId" ASC);

-- CreateIndex
CREATE INDEX "MissionReschedule_missionId_idx" ON "public"."MissionReschedule"("missionId" ASC);

-- CreateIndex
CREATE INDEX "MissionStatusHistory_missionId_idx" ON "public"."MissionStatusHistory"("missionId" ASC);

-- CreateIndex
CREATE INDEX "Notification_status_idx" ON "public"."Notification"("status" ASC);

-- CreateIndex
CREATE INDEX "Notification_userId_idx" ON "public"."Notification"("userId" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "NotificationTemplate_code_key" ON "public"."NotificationTemplate"("code" ASC);

-- CreateIndex
CREATE INDEX "OtpCode_expiresAt_idx" ON "public"."OtpCode"("expiresAt" ASC);

-- CreateIndex
CREATE INDEX "OtpCode_target_purpose_idx" ON "public"."OtpCode"("target" ASC, "purpose" ASC);

-- CreateIndex
CREATE INDEX "PasswordResetToken_expiresAt_idx" ON "public"."PasswordResetToken"("expiresAt" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "PasswordResetToken_tokenHash_key" ON "public"."PasswordResetToken"("tokenHash" ASC);

-- CreateIndex
CREATE INDEX "PasswordResetToken_userId_idx" ON "public"."PasswordResetToken"("userId" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "Permission_code_key" ON "public"."Permission"("code" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "Permission_module_action_key" ON "public"."Permission"("module" ASC, "action" ASC);

-- CreateIndex
CREATE INDEX "ProviderAvailability_providerId_idx" ON "public"."ProviderAvailability"("providerId" ASC);

-- CreateIndex
CREATE INDEX "ProviderDocument_providerId_idx" ON "public"."ProviderDocument"("providerId" ASC);

-- CreateIndex
CREATE INDEX "ProviderDocument_status_idx" ON "public"."ProviderDocument"("status" ASC);

-- CreateIndex
CREATE INDEX "ProviderInternalNote_providerId_idx" ON "public"."ProviderInternalNote"("providerId" ASC);

-- CreateIndex
CREATE INDEX "ProviderPortfolioItem_providerId_idx" ON "public"."ProviderPortfolioItem"("providerId" ASC);

-- CreateIndex
CREATE INDEX "ProviderProfile_availabilityStatus_idx" ON "public"."ProviderProfile"("availabilityStatus" ASC);

-- CreateIndex
CREATE INDEX "ProviderProfile_score_idx" ON "public"."ProviderProfile"("score" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "ProviderProfile_userId_key" ON "public"."ProviderProfile"("userId" ASC);

-- CreateIndex
CREATE INDEX "ProviderProfile_validationStatus_idx" ON "public"."ProviderProfile"("validationStatus" ASC);

-- CreateIndex
CREATE INDEX "ProviderService_providerId_idx" ON "public"."ProviderService"("providerId" ASC);

-- CreateIndex
CREATE INDEX "ProviderService_serviceTypeId_idx" ON "public"."ProviderService"("serviceTypeId" ASC);

-- CreateIndex
CREATE INDEX "ProviderUnavailability_providerId_idx" ON "public"."ProviderUnavailability"("providerId" ASC);

-- CreateIndex
CREATE INDEX "ProviderUnavailability_startAt_endAt_idx" ON "public"."ProviderUnavailability"("startAt" ASC, "endAt" ASC);

-- CreateIndex
CREATE INDEX "Review_missionId_idx" ON "public"."Review"("missionId" ASC);

-- CreateIndex
CREATE INDEX "Review_status_idx" ON "public"."Review"("status" ASC);

-- CreateIndex
CREATE INDEX "Review_targetId_idx" ON "public"."Review"("targetId" ASC);

-- CreateIndex
CREATE INDEX "ReviewReport_reviewId_idx" ON "public"."ReviewReport"("reviewId" ASC);

-- CreateIndex
CREATE INDEX "ReviewReport_status_idx" ON "public"."ReviewReport"("status" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "Role_code_key" ON "public"."Role"("code" ASC);

-- CreateIndex
CREATE INDEX "ServicePack_providerServiceId_idx" ON "public"."ServicePack"("providerServiceId" ASC);

-- CreateIndex
CREATE INDEX "ServicePackOption_packId_idx" ON "public"."ServicePackOption"("packId" ASC);

-- CreateIndex
CREATE INDEX "ServiceType_active_idx" ON "public"."ServiceType"("active" ASC);

-- CreateIndex
CREATE INDEX "ServiceType_categoryId_idx" ON "public"."ServiceType"("categoryId" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "ServiceType_slug_key" ON "public"."ServiceType"("slug" ASC);

-- CreateIndex
CREATE INDEX "User_createdAt_idx" ON "public"."User"("createdAt" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "public"."User"("email" ASC);

-- CreateIndex
CREATE UNIQUE INDEX "User_phone_key" ON "public"."User"("phone" ASC);

-- CreateIndex
CREATE INDEX "User_status_idx" ON "public"."User"("status" ASC);

-- CreateIndex
CREATE INDEX "Zone_active_idx" ON "public"."Zone"("active" ASC);

-- CreateIndex
CREATE INDEX "Zone_cityId_idx" ON "public"."Zone"("cityId" ASC);

-- CreateIndex
CREATE INDEX "Zone_latitude_longitude_idx" ON "public"."Zone"("latitude" ASC, "longitude" ASC);

-- AddForeignKey
ALTER TABLE "public"."Address" ADD CONSTRAINT "Address_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."AdminProfile" ADD CONSTRAINT "AdminProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."AuditLog" ADD CONSTRAINT "AuditLog_actorId_fkey" FOREIGN KEY ("actorId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."CatalogCategory" ADD CONSTRAINT "CatalogCategory_iconFileId_fkey" FOREIGN KEY ("iconFileId") REFERENCES "public"."File"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ChatMessage" ADD CONSTRAINT "ChatMessage_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ChatMessage" ADD CONSTRAINT "ChatMessage_threadId_fkey" FOREIGN KEY ("threadId") REFERENCES "public"."ChatThread"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ChatMessageFile" ADD CONSTRAINT "ChatMessageFile_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "public"."File"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ChatMessageFile" ADD CONSTRAINT "ChatMessageFile_messageId_fkey" FOREIGN KEY ("messageId") REFERENCES "public"."ChatMessage"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ChatThread" ADD CONSTRAINT "ChatThread_missionId_fkey" FOREIGN KEY ("missionId") REFERENCES "public"."Mission"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ClientProfile" ADD CONSTRAINT "ClientProfile_avatarFileId_fkey" FOREIGN KEY ("avatarFileId") REFERENCES "public"."File"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ClientProfile" ADD CONSTRAINT "ClientProfile_defaultAddressId_fkey" FOREIGN KEY ("defaultAddressId") REFERENCES "public"."Address"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ClientProfile" ADD CONSTRAINT "ClientProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Dispute" ADD CONSTRAINT "Dispute_assignedTo_fkey" FOREIGN KEY ("assignedTo") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Dispute" ADD CONSTRAINT "Dispute_missionId_fkey" FOREIGN KEY ("missionId") REFERENCES "public"."Mission"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Dispute" ADD CONSTRAINT "Dispute_openedBy_fkey" FOREIGN KEY ("openedBy") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DisputeFile" ADD CONSTRAINT "DisputeFile_disputeId_fkey" FOREIGN KEY ("disputeId") REFERENCES "public"."Dispute"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DisputeFile" ADD CONSTRAINT "DisputeFile_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "public"."File"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DisputeMessage" ADD CONSTRAINT "DisputeMessage_disputeId_fkey" FOREIGN KEY ("disputeId") REFERENCES "public"."Dispute"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."DisputeMessage" ADD CONSTRAINT "DisputeMessage_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ExportJob" ADD CONSTRAINT "ExportJob_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "public"."File"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ExportJob" ADD CONSTRAINT "ExportJob_requestedBy_fkey" FOREIGN KEY ("requestedBy") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."File" ADD CONSTRAINT "File_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Mission" ADD CONSTRAINT "Mission_addressId_fkey" FOREIGN KEY ("addressId") REFERENCES "public"."Address"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Mission" ADD CONSTRAINT "Mission_clientId_fkey" FOREIGN KEY ("clientId") REFERENCES "public"."User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Mission" ADD CONSTRAINT "Mission_packId_fkey" FOREIGN KEY ("packId") REFERENCES "public"."ServicePack"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Mission" ADD CONSTRAINT "Mission_providerId_fkey" FOREIGN KEY ("providerId") REFERENCES "public"."ProviderProfile"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."MissionCancellation" ADD CONSTRAINT "MissionCancellation_cancelledBy_fkey" FOREIGN KEY ("cancelledBy") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."MissionCancellation" ADD CONSTRAINT "MissionCancellation_missionId_fkey" FOREIGN KEY ("missionId") REFERENCES "public"."Mission"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."MissionReschedule" ADD CONSTRAINT "MissionReschedule_createdBy_fkey" FOREIGN KEY ("createdBy") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."MissionReschedule" ADD CONSTRAINT "MissionReschedule_missionId_fkey" FOREIGN KEY ("missionId") REFERENCES "public"."Mission"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."MissionStatusHistory" ADD CONSTRAINT "MissionStatusHistory_changedBy_fkey" FOREIGN KEY ("changedBy") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."MissionStatusHistory" ADD CONSTRAINT "MissionStatusHistory_missionId_fkey" FOREIGN KEY ("missionId") REFERENCES "public"."Mission"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Notification" ADD CONSTRAINT "Notification_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."PasswordResetToken" ADD CONSTRAINT "PasswordResetToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderAvailability" ADD CONSTRAINT "ProviderAvailability_providerId_fkey" FOREIGN KEY ("providerId") REFERENCES "public"."ProviderProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderDocument" ADD CONSTRAINT "ProviderDocument_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "public"."File"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderDocument" ADD CONSTRAINT "ProviderDocument_providerId_fkey" FOREIGN KEY ("providerId") REFERENCES "public"."ProviderProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderDocument" ADD CONSTRAINT "ProviderDocument_reviewedBy_fkey" FOREIGN KEY ("reviewedBy") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderInternalNote" ADD CONSTRAINT "ProviderInternalNote_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderInternalNote" ADD CONSTRAINT "ProviderInternalNote_providerId_fkey" FOREIGN KEY ("providerId") REFERENCES "public"."ProviderProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderPortfolioItem" ADD CONSTRAINT "ProviderPortfolioItem_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "public"."File"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderPortfolioItem" ADD CONSTRAINT "ProviderPortfolioItem_providerId_fkey" FOREIGN KEY ("providerId") REFERENCES "public"."ProviderProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderProfile" ADD CONSTRAINT "ProviderProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderService" ADD CONSTRAINT "ProviderService_providerId_fkey" FOREIGN KEY ("providerId") REFERENCES "public"."ProviderProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderService" ADD CONSTRAINT "ProviderService_serviceTypeId_fkey" FOREIGN KEY ("serviceTypeId") REFERENCES "public"."ServiceType"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderUnavailability" ADD CONSTRAINT "ProviderUnavailability_providerId_fkey" FOREIGN KEY ("providerId") REFERENCES "public"."ProviderProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderZone" ADD CONSTRAINT "ProviderZone_providerId_fkey" FOREIGN KEY ("providerId") REFERENCES "public"."ProviderProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ProviderZone" ADD CONSTRAINT "ProviderZone_zoneId_fkey" FOREIGN KEY ("zoneId") REFERENCES "public"."Zone"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Review" ADD CONSTRAINT "Review_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Review" ADD CONSTRAINT "Review_missionId_fkey" FOREIGN KEY ("missionId") REFERENCES "public"."Mission"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Review" ADD CONSTRAINT "Review_targetId_fkey" FOREIGN KEY ("targetId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ReviewReport" ADD CONSTRAINT "ReviewReport_reportedBy_fkey" FOREIGN KEY ("reportedBy") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ReviewReport" ADD CONSTRAINT "ReviewReport_reviewId_fkey" FOREIGN KEY ("reviewId") REFERENCES "public"."Review"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."RolePermission" ADD CONSTRAINT "RolePermission_permissionId_fkey" FOREIGN KEY ("permissionId") REFERENCES "public"."Permission"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."RolePermission" ADD CONSTRAINT "RolePermission_roleId_fkey" FOREIGN KEY ("roleId") REFERENCES "public"."Role"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ServicePack" ADD CONSTRAINT "ServicePack_providerServiceId_fkey" FOREIGN KEY ("providerServiceId") REFERENCES "public"."ProviderService"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ServicePackOption" ADD CONSTRAINT "ServicePackOption_packId_fkey" FOREIGN KEY ("packId") REFERENCES "public"."ServicePack"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."ServiceType" ADD CONSTRAINT "ServiceType_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "public"."CatalogCategory"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."SystemSetting" ADD CONSTRAINT "SystemSetting_updatedBy_fkey" FOREIGN KEY ("updatedBy") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."UserRole" ADD CONSTRAINT "UserRole_roleId_fkey" FOREIGN KEY ("roleId") REFERENCES "public"."Role"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."UserRole" ADD CONSTRAINT "UserRole_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."Zone" ADD CONSTRAINT "Zone_cityId_fkey" FOREIGN KEY ("cityId") REFERENCES "public"."City"("id") ON DELETE SET NULL ON UPDATE CASCADE;

