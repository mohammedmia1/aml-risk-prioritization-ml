/*
===============================================================================
AML RISK PRIORITIZATION - SQL DATA ENGINEERING PIPELINE
===============================================================================
Purpose
-------
Transform synthetic transaction-level AML data into leakage-aware account-day
features for temporal model development and a later OOD monitoring period.

Portfolio notes
---------------
1. The raw table was loaded before this script. Early Workbench import attempts
   encountered truncation/schema issues; the working ingestion path used an
   explicit schema plus LOAD DATA LOCAL INFILE.
2. This script intentionally keeps validation queries beside transformations so
   each major table/view can be reconciled before the next stage.
3. Sep. 1-10 is the model-development population. Sep. 11-18 is kept separate
   for OOD monitoring and is never used to tune the final model.
4. account_id and activity_date remain metadata for traceability/splitting; they
   are not model predictors.

Expected raw table columns
--------------------------
transaction_timestamp, from_bank, from_account, to_bank, to_account,
amount_received, receiving_currency, amount_paid, payment_currency,
payment_format, is_laundering
===============================================================================
*/

USE aml_portfolio;

-- OPTIONAL SERVER SETUP: requires appropriate MySQL privileges.
SET GLOBAL local_infile = 1;
SHOW GLOBAL VARIABLES LIKE 'local_infile';

-- ============================================================================
-- 01. RAW-DATA INTEGRITY AND HIGH-LEVEL PROFILING
-- ============================================================================
SELECT
    COUNT(*) AS total_rows,

    MIN(transaction_timestamp) AS min_timestamp,
    MAX(transaction_timestamp) AS max_timestamp,

    MIN(amount_received) AS min_amount_received,
    MAX(amount_received) AS max_amount_received,

    MIN(amount_paid) AS min_amount_paid,
    MAX(amount_paid) AS max_amount_paid,

    SUM(CASE WHEN is_laundering = 0 THEN 1 ELSE 0 END) AS non_laundering_rows,
    SUM(CASE WHEN is_laundering = 1 THEN 1 ELSE 0 END) AS laundering_rows,

    ROUND(
        SUM(CASE WHEN is_laundering = 0 THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*),
        4
    ) AS non_laundering_pct,

    ROUND(
        SUM(CASE WHEN is_laundering = 1 THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*),
        4
    ) AS laundering_pct

FROM raw_transactions;



-- =========================================================
-- 1. CORE ENTITY COUNTS
-- =========================================================
SELECT
    COUNT(DISTINCT from_account) AS unique_sending_accounts,
    COUNT(DISTINCT to_account) AS unique_receiving_accounts,
    COUNT(DISTINCT from_bank) AS unique_sending_banks,
    COUNT(DISTINCT to_bank) AS unique_receiving_banks
FROM raw_transactions;


-- =========================================================
-- 2. CURRENCIES
-- =========================================================
SELECT
    payment_currency AS currency,
    COUNT(*) AS transaction_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM raw_transactions), 4) AS pct_of_transactions
FROM raw_transactions
GROUP BY payment_currency
ORDER BY transaction_count DESC;


-- =========================================================
-- 3. PAYMENT FORMATS
-- =========================================================
SELECT
    payment_format,
    COUNT(*) AS transaction_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM raw_transactions), 4) AS pct_of_transactions
FROM raw_transactions
GROUP BY payment_format
ORDER BY transaction_count DESC;


-- =========================================================
-- 4. TRANSACTION ACTIVITY BY DAY
-- =========================================================
SELECT
    DATE(transaction_timestamp) AS transaction_date,
    COUNT(*) AS transaction_count,
    SUM(is_laundering) AS laundering_transactions,
    ROUND(
        SUM(is_laundering) * 100.0 / COUNT(*),
        4
    ) AS laundering_rate_pct
FROM raw_transactions
GROUP BY DATE(transaction_timestamp)
ORDER BY transaction_date;


-- =========================================================
-- 5. HIGH-LEVEL LAUNDERING VS NON-LAUNDERING PROFILE
-- =========================================================
SELECT
    is_laundering,

    COUNT(*) AS transaction_count,

    ROUND(AVG(amount_paid), 2) AS avg_amount_paid,
    ROUND(MIN(amount_paid), 6) AS min_amount_paid,
    ROUND(MAX(amount_paid), 6) AS max_amount_paid,

    COUNT(DISTINCT from_account) AS unique_senders,
    COUNT(DISTINCT to_account) AS unique_receivers,

    COUNT(DISTINCT from_bank) AS unique_from_banks,
    COUNT(DISTINCT to_bank) AS unique_to_banks,

    COUNT(DISTINCT payment_currency) AS currencies_used,
    COUNT(DISTINCT payment_format) AS payment_formats_used

