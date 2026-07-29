# Tasks: PRESTGO Back-office Admin and Backend Services

**Input**: Design documents from `specs/001-prestgo-admin-backend/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/openapi.yaml, quickstart.md

**Tests**: Included because the implementation plan explicitly requires unit, contract, integration and end-to-end validation for critical admin workflows.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize the TypeScript monorepo, shared tooling and baseline project layout.

- [X] T001 Create monorepo folders from the implementation plan in apps/api, apps/admin, packages/contracts, packages/config and packages/test-utils
- [X] T002 Initialize root package manager workspace and TypeScript configuration in package.json, tsconfig.base.json and pnpm-workspace.yaml
- [X] T003 [P] Configure shared linting and formatting in eslint.config.js, prettier.config.js and .editorconfig
- [X] T004 [P] Create shared environment schema package in packages/config/src/env.ts
- [X] T005 [P] Add shared test utilities scaffold in packages/test-utils/src/index.ts
- [X] T006 Create API app scaffold with NestJS entry files in apps/api/src/main.ts and apps/api/src/app.module.ts
- [X] T007 Create admin app scaffold with Vite/React entry files in apps/admin/src/app/App.tsx and apps/admin/src/main.tsx
- [X] T008 Copy OpenAPI source contract into packages/contracts/openapi.yaml from specs/001-prestgo-admin-backend/contracts/openapi.yaml

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that must be complete before any user story can be implemented.

**CRITICAL**: No user story work can begin until this phase is complete.

- [X] T009 Configure Prisma and PostgreSQL/PostGIS bootstrap in apps/api/prisma/schema.prisma and apps/api/prisma/migrations/000001_init_postgis/migration.sql
- [X] T010 Define shared API response, pagination and error contracts in apps/api/src/common/contracts/api-response.ts
- [X] T011 Implement global validation, exception filtering and request correlation in apps/api/src/common/filters/http-exception.filter.ts and apps/api/src/common/interceptors/correlation.interceptor.ts
- [X] T012 Implement authentication token primitives in apps/api/src/modules/auth/auth.module.ts, apps/api/src/modules/auth/auth.service.ts and apps/api/src/modules/auth/jwt.strategy.ts
- [X] T013 Implement RBAC decorators and guards in apps/api/src/common/decorators/permissions.decorator.ts and apps/api/src/common/guards/permissions.guard.ts
- [X] T014 Create initial user, role, permission and audit Prisma models in apps/api/prisma/schema.prisma
- [X] T015 Seed baseline roles, permissions and super admin in apps/api/prisma/seed.ts
- [X] T016 Implement audit logging service in apps/api/src/modules/audit/audit.service.ts
- [X] T017 Implement file metadata and sensitive access guard foundation in apps/api/src/modules/files/files.module.ts and apps/api/src/modules/files/file-access.guard.ts
- [X] T018 Configure Redis and queue module foundation in apps/api/src/common/queues/queue.module.ts
- [X] T019 [P] Configure OpenAPI generation and contract export in apps/api/src/common/openapi/openapi.setup.ts
- [X] T020 [P] Configure admin API client generation entry in apps/admin/src/lib/api-client.ts
- [X] T021 [P] Create admin layout, protected route shell and permission-aware navigation in apps/admin/src/app/AdminShell.tsx and apps/admin/src/routes/protected-routes.tsx
- [X] T022 Create foundational contract tests for auth and permission failures in apps/api/tests/contract/auth-permissions.contract.spec.ts
- [X] T023 Create foundational integration tests for audit and RBAC in apps/api/tests/integration/rbac-audit.integration.spec.ts

**Checkpoint**: Foundation ready; user story implementation can now begin.

---

## Phase 3: User Story 1 - Administrer la plateforme en securite (Priority: P1) MVP

**Goal**: Internal users sign in, see only authorized modules and perform only permitted administrative actions.

**Independent Test**: Sign in as super admin and read-only user, confirm dashboard/module access differs by role, and verify unauthorized sensitive actions are rejected without data changes.

### Tests for User Story 1

- [X] T024 [P] [US1] Add contract tests for /auth/login, /auth/refresh, /auth/logout, /admin/dashboard/summary, /admin/users and /admin/users/{id}/status in apps/api/tests/contract/admin-access.contract.spec.ts
- [X] T025 [P] [US1] Add integration tests for login, dashboard visibility and read-only permission denial in apps/api/tests/integration/admin-access.integration.spec.ts
- [X] T026 [P] [US1] Add admin e2e test for super admin and read-only navigation in apps/admin/tests/e2e/admin-access.e2e.spec.ts

### Implementation for User Story 1

- [X] T027 [P] [US1] Implement User, Role, Permission and AdminProfile domain types in apps/api/src/modules/users/user.types.ts and apps/api/src/modules/roles/role.types.ts
- [X] T028 [US1] Implement auth login, refresh and logout handlers in apps/api/src/modules/auth/auth.controller.ts and apps/api/src/modules/auth/auth.service.ts
- [X] T029 [US1] Implement users list, detail and status change service in apps/api/src/modules/users/users.service.ts
- [X] T030 [US1] Implement users admin controller in apps/api/src/modules/users/admin-users.controller.ts
- [X] T031 [US1] Implement role and permission management services in apps/api/src/modules/roles/roles.service.ts
- [X] T032 [US1] Implement dashboard summary service in apps/api/src/modules/admin/dashboard.service.ts
- [X] T033 [US1] Implement dashboard and admin user endpoints in apps/api/src/modules/admin/dashboard.controller.ts and apps/api/src/modules/users/admin-users.controller.ts
- [X] T034 [US1] Implement admin authentication screens in apps/admin/src/features/auth/LoginPage.tsx and apps/admin/src/features/auth/auth.store.ts
- [X] T035 [US1] Implement dashboard page and metric cards in apps/admin/src/features/dashboard/DashboardPage.tsx
- [X] T036 [US1] Implement users and roles pages with permission-aware actions in apps/admin/src/features/users/UsersPage.tsx and apps/admin/src/features/users/UserDetailPage.tsx
- [X] T037 [US1] Wire audit logging for login-sensitive admin actions and user status changes in apps/api/src/modules/audit/audit.service.ts

**Checkpoint**: US1 is independently functional and demoable as the MVP.

---

## Phase 4: User Story 2 - Valider les prestataires (Priority: P1)

**Goal**: Validation agents review provider profiles and documents, then approve, reject or request corrections with required reasons and audit history.

**Independent Test**: Submit complete and incomplete provider dossiers, process document rejection and approval, and verify provider visibility follows validation status.

### Tests for User Story 2

- [X] T038 [P] [US2] Add contract tests for /admin/providers, /admin/providers/{id}, /admin/providers/{id}/status, /admin/verifications/documents/{id}/approve and /admin/verifications/documents/{id}/reject in apps/api/tests/contract/provider-validation.contract.spec.ts
- [X] T039 [P] [US2] Add integration tests for provider validation status transitions in apps/api/tests/integration/provider-validation.integration.spec.ts
- [X] T040 [P] [US2] Add admin e2e test for provider validation queue and document rejection reason in apps/admin/tests/e2e/provider-validation.e2e.spec.ts

### Implementation for User Story 2

- [X] T041 [P] [US2] Add provider, document, internal note and provider status models to apps/api/prisma/schema.prisma
- [X] T042 [P] [US2] Add provider validation state machine in apps/api/src/modules/providers/provider-status.machine.ts
- [X] T043 [US2] Implement provider query and detail service in apps/api/src/modules/providers/providers.service.ts
- [X] T044 [US2] Implement provider document review service in apps/api/src/modules/documents/provider-documents.service.ts
- [X] T045 [US2] Implement provider status mutation endpoints in apps/api/src/modules/providers/admin-providers.controller.ts
- [X] T046 [US2] Implement document approve/reject endpoints in apps/api/src/modules/documents/admin-verifications.controller.ts
- [X] T047 [US2] Implement provider validation queue page in apps/admin/src/features/providers/ProviderValidationQueue.tsx
- [X] T048 [US2] Implement provider detail, document viewer and decision modal in apps/admin/src/features/providers/ProviderDetailPage.tsx
- [X] T049 [US2] Wire required rejection/correction reasons and audit logging in apps/api/src/modules/providers/providers.service.ts and apps/api/src/modules/documents/provider-documents.service.ts

**Checkpoint**: US2 can be validated without relying on mission, dispute or review features.

---

## Phase 5: User Story 3 - Superviser missions, litiges, avis et messages (Priority: P1)

**Goal**: Support and moderation teams supervise missions, process disputes, review message context and moderate reported reviews with motivated decisions.

**Independent Test**: Create a mission, change status, open and resolve a dispute, report and moderate a review, and verify history/audit preservation.

### Tests for User Story 3

- [X] T050 [P] [US3] Add contract tests for mission endpoints in apps/api/tests/contract/missions.contract.spec.ts
- [X] T051 [P] [US3] Add contract tests for dispute, review and message endpoints in apps/api/tests/contract/support-moderation.contract.spec.ts
- [X] T052 [P] [US3] Add integration tests for mission, dispute and review status machines in apps/api/tests/integration/operations-workflows.integration.spec.ts
- [X] T053 [P] [US3] Add admin e2e test for mission supervision, dispute resolution and review moderation in apps/admin/tests/e2e/operations-workflows.e2e.spec.ts

### Implementation for User Story 3

- [X] T054 [P] [US3] Add mission, mission history, reschedule, cancellation, chat, review and dispute models to apps/api/prisma/schema.prisma
- [X] T055 [P] [US3] Implement mission status machine in apps/api/src/modules/missions/mission-status.machine.ts
- [X] T056 [P] [US3] Implement dispute status machine in apps/api/src/modules/disputes/dispute-status.machine.ts
- [X] T057 [P] [US3] Implement review moderation status rules in apps/api/src/modules/reviews/review-status.rules.ts
- [X] T058 [US3] Implement mission list, detail, status, reschedule and cancel services in apps/api/src/modules/missions/missions.service.ts
- [X] T059 [US3] Implement mission admin controller in apps/api/src/modules/missions/admin-missions.controller.ts
- [X] T060 [US3] Implement message thread list/detail service in apps/api/src/modules/messages/messages.service.ts
- [X] T061 [US3] Implement review list and moderation service in apps/api/src/modules/reviews/reviews.service.ts
- [X] T062 [US3] Implement dispute open, assign, message and status services in apps/api/src/modules/disputes/disputes.service.ts
- [X] T063 [US3] Implement admin mission screens in apps/admin/src/features/missions/MissionsPage.tsx and apps/admin/src/features/missions/MissionDetailPage.tsx
- [X] T064 [US3] Implement dispute list/detail workflow screens in apps/admin/src/features/disputes/DisputesPage.tsx and apps/admin/src/features/disputes/DisputeDetailPage.tsx
- [X] T065 [US3] Implement review moderation screen in apps/admin/src/features/reviews/ReviewsPage.tsx
- [X] T066 [US3] Implement message supervision screen in apps/admin/src/features/messages/MessagesPage.tsx
- [X] T067 [US3] Wire audit logging for mission status changes, dispute decisions and review moderation in apps/api/src/modules/audit/audit.service.ts

**Checkpoint**: US3 critical operations are functional and independently testable.

---

## Phase 6: User Story 4 - Gerer le catalogue, les zones et les disponibilites (Priority: P2)

**Goal**: Admin users manage service categories, service types, provider packs, zones and provider availability.

**Independent Test**: Create active catalog and zone records, attach them to a provider, add availability, then deactivate catalog or zone while retaining admin history.

### Tests for User Story 4

- [X] T068 [P] [US4] Add contract tests for /admin/categories and /admin/zones in apps/api/tests/contract/catalog-zones.contract.spec.ts
- [X] T069 [P] [US4] Add integration tests for catalog deactivation, zone validation and availability overlaps in apps/api/tests/integration/catalog-zones.integration.spec.ts
- [X] T070 [P] [US4] Add admin e2e test for catalog, zone and availability management in apps/admin/tests/e2e/catalog-zones.e2e.spec.ts

### Implementation for User Story 4

- [X] T071 [P] [US4] Add category, service type, provider service, service pack, zone, address and availability models to apps/api/prisma/schema.prisma
- [X] T072 [US4] Implement catalog service and admin controller in apps/api/src/modules/catalog/catalog.service.ts and apps/api/src/modules/catalog/admin-catalog.controller.ts
- [X] T073 [US4] Implement zones service and admin controller in apps/api/src/modules/zones/zones.service.ts and apps/api/src/modules/zones/admin-zones.controller.ts
- [X] T074 [US4] Implement provider availability service in apps/api/src/modules/availability/availability.service.ts
- [X] T075 [US4] Implement catalog admin screens in apps/admin/src/features/catalog/CatalogPage.tsx and apps/admin/src/features/catalog/ServiceTypeEditor.tsx
- [X] T076 [US4] Implement zones admin screens in apps/admin/src/features/zones/ZonesPage.tsx and apps/admin/src/features/zones/ZoneEditor.tsx
- [X] T077 [US4] Implement provider availability editor in apps/admin/src/features/providers/ProviderAvailabilityPanel.tsx

**Checkpoint**: US4 can be validated using catalog, zones and provider availability workflows.

---

## Phase 7: User Story 5 - Auditer, parametrer, notifier et exporter (Priority: P2)

**Goal**: Authorized admins consult audit logs, update functional settings, send notifications and request permission-safe exports.

**Independent Test**: Perform sensitive actions, update a setting, send a notification, request an export and verify access restrictions on the generated file.

### Tests for User Story 5

- [X] T078 [P] [US5] Add contract tests for settings, audit, notifications and exports in apps/api/tests/contract/admin-operations.contract.spec.ts
- [X] T079 [P] [US5] Add integration tests for notification queueing, setting validation, audit filters and export restrictions in apps/api/tests/integration/admin-operations.integration.spec.ts
- [X] T080 [P] [US5] Add admin e2e test for settings, audit, notification and export workflows in apps/admin/tests/e2e/admin-operations.e2e.spec.ts

### Implementation for User Story 5

- [X] T081 [P] [US5] Add notification, notification template, system setting, audit log, file and export job models to apps/api/prisma/schema.prisma
- [X] T082 [US5] Implement settings service and admin controller in apps/api/src/modules/settings/settings.service.ts and apps/api/src/modules/settings/admin-settings.controller.ts
- [X] T083 [US5] Implement notification template and send services in apps/api/src/modules/notifications/notifications.service.ts
- [X] T084 [US5] Implement export job service and controller in apps/api/src/modules/reports/exports.service.ts and apps/api/src/modules/reports/admin-exports.controller.ts
- [X] T085 [US5] Implement audit log query controller in apps/api/src/modules/audit/admin-audit.controller.ts
- [X] T086 [US5] Implement file upload/download controller and restricted file policy in apps/api/src/modules/files/files.controller.ts and apps/api/src/modules/files/file-access.policy.ts
- [X] T087 [US5] Implement settings page in apps/admin/src/features/settings/SettingsPage.tsx
- [X] T088 [US5] Implement audit log page in apps/admin/src/features/audit/AuditLogPage.tsx
- [X] T089 [US5] Implement notifications page in apps/admin/src/features/notifications/NotificationsPage.tsx
- [X] T090 [US5] Implement exports page and export status view in apps/admin/src/features/exports/ExportsPage.tsx

**Checkpoint**: US5 operations are functional and permission-safe.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final hardening, documentation and validation across stories.

- [ ] T091 [P] Update API contract examples and error responses in packages/contracts/openapi.yaml
- [ ] T092 [P] Update developer setup documentation in README.md using specs/001-prestgo-admin-backend/quickstart.md
- [ ] T093 Run generated OpenAPI validation and client generation from packages/contracts/openapi.yaml
- [ ] T094 Run unit, contract, integration and admin e2e test suites from apps/api and apps/admin
- [ ] T095 Verify quickstart scenarios manually and record results in specs/001-prestgo-admin-backend/quickstart-results.md
- [ ] T096 Review audit coverage for every sensitive action listed in specs/001-prestgo-admin-backend/spec.md
- [ ] T097 Review admin UI accessibility, empty states, validation errors and permission-denied states in apps/admin/src/features
- [ ] T098 Remove implementation drift by comparing final routes, schemas and UI workflows against specs/001-prestgo-admin-backend/contracts/openapi.yaml

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies; can start immediately.
- **Foundational (Phase 2)**: Depends on Setup completion; blocks all user stories.
- **US1 (Phase 3)**: Depends on Foundational; MVP.
- **US2 (Phase 4)**: Depends on Foundational and file/audit foundations; can run beside US1 after shared auth/RBAC is stable.
- **US3 (Phase 5)**: Depends on Foundational plus baseline users/providers/catalog availability for realistic mission scenarios.
- **US4 (Phase 6)**: Depends on Foundational and provider basics; can run beside US2 once provider model exists.
- **US5 (Phase 7)**: Depends on Foundational audit/file/queue foundations; can run beside US2-US4 after shared models stabilize.
- **Polish (Phase 8)**: Depends on selected stories being complete.

### User Story Dependencies

- **US1**: No dependency on other user stories; recommended MVP.
- **US2**: Uses foundational users, roles, files and audit; does not depend on missions.
- **US3**: Uses users, providers and catalog concepts; mission/dispute/review workflows are independently testable after fixtures exist.
- **US4**: Uses provider concepts; independently validates catalog, zones and availability.
- **US5**: Cross-cutting admin operations; independently validates audit, settings, notifications, files and exports.

### Parallel Opportunities

- T003, T004, T005, T019, T020 and T021 can run in parallel after T001-T002.
- T024-T026 can run in parallel for US1 tests.
- T038-T040 can run in parallel for US2 tests.
- T050-T053 can run in parallel for US3 tests.
- T068-T070 can run in parallel for US4 tests.
- T078-T080 can run in parallel for US5 tests.
- UI screen tasks in each story can run in parallel with API controller tasks after service contracts are agreed.

---

## Parallel Example: User Story 1

```text
Task: "T024 [P] [US1] Add contract tests for /auth/login, /auth/refresh, /auth/logout, /admin/dashboard/summary, /admin/users and /admin/users/{id}/status in apps/api/tests/contract/admin-access.contract.spec.ts"
Task: "T025 [P] [US1] Add integration tests for login, dashboard visibility and read-only permission denial in apps/api/tests/integration/admin-access.integration.spec.ts"
Task: "T026 [P] [US1] Add admin e2e test for super admin and read-only navigation in apps/admin/tests/e2e/admin-access.e2e.spec.ts"
```

## Parallel Example: User Story 2

```text
Task: "T041 [P] [US2] Add provider, document, internal note and provider status models to apps/api/prisma/schema.prisma"
Task: "T042 [P] [US2] Add provider validation state machine in apps/api/src/modules/providers/provider-status.machine.ts"
Task: "T047 [US2] Implement provider validation queue page in apps/admin/src/features/providers/ProviderValidationQueue.tsx"
```

## Parallel Example: User Story 3

```text
Task: "T055 [P] [US3] Implement mission status machine in apps/api/src/modules/missions/mission-status.machine.ts"
Task: "T056 [P] [US3] Implement dispute status machine in apps/api/src/modules/disputes/dispute-status.machine.ts"
Task: "T057 [P] [US3] Implement review moderation status rules in apps/api/src/modules/reviews/review-status.rules.ts"
```

---

## Implementation Strategy

### MVP First

1. Complete Phase 1 Setup.
2. Complete Phase 2 Foundational.
3. Complete Phase 3 US1 admin access and permissions.
4. Validate US1 using contract, integration and admin e2e tests.
5. Demo the secure admin shell, dashboard, user list and role-limited behavior.

### Incremental Delivery

1. Deliver US1 for secure operations baseline.
2. Add US2 for provider validation.
3. Add US3 for mission, dispute, review and message supervision.
4. Add US4 for catalog, zones and availability.
5. Add US5 for audit, settings, notifications, files and exports.
6. Finish with cross-story validation from quickstart.md.

### Validation Discipline

- Write each story's tests before its implementation tasks.
- Keep every story independently demoable at its checkpoint.
- Preserve audit, RBAC and sensitive file checks as non-negotiable acceptance gates.
- Use specs/001-prestgo-admin-backend/quickstart.md as the final end-to-end validation guide.
