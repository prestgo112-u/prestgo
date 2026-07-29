# Quickstart: PRESTGO Back-office Admin and Backend Services

This guide validates the planned V1 behavior once implementation tasks are generated and completed. It intentionally avoids implementation code; use it as the end-to-end acceptance guide for the feature.

## Prerequisites

- Node.js 22 LTS
- Package manager selected by the project during implementation
- PostgreSQL with PostGIS enabled
- Redis available for OTP, queue and notification workflows
- Environment variables configured for database, Redis, token secrets and file storage

## Setup

1. Install dependencies from the repository root.
2. Create the local database and enable geographic support.
3. Run database migrations and seed baseline roles, permissions, admin user, catalog samples and zones.
4. Start the API service.
5. Start the admin web app.
6. Open the admin back-office in a browser and sign in with the seeded super admin account.

## Contract Validation

- Validate `contracts/openapi.yaml` with the project's OpenAPI tooling.
- Generate or refresh API client types for the admin app from the contract.
- Run contract tests against the local API and verify that secured routes reject anonymous and unauthorized calls.

## Scenario 1: Admin Access And Permissions

1. Sign in as super admin.
2. Confirm dashboard, users, roles, providers, missions, disputes, reviews, settings, audit and exports are visible.
3. Create or activate a read-only internal user.
4. Sign in as read-only user.
5. Confirm list/detail views are accessible but sensitive actions are unavailable or rejected.

**Expected outcome**: Role and permission behavior matches the spec, and unauthorized sensitive actions do not modify data.

## Scenario 2: Provider Validation

1. Create a provider account with profile, category, zone, services, availability and required documents.
2. Confirm the provider appears in the validation queue.
3. Reject one document with a required reason.
4. Resubmit the corrected document.
5. Approve the document and approve the provider profile.

**Expected outcome**: Provider status moves through the expected states, reasons are required where applicable and audit entries are created.

## Scenario 3: Mission Supervision

1. Create a mission for a client, provider, pack, address and scheduled date.
2. Move it through allowed status transitions.
3. Attempt an invalid transition.
4. Reprogram or cancel with a required reason.

**Expected outcome**: Valid transitions succeed, invalid transitions fail with understandable errors and full status history is preserved.

## Scenario 4: Dispute Handling

1. Open a dispute for a mission.
2. Assign it to a support agent.
3. Add an internal comment and a proof file.
4. Resolve the dispute with a decision.
5. Close the dispute.

**Expected outcome**: The dispute workflow is traceable from opening to closure, and decision/closure actions require reasons.

## Scenario 5: Review Moderation

1. Create or seed a completed mission with a review.
2. Report the review.
3. Sign in as moderator.
4. Mask or reject the review with a reason.

**Expected outcome**: Moderation status changes are permission-controlled, motivated and audited.

## Scenario 6: Catalog, Zones And Availability

1. Create a category, service type, provider service and pack.
2. Create a city/zone with coordinates and radius.
3. Attach the provider to the zone and add weekly availability.
4. Deactivate the category or zone.

**Expected outcome**: Active items are usable for operations; inactive items remain visible in admin history but not available for new public use.

## Scenario 7: Files, Audit And Exports

1. Upload a sensitive provider document.
2. Attempt access as unauthorized user.
3. Access as authorized validation agent.
4. Perform several sensitive admin actions.
5. Request an export with filters and download it as an authorized admin.

**Expected outcome**: Sensitive files are protected, audit entries cover sensitive actions and export files are permission-restricted.

## Success Criteria Mapping

- SC-001 and SC-002: Scenarios 1, 2, 3, 4 and 5.
- SC-003: Scenario 2.
- SC-004: Scenario 3.
- SC-005: List views covered across dashboard, providers, missions, disputes and reviews.
- SC-006: Scenarios 2, 3, 4 and 5.
- SC-007: Scenario 7.
- SC-008: All scenarios together.