FROM raw_transactions
GROUP BY is_laundering;



SELECT
    CASE
        WHEN DATE(transaction_timestamp) <= '2022-09-10'
            THEN 'Sep 01-10'
        ELSE 'Sep 11-18'
    END AS period,

    COUNT(*) AS transactions,
    SUM(is_laundering) AS laundering_transactions,
    SUM(is_laundering = 0) AS normal_transactions,

    COUNT(DISTINCT from_account) AS unique_senders,
    COUNT(DISTINCT to_account) AS unique_receivers,

    ROUND(AVG(amount_paid), 2) AS avg_amount,
    COUNT(DISTINCT payment_format) AS payment_formats,
    COUNT(DISTINCT payment_currency) AS currencies

FROM raw_transactions

GROUP BY
    CASE
        WHEN DATE(transaction_timestamp) <= '2022-09-10'
            THEN 'Sep 01-10'
        ELSE 'Sep 11-18'
    END;
    
  -- ============================================================================
-- 02. ACCOUNT-CENTRIC TRANSACTION VIEW
-- Each raw transaction is represented from both sender and receiver perspectives.
-- ============================================================================

CREATE INDEX idx_from_account_time
ON raw_transactions (from_account, transaction_timestamp);

CREATE INDEX idx_to_account_time
ON raw_transactions (to_account, transaction_timestamp);



CREATE OR REPLACE VIEW vw_account_transactions AS

-- Sender perspective
SELECT
    transaction_timestamp,
    DATE(transaction_timestamp) AS activity_date,

    from_account AS account_id,
    from_bank AS account_bank,

    to_account AS counterparty_account,
    to_bank AS counterparty_bank,

    'OUTGOING' AS direction,

    amount_paid AS amount,
    payment_currency AS currency,
    payment_format,

    CASE
        WHEN from_bank <> to_bank THEN 1
        ELSE 0
    END AS is_cross_bank,

    is_laundering

FROM raw_transactions

UNION ALL

-- Receiver perspective
SELECT
    transaction_timestamp,
    DATE(transaction_timestamp) AS activity_date,

    to_account AS account_id,
    to_bank AS account_bank,

    from_account AS counterparty_account,
    from_bank AS counterparty_bank,

    'INCOMING' AS direction,

    amount_received AS amount,
    receiving_currency AS currency,
    payment_format,

    CASE
        WHEN from_bank <> to_bank THEN 1
        ELSE 0
    END AS is_cross_bank,

    is_laundering

FROM raw_transactions;




SELECT *
FROM vw_account_transactions
LIMIT 20;


SELECT
    direction,
    COUNT(*) AS rows_by_direction
FROM vw_account_transactions
GROUP BY direction;



USE aml_portfolio;

-- ============================================================================
-- 03. DEVELOPMENT ACCOUNT-DAY FEATURE TABLE (SEP. 1-10)
-- ============================================================================
DROP TABLE IF EXISTS account_daily_features_dev;

CREATE TABLE account_daily_features_dev AS

WITH dev_transactions AS (
    SELECT *
    FROM vw_account_transactions
    WHERE transaction_timestamp >= '2022-09-01 00:00:00'
      AND transaction_timestamp <  '2022-09-11 00:00:00'
),

ordered_activity AS (
    SELECT
        *,
        LAG(transaction_timestamp) OVER (
            PARTITION BY account_id, activity_date
            ORDER BY transaction_timestamp
        ) AS previous_transaction_timestamp
    FROM dev_transactions
)

SELECT
    account_id,
    activity_date,

    COUNT(*) AS transaction_count,

    SUM(CASE WHEN direction = 'OUTGOING' THEN 1 ELSE 0 END)
        AS outgoing_count,

    SUM(CASE WHEN direction = 'INCOMING' THEN 1 ELSE 0 END)
        AS incoming_count,

    SUM(CASE WHEN direction = 'OUTGOING' THEN amount ELSE 0 END)
        AS total_sent,

    SUM(CASE WHEN direction = 'INCOMING' THEN amount ELSE 0 END)
        AS total_received,

    AVG(amount)
        AS avg_transaction_amount,

    MAX(amount)
        AS max_transaction_amount,

    COUNT(DISTINCT counterparty_account)
        AS unique_counterparties,

    COUNT(DISTINCT counterparty_bank)
        AS unique_banks,

    COUNT(DISTINCT currency)
        AS currency_diversity,

    COUNT(DISTINCT payment_format)
        AS payment_format_diversity,

    SUM(CASE WHEN direction = 'OUTGOING' THEN amount ELSE 0 END)
    /
    NULLIF(
        SUM(CASE WHEN direction = 'INCOMING' THEN amount ELSE 0 END),
        0
    ) AS sent_received_ratio,

    SUM(
        CASE
            WHEN previous_transaction_timestamp IS NOT NULL
             AND TIMESTAMPDIFF(
                    MINUTE,
                    previous_transaction_timestamp,
                    transaction_timestamp
                 ) <= 10
            THEN 1
            ELSE 0
        END
    ) AS rapid_transaction_count,

    AVG(is_cross_bank)
        AS cross_bank_ratio,

    MAX(is_laundering)
        AS has_laundering_tx

