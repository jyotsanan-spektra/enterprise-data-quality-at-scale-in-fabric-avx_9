# Challenge 4: Enforce Spark-based data quality gates before Silver promotion

### Estimated Duration: 40 Minutes

## Scenario
The CDC process you configured earlier now lands operational changes in the Bronze layer, but Bronze data isn't trusted automatically. In this challenge, you will build a PySpark quality gate in Microsoft Fabric so that `bronze_orders_cdc` is promoted to `silver_orders` only when required checks pass. You will also capture failure evidence that can be reused in the final orchestration challenge.

## Overview
You will open or create a Fabric notebook, attach it to your Lakehouse, and implement five explicit validations against the Bronze orders table: null, range, referential integrity, freshness, and schema checks. You will then add conditional write logic so `silver_orders` is updated only when all rules pass, record the quality results, and rerun the notebook with a controlled defect to verify that promotion is blocked.

## Objectives
- Task 1: Prepare the Lakehouse and notebook context for the quality gate
- Task 2: Implement and run the PySpark quality checks
- Task 3: Trigger the failure path and confirm Silver promotion is blocked

## Task 1: Prepare the Lakehouse and notebook context for the quality gate

In this task, you will return to your learner-created Fabric items and prepare the notebook environment that will enforce the Bronze-to-Silver gate.

1. Sign in to Microsoft Fabric by using Username: <inject key="AzureAdUserEmail"></inject> and Password: <inject key="AzureAdUserPassword"></inject>.
2. Open the Fabric workspace you used in the previous challenges.
3. Note the deployment reference for this lab environment as **<inject key="DeploymentID" enableCopy="false"/>**.
4. Open the Lakehouse you created or confirmed in Challenge 1.
5. In the **Tables** pane, confirm that the Bronze table `bronze_orders_cdc` exists.
6. Confirm whether `silver_orders` already exists. If it does, keep it as the target curated table for this challenge. If it doesn't exist yet, you will create it from the notebook only after the quality checks pass.
7. From the Lakehouse page, select **Open notebook** and then choose an existing notebook you want to reuse, or create a new notebook for this challenge.
8. If more than one Lakehouse is attached to the notebook, make sure the correct Lakehouse is pinned as the default Lakehouse before you run Spark SQL or use relative table paths.
9. In the first notebook cell, run a simple check to verify that `bronze_orders_cdc` can be queried successfully and review the available columns before you add validation logic.

> [!Note]
> Microsoft Learn notes that the pinned default Lakehouse determines the root context for relative paths and Spark SQL in a notebook. Verify the correct Lakehouse is pinned before you run validation code.

## Task 2: Implement and run the PySpark quality checks

In this task, you will build the step-by-step validation logic that determines whether Bronze data is allowed into the Silver layer.

1. Add a new notebook section named **Quality gate setup**.
2. Load `bronze_orders_cdc` into a Spark DataFrame by using either `spark.read.format("delta").load("Tables/bronze_orders_cdc")` or a Spark SQL query against the table.
3. Display the schema and a sample of rows so you can confirm the dataset matches what was ingested during the CDC challenge.
4. Define the expected business-critical columns you will validate, such as order identifier, customer identifier, product identifier, order date, quantity, and amount fields that exist in your Bronze table.
5. Create a null-check result that counts records where required fields are blank or null.
6. Create a range-check result that identifies invalid values, such as negative quantities, zero-or-negative sales amounts, or dates outside the expected business pattern for the supplied dataset.
7. Create a referential integrity check that verifies the order rows can be matched to the related business key set available in your lab design. Use the lookup or parent table you prepared in earlier challenges, such as customer or product data, and count unmatched records.
8. Create a freshness check that compares the most recent order change or ingestion timestamp in `bronze_orders_cdc` with the expected recent CDC activity and flags stale data.
9. Create a schema check that compares the incoming Bronze schema with the column set and data types you expect to promote to Silver.
10. Combine the five checks into a results DataFrame or Python structure with one row per rule, including at least the rule name, status, failed row count, and a short message.
11. Display the results so you can visually confirm each rule outcome in the notebook output.
12. Add logic that evaluates whether any check failed. If one or more checks fail, set an overall gate status of **Failed**. If all checks pass, set the overall gate status of **Passed**.
13. Create or overwrite a quality evidence table such as `quality_gate_log` in the same Lakehouse so the run results are retained outside the notebook cell output.
14. Add conditional write logic so `silver_orders` is written only when the overall gate status is **Passed**.
15. When the gate passes, write the curated DataFrame to `silver_orders` as a Delta table in the Lakehouse.
16. Run the notebook with the current valid Bronze data and confirm that all five checks pass.
17. Refresh the Lakehouse **Tables** pane and verify that `silver_orders` exists or was updated after the successful run.
18. Query `silver_orders` and record the row count so you have baseline evidence before testing the failure path.

> [!Important]
> Microsoft Learn documents Delta tables in Fabric Lakehouse as the default managed table format and shows `saveAsTable()` as the standard pattern for writing Spark output to Lakehouse tables. Keep the Silver write inside the pass-only branch of your notebook logic.

## Task 3: Trigger the failure path and confirm Silver promotion is blocked

In this task, you will deliberately test the gate with bad data and confirm the notebook records the failure without refreshing the Silver table.

1. Return to the notebook and identify one validation rule you can safely fail by using the lab's controlled defect scenario.
2. Introduce the planned defect into the Bronze-side test path. For example, use the provided bad-data variation or temporarily shape a test DataFrame so that one of the required columns becomes null, a numeric value falls out of range, or a key no longer matches the lookup data.
3. Rerun the notebook with the defective input.
4. Review the displayed quality results and identify which of the five checks failed.
5. Confirm that the notebook records the failed rule in your quality evidence output, such as the `quality_gate_log` table or equivalent result artifact.
6. Confirm that the notebook does not write the defective dataset to `silver_orders`.
7. Query `silver_orders` again and verify that its row count or last valid state remains unchanged from the successful run.
8. If you are also preparing for Challenge 6, optionally add a final notebook statement that raises an error when the gate status is **Failed** so the pipeline can recognize the failure clearly during orchestration testing.
9. Save the notebook after both the pass and fail runs are complete.
10. Keep the Lakehouse, notebook, and logged output available for downstream verification.

<validation step="Spark quality gate behavior"/>
<question>

## Summary
You implemented a Fabric notebook that evaluates `bronze_orders_cdc` with null, range, referential integrity, freshness, and schema checks before any Silver promotion occurs. You then wrote `silver_orders` only when the gate passed, captured quality evidence in the Lakehouse, and proved that a controlled defect prevents the Silver layer from being refreshed.
