# Data

## Source
This project uses synthetic anti-money-laundering transaction data associated with IBM AMLSim / commonly distributed AML benchmark files. The project file used during development was named `HI-Small_Trans.csv`.

IBM AMLSim project: https://github.com/IBM/AMLSim

## Why the raw CSV is not committed here
The working raw transaction file contains millions of rows and is larger than GitHub's normal 100 MiB single-file limit. Keeping the repository lightweight also makes it easier for reviewers to clone.

To reproduce the project:
1. Obtain the same HI-Small transaction CSV.
2. Load it into MySQL as `aml_portfolio.raw_transactions` using the schema expected by `../sql/AML_Portfolio_Pipeline.sql`.
3. Run the SQL pipeline to construct `vw_modeling_dev` and `vw_modeling_ood`.
4. Export those views to TSV/CSV and update the two Drive paths at the top of the notebook if necessary.

## Expected raw fields
- transaction_timestamp
- from_bank
- from_account
- to_bank
- to_account
- amount_received
- receiving_currency
- amount_paid
- payment_currency
- payment_format
- is_laundering

## Expected modeling fields
`account_id, activity_date, transaction_count, outgoing_ratio, total_sent, total_received, avg_transaction_amount, max_transaction_amount, unique_counterparties, unique_banks, currency_diversity, rapid_transaction_ratio, has_laundering_tx`

## Synthetic-data disclaimer
This project is for portfolio/research demonstration. It should not be interpreted as a validated production AML model or as evidence about real customer behavior.
