# Development Notes - Hurdles, Fixes, and What Changed

This file is intentionally included because the project was developed iteratively rather than appearing fully formed.

## 1. Raw-data ingestion
Early MySQL Workbench import attempts produced truncation/schema problems. The workflow moved to an explicit MySQL table and `LOAD DATA LOCAL INFILE`, followed by row-count, date-range, amount-range, and label-distribution checks before analysis continued.

## 2. Feature engineering scale
Transaction values and account activity are extremely right-skewed. Training-only EDA showed several features with very large skewness and extreme maxima, so the final preprocessing schema applies `log1p` to transaction counts/amounts and unique-bank count.

## 3. Class imbalance changed the evaluation plan
The development positive rate is below 0.4%. At a default 0.50 logistic threshold, more than 115,000 validation alerts would be generated. This made it clear that the project needed ranking/capacity metrics instead of a threshold-first workflow.

## 4. Baseline before complexity
A class-balanced logistic regression established a validation PR-AUC of 0.0378. XGBoost improved ranking performance materially (tracked validation PR-AUC ~0.13), justifying the more complex model.

## 5. Capacity became a business decision
The selected 2,500-alert validation policy was not presented as mathematically universal. Cost-sensitivity analysis showed that the preferred queue changes when the assumed cost of a missed positive changes.

## 6. MLflow schema detail
An early result-display attempt expected a `run_name` column. MLflow returns the run name in `tags.mlflow.runName`; the final notebook uses the correct field. The environment also emitted a deprecation warning for `artifact_path`, and the polished notebook uses the current `name=` argument.

## 7. OOD interpretation changed after seeing the labels
The Sep. 11-18 OOD set contains 922 positives and only 1 negative. A near-perfect PR-AUC is therefore not useful evidence of model quality. The final interpretation focuses on severe population drift and limited evaluation power.

## 8. Tableau required a separate QA loop
A workbook can be analytically correct yet fail to render as intended. During dashboard development, some generated Tableau XML failed schema validation, some worksheets rendered blank, and some cosmetic changes silently failed to materialize. The final workflow therefore treats workbook logic and rendered-dashboard QA as separate gates.

## What I would change with real bank data
- Separate account/customer/entity grains explicitly.
- Use investigation/SAR outcomes with label-lag controls rather than transaction-level simulator labels.
- Add scenario/channel/customer-risk context available at decision time.
- Estimate review cost and missed-risk cost from business evidence rather than hypothetical ratios.
- Revalidate temporal stability across multiple months/quarters and monitor calibration as well as feature drift.
