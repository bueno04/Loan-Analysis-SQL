-- Data quality checks on the raw tables.
-- Each check returns the offending rows; dq_00_summary counts them.
-- These run against the raw tables on purpose: the reporting views already
-- filter or neutralise these problems, and the checks show what was filtered.

-- name: dq_00_summary
SELECT 'Duplicate payment records' AS check_name, COUNT(*) AS issues
FROM (
    SELECT installment_id
    FROM payments
    GROUP BY installment_id, payment_date, amount_paid
    HAVING COUNT(*) > 1
) d
UNION ALL
SELECT 'Payments without a matching installment', COUNT(*)
FROM payments p
LEFT JOIN installments i ON i.installment_id = p.installment_id
WHERE i.installment_id IS NULL
UNION ALL
SELECT 'Payments with missing or non-positive amount', COUNT(*)
FROM payments
WHERE amount_paid IS NULL OR amount_paid <= 0
UNION ALL
SELECT 'Installments paid above the amount due', COUNT(*)
FROM v_installment_status
WHERE amount_paid > amount_due + 0.01
UNION ALL
SELECT 'Contracts whose installment count differs from the term', COUNT(*)
FROM (
    SELECT c.contract_id
    FROM contracts c
    LEFT JOIN installments i ON i.contract_id = c.contract_id
    GROUP BY c.contract_id, c.term_months
    HAVING COUNT(i.installment_id) <> c.term_months
) m
UNION ALL
SELECT 'Payments dated before the contract origination', COUNT(*)
FROM payments p
JOIN installments i ON i.installment_id = p.installment_id
JOIN contracts c ON c.contract_id = i.contract_id
WHERE p.payment_date < c.origination_date;

-- name: dq_01_duplicate_payments
SELECT
    installment_id,
    payment_date,
    amount_paid,
    COUNT(*)        AS records,
    MIN(payment_id) AS first_payment_id,
    MAX(payment_id) AS last_payment_id
FROM payments
GROUP BY installment_id, payment_date, amount_paid
HAVING COUNT(*) > 1
ORDER BY installment_id;

-- name: dq_02_orphan_payments
SELECT p.payment_id, p.installment_id, p.payment_date, p.amount_paid
FROM payments p
LEFT JOIN installments i ON i.installment_id = p.installment_id
WHERE i.installment_id IS NULL
ORDER BY p.payment_id;

-- name: dq_03_missing_or_invalid_amounts
SELECT payment_id, installment_id, payment_date, amount_paid
FROM payments
WHERE amount_paid IS NULL OR amount_paid <= 0
ORDER BY payment_id;

-- name: dq_04_overpayments
SELECT
    installment_id,
    contract_id,
    due_date,
    amount_due,
    ROUND(amount_paid, 2)              AS amount_paid,
    ROUND(amount_paid - amount_due, 2) AS excess_amount
FROM v_installment_status
WHERE amount_paid > amount_due + 0.01
ORDER BY excess_amount DESC;

-- name: dq_05_installment_count_mismatch
SELECT
    c.contract_id,
    c.term_months,
    COUNT(i.installment_id) AS installments_found
FROM contracts c
LEFT JOIN installments i ON i.contract_id = c.contract_id
GROUP BY c.contract_id, c.term_months
HAVING COUNT(i.installment_id) <> c.term_months
ORDER BY c.contract_id;

-- name: dq_06_payment_before_origination
SELECT
    p.payment_id,
    i.contract_id,
    c.origination_date,
    p.payment_date,
    p.amount_paid
FROM payments p
JOIN installments i ON i.installment_id = p.installment_id
JOIN contracts c ON c.contract_id = i.contract_id
WHERE p.payment_date < c.origination_date
ORDER BY p.payment_id;
