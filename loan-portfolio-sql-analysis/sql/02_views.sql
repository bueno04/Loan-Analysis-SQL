-- Reporting views (SQLite dialect).
--
-- Every date calculation in the project lives in this file. The analysis and
-- data quality queries only read these views, so moving the project to another
-- SQL engine means rewriting this file only (see "Porting" in the README).

DROP VIEW IF EXISTS v_contract_status;
DROP VIEW IF EXISTS v_installment_status;
DROP VIEW IF EXISTS v_payments_clean;

-- 1) Payments that are safe to use in reporting:
--    - rows without a valid amount are excluded
--    - payments that do not match any installment are excluded
--    - exact duplicates (same installment, date and amount) count once
CREATE VIEW v_payments_clean AS
SELECT
    MIN(p.payment_id) AS payment_id,
    p.installment_id,
    p.payment_date,
    p.amount_paid
FROM payments p
JOIN installments i ON i.installment_id = p.installment_id
WHERE p.amount_paid IS NOT NULL
  AND p.amount_paid > 0
GROUP BY p.installment_id, p.payment_date, p.amount_paid;

-- 2) One row per installment with what was paid, what is still open,
--    days past due at the snapshot date and the aging bucket.
CREATE VIEW v_installment_status AS
WITH paid AS (
    SELECT
        installment_id,
        SUM(amount_paid)  AS amount_paid,
        MAX(payment_date) AS last_payment_date
    FROM v_payments_clean
    GROUP BY installment_id
),
base AS (
    SELECT
        i.installment_id,
        i.contract_id,
        i.installment_number,
        i.due_date,
        strftime('%Y-%m', i.due_date)          AS due_month,
        i.amount_due,
        COALESCE(p.amount_paid, 0)             AS amount_paid,
        p.last_payment_date,
        rp.snapshot_date,
        CASE WHEN COALESCE(p.amount_paid, 0) >= i.amount_due THEN i.amount_due
             ELSE COALESCE(p.amount_paid, 0) END AS collected_amount,
        CASE WHEN i.amount_due - COALESCE(p.amount_paid, 0) > 0.01
             THEN ROUND(i.amount_due - COALESCE(p.amount_paid, 0), 2)
             ELSE 0 END                        AS open_amount
    FROM installments i
    CROSS JOIN report_params rp
    LEFT JOIN paid p ON p.installment_id = i.installment_id
),
with_dpd AS (
    SELECT
        base.*,
        CASE WHEN open_amount > 0 AND due_date < snapshot_date
             THEN CAST(julianday(snapshot_date) - julianday(due_date) AS INTEGER)
             ELSE 0 END AS days_past_due
    FROM base
)
SELECT
    with_dpd.*,
    CASE WHEN days_past_due = 0   THEN 'Current'
         WHEN days_past_due <= 30 THEN '1-30 days'
         WHEN days_past_due <= 60 THEN '31-60 days'
         WHEN days_past_due <= 90 THEN '61-90 days'
         ELSE '90+ days' END AS aging_bucket,
    CASE WHEN days_past_due = 0   THEN 0
         WHEN days_past_due <= 30 THEN 1
         WHEN days_past_due <= 60 THEN 2
         WHEN days_past_due <= 90 THEN 3
         ELSE 4 END AS aging_bucket_order
FROM with_dpd;

-- 3) One row per contract: balances and worst delinquency at the snapshot date.
CREATE VIEW v_contract_status AS
SELECT
    c.contract_id,
    c.customer_id,
    c.product_type,
    c.equipment_type,
    c.origination_date,
    strftime('%Y', c.origination_date) || '-Q' ||
        ((CAST(strftime('%m', c.origination_date) AS INTEGER) + 2) / 3) AS origination_quarter,
    c.term_months,
    c.financed_amount,
    ROUND(SUM(s.open_amount), 2)                                         AS outstanding_amount,
    ROUND(SUM(CASE WHEN s.days_past_due > 0 THEN s.open_amount ELSE 0 END), 2) AS overdue_amount,
    MAX(s.days_past_due)                                                 AS max_days_past_due
FROM contracts c
JOIN v_installment_status s ON s.contract_id = c.contract_id
GROUP BY
    c.contract_id, c.customer_id, c.product_type, c.equipment_type,
    c.origination_date, c.term_months, c.financed_amount;