FROM ordered_activity

GROUP BY
    account_id,
    activity_date;
    
    
    
    
    
SELECT
    COUNT(*) AS feature_rows,
    COUNT(DISTINCT account_id) AS unique_accounts,
    MIN(activity_date) AS min_date,
    MAX(activity_date) AS max_date,
    SUM(has_laundering_tx = 1) AS positive_rows,
    SUM(has_laundering_tx = 0) AS negative_rows,
    ROUND(
        SUM(has_laundering_tx = 1) * 100.0 / COUNT(*),
        4
    ) AS positive_rate_pct,

    SUM(transaction_count IS NULL) AS null_transaction_count,
    SUM(total_sent IS NULL) AS null_total_sent,
    SUM(total_received IS NULL) AS null_total_received,
    SUM(avg_transaction_amount IS NULL) AS null_avg_amount,
    SUM(max_transaction_amount IS NULL) AS null_max_amount,
    SUM(unique_counterparties IS NULL) AS null_counterparties,
    SUM(unique_banks IS NULL) AS null_banks,
    SUM(currency_diversity IS NULL) AS null_currency_diversity,
    SUM(payment_format_diversity IS NULL) AS null_format_diversity,
    SUM(sent_received_ratio IS NULL) AS null_sent_received_ratio,
    SUM(rapid_transaction_count IS NULL) AS null_rapid_count,
    SUM(cross_bank_ratio IS NULL) AS null_cross_bank_ratio,
    SUM(has_laundering_tx IS NULL) AS null_target
FROM account_daily_features_dev;





SELECT
    has_laundering_tx,

    COUNT(*) AS account_days,

    ROUND(AVG(transaction_count), 2) AS avg_tx_count,
    ROUND(AVG(outgoing_count), 2) AS avg_outgoing,
    ROUND(AVG(incoming_count), 2) AS avg_incoming,

    ROUND(AVG(total_sent), 2) AS avg_total_sent,
    ROUND(AVG(total_received), 2) AS avg_total_received,

    ROUND(AVG(avg_transaction_amount), 2) AS avg_tx_amount,
    ROUND(AVG(max_transaction_amount), 2) AS avg_max_amount,

    ROUND(AVG(unique_counterparties), 2) AS avg_counterparties,
    ROUND(AVG(unique_banks), 2) AS avg_banks,
    ROUND(AVG(currency_diversity), 2) AS avg_currency_diversity,
    ROUND(AVG(payment_format_diversity), 2) AS avg_format_diversity,

    ROUND(AVG(rapid_transaction_count), 2) AS avg_rapid_count,
    ROUND(AVG(cross_bank_ratio), 4) AS avg_cross_bank_ratio,

    ROUND(
        AVG(
            total_sent /
            NULLIF(total_sent + total_received, 0)
        ),
        4
    ) AS avg_outflow_share,

    ROUND(
        AVG(
            rapid_transaction_count /
            NULLIF(transaction_count, 0)
        ),
        4
    ) AS avg_rapid_ratio

FROM account_daily_features_dev
GROUP BY has_laundering_tx;



-- ________________________________________________________ --

USE aml_portfolio;

CREATE INDEX idx_dev_activity_date
ON account_daily_features_dev (activity_date);

CREATE INDEX idx_dev_account_date
ON account_daily_features_dev (account_id, activity_date);




-- ============================================================================
-- 04. FROZEN DEVELOPMENT MODELING VIEW
-- ============================================================================
CREATE OR REPLACE VIEW vw_modeling_dev AS

SELECT
    -- Metadata: retained for splitting/traceability,
    -- NEVER passed to the model as predictors
    account_id,
    activity_date,

    -- Frozen predictor set
    transaction_count,

    outgoing_count / NULLIF(transaction_count, 0)
        AS outgoing_ratio,

    total_sent,
    total_received,
    avg_transaction_amount,
    max_transaction_amount,

    unique_counterparties,
    unique_banks,
    currency_diversity,

    rapid_transaction_count / NULLIF(transaction_count, 0)
        AS rapid_transaction_ratio,

    -- Target
    has_laundering_tx

