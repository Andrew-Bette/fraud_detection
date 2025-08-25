# Fraud detection using SQL

## Project Overview

This project explores the detection of fraudulent mobile money transactions using SQL

### Dataset description

**Source:** Synthetic Mobile money transaction dataset in csv file format

**Main table:** transactions2 (fully cleaned)

**Time period:** 2022-2023

**Size:** 4,638 rows

## Key columns
| Column name | Description |
| :---           | :---            |
| id           | transaction id           |
| trans_type            | transaction type            |
| amount            | amount           |
| nameOrig            |identifier of originating account              |
| oldbalanceOrg            | 	Balance of the originating account before the transaction           |
| newbalanceOrig            |Balance of the originating account after the transaction             |
| nameDest            | identifier of destination account             |
| oldbalanceDest            |Balance of the destination account before the transaction             |
| newbalanceDest            |Balance of the destination account after the transaction             |
| isFraud            |1=Fraud, 0=No fraud             |
| isFlaggedFraud            |flagged my initial system as potentially fraudulent             |
| trans_datetime            |date and timestamp when transaction occured             |
| suspicious_transfer           |my own flag 1=suspicious, 0=safe             |
| detection_method            |improved flagging method             |
| risk_score            |where 1 = very low risk and 10 = very high risk   |


## Data Cleaning and Preparation

1. Removed duplicates using ROW_NUMBER() and CTE
2. Removed unwanted whitespaces in trans_type using TRIM() and set everything to lowercase using LOWER()
3. Standardized ununiform transaction types like Cashout, Cash_Out and transfee
4. Fixed inconsisitent date formats and converted trans_datetime from STR to date using STR_TO_DATE
5. Checked for blank strings and nonsense names like '####' in nameOrig and nameDest and set them to 'Unknown'
6. Checked for negative amounts in numerical fields.

### Code for removing duplicates
```
SELECT*,
ROW_NUMBER() OVER(
PARTITION BY trans_type, amount, nameOrig, oldbalanceOrg, newbalanceOrig, nameDest, 
oldbalanceDest, newbalanceDest, isFraud, isFlaggedFraud, trans_datetime) AS row_num
FROM transactions;

WITH dupli_cte AS
(
SELECT*,
ROW_NUMBER() OVER(
PARTITION BY trans_type, amount, nameOrig, oldbalanceOrg, newbalanceOrig, nameDest, 
oldbalanceDest, newbalanceDest, isFraud, isFlaggedFraud, trans_datetime) AS row_num
FROM transactions
)
SELECT *
FROM dupli_cte
WHERE row_num > 1;

DELETE
FROM transactions2
WHERE row_num > 1;
```


11 rows (0.23%) of the dataset contained negative balances. Given that such values typically indicate overdrafts or system issues, but no metadata confirmed that behavior, I treated them as suspicious and incorporated that into my new flagging system rather than dropping them.

Performance comparison of flagging systems

<img width="676" height="221" alt="Screenshot 2025-08-24 131853" src="https://github.com/user-attachments/assets/e5b5edcd-ff62-440b-bc8b-d8d60d10814b" />

Key Insights
The existing fraud detection system had 0% precision. Every single alert was a false positive. 
My system caught 3 more frauds than the original. 

To improve on the unrealistic lack of true positives, I developed an enhanced system using my domian knowledge of mobile money systems that significantly outperformed the original. my system achieved 3.16% precision compared to the original 0% and also increased recall from 0% to 4.23% meaning we are catching more actual fraud while also reducing false positives.
```
UPDATE transactions2
SET suspicious_transfer = CASE
    WHEN (trans_type = 'Transfer' OR trans_type = 'Cash_Out')
         AND (
			amount > 15000 OR
            (oldbalanceOrg - amount < 0 AND amount > 20000) OR-- Overdrafts with siginificant amounts
			(amount % 10000 = 0 AND amount > 30000) OR  -- Large and round amounts
			(oldbalanceOrg = 0 AND amount > 30000) OR -- New account abuse
			(oldbalanceDest = 0 AND amount > 20000)  -- Mule account pattern
         )
    THEN 1
    ELSE 0
END;
```
## Exploratory Data Analysis

Fraud by transaction type
```
SELECT
	trans_type,
    COUNT(*) AS total_trans,
    SUM(isFraud) AS total_fraud,
    ROUND(SUM(isFraud)/COUNT(*)*100,2) AS fraud_rate
FROM transactions2
GROUP BY trans_type
ORDER BY fraud_rate DESC;
```
<img width="563" height="372" alt="Screenshot 2025-08-25 181142" src="https://github.com/user-attachments/assets/25d14005-674c-41ad-bf4f-f156d9c61c10" />

