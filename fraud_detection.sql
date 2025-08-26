CREATE DATABASE fraud_detection;
USE fraud_detection;

CREATE TABLE transactions_raw (
id INT AUTO_INCREMENT PRIMARY KEY,
trans_type VARCHAR(10),
amount DECIMAL(10,2) NULL,
nameOrig VARCHAR(20),	
oldbalanceOrg DECIMAL(10,2) NULL,
newbalanceOrig DECIMAL(10,2) NULL,
nameDest VARCHAR(20),
oldbalanceDest DECIMAL(10,2) NULL,
newbalanceDest DECIMAL(10,2) NULL,
isFraud TINYINT,
isFlaggedFraud TINYINT,
trans_datetime VARCHAR(30)
);

LOAD DATA LOCAL INFILE "C:/Users/HP 14s/Downloads/fraud_detection_dataset syn.csv"
INTO TABLE transactions_raw
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
  trans_type, 
  @amount, 
  nameOrig, 
  @oldbalanceOrg, 
  @newbalanceOrig,
  nameDest, 
  @oldbalanceDest, 
  @newbalanceDest,
  @isFraud, 
  @isFlaggedFraud, 
  trans_datetime
)
SET
  amount = NULLIF(@amount, ''),
  oldbalanceOrg = NULLIF(@oldbalanceOrg, ''),
  newbalanceOrig = NULLIF(@newbalanceOrig, ''),
  oldbalanceDest = NULLIF(@oldbalanceDest, ''),
  newbalanceDest = NULLIF(@newbalanceDest, ''),
  isFraud = NULLIF(@isFraud, ''),
  isFlaggedFraud = NULLIF(@isFlaggedFraud, '');
#Now we've loaded our data from the csv into our table. First things first, we are going to duplicate the table so as to avoid
#tampering with the original

SELECT*
FROM transactions_raw
LIMIT 10;

CREATE TABLE transactions
LIKE transactions_raw;

INSERT transactions
SELECT *
FROM transactions_raw;

#Now we can start cleaning the data

# Checking for Duplicates and removing them, if any (Using Window Functions and CTEs)
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
WHERE row_num > 1;   #Wherever row_num>1 means those are duplicates.

# Now we want to delete those duplicates but we cant Delete(Update) a CTE so
# We have to create yet another table which we can now delete from and go on doing more cleaning with this new table

CREATE TABLE `transactions2` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `trans_type` varchar(10) DEFAULT NULL,
  `amount` decimal(10,2) DEFAULT NULL,
  `nameOrig` varchar(10) DEFAULT NULL,
  `oldbalanceOrg` decimal(10,2) DEFAULT NULL,
  `newbalanceOrig` decimal(10,2) DEFAULT NULL,
  `nameDest` varchar(10) DEFAULT NULL,
  `oldbalanceDest` decimal(10,2) DEFAULT NULL,
  `newbalanceDest` decimal(10,2) DEFAULT NULL,
  `isFraud` tinyint DEFAULT NULL,
  `isFlaggedFraud` tinyint DEFAULT NULL,
  `trans_datetime` varchar(30) DEFAULT NULL,
  `row_num`INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SELECT *
FROM transactions2;

INSERT INTO transactions2
SELECT*,
ROW_NUMBER() OVER(
PARTITION BY trans_type, amount, nameOrig, oldbalanceOrg, newbalanceOrig, nameDest, 
oldbalanceDest, newbalanceDest, isFraud, isFlaggedFraud, trans_datetime) AS row_num
FROM transactions;

#Filter for duplicates and delete them
SELECT *
FROM transactions2
WHERE row_num > 1;

DELETE
FROM transactions2
WHERE row_num > 1;

#Next we need to STANDARDIZE the data.
# First lets check out our trans_type column

SELECT DISTINCT trans_type
FROM transactions2;

#We need to do a trim since there are some unwanted spaces
UPDATE transactions2
SET trans_type = TRIM(trans_type);

UPDATE transactions2
SET trans_type = LOWER(trans_type);

