-- Portfolio analysis queries.
-- Each query starts with a "-- name:" line; run_analysis.py runs them one by
-- one and saves each result to output/<name>.csv.
-- All amounts are in BRL. "Overdue" means open and past the due date at the
-- snapshot date stored in report_params.

-- name: 01_portfolio_overview
-- Size and health of the portfolio by product type.
SELECT
    product_type,
    COUNT(*)                                                    AS contracts,
    ROUND(SUM(financed_amount), 2)                              AS financed_amount,
    ROUND(SUM(outstanding_amount), 2)                           AS outstanding_amount,
    ROUND(SUM(overdue_amount), 2)                               AS overdue_amount,
    ROUND(100.0 * SUM(overdue_amount) / SUM(outstanding_amount), 2) AS overdue_pct_of_outstanding
FROM v_contract_status
GROUP BY product_type
ORDER BY outstanding_amount DESC;

-- name: 02_aging_buckets
-- Aging of open receivables: how much is current and how much is late, by bucket.
SELECT
    aging_bucket,
    COUNT(DISTINCT contract_id)                                 AS contracts,
    COUNT(*)                                                    AS open_installments,
    ROUND(SUM(open_amount), 2)                                  AS open_amount,
    ROUND(100.0 * SUM(open_amount) / SUM(SUM(open_amount)) OVER (), 2) AS pct_of_open_amount
FROM v_installment_status
WHERE open_amount > 0
GROUP BY aging_bucket, aging_bucket_order
ORDER BY aging_bucket_order;

-- name: 03_delinquency_by_segment_and_rating
-- Share of contracts more than 30 days past due, by customer segment and credit rating.
SELECT
    cu.segment,
    cu.credit_rating,
    COUNT(*)                                                    AS contracts,
    SUM(CASE WHEN cs.max_days_past_due > 30 THEN 1 ELSE 0 END)  AS contracts_over_30_dpd,
    ROUND(100.0 * SUM(CASE WHEN cs.max_days_past_due > 30 THEN 1 ELSE 0 END) / COUNT(*), 2)
                                                                AS pct_contracts_over_30_dpd,
    ROUND(SUM(cs.overdue_amount), 2)                            AS overdue_amount
FROM v_contract_status cs
JOIN customers cu ON cu.customer_id = cs.customer_id
GROUP BY cu.segment, cu.credit_rating
ORDER BY cu.segment, cu.credit_rating;

-- name: 04_monthly_collection_trend
-- Amount billed vs. collected per due month, with a 3-month moving average
-- and the month-over-month change of the collection rate.
WITH monthly AS (
    SELECT
        due_month,
        SUM(amount_due)       AS billed_amount,
        SUM(collected_amount) AS collected_amount
    FROM v_installment_status
    WHERE due_date <= snapshot_date
    GROUP BY due_month
),
rates AS (
    SELECT
        due_month,
        billed_amount,
        collected_amount,
        100.0 * collected_amount / billed_amount AS collection_rate
    FROM monthly
)
SELECT
    due_month,
    ROUND(billed_amount, 2)                                     AS billed_amount,
    ROUND(collected_amount, 2)                                  AS collected_amount,
    ROUND(collection_rate, 2)                                   AS collection_rate_pct,
    ROUND(AVG(collection_rate) OVER (
        ORDER BY due_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)
                                                                AS collection_rate_3m_avg,
    ROUND(collection_rate - LAG(collection_rate) OVER (ORDER BY due_month), 2)
                                                                AS change_vs_prior_month_pp
FROM rates
ORDER BY due_month;

-- name: 05_top10_customers_by_overdue
-- Largest overdue exposures and how concentrated the overdue balance is.
WITH by_customer AS (
    SELECT
        cu.customer_id,
        cu.segment,
        cu.state,
        cu.credit_rating,
        COUNT(*)                   AS contracts,
        SUM(cs.overdue_amount)     AS overdue_amount,
        MAX(cs.max_days_past_due)  AS max_days_past_due
    FROM v_contract_status cs
    JOIN customers cu ON cu.customer_id = cs.customer_id
    GROUP BY cu.customer_id, cu.segment, cu.state, cu.credit_rating
    HAVING SUM(cs.overdue_amount) > 0
)
SELECT
    RANK() OVER (ORDER BY overdue_amount DESC)                  AS overdue_rank,
    customer_id,
    segment,
    state,
    credit_rating,
    contracts,
    ROUND(overdue_amount, 2)                                    AS overdue_amount,
    max_days_past_due,
    ROUND(100.0 * overdue_amount / SUM(overdue_amount) OVER (), 2) AS pct_of_total_overdue
FROM by_customer
ORDER BY overdue_rank
LIMIT 10;

-- name: 06_vintage_90dpd_by_origination_quarter
-- Vintage view: share of contracts 90+ days past due, by origination quarter.
SELECT
    origination_quarter,
    COUNT(*)                                                    AS contracts,
    SUM(CASE WHEN max_days_past_due > 90 THEN 1 ELSE 0 END)     AS contracts_over_90_dpd,
    ROUND(100.0 * SUM(CASE WHEN max_days_past_due > 90 THEN 1 ELSE 0 END) / COUNT(*), 2)
                                                                AS pct_contracts_over_90_dpd
FROM v_contract_status
GROUP BY origination_quarter
ORDER BY origination_quarter;