Observation: Fraud is more common in transaction types of Transfer and Cash Out and almost non existent in Cash In and Payment

Fraud by amount range
```
SELECT
	CASE
		WHEN amount < 1000 THEN 'Low Risk'
        WHEN amount BETWEEN 1000 AND 10000 THEN 'Medium risk'
        WHEN amount BETWEEN 10000 AND 25000 THEN 'High risk'
        ELSE 'Very high risk'
	END AS amount_range,
	COUNT(*) as total,
    SUM(isFraud) as fraud_count,
    ROUND(SUM(isFraud) / COUNT(*) * 100,2) as fraud_rate
FROM transactions2
GROUP BY amount_range
ORDER BY fraud_rate DESC;
```
<img width="565" height="337" alt="Screenshot 2025-08-25 181250" src="https://github.com/user-attachments/assets/c624d13f-f053-418e-bfb5-91590af40df4" />

Observation:Fraud is common with higher amounts

Fraud by time of day
```
SELECT
	CASE
		WHEN HOUR(trans_datetime) BETWEEN 0 AND 5 THEN 'Late Night(00:00 - 05:00 hrs)'
        WHEN HOUR(trans_datetime) BETWEEN 6 AND 11 THEN 'Morning(06:00 - 11:00 hrs)'
        WHEN HOUR(trans_datetime) BETWEEN 12 AND 17 THEN 'Afternoon (12:00 - 17:00 hrs)'
        ELSE 'Evening (18:00 - 23:00 hrs)'
	END AS time_of_day,
    COUNT(*) as total_trans,
    SUM(isFraud) as total_fraud,
    ROUND(AVG(isFraud)*100,2) as fraud_rate_perc
FROM transactions2
GROUP BY time_of_day
ORDER BY fraud_rate_perc DESC;
```
<img width="538" height="337" alt="Screenshot 2025-08-25 181006" src="https://github.com/user-attachments/assets/c173f96e-250c-4804-893b-0a89c6c802e5" />

Observation: fraud cases are more common late night between midnight and 5AM

Fraud by day of week
```
SELECT
	DAYNAME(trans_datetime) as day_of_week,
    COUNT(*) as total_trans,
    SUM(isFraud) as total_fraud,
    ROUND(AVG(isFraud)*100,2) as fraud_rate_perc
from transactions2
GROUP BY day_of_week
ORDER BY fraud_rate_perc desc;
```
Observation: Fraud is more common on Thursdays and Fridays

Additional Analysis
* Fraud by origin (Trying to spot risky accounts/merchants)
* Correlation between flagged and actual fraud

## Tools
SQL: MySQL 8.0
Analysis: MySQL
Visualization: Power Bi

## Conclusions
* Original fraud detection system demonstrated critical performance issues such as 0% precision and recall.
* The system i developed showed measurable improvements. From 0& to 3.16% and 4.23% respectively.
* Fraudulent transactions made up a small fraction of total transactions but were heavily concentrated in large transfers.
* Cash_Out and Transfer were the transaction types most commonly associated with fraud.
* Fraud attempts peaked during late-night to early-morning hours, when detection or human monitoring may be weaker.

  ## Challenges and limitations
* During data import, i came across Error 1292: Incorrect date value: '0000-00-00' for column 'trans_datetime' at row 1. No matter what fixes I tried, the error wasnt getting resolved. What i finally did was to change trans_datetime data type to text (varchar) and then converted to Datetime after.
* When I tried to connect MySQL to Power Bi for visualizations, i encountered a SSL/TLS issue where an error occured during the pre-login handshake. To fix it i edited connections in MySQL and disabled SSL.

## Recommendations
* Tighten controls on large transactions. Since most fraud was observed in the >15,000 range,additional checks (multi-factor authentication, short delays for manual review should be enforced.
* Prioritize monitoring of Cash Out and Transfer. These two types accounted for the bulk of fraud cases. Stricter thresholds and more aggressive flagging rules should be applied to them compared to Payment and Cash In
* Implement stricter flagging during late night periods (between Midnight and 5:00 AM since fraud peaked around these hours
* Leverage customer profiling. Incorporating account history such as typical transaction amounts and times can help build risk scores that adapt to individial accounts rather than one size fits all.








