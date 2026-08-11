# Challenge 4: Enforce Spark-based data quality gates before Silver promotion

### Estimated Duration: 40 Minutes

## Scenario
In Challenge 1, you confirmed the workspace foundation and either created or validated the Fabric control-plane items required for this lab. In this challenge, you will build on those learner-owned items by using the notebook and Lakehouse structure from your earlier work to enforce data quality before curated data can move from Bronze to Silver.

## Overview
You will use the Lakehouse, notebook, and table design established in earlier challenges to implement a PySpark quality gate for orders data. You will define the required rules, evaluate `bronze_orders_cdc`, record the outcome, and ensure that `silver_orders` is only refreshed when the validation result is successful. You will then introduce a controlled defect and prove that your quality gate blocks promotion.

## Objectives
- Task 1: Reuse the Fabric items established in Challenge 1 for the quality-gate design
- Task 2: Implement PySpark validation logic against Bronze orders data
- Task 3: Prove that failed validation blocks Silver promotion and creates observable evidence

## Task 1: Reuse the Fabric items established in Challenge 1 for the quality-gate design
In this task, you will confirm the learner-created Fabric items that this challenge depends on and align them to the Bronze-to-Silver quality pattern.

1. Sign in to Microsoft Fabric by using Username: <inject key="AzureAdUserEmail"></inject> and Password: <inject key="AzureAdUserPassword"></inject>.
2. Return to the same Fabric workspace you reviewed in Challenge 1 and record the deployment reference **<inject key="DeploymentID" enableCopy="false"/>** so your notebook and validation evidence can be tied to the correct lab environment.
3. Confirm that you are working with the Fabric items you established earlier in the lab rather than any assumed pre-seeded objects. At minimum, identify the workspace, the Lakehouse that holds your Bronze and Silver tables, and the notebook artifact you will use or create for data quality processing.
4. Verify that the Bronze-side ingestion work from Challenge 2 produced the `bronze_orders_cdc` Delta table in your Lakehouse and that the Silver target `silver_orders` is the curated destination this challenge will protect.
5. Reconfirm the medallion responsibilities for these items: Bronze preserves landed operational change data, Silver contains validated and promoted data, and the notebook provides the Spark-based processing logic that enforces the gate between them.
6. Define the success criteria for the quality gate: null checks, value-range checks, referential integrity checks, freshness checks, and schema-conformance checks must all pass before the Silver write is allowed.

> [!Important]
> Do not assume any notebook, pipeline, semantic model, warehouse, or other Fabric control-plane item was provisioned for you beyond what you explicitly confirmed or created in Challenge 1. This challenge must build on the items already present in your own workspace scope.

## Task 2: Implement PySpark validation logic against Bronze orders data
In this task, you will use a Fabric notebook to evaluate Bronze orders data before any Silver-layer write occurs.

1. Open the notebook artifact you created earlier for engineering work, or create a new notebook now in the same workspace if you did not already create one in Challenge 1.
2. Attach the notebook to the Lakehouse that contains `bronze_orders_cdc` so the notebook can read the Bronze table and write any approved output to the Silver layer.
3. Use PySpark to load `bronze_orders_cdc` into a DataFrame and profile the dataset so you can measure row counts, required columns, and data conditions before promotion.
4. Implement a null-check rule for required order columns so incomplete records are identified before curation.
5. Implement value-range checks for business-critical numeric or domain fields so invalid quantities, amounts, or other out-of-range values are rejected.
6. Implement a referential integrity check that confirms orders can be matched to the required lookup or parent data used by your design.
7. Implement a freshness check that verifies the Bronze data reflects recent CDC activity rather than stale ingestion output.
8. Implement a schema-conformance check that compares the incoming structure to the expected Silver-ready contract and flags drift or missing fields.
9. Aggregate the five rule outcomes into a single pass/fail result that the notebook can use to control whether `silver_orders` is written.
10. Write clear quality evidence to a log table, notebook result set, or durable output artifact so another reviewer can tell which rule passed or failed without repeating the run.
11. Execute the notebook against a clean Bronze state and confirm that the rule set passes and that the notebook permits promotion to `silver_orders`.

> [!Note]
> Microsoft Learn describes notebooks as Fabric data engineering artifacts for ingestion, preparation, and transformation, and positions lakehouses as the storage foundation for Spark-based processing. Keep your implementation centered on the notebook and Lakehouse items you control in this workspace.

## Task 3: Prove that failed validation blocks Silver promotion and creates observable evidence
In this task, you will demonstrate that the quality gate protects the Silver layer by stopping promotion when the Bronze dataset is invalid.

1. Update or confirm your notebook logic so that the write to `silver_orders` occurs only when the aggregated quality result is successful.
2. Make the blocking behavior explicit and testable by returning a failed notebook outcome, raising an error, or otherwise surfacing a clear failure condition when any rule breaches its threshold.
3. Introduce the planned controlled defect into the Bronze-side test path by using the lab data variation intended to trigger one of your quality rules.
4. Rerun the notebook and verify that the quality output identifies the failed rule and captures enough detail to explain why promotion was denied.
5. Confirm that `silver_orders` is not refreshed from the defective Bronze state and that the previously valid Silver result remains protected.
6. Review the evidence generated by the notebook run and summarize which rule failed, what threshold or condition was violated, and how the notebook signaled the failure.
7. Preserve the notebook, the quality evidence, and the resulting table state for downstream orchestration work in the next challenge.

<validation step="Spark quality gate behavior"/>
<question>

## Summary
You used the Fabric workspace items established in Challenge 1 to implement a Spark-based quality gate on top of your own Lakehouse and notebook artifacts. By evaluating `bronze_orders_cdc` with five explicit checks, logging the results, and allowing `silver_orders` to refresh only on success, you proved that Silver promotion depends on learner-implemented validation rather than any pre-seeded Fabric processing object.