#Okay so we have ununiform trans_types--Cash Out and Transfer
#We shall use Case Statement to clean up all that mess at once

UPDATE transactions2
SET trans_type = CASE
	WHEN trans_type LIKE 'cash_out' OR trans_type LIKE 'cashout' THEN 'Cash_Out'
	WHEN trans_type LIKE 'transfe%' THEN 'Transfer'
	WHEN trans_type LIKE 'cash_in' THEN 'Cash_In'
    WHEN trans_type LIKE 'payment' THEN 'Payment'
    ELSE trans_type
END;

#Here we need to change the trans_datettime format from text to date

SELECT trans_datetime
FROM transactions2;

UPDATE transactions2
SET trans_datetime = STR_TO_DATE(trans_datetime, '%d/%m/%Y %H:%i');

ALTER TABLE transactions2
MODIFY COLUMN trans_datetime DATETIME;

#Lets clean the trans_type column. Be sure no funny names or values.
SELECT DISTINCT trans_type
FROM transactions2
WHERE trans_type NOT IN ('Cash_Out', 'Payment', 'Transfer', 'Cash_In');

#Checking for nulls, negatives, empty strings and incorrect zero balances
SELECT *
FROM transactions2;

SELECT *
FROM transactions2
WHERE 
  amount IS NULL OR amount < 0 OR
  (amount > 0 AND oldbalanceOrg = 0 AND newbalanceOrig = 0) OR	#Possibly incorrect zero balances when amount is not zero
  (amount > 0 AND oldbalanceDest = 0 AND newbalanceDest = 0) OR
  oldbalanceOrg IS NULL OR oldbalanceOrg < 0 OR    #Checking for nulls and negatives        
  newbalanceOrig IS NULL OR newbalanceOrig < 0 OR
  oldbalanceDest IS NULL OR oldbalanceDest < 0 OR
  newbalanceDest IS NULL OR newbalanceDest < 0 OR
  nameOrig IS NULL OR nameOrig = '' OR nameOrig NOT LIKE 'C%' Or #Checking for empty strings and inconsistencies
  nameDest IS NULL OR nameDest = '' OR nameDest NOT LIKE 'C%' OR
  trans_datetime IS NULL OR LENGTH(trans_datetime) = 0;

#Lets deal with blankl strings (replace with placeholders)
UPDATE transactions2
SET nameOrig = 'Unkwn Orig'
WHERE nameOrig = '' OR nameOrig NOT LIKE 'C%';

UPDATE transactions2
SET nameDest = 'Unkwn Dest'
WHERE nameDest = '' OR nameDest NOT LIKE 'C%';

#Dropping row_num column(its unecessary)
ALTER TABLE transactions2
DROP COLUMN row_num;

SELECT *
FROM transactions2;

#Lets check for the effectiveness of the fraud flafgging system
SELECT
	COUNT(*) AS total,
    SUM(CASE WHEN isFraud = 1 AND isFlaggedFraud = 0 THEN 1 ELSE 0 END) AS false_negative,
    SUM(CASE WHEN isFraud = 0 AND isFlaggedFraud = 1 THEN 1 ELSE 0 END) AS false_positive,
	SUM(CASE WHEN isFraud = 1 AND isFlaggedFraud = 1 THEN 1 ELSE 0 END) AS true_positive,
	SUM(CASE WHEN isFraud = 0 AND isFlaggedFraud = 0 THEN 1 ELSE 0 END) AS true_negative
FROM transactions2;

#Lets try to introduce a smarter way of detecting fraud
ALTER TABLE transactions2
ADD COLUMN suspicious_transfer TINYINT;

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

#New false positives
SELECT COUNT(*) FROM transactions2
WHERE isFraud = 0 AND suspicious_transfer = 1;

#New false negatives
SELECT COUNT(*) FROM transactions2
WHERE isFraud = 1 AND suspicious_transfer = 0;

SELECT COUNT(*)
FROM transactions2
WHERE suspicious_transfer=1;

SELECT trans_type, COUNT(*) 
FROM transactions2 
GROUP BY trans_type;

