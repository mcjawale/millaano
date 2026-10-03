-- ============================================================================
-- 0001_multi_tenancy.sql
-- MCJ Sahan Fleet Management System
--
-- PURPOSE
--   Introduce companies (tenants) so each company can create and manage its
--   own users and its own isolated fleet data. Lays the groundwork for turning
--   the system into a paid, packaged product (plans -> subscriptions ->
--   invoices) without requiring a second round of schema surgery.
--
-- STATUS
--   Sections A and B are SAFE to run: they only CREATE new tables and are
--   independent of the existing schema.
--   Section C (ALTER TABLE ...) and D (data backfill) are NOT yet verified
--   against the real database -- column and table names were inferred from the
--   live HTML form fields, not read from the schema. DO NOT RUN C OR D until
--   the source has been pulled down and `.schema` has been inspected.
--
-- CONVENTIONS
--   * All money is stored as INTEGER minor units (cents). Never REAL/FLOAT.
--   * Every tenant-owned row carries a non-null company_id with an index.
--   * ON DELETE CASCADE so deleting a company removes its data cleanly.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- SECTION A — safe to run now
-- ----------------------------------------------------------------------------

-- A1. The tenant itself ------------------------------------------------------
CREATE TABLE companies (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT    NOT NULL,
    slug            TEXT    NOT NULL UNIQUE,
    contact_email   TEXT,
    phone           TEXT,
    country         TEXT,
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),

    CHECK (is_active IN (0, 1))
);

-- A2. Users belong to exactly one company ------------------------------------
-- NOTE: assumes a `users` table already exists. If not, this block should be
-- merged into its full definition rather than run as an ALTER. Verify first.
--
-- Planned shape once verified:
--
--   ALTER TABLE users ADD COLUMN company_id INTEGER
--       REFERENCES companies(id) ON DELETE CASCADE;
--   ALTER TABLE users ADD COLUMN full_name    TEXT;
--   ALTER TABLE users ADD COLUMN role         TEXT    NOT NULL DEFAULT 'staff';
--   ALTER TABLE users ADD COLUMN is_active    INTEGER NOT NULL DEFAULT 1;
--   ALTER TABLE users ADD COLUMN last_login_at TEXT;
--   CREATE INDEX idx_users_company ON users(company_id);
--
-- Roles are about PERMISSION, not about plan limits (see plans below):
--   owner  - created the company; sole account that can delete the company or
--            change billing. Cannot be deleted or demoted.
--   admin  - full access within the company, including user management.
--   staff  - day-to-day operations, cannot manage users.
--   viewer - read-only.
-- Suggested CHECK: role IN ('owner','admin','staff','viewer')

-- A3. Audit log --------------------------------------------------------------
-- Not optional for a paid product: you need to answer "who did this, when".
CREATE TABLE audit_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    company_id  INTEGER NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id     INTEGER REFERENCES users(id) ON DELETE SET NULL,
    action      TEXT    NOT NULL,          -- e.g. 'trip.create', 'user.delete'
    entity      TEXT,                      -- e.g. 'trip'
    entity_id   TEXT,
    detail      TEXT,                      -- JSON blob, no secrets/passwords
    ip_address  TEXT,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_audit_company ON audit_log(company_id, created_at DESC);
CREATE INDEX idx_audit_entity  ON audit_log(company_id, entity, entity_id);


-- ----------------------------------------------------------------------------
-- SECTION B — safe to run now: packaging / billing scaffolding.
--
-- These tables stay EMPTY until you actually start charging. Adding them now
-- means going commercial later is a matter of wiring a payment provider to
-- tables that already exist, rather than restructuring live customer data.
-- ----------------------------------------------------------------------------

-- B1. Plan catalogue ---------------------------------------------------------
-- Limits live here, NOT in the roles table.
CREATE TABLE plans (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    code                TEXT    NOT NULL UNIQUE,     -- 'free', 'standard', 'fleet'
    name                TEXT    NOT NULL,
    price_cents         INTEGER NOT NULL DEFAULT 0, -- per month
    currency            TEXT    NOT NULL DEFAULT 'USD',
    trial_days          INTEGER NOT NULL DEFAULT 0,

    -- Quotas. Use -1 for "unlimited" rather than NULL, so comparison is simple.
    max_vehicles        INTEGER NOT NULL DEFAULT -1,
    max_users           INTEGER NOT NULL DEFAULT -1,
    max_trips_per_month INTEGER NOT NULL DEFAULT -1,
    max_storage_mb      INTEGER NOT NULL DEFAULT -1,

    -- Capability flags, data-driven so you never hardcode `if plan == ...`.
    -- Suggested keys: gps_tracking, fuel_analytics, maintenance_scheduling,
    --                 api_access, white_label, pdf_exports, multi_branch.
    features            TEXT    NOT NULL DEFAULT '{}',   -- JSON object
    is_active           INTEGER NOT NULL DEFAULT 1,
    sort_order          INTEGER NOT NULL DEFAULT 0,

    CHECK (price_cents >= 0),
    CHECK (is_active IN (0, 1))
);

