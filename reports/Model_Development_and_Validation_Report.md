# Model Development and Validation Report

## AML Risk Prioritization Using Synthetic Transaction Data

### Executive summary
This project develops an account-day risk ranking workflow for synthetic AML data. Rather than optimizing a single classification threshold, the model is evaluated against a finite investigator review capacity. A class-balanced logistic regression is used as the baseline and XGBoost as the challenger. The final XGBoost model and 0.555% review policy are frozen on validation data and evaluated once on Sep. 9-10 test data.

The frozen test policy prioritizes **2,747 of 494,707 account-days**, captures **397 positives**, produces **14.45% positive yield**, **26.48% positive coverage**, and **47.7x lift versus random review**. ROC-AUC is **0.8529** and PR-AUC is **0.1231**.

## 1. Business framing
The operational problem is not merely whether an account-day can be classified as positive. AML teams have finite investigator capacity. The relevant decision is therefore: **which account-days should be reviewed first, and how does review capacity trade off positive yield and positive coverage?**

This framing drives the use of rank-based metrics, capacity analysis, and business-facing dashboard terminology.

## 2. Data and analytical grain
The source is synthetic AML transaction data. SQL transforms each raw transaction into both sender and receiver perspectives and aggregates activity to an **account-day** unit. Development features include transaction counts, direction ratios, sent/received amounts, transaction-size statistics, unique banks/counterparties, currency diversity, and rapid-transaction behavior.

The development modeling extract contains **2,479,354 account-days** from Sep. 1-10, with **7,131 positives (0.2876%)**.

## 3. Leakage control and temporal validation
The project uses chronological splits: Sep. 1-6 train, Sep. 7-8 validation, and Sep. 9-10 test. Sep. 11-18 remains untouched until the model and policy are frozen and is used only for OOD monitoring. Account ID and activity date remain metadata and are excluded from predictors.

Train: 1,534,403 rows / 4,003 positives. Validation: 450,244 / 1,629. Test: 494,707 / 1,499.

## 4. Training-only EDA and preprocessing
Amount and activity features are strongly right-skewed; several maxima are orders of magnitude above medians. The frozen preprocessing function applies `log1p` to transaction count, total sent/received, average/max transaction amount, and unique-bank count. Ratios and currency diversity remain untransformed. The final model uses nine predictors.

## 5. Baseline model
Class-balanced logistic regression achieves validation ROC-AUC **0.7995** and PR-AUC **0.0378**. At the default 0.50 threshold it produces 115,343 alerts, which is operationally unrealistic. That result motivates explicit top-K capacity analysis.

## 6. XGBoost challenger and model selection
The XGBoost challenger uses class weighting and modest targeted tuning. Validation performance improves materially (tracked ROC-AUC about **0.846**, PR-AUC about **0.13**). The final selected configuration uses 300 trees, max depth 5, learning rate 0.05, subsample 0.8, and column subsample 0.8.

## 7. Operating-policy selection
Validation ranking was evaluated at several capacities. At 500 alerts, yield is very high but coverage is limited; larger queues capture more positives but reduce efficiency. A **2,500-alert** validation policy was frozen as the primary operating point (about 0.555% of validation account-days).

This is deliberately framed as an operating policy, not as a universally optimal threshold.

## 8. Final test results
| Metric | Result |
|---|---:|
| ROC-AUC | 0.8529 |
| PR-AUC | 0.1231 |
| Review rate | 0.555% |
| Alerts reviewed | 2,747 |
| True positives | 397 |
| False positives | 2,350 |
| False negatives | 1,102 |
| Positive yield | 14.45% |
| Positive coverage | 26.48% |
| Lift vs random | 47.7x |
| Test threshold | 0.9034 |

The test results are consistent with the validation rationale: reviewing a very small share of the population produces a queue far more concentrated in positives than random review.

## 9. Explainability
SHAP is used for both global feature importance and local case explanation. The model relies heavily on banking-network breadth, transaction magnitude/activity, and selected flow-pattern variables. SHAP is treated as an explanation of the fitted model's behavior, not evidence that the features causally generate laundering activity.

## 10. Cost-sensitive policy analysis
A sensitivity analysis assigns one cost unit to an unnecessary review and varies the relative cost of a missed positive. The cost-minimizing tested capacity increases as false-negative cost increases: 1,000 alerts at 10x, 2,500 at 25x, 10,000 at 50x, 25,000 at 100x, and 50,000 at 250x. This demonstrates why operating capacity should be governed by business assumptions rather than copied directly from a model score.

## 11. Experiment tracking
MLflow logs the baseline and final XGBoost parameters, validation metrics, selected policy metrics, test metrics, and model artifacts. The tracked results preserve the model comparison outside transient notebook state.

## 12. OOD monitoring
The OOD extract contains only **923 account-days** and is extremely unusual: **922 are positive**. ROC-AUC is 0.8482, but PR-AUC 0.9998 is not a meaningful generalization claim because the positive prevalence is itself almost 100%.

The useful result is distribution shift. Robust PSI is high for several variables: log average transaction amount ~1.72, log max transaction amount ~1.40, currency diversity ~1.14, rapid-transaction ratio ~0.93, and total received ~0.70. The dashboard therefore labels population drift **HIGH** and cautions against treating OOD metrics as ordinary performance evidence.

## 13. Visualization and decision support
The final Tableau dashboard translates technical metrics into review-policy language: alerts prioritized, positives identified, positive yield, positive coverage, lift versus random, capacity checkpoints, reviewed-queue composition, investigation priority, model context, and drift warning. Ground-truth outcomes remain evaluation information and are not intended to be shown as known facts in a live decision queue.

## 14. Development hurdles and fixes
The project encountered realistic implementation issues: raw-data import truncation/schema problems, extreme feature skew, severe class imbalance, an initially impractical threshold-based alert volume, an MLflow result-field mismatch (`run_name` vs `tags.mlflow.runName`), a later OOD population whose label distribution invalidated naive metric interpretation, and several Tableau schema/rendering failures during automated workbook construction. Each issue changed the workflow rather than being hidden from the final narrative.

## 15. Limitations
- Synthetic data and synthetic labels do not capture real AML investigation complexity.
- Account-day aggregation simplifies customer/entity structure.
- The OOD sample is tiny and almost entirely positive.
- Cost ratios are hypothetical sensitivity scenarios, not institution-estimated losses.
- The model is a prioritization prototype, not a production transaction-monitoring replacement.

## 16. Reproducibility
Run `sql/AML_Portfolio_Pipeline.sql` against the raw transaction table, export the development/OOD modeling views, then execute `notebooks/AML_Model_Development_Portfolio.ipynb`. The Tableau workbook is packaged separately and uses the model decision export.

## 17. Interview discussion points
The project is designed to support deeper discussion of temporal validation, leakage prevention, account-level feature engineering, imbalanced classification, operational thresholding, explainability, cost tradeoffs, MLOps tracking, drift monitoring, and the distinction between model output and investigator workflow.
