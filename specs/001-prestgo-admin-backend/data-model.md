# Data Model: PRESTGO Back-office Admin and Backend Services

## Entity Overview

### User

Represents a shared account for internal admins, clients and providers.

**Fields**: id, firstName, lastName, phone, email, passwordHash, status, phoneVerifiedAt, emailVerifiedAt, createdAt, updatedAt.

**Relationships**: Has many role assignments, addresses, notifications, files and audit actions. May have one admin profile, client profile or provider profile depending on account type.

**Validation**: Email and phone must be unique when present. Status must follow the user status transition rules.

### Role

Represents a named access profile such as super admin, admin, support, validation, moderator or read-only.

**Fields**: id, code, name, description, isSystem, createdAt, updatedAt.

**Relationships**: Many-to-many with users and permissions.

**Validation**: System roles cannot be deleted; role code is unique.

### Permission

Represents a granular action authorization.

**Fields**: id, code, module, action, description.

**Relationships**: Many-to-many with roles.

**Validation**: Permission code is unique and maps to a known module/action pair.

### AdminProfile

Represents internal PRESTGO staff metadata.

**Fields**: userId, jobTitle, department, isActive.

**Relationships**: Belongs to user.

**Validation**: Only users with internal roles can have an active admin profile.

### ClientProfile

Represents a platform client.

**Fields**: userId, avatarFileId, defaultAddressId, notes.

**Relationships**: Belongs to user; has addresses, missions, reviews and disputes.

### ProviderProfile

Represents a service provider subject to validation.

**Fields**: userId, publicName, bio, experienceYears, validationStatus, availabilityStatus, score, createdAt, updatedAt.

**Relationships**: Belongs to user; has documents, services, zones, availability slots, unavailability periods, portfolio items, missions, reviews, disputes and internal notes.

**Validation**: Approved providers require complete profile, required documents and at least one active service/zone combination.

**Status transitions**:

```text
profile_incomplete -> pending_review
pending_review -> approved | rejected | changes_requested
changes_requested -> pending_review
approved -> suspended
suspended -> approved | rejected
```

### ProviderDocument

Represents a verification document.

**Fields**: id, providerId, type, fileId, status, rejectionReason, reviewedBy, reviewedAt, createdAt.

**Relationships**: Belongs to provider, file and reviewing user.

**Validation**: Rejected documents require rejectionReason. Approved/rejected documents require reviewedBy and reviewedAt.

### CatalogCategory

Represents a primary service category.

**Fields**: id, name, slug, description, iconFileId, active, displayOrder.

**Relationships**: Has many service types.

**Validation**: Slug is unique. Inactive categories remain visible in admin history but unavailable for new public use.

### ServiceType

Represents a sub-service under a category.

**Fields**: id, categoryId, name, slug, description, active.

**Relationships**: Belongs to category; has provider services.

### ProviderService

Represents a service offered by a provider.

**Fields**: id, providerId, serviceTypeId, title, description, active.

**Relationships**: Belongs to provider and service type; has service packs.

### ServicePack

Represents a sellable pack of work from a provider.

**Fields**: id, providerServiceId, title, description, price, durationMinutes, active.

**Relationships**: Belongs to provider service; has optional add-ons.

**Validation**: Price and duration must be positive when active.

### Zone

Represents a covered city/commune/radius.

**Fields**: id, cityId, name, latitude, longitude, radiusKm, active.

**Relationships**: Belongs to city; many-to-many with providers.

**Validation**: Active zones require valid coordinates and positive radius.

### Address

Represents a user address used for missions.

**Fields**: id, userId, label, city, commune, details, latitude, longitude, isDefault.

**Relationships**: Belongs to user; referenced by missions.

### ProviderAvailability

Represents recurring weekly provider availability.

**Fields**: id, providerId, weekday, startTime, endTime, active.

**Validation**: endTime must be after startTime; overlapping active slots for the same provider/day are not allowed.

### ProviderUnavailability

Represents exceptional provider absence.

**Fields**: id, providerId, startAt, endAt, reason.

**Validation**: endAt must be after startAt.

### Mission

Represents a client service request/reservation.

**Fields**: id, clientId, providerId, packId, scheduledAt, addressId, status, instructions, createdAt, updatedAt.

**Relationships**: Belongs to client, provider, pack and address; has status history, reschedules, cancellations, chat thread, reviews and disputes.

**Status transitions**:

```text
draft -> pending_provider
pending_provider -> confirmed | cancelled
confirmed -> in_progress | cancelled
confirmed -> confirmed via reschedule
in_progress -> completed | disputed
completed -> closed | disputed
disputed -> completed | closed | cancelled
```

**Validation**: Cancellation requires a reason. Manual status changes require actor, permission and history entry.

### MissionStatusHistory

Represents status changes for missions.

**Fields**: id, missionId, oldStatus, newStatus, changedBy, reason, createdAt.

**Validation**: Created for every mission status change.

### ChatThread and ChatMessage

Represent mission conversations and messages.

**Fields**: thread id, missionId, status, createdAt; message id, threadId, senderId, message, createdAt, readAt.

**Relationships**: Thread belongs to mission; messages belong to thread and sender; message files link to files.

### Review

Represents a rating/comment after a mission.

**Fields**: id, missionId, authorId, targetId, rating, comment, status, createdAt.

**Relationships**: Belongs to mission, author and target; has reports.

**Validation**: Rating must stay within configured bounds. Moderation decisions require reason when masking/rejecting.

### Dispute

Represents a support ticket tied to a mission.

**Fields**: id, missionId, openedBy, reason, description, status, assignedTo, decision, createdAt, updatedAt.

**Relationships**: Belongs to mission and opening user; may be assigned to support user; has messages and files.

**Status transitions**:

```text
open -> in_review
in_review -> waiting_client | waiting_provider | resolved | rejected
waiting_client -> in_review | resolved
waiting_provider -> in_review | resolved
resolved -> closed
rejected -> closed
```

**Validation**: Resolution, rejection and closure require a decision or reason.

### Notification and NotificationTemplate

Represent system messages and reusable templates.

**Fields**: notification id, userId, type, title, body, channel, status, createdAt, sentAt; template id, code, titleTemplate, bodyTemplate, active.

**Validation**: Template code is unique. Sent notifications keep immutable content.

### File

Represents uploaded metadata and access rules.

**Fields**: id, ownerId, originalName, mimeType, size, storageKey, visibility, createdAt, disabledAt.

**Relationships**: Referenced by provider documents, portfolio items, disputes and messages.

**Validation**: Sensitive visibility requires explicit permission checks before access.

### SystemSetting

Represents a configurable business setting.

**Fields**: key, value, type, description, updatedBy, updatedAt.

**Validation**: Setting value must match declared type and module constraints.

### AuditLog

Represents a trace of sensitive actions.

**Fields**: id, actorId, action, entity, entityId, oldValue, newValue, ip, createdAt.

**Validation**: Sensitive actions must produce exactly one audit log entry with actor and target.

### ExportJob

Represents an operational export request.

**Fields**: id, requestedBy, type, filters, status, fileId, createdAt, completedAt.

**Relationships**: Belongs to requesting user and final file.

**Validation**: Export filters must be permission-safe; final file inherits restricted visibility.