-- B2. A company's current subscription --------------------------------------
CREATE TABLE subscriptions (
    id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    company_id             INTEGER NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    plan_id                INTEGER NOT NULL REFERENCES plans(id),

    status                 TEXT    NOT NULL DEFAULT 'trialing',
    -- trialing | active | past_due | canceled | expired
    started_at             TEXT    NOT NULL DEFAULT (datetime('now')),
    current_period_start   TEXT    NOT NULL,
    current_period_end     TEXT    NOT NULL,
    cancel_at_period_end   INTEGER NOT NULL DEFAULT 0,
    canceled_at            TEXT,

    -- Payment provider bookkeeping. NULL while on a manual/free plan.
    provider               TEXT,                       -- 'stripe', 'manual'
    provider_customer_id   TEXT,
    provider_subscription_id TEXT UNIQUE,

    CHECK (status IN ('trialing','active','past_due','canceled','expired')),
    CHECK (cancel_at_period_end IN (0, 1))
);

-- Enforce exactly one live subscription per company.
CREATE UNIQUE INDEX idx_sub_active_company
    ON subscriptions(company_id)
    WHERE status IN ('trialing','active','past_due');

-- B3. Invoices ---------------------------------------------------------------
CREATE TABLE invoices (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    company_id         INTEGER NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    subscription_id    INTEGER REFERENCES subscriptions(id) ON DELETE SET NULL,
    number             TEXT    NOT NULL UNIQUE,          -- INV-2026-0001
    amount_cents       INTEGER NOT NULL,
    currency           TEXT    NOT NULL DEFAULT 'USD',
    status             TEXT    NOT NULL DEFAULT 'draft',
    -- draft | open | paid | void | uncollectible
    period_start       TEXT,
    period_end         TEXT,
    issued_at          TEXT,
    paid_at            TEXT,
    provider_invoice_id TEXT UNIQUE,

    CHECK (amount_cents >= 0),
    CHECK (status IN ('draft','open','paid','void','uncollectible'))
);

CREATE INDEX idx_invoices_company ON invoices(company_id, issued_at DESC);

-- B4. Seed the plan catalogue -----------------------------------------------
INSERT INTO plans (code, name, price_cents, trial_days,
                   max_vehicles, max_users, max_trips_per_month, features, sort_order)
VALUES
    ('free', 'Free',     0,   0,   2,    2,   -1,                 '{}', 1),
    ('standard', 'Standard', 2900, 14, 25,  10,  500,
        '{"pdf_exports":true,"maintenance_scheduling":true}', 2),
    ('fleet', 'Fleet',   9900, 14, -1,   -1,  -1,
        '{"pdf_exports":true,"maintenance_scheduling":true,"gps_tracking":true,"fuel_analytics":true,"api_access":true,"multi_branch":true}', 3);

-- Every new signup starts on the free plan.
INSERT INTO subscriptions (company_id, plan_id, status,
                           current_period_start, current_period_end)
SELECT c.id, p.id, 'active', date('now'), date('now', '+100 years')
FROM companies c
CROSS JOIN plans p
WHERE p.code = 'free';


-- ----------------------------------------------------------------------------
-- SECTION C -- DO NOT RUN YET. Requires the real schema.
--
-- Add tenant scoping to every business table. For each, you need:
--   1. company_id INTEGER NOT NULL REFERENCES companies(id) ON DELETE CASCADE
--   2. an index on company_id
--   3. every existing row backfilled to the default company (Section D)
--
-- Tables that need this, per the live form fields:
--   vehicles             (plate_no, make, model, year, capacity, odometer)
--   drivers              (name, phone, licence_no, licence_expiry)
--   routes
--   trips                (departure_at, arrival_at, distance_km, revenue, cost)
--   bookings             (passenger_name, phone, pickup, dropoff, seats, fare)
--   fuel_records
--   maintenance_records
--
-- Example shape, once table names are confirmed:
--
--   ALTER TABLE trips ADD COLUMN company_id INTEGER
--       REFERENCES companies(id) ON DELETE CASCADE;
--   CREATE INDEX idx_trips_company ON trips(company_id);
--
-- ALSO verify in the same pass: money columns (revenue, cost, fare, amount).
-- If they are REAL, convert to INTEGER cents before you store any real money.
--   ALTER TABLE trips RENAME COLUMN revenue TO revenue_old;
--   ALTER TABLE trips ADD COLUMN revenue_cents INTEGER;
--   UPDATE trips SET revenue_cents = CAST(ROUND(revenue * 100) AS INTEGER);
-- ----------------------------------------------------------------------------


