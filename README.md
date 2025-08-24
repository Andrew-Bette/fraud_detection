# fraud_detection
Fraud detection in mobile transactions using SQL.

## Project Overview

This project explores the detection of fraudulent mobile money transactions using SQL

## Dataset description

Source: Synthetic Mobile money transaction dataset in csv file format

Main table: transactions2 (fully cleaned)

Size: 4,638 rows

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
Insight: Fraud is more common in transaction types of Transfer and Cash Out and almost non existent in Cash In and Payment

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
Insight:Fraud is common with higher amounts

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
Insight: fraud cases are more common late night between midnight and 5AM

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
Insight: Fraud is more common on Thursdays and Fridays












