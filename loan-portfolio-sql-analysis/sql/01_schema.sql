-- Schema for the equipment-financing portfolio.
-- Dates are stored as ISO text (YYYY-MM-DD), which SQLite compares correctly.

DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS installments;
DROP TABLE IF EXISTS contracts;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS report_params;

CREATE TABLE customers (
    customer_id     INTEGER PRIMARY KEY,
    segment         TEXT NOT NULL,      -- Agriculture, Construction, Landscaping
    state           TEXT NOT NULL,
    credit_rating   TEXT NOT NULL,      -- A (best) to D (worst)
    customer_since  DATE NOT NULL
);

CREATE TABLE contracts (
    contract_id           INTEGER PRIMARY KEY,
    customer_id           INTEGER NOT NULL REFERENCES customers (customer_id),
    product_type          TEXT NOT NULL,     -- Installment Loan, Lease
    equipment_type        TEXT NOT NULL,
    origination_date      DATE NOT NULL,
    term_months           INTEGER NOT NULL,
    financed_amount       NUMERIC NOT NULL,
    annual_interest_rate  NUMERIC NOT NULL,
    status                TEXT NOT NULL      -- Active, Closed
);

CREATE TABLE installments (
    installment_id      INTEGER PRIMARY KEY,
    contract_id         INTEGER NOT NULL REFERENCES contracts (contract_id),
    installment_number  INTEGER NOT NULL,
    due_date            DATE NOT NULL,
    amount_due          NUMERIC NOT NULL
);

-- No foreign key on installment_id on purpose: the source file contains
-- orphan payments, and the data quality checks need to be able to load them.
CREATE TABLE payments (
    payment_id      INTEGER PRIMARY KEY,
    installment_id  INTEGER NOT NULL,
    payment_date    DATE NOT NULL,
    amount_paid     NUMERIC
);

-- Single-row table holding the reporting (snapshot) date.
CREATE TABLE report_params (
    snapshot_date DATE NOT NULL
);
INSERT INTO report_params (snapshot_date) VALUES ('2026-10-31');