-- ----------------------------------------------------------------------------
-- SECTION D -- DO NOT RUN YET. Requires the real schema.
--
-- Backfill existing data into a default company, then make that company own it.
-- Everything currently in the database belongs to MCJ Sahan today.
--
--   INSERT INTO companies (name, slug, is_active)
--       VALUES ('MCJ Sahan', 'mcj-sahan', 1);
--
--   -- attach the existing admin as 'owner' of that company
--   UPDATE users
--      SET company_id = (SELECT id FROM companies WHERE slug = 'mcj-sahan'),
--          role = 'owner'
--    WHERE username = 'admin';
--
--   UPDATE trips            SET company_id = (SELECT id FROM companies WHERE slug='mcj-sahan');
--   UPDATE bookings         SET company_id = (SELECT id FROM companies WHERE slug='mcj-sahan');
--   UPDATE vehicles         SET company_id = (SELECT id FROM companies WHERE slug='mcj-sahan');
--   UPDATE drivers          SET company_id = (SELECT id FROM companies WHERE slug='mcj-sahan');
--   UPDATE routes           SET company_id = (SELECT id FROM companies WHERE slug='mcj-sahan');
--   UPDATE fuel_records     SET company_id = (SELECT id FROM companies WHERE slug='mcj-sahan');
--   UPDATE maintenance_records SET company_id = (SELECT id FROM companies WHERE slug='mcj-sahan');
--
-- Then enforce NOT NULL on each company_id so a row can never be orphaned.
-- ----------------------------------------------------------------------------


-- ----------------------------------------------------------------------------
-- Notes for the application layer (not enforceable in SQL)
-- ----------------------------------------------------------------------------
--
-- * TENANT URL STRATEGY -- decided, do not revisit casually.
--
--   Companies get a slug-based path, NOT a subdomain:
--       /app/<slug>/trips, /app/<slug>/fleet/vehicles, ...
--
--   Why: PythonAnywhere has no wildcard subdomain support. Every distinct
--   hostname needs its own web app entry on the Web tab plus its own DNS
--   record, which would mean manually provisioning infrastructure for each new
--   customer. That defeats self-service signup.
--   (Cloudflare wildcard DNS is also unavailable on pythonanywhere.com hosts.)
--
--   Because companies are added at any time and subscribers will follow, the
--   slug path is the only option that scales without per-customer ops work.
--
--   TO KEEP THIS CHEAP TO REVERSE, all tenant resolution must live in exactly
--   one module that:
--     1. extracts a slug from the URL,
--     2. looks up companies.id for it,
--     3. assigns g.company_id / g.company for the request,
--     4. rejects unknown or inactive slugs.
--   Routes must never re-derive the tenant themselves. If the business later
--   moves to infrastructure with wildcard DNS, migrating to true subdomains
--   should mean editing only that module, not every blueprint.
--
--   Picking a subdomain earlier would be a cheaper move on Fly.io/Render-style
--   hosting, but is a costly one on PythonAnywhere.
--
-- * Self-signup must create the company AND its first 'owner' user in a single
--   transaction. A company with no owner is unmanageable.
--
-- * The session stores user_id + company_id. NEVER read company_id from a
--   form field or URL to decide what data to show -- that is a data leak.
--   Derive it from the authenticated user on every request.
--
-- * Enforce quotas at the write path (count rows for company, compare against
--   the plan limit, reject with a clear message). Rely on the indexes above so
--   COUNT stays cheap.
--
-- * Gate features through a helper that reads plans.features, e.g.
--       plan_allows(company, 'gps_tracking')
--   rather than hardcoding plan checks into templates.
--
-- * Never store a plaintext or unhashed password. Use
--   werkzeug.security.generate_password_hash / check_password_hash.
--
-- * Delete the default admin/admin123 account before going live, or force a
--   password reset on first login.