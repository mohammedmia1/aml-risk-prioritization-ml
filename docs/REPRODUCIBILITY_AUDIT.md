# AML model reproducibility audit

## Verdict

**Refactor regression: PASS for the final-model pathway in the tested environment.** Independent original-configuration and guided-configuration refits produced identical prediction vectors on all 494,707 held-out rows (SHA-256: `9e792e0cdfad3edc8786fff9855e8d3de44bdbcf4dfd173872abd012aa6384c3`).

**Historical-model reproduction: NOT RECONCILED.** The historical Tableau export has 397 selected positives; fresh refits have 389. This is not attributable to the simplified notebook's final-model configuration in the tested environment. We have **not proven** whether the difference arose from a different historical XGBoost version, historical model state, or another environment detail.

## Test design

- Inputs: original supplied `aml_modeling_dev.tsv` and historical `aml_tableau_decision_data.csv`.
- Chronological splits: train September 1–6, validation September 7–8, test September 9–10, 2022.
- Train: 1,534,403; validation: 450,244; test: 494,707 account-days.
- Both independent refits used the original nine predictors and `log1p` transformation, 300 trees, depth 5, learning rate 0.05, subsample 0.8, column subsample 0.8, class weight ratio, and `random_state=42`.
- Environment: XGBoost 3.1.3, pandas 2.2.3, scikit-learn 1.8.0. Both refits used `n_jobs=2` to avoid oversubscription; original notebook specified `n_jobs=-1`. No model hyperparameters were retuned.
- Both predictions were scored against the same original test row order; full vector equality was checked, not just rounded metrics.

## Numerical evidence

| Metric | Historical Tableau export | Both fresh refits |
|---|---:|---:|
| Test account-days | 494,707 | 494,707 |
| Review queue | 2,747 | 2,747 |
| Selected positive synthetic labels | 397 | 389 |
| Precision | 14.45% | 14.16% |
| Recall | 26.48% | 25.95% |
| Lift | 47.7x | 46.73x |
| ROC-AUC | 0.85294841 | 0.85225494 |
| PR-AUC | 0.12311784 | 0.12141259 |

The historical export's keys, ten raw features, labels, ranks, and selected flags have been checked against the original test records. Compared with fresh predictions, 536 records change queue membership, mean absolute score difference is 0.0228055, and maximum absolute score difference is 0.6955101.

## What the test does and does not prove

The **final preprocessing and fitted XGBoost prediction pathway** agrees across the original and guided configurations in the current environment. Some code cells differ because of readability edits, and optional tuning, SHAP, MLflow, OOD drift, and Tableau CSV writing were **not independently executed end to end** in this controlled comparison. This is not a full notebook execution certification.

The original trained model and historical XGBoost version were not provided. We cannot assign a definitive root cause for the historical-versus-fresh difference. Do not tune to the held-out test or substitute fresh scores into the historical dashboard without relabeling them.

## Publication recommendation

Publish the guided notebook as an **audited alternative walkthrough**, alongside the original notebook, not as an identical historical replacement. Publish this audit with it. The website may display historical verified-export metrics only if prominently labeled, and must disclose the fresh-model discrepancy. The original TSV files should not be committed unless licensing and size are appropriate; use the repository data notes.

## Re-run

Run `python verification/compare_original_guided.py` after placing `aml_modeling_dev.tsv` at `/mnt/data/aml_modeling_dev.tsv` (or edit its `root` path). Requires pandas, numpy, scikit-learn and XGBoost; saves full score arrays and a JSON comparison. No seed or hyperparameter searching is performed.
