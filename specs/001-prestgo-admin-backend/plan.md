# Implementation Plan: PRESTGO Back-office Admin and Backend Services

**Branch**: `001-prestgo-admin-backend` | **Date**: 2026-06-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-prestgo-admin-backend/spec.md`

## Summary

Build the PRESTGO V1 operational backbone: a centralized backend service and an internal web back-office for secure administration, provider validation, mission supervision, dispute handling, review moderation, catalog and zone management, notifications, audit, settings and exports. The technical approach is a TypeScript monorepo with a NestJS API, PostgreSQL/PostGIS persistence, Prisma data access, Redis-backed short-lived workflows, and a React admin app consuming documented versioned contracts.

## Technical Context

**Language/Version**: TypeScript 5.x on Node.js 22 LTS for backend and admin web.

**Primary Dependencies**: NestJS, Prisma, PostgreSQL/PostGIS, Redis, BullMQ, React, Vite, TanStack Query, TanStack Table, React Hook Form, Zod, Tailwind CSS with shadcn/ui or Material UI, Swagger/OpenAPI.

**Storage**: PostgreSQL with PostGIS for relational data and geographic search; Redis for OTP, cache, queues and async notification jobs; object/file storage abstraction for uploaded documents and attachments.

**Testing**: Unit tests for domain services and validation, contract tests from OpenAPI, integration tests against API modules and database behavior, end-to-end tests for critical admin workflows.

**Target Platform**: Web-based internal admin and backend service deployable to Linux server/container environments.

**Project Type**: Web application with backend service and admin frontend in a monorepo.

**Performance Goals**: 95% of common admin filtered lists visible in under 2 seconds under normal operational volume; provider validation workflow completable in under 5 minutes; mission lookup and history retrieval in under 2 minutes by support staff.

**Constraints**: All admin actions require authentication and permission checks; sensitive file access must be explicit; all sensitive actions are audited; all admin lists are paginated and filter-controlled; V1 excludes financial integrations and advanced premium/live/recommendation modules.

**Scale/Scope**: V1 covers auth, users, roles, clients, providers, documents, catalog, zones, availability, missions, messages, reviews, disputes, notifications, files, settings, audit and operational exports.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The current constitution file is still the default unratified template and does not define enforceable project gates. Planning therefore applies the feature-level constraints from the specification and source cahier des charges:

- PASS: Scope is bounded to backend services and internal back-office V1.
- PASS: Sensitive actions require explicit permissions and audit records.
- PASS: Public client/provider interfaces, financial integrations and advanced modules remain out of scope.
- PASS: Contracts, data model and quickstart validation artifacts are produced before implementation tasks.

Post-design re-check: PASS. The research, data model, contracts and quickstart preserve the same scope and do not introduce out-of-scope financial, premium, shop, insurance, live video or recommendation capabilities.

## Project Structure

### Documentation (this feature)

```text
specs/001-prestgo-admin-backend/
|-- plan.md
|-- research.md
|-- data-model.md
|-- quickstart.md
|-- contracts/
|   `-- openapi.yaml
|-- checklists/
|   `-- requirements.md
`-- tasks.md
```

### Source Code (repository root)

```text
apps/
|-- api/
|   |-- src/
|   |   |-- modules/
|   |   |   |-- auth/
|   |   |   |-- users/
|   |   |   |-- admin/
|   |   |   |-- roles/
|   |   |   |-- clients/
|   |   |   |-- providers/
|   |   |   |-- documents/
|   |   |   |-- catalog/
|   |   |   |-- zones/
|   |   |   |-- availability/
|   |   |   |-- missions/
|   |   |   |-- messages/
|   |   |   |-- reviews/
|   |   |   |-- disputes/
|   |   |   |-- notifications/
|   |   |   |-- files/
|   |   |   |-- settings/
|   |   |   |-- audit/
|   |   |   `-- reports/
|   |   |-- common/
|   |   `-- prisma/
|   `-- tests/
|       |-- contract/
|       |-- integration/
|       `-- unit/
`-- admin/
    |-- src/
    |   |-- app/
    |   |-- components/
    |   |-- features/
    |   |   |-- dashboard/
    |   |   |-- users/
    |   |   |-- providers/
    |   |   |-- catalog/
    |   |   |-- zones/
    |   |   |-- missions/
    |   |   |-- messages/
    |   |   |-- reviews/
    |   |   |-- disputes/
    |   |   |-- notifications/
    |   |   |-- settings/
    |   |   |-- audit/
    |   |   `-- exports/
    |   |-- lib/
    |   `-- routes/
    `-- tests/
        |-- e2e/
        `-- component/

packages/
|-- contracts/
|-- config/
`-- test-utils/
```

**Structure Decision**: Use a TypeScript monorepo with separate deployable apps for API and admin UI, plus shared packages for generated contracts, common configuration and test utilities. This keeps backend and back-office delivery coordinated while preserving clear module boundaries.

## Complexity Tracking

No constitution violations identified. The monorepo structure is justified by the feature scope: one backend service, one admin web app, shared contracts and shared test/config tooling.
