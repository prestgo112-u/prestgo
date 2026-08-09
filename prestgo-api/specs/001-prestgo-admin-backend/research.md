# Research: PRESTGO Back-office Admin and Backend Services

## Decision: TypeScript monorepo with NestJS API and React admin

**Rationale**: The source cahier des charges explicitly targets a modular backend, a typed admin interface and shared contracts. A monorepo keeps API contracts, validation schemas and admin client integration close together while allowing separate deployments for the API and admin app.

**Alternatives considered**: Separate repositories for API and admin would reduce repository size but increase coordination overhead for contracts. A single full-stack app would be simpler initially but weaker for the modular API surface required by future public interfaces.

## Decision: PostgreSQL with PostGIS as system of record

**Rationale**: PRESTGO needs relational integrity for users, providers, missions, disputes, audit and permissions, plus geographic zone and radius-based search. PostgreSQL with PostGIS supports both needs without introducing a second primary datastore.

**Alternatives considered**: A document database would be flexible but less suitable for relational audit, permissions and status histories. Plain PostgreSQL without geographic extension would push location logic into application code.

## Decision: Prisma for data access and migrations

**Rationale**: The project needs a clear schema, repeatable migrations and typed access to a large relational model. Prisma provides a productive contract between the data model and TypeScript service layer.

**Alternatives considered**: Direct SQL offers maximum control but increases boilerplate and migration discipline needs. TypeORM is viable but less aligned with the source document recommendation.

## Decision: Redis and BullMQ for short-lived workflows and async jobs

**Rationale**: OTP flows, notification queues, short-lived cache and export/notification jobs should not block admin requests. Redis-backed queues fit these use cases and can be introduced incrementally.

**Alternatives considered**: Database-backed queues reduce infrastructure but add load to the primary database. A full message broker is heavier than needed for V1.

## Decision: RBAC with permission-level guards

**Rationale**: The specification requires roles such as super admin, admin, support, validation, moderator and read-only, while also requiring explicit permissions for sensitive actions. RBAC with fine-grained permissions supports both simple role assignment and auditable action control.

**Alternatives considered**: Role-only access is simpler but cannot model sensitive exceptions cleanly. Attribute-based access alone would be more flexible but too complex for the V1 back-office.

## Decision: OpenAPI contracts generated from the backend source of truth

**Rationale**: The future public and provider interfaces will consume the same backend rules and entities. Versioned OpenAPI contracts give the admin app and future clients a stable integration surface and support contract testing.

**Alternatives considered**: Informal endpoint documentation is faster but increases integration drift. GraphQL could reduce over-fetching but does not match the REST-oriented cahier des charges.

## Decision: Soft deactivation and immutable histories for operational entities

**Rationale**: Missions, users, providers, files, reviews and catalog entries appear in histories and audits. The system should prefer status changes and deactivation over destructive deletion when an entity has operational references.

**Alternatives considered**: Hard deletion is simpler but conflicts with auditability, support investigations and mission history.

## Decision: Explicit status machines for providers, missions, disputes and reviews

**Rationale**: The spec requires controlled transitions and motivated decisions. Status machines make invalid transitions testable and prevent admin actions from corrupting operational history.

**Alternatives considered**: Free-form status updates are easier to implement but weaken audit, support and data quality.

## Decision: Admin UI built around dense operational screens

**Rationale**: The back-office is an internal operations tool. It should prioritize searchable lists, filters, detail views, forms, moderation actions, audit visibility and fast task completion over marketing-style presentation.

**Alternatives considered**: Generic CRUD scaffolding would be quick but insufficient for provider validation, mission support and dispute workflows.