select count(*)
from transactions2
where suspicious_transfer =1 and isFraud=1;

#Lets Add a comprehensive detection column
ALTER TABLE transactions2 ADD COLUMN detection_method VARCHAR(50);

UPDATE transactions2 
SET detection_method = CASE
    WHEN suspicious_transfer = 1 AND isFlaggedFraud = 1 THEN 'Both Systems'
    WHEN suspicious_transfer = 1 AND isFlaggedFraud = 0 THEN 'My System Only'  
    WHEN suspicious_transfer = 0 AND isFlaggedFraud = 1 THEN 'Original Only'
    ELSE 'Neither'
END;

select count(*) from transactions2 where isFraud=1;

#Performance comparison
SELECT
	detection_method,
    COUNT(*) AS trans_flagged,
    SUM(isFraud) AS actual_fraud_caught,
    ROUND(AVG(isFraud)*100, 2) AS precision_perc,
    ROUND((SUM(isFraud)/71) *100, 2) AS recall_perc
FROM transactions2
GROUP BY detection_method
ORDER BY actual_fraud_caught;

#Lets also assign a risk scoring system
ALTER TABLE transactions2 ADD COLUMN risk_score INT DEFAULT 0;

UPDATE transactions2
SET risk_score = CASE
	WHEN detection_method = 'Both Systems' THEN 10 			-- Highest priority
    WHEN detection_method = 'My System Only' THEN 7 		-- High priority
    WHEN detection_method = 'Original Only' THEN 5 			-- Medium priority
	WHEN amount > 25000 THEN 3 				   			-- Large amount flag
	WHEN trans_type = 'Cash_Out' AND amount > 20000 THEN 2  -- Suspicious cash-out
	ELSE 1													-- Low Risk
END;

-- Now that we're done cleaning and and improving the flagging system its time to delve into the analysis proper

#Fraud rate overview
SELECT
	COUNT(*) AS total_trans,
    SUM(isFraud) AS total_fraud,
    ROUND(SUM(isFraud) / COUNT(*) *100, 2) AS fraud_percentages
FROM transactions2;

#Fraud by transaction type
SELECT
	trans_type,
    COUNT(*) AS total_trans,
    SUM(isFraud) AS total_fraud,
    ROUND(SUM(isFraud)/COUNT(*)*100,2) AS fraud_rate
FROM transactions2
GROUP BY trans_type
ORDER BY fraud_rate DESC;

#Fraud by amount range
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

#Fraud by origin--Lets try to spot risky accounts
SELECT
	nameOrig,
	COUNT(*) AS total_sent,
    SUM(isFraud) as fraud_sent,
    ROUND(SUM(isFraud)/COUNT(*)*100,2) AS fraud_rate
FROM transactions2
GROUP BY nameOrig
HAVING SUM(isFraud) > 0
ORDER BY fraud_rate DESC
LIMIT 10;

SELECT
	nameDest,
	COUNT(*) AS total_sent,
    SUM(isFraud) as fraud_sent,
    ROUND(SUM(isFraud)/COUNT(*)*100,2) AS fraud_rate
FROM transactions2
GROUP BY nameDest
HAVING SUM(isFraud) > 0
ORDER BY fraud_rate DESC
LIMIT 10;

#Correlation between flagged and actual fraud
SELECT
	isFLaggedFraud,
    COUNT(*) AS total,
    SUM(isFraud) AS actual_fraud,
    ROUND(SUM(isFraud) / COUNT(*) *100, 2) AS fraud_rate
FROM transactions2
GROUP BY isFLaggedFraud;

#Fraud by time of day
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

#Fraud by day of week
SELECT
	DAYNAME(trans_datetime) as day_of_week,
    COUNT(*) as total_trans,
    SUM(isFraud) as total_fraud,
    ROUND(AVG(isFraud)*100,2) as fraud_rate_perc
from transactions2
GROUP BY day_of_week
ORDER BY fraud_rate_perc desc;

SELECT COUNT(*) FROM transactions2 where isFraud = 1;

select*
from transactions2;