FROM account_daily_features_dev;





SELECT
    CASE
        WHEN activity_date BETWEEN '2022-09-01' AND '2022-09-06'
            THEN 'TRAIN'
        WHEN activity_date BETWEEN '2022-09-07' AND '2022-09-08'
            THEN 'VALIDATION'
        WHEN activity_date BETWEEN '2022-09-09' AND '2022-09-10'
            THEN 'TEST'
    END AS dataset_split,

    COUNT(*) AS account_days,
    COUNT(DISTINCT account_id) AS unique_accounts,

    SUM(has_laundering_tx = 1) AS positive_rows,

    ROUND(
        SUM(has_laundering_tx = 1) * 100.0 / COUNT(*),
        4
    ) AS positive_rate_pct

FROM vw_modeling_dev

GROUP BY
    CASE
        WHEN activity_date BETWEEN '2022-09-01' AND '2022-09-06'
            THEN 'TRAIN'
        WHEN activity_date BETWEEN '2022-09-07' AND '2022-09-08'
            THEN 'VALIDATION'
        WHEN activity_date BETWEEN '2022-09-09' AND '2022-09-10'
            THEN 'TEST'
    END

ORDER BY
    MIN(activity_date);
    
    
    
    
    
    WITH
train_accounts AS (
    SELECT DISTINCT account_id
    FROM vw_modeling_dev
    WHERE activity_date BETWEEN '2022-09-01' AND '2022-09-06'
),

validation_accounts AS (
    SELECT DISTINCT account_id
    FROM vw_modeling_dev
    WHERE activity_date BETWEEN '2022-09-07' AND '2022-09-08'
),

test_accounts AS (
    SELECT DISTINCT account_id
    FROM vw_modeling_dev
    WHERE activity_date BETWEEN '2022-09-09' AND '2022-09-10'
)

SELECT
    (SELECT COUNT(*) FROM train_accounts)
        AS train_accounts,

    (SELECT COUNT(*) FROM validation_accounts)
        AS validation_accounts,

    (SELECT COUNT(*) FROM test_accounts)
        AS test_accounts,

    (
        SELECT COUNT(*)
        FROM validation_accounts v
        INNER JOIN train_accounts t
            ON v.account_id = t.account_id
    ) AS validation_seen_in_train,

    (
        SELECT COUNT(*)
        FROM test_accounts te
        INNER JOIN train_accounts tr
            ON te.account_id = tr.account_id
    ) AS test_seen_in_train,

    (
        SELECT COUNT(*)
        FROM test_accounts te
        INNER JOIN validation_accounts v
            ON te.account_id = v.account_id
    ) AS test_seen_in_validation;
    
    
    
    
    
    
    -- ============================================================================
-- 05. OOD ACCOUNT-DAY FEATURE TABLE (SEP. 11-18)
-- ============================================================================
DROP TABLE IF EXISTS account_daily_features_ood;

CREATE TABLE account_daily_features_ood AS

WITH ood_transactions AS (

    SELECT *
    FROM vw_account_transactions
    WHERE transaction_timestamp >= '2022-09-11 00:00:00'

),

ordered_activity AS (

    SELECT
        *,

        LAG(transaction_timestamp) OVER (
            PARTITION BY account_id, activity_date
            ORDER BY transaction_timestamp
        ) AS previous_transaction_timestamp

    FROM ood_transactions
)

SELECT
    account_id,
    activity_date,

    COUNT(*) AS transaction_count,

    SUM(
        CASE WHEN direction = 'OUTGOING'
             THEN 1 ELSE 0 END
    ) AS outgoing_count,

    SUM(
        CASE WHEN direction = 'INCOMING'
             THEN 1 ELSE 0 END
    ) AS incoming_count,

    SUM(
        CASE WHEN direction = 'OUTGOING'
             THEN amount ELSE 0 END
    ) AS total_sent,

    SUM(
        CASE WHEN direction = 'INCOMING'
             THEN amount ELSE 0 END
    ) AS total_received,

    AVG(amount)
        AS avg_transaction_amount,

    MAX(amount)
        AS max_transaction_amount,

    COUNT(DISTINCT counterparty_account)
        AS unique_counterparties,

    COUNT(DISTINCT counterparty_bank)
        AS unique_banks,

    COUNT(DISTINCT currency)
        AS currency_diversity,

    COUNT(DISTINCT payment_format)
        AS payment_format_diversity,

    SUM(
        CASE WHEN direction = 'OUTGOING'
             THEN amount ELSE 0 END
    )
    /
    NULLIF(
        SUM(
            CASE WHEN direction = 'INCOMING'
                 THEN amount ELSE 0 END
        ),
        0
    ) AS sent_received_ratio,

    SUM(
        CASE
            WHEN previous_transaction_timestamp IS NOT NULL
             AND TIMESTAMPDIFF(
                    MINUTE,
                    previous_transaction_timestamp,
                    transaction_timestamp
                 ) <= 10
            THEN 1
            ELSE 0
        END
    ) AS rapid_transaction_count,

    AVG(is_cross_bank)
        AS cross_bank_ratio,

    MAX(is_laundering)
        AS has_laundering_tx

