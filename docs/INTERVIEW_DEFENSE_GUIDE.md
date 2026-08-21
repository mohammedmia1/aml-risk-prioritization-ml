# AML Risk Prioritization - Interview Defense Guide

Use this as a review guide, not a script to memorize.

## 1. Why did you model account-days instead of transactions?
The operational question was which account activity should be prioritized for review. Aggregating sender and receiver activity to account-day level creates one ranking unit that summarizes volume, value, counterparties, banks, currencies, direction, and rapid activity.

## 2. Why a temporal split?
A random split would let later observations influence model selection and would be less representative of deployment. I trained on Sep. 1-6, validated on Sep. 7-8, froze the model/policy, and tested once on Sep. 9-10.

## 3. Why keep Sep. 11-18 separate?
It was reserved as an OOD monitoring period. I did not use it for feature decisions, tuning, or threshold/capacity selection.

## 4. Why not accuracy?
The positive rate is around three-tenths of one percent. A model can have very high accuracy while being useless for prioritizing positives. PR-AUC, precision/recall at review capacity, and lift are more informative.

## 5. Why logistic regression first?
It is a simple, defensible baseline. If XGBoost did not materially improve ranking quality, the added complexity would be harder to justify.

## 6. Why XGBoost?
The feature relationships are nonlinear, highly skewed, and likely interactive. XGBoost improved validation PR-AUC substantially over the logistic baseline while remaining practical to explain with SHAP.

## 7. What does 47.7x lift mean?
At the frozen test review rate, positives are about 47.7 times as concentrated in the reviewed queue as they would be under random selection from the same test population.

## 8. Why select 2,500 validation alerts?
It was an operating compromise: increasing capacity improved positive coverage but reduced yield and increased false positives. I froze that validation policy before looking at test performance.

## 9. Why does test review contain 2,747 rather than 2,500 alerts?
I froze the validation **review rate** (2,500 / 450,244), then applied that rate to the larger 494,707-row test population.

## 10. What is the difference between precision and recall here?
Positive yield/precision asks: of the account-days investigators review, how many are positive? Positive coverage/recall asks: of all positive account-days in the population, how many did the queue capture?

## 11. Why use log transforms?
Training EDA showed extreme right skew in amounts/counts. `log1p` compresses extreme magnitude while preserving zero values and relative ordering.

## 12. Why exclude unique counterparties from the final predictors?
In training it was almost perfectly correlated with transaction count at this constructed grain, so keeping both added little independent information.

## 13. What did SHAP tell you?
Globally, unique-bank activity, transaction amounts/count, and several flow-pattern measures materially influence scores. Locally, a high-risk case can be decomposed into features that push its score up or down. I treat SHAP as model explanation, not causal explanation.

## 14. Why perform cost-sensitive analysis after choosing a policy?
It demonstrates that there is no universal optimal queue. The selected policy is an operating choice; different relative costs of false negatives and false positives justify different review capacities.

## 15. What was MLflow adding?
It created an auditable record of model type, parameters, validation metrics, test metrics, and model artifacts so the baseline/challenger comparison was not just notebook state.

## 16. Why is the OOD PR-AUC 0.9998 not impressive?
Because 922 of 923 OOD rows are positive. PR-AUC depends heavily on prevalence; a nearly all-positive population makes the metric uninformative for ordinary discrimination. The more useful conclusion is that the population shifted dramatically.

## 17. What did PSI show?
Several features showed severe shift, especially average/max transaction amount, currency diversity, rapid-transaction ratio, and received amounts. The dashboard therefore flags population drift as HIGH.

## 18. What is the biggest limitation?
The dataset is synthetic and the labels/population are simulator-generated. A real bank implementation would need label-lag controls, customer/entity context, capacity/cost estimates, calibration, and longer temporal validation.

## 19. What technical hurdle are you most comfortable discussing?
The ingestion and end-to-end validation loop: schema/import issues, account-centric SQL transformation, temporal feature tables, class imbalance, capacity-based model evaluation, and later Tableau rendering repair all required iterative debugging.

## 20. What would productionization look like?
Scheduled feature pipelines, a governed model registry, versioned thresholds/capacity policy, data-quality/drift monitoring, decision-time feature controls, investigator feedback capture, and periodic revalidation/retraining under model-risk governance.