FROM ordered_activity

GROUP BY
    account_id,
    activity_date;
    
    
    
    
    
-- ============================================================================
-- 06. OOD MODELING VIEW AND FINAL INTEGRITY CHECKS
-- ============================================================================
CREATE OR REPLACE VIEW vw_modeling_ood AS

SELECT
    account_id,
    activity_date,
    transaction_count,
    outgoing_count / NULLIF(transaction_count, 0) AS outgoing_ratio,
    total_sent,
    total_received,
    avg_transaction_amount,
    max_transaction_amount,
    unique_counterparties,
    unique_banks,
    currency_diversity,
    rapid_transaction_count / NULLIF(transaction_count, 0) AS rapid_transaction_ratio,
    has_laundering_tx

FROM account_daily_features_ood;


SELECT
    MIN(activity_date) AS min_date,
    MAX(activity_date) AS max_date
FROM account_daily_features_ood;






USE aml_portfolio;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT account_id) AS unique_accounts,

    MIN(activity_date) AS min_date,
    MAX(activity_date) AS max_date,

    SUM(has_laundering_tx = 1) AS positive_rows,
    SUM(has_laundering_tx = 0) AS negative_rows,

    SUM(transaction_count IS NULL) AS null_transaction_count,
    SUM(outgoing_ratio IS NULL) AS null_outgoing_ratio,
    SUM(total_sent IS NULL) AS null_total_sent,
    SUM(total_received IS NULL) AS null_total_received,
    SUM(avg_transaction_amount IS NULL) AS null_avg_amount,
    SUM(max_transaction_amount IS NULL) AS null_max_amount,
    SUM(unique_counterparties IS NULL) AS null_counterparties,
    SUM(unique_banks IS NULL) AS null_banks,
    SUM(currency_diversity IS NULL) AS null_currency_diversity,
    SUM(rapid_transaction_ratio IS NULL) AS null_rapid_ratio,
    SUM(has_laundering_tx IS NULL) AS null_target,

    SUM(outgoing_ratio < 0 OR outgoing_ratio > 1) AS bad_outgoing_ratio,
    SUM(rapid_transaction_ratio < 0 OR rapid_transaction_ratio > 1) AS bad_rapid_ratio

FROM vw_modeling_dev;





SELECT
    COUNT(*) AS total_rows,
    MIN(activity_date) AS min_date,
    MAX(activity_date) AS max_date,

    SUM(transaction_count IS NULL) AS null_transaction_count,
    SUM(outgoing_ratio IS NULL) AS null_outgoing_ratio,
    SUM(total_sent IS NULL) AS null_total_sent,
    SUM(total_received IS NULL) AS null_total_received,
    SUM(avg_transaction_amount IS NULL) AS null_avg_amount,
    SUM(max_transaction_amount IS NULL) AS null_max_amount,
    SUM(unique_counterparties IS NULL) AS null_counterparties,
    SUM(unique_banks IS NULL) AS null_banks,
    SUM(currency_diversity IS NULL) AS null_currency_diversity,
    SUM(rapid_transaction_ratio IS NULL) AS null_rapid_ratio,
    SUM(has_laundering_tx IS NULL) AS null_target,

    SUM(outgoing_ratio < 0 OR outgoing_ratio > 1) AS bad_outgoing_ratio,
    SUM(rapid_transaction_ratio < 0 OR rapid_transaction_ratio > 1) AS bad_rapid_ratio

FROM vw_modeling_ood;





SHOW VARIABLES LIKE 'secure_file_priv';

-- ============================================================================
-- END OF PIPELINE
-- Next step: export vw_modeling_dev and vw_modeling_ood as TSV/CSV and run the
-- Python notebook in ../notebooks/AML_Model_Development_Portfolio.ipynb.
-- ============================================================================
