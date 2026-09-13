CREATE TABLE marketing_campaigns (
    campaign_id INT PRIMARY KEY,
    company VARCHAR(100),
    campaign_type VARCHAR(50),
    target_audience VARCHAR(50),
    channel_used VARCHAR(50),
    conversion_rate NUMERIC(10, 4),
    acquisition_cost NUMERIC(12, 2),
    roi NUMERIC(10, 4),
    location VARCHAR(50),
    language VARCHAR(50),
    clicks INT,
    impressions INT,
    engagement_score INT,
    customer_segment VARCHAR(50),
    date DATE,
    duration_days INT,
    ctr_percent NUMERIC(10, 4),
    cpc NUMERIC(10, 4),
    calculated_revenue NUMERIC(14, 2),
    net_profit NUMERIC(14, 2)
);

SELECT COUNT(*) AS total_rows FROM marketing_campaigns;

SELECT * FROM marketing_campaigns;

-- Step 1 :- Channel-Wise Executive Performance Summary

SELECT 
    channel_used,
    COUNT(campaign_id) AS total_campaigns,
    ROUND(SUM(acquisition_cost) / 1e6, 2) AS spend_millions,
    ROUND(SUM(calculated_revenue) / 1e6, 2) AS revenue_millions,
    ROUND(SUM(net_profit) / 1e6, 2) AS profit_millions,
    ROUND(AVG(roi), 2) AS avg_roi,
    ROUND(AVG(ctr_percent), 2) AS avg_ctr
FROM marketing_campaigns
GROUP BY channel_used
ORDER BY revenue_millions DESC;


-- Step 2 :- Campaign Type Ranking using Window Functions

SELECT 
    campaign_type,
    ROUND(SUM(net_profit) / 1e6, 2) AS total_profit_millions,
    ROUND(AVG(roi), 2) AS avg_roi,
    DENSE_RANK() OVER (ORDER BY SUM(net_profit) DESC) AS profit_rank
FROM marketing_campaigns
GROUP BY campaign_type;


-- Step 3 :- Monthly Revenue & Month-over-Month Growth

WITH monthly_metrics AS (
    SELECT 
        TO_CHAR(date, 'YYYY-MM') AS month_year,
        ROUND(SUM(calculated_revenue) / 1e6, 2) AS current_month_revenue
    FROM marketing_campaigns
    GROUP BY TO_CHAR(date, 'YYYY-MM')
)
SELECT 
    month_year,
    current_month_revenue,
    LAG(current_month_revenue) OVER (ORDER BY month_year) AS previous_month_revenue,
    ROUND(
        ((current_month_revenue - LAG(current_month_revenue) OVER (ORDER BY month_year)) 
        / LAG(current_month_revenue) OVER (ORDER BY month_year)) * 100, 2
    ) AS mom_growth_percent
FROM monthly_metrics
ORDER BY month_year;


-- Step 4 :- Top Performing Customer Segment per Channel

WITH Segment_Profit AS (
    SELECT 
        channel_used,
        customer_segment,
        ROUND(SUM(net_profit) / 1e6, 2) AS total_profit_millions,
        DENSE_RANK() OVER (
            PARTITION BY channel_used 
            ORDER BY SUM(net_profit) DESC
        ) AS segment_rank
    FROM marketing_campaigns
    GROUP BY channel_used, customer_segment
)
SELECT 
    channel_used,
    customer_segment AS top_customer_segment,
    total_profit_millions
FROM Segment_Profit
WHERE segment_rank = 1
ORDER BY total_profit_millions DESC;


-- Step 5 :- Efficiency Metric — Conversion Cost & Revenue Efficiency Ratio

SELECT 
    channel_used,
    ROUND(SUM(calculated_revenue) / NULLIF(SUM(acquisition_cost), 0), 2) AS revenue_per_dollar_spent,
    ROUND(AVG(acquisition_cost / NULLIF(conversion_rate, 0)), 2) AS avg_cost_per_conversion
FROM marketing_campaigns
GROUP BY channel_used
ORDER BY revenue_per_dollar_spent DESC;


-- Step 6 :- Cumulative Running Total Revenue over Time

WITH Monthly_Data AS (
    SELECT 
        TO_CHAR(date, 'YYYY-MM') AS month_year,
        ROUND(SUM(calculated_revenue) / 1e6, 2) AS monthly_revenue_m
    FROM marketing_campaigns
    GROUP BY TO_CHAR(date, 'YYYY-MM')
)
SELECT 
    month_year,
    monthly_revenue_m,
    SUM(monthly_revenue_m) OVER (ORDER BY month_year) AS running_total_revenue_m
FROM Monthly_Data
ORDER BY month_year;


-- Step 7 :- Multi-Tier Cohort & Outlier Detection (Z-Score + Window Framing)

WITH Channel_Stats AS (
    SELECT 
        campaign_id,
        channel_used,
        roi,
        acquisition_cost,
        net_profit,
        AVG(roi) OVER(PARTITION BY channel_used) AS channel_avg_roi,
        STDDEV(roi) OVER(PARTITION BY channel_used) AS channel_stddev_roi
    FROM marketing_campaigns
),
Z_Score_Calculation AS (
    SELECT 
        campaign_id,
        channel_used,
        roi,
        net_profit,
        ROUND((roi - channel_avg_roi) / NULLIF(channel_stddev_roi, 0), 2) AS roi_z_score
    FROM Channel_Stats
)
SELECT 
    channel_used,
    COUNT(campaign_id) AS total_high_variance_campaigns,
    ROUND(AVG(roi), 2) AS avg_variance_roi,
    ROUND(SUM(net_profit) / 1e6, 2) AS total_variance_profit_m
FROM Z_Score_Calculation
WHERE roi_z_score > 1.0 OR roi_z_score < -1.0  -- 1 Standard Deviation Threshold
GROUP BY channel_used
ORDER BY total_variance_profit_m DESC;


-- Step 8 :- Dynamic Budget Reallocation Engine (Percentile Cont & Conditional Aggregations)

WITH Ranked_Campaigns AS (
    SELECT 
        campaign_id,
        channel_used,
        acquisition_cost,
        net_profit,
        roi,
        NTILE(4) OVER (PARTITION BY channel_used ORDER BY roi DESC) AS roi_quartile
    FROM marketing_campaigns
)
SELECT 
    channel_used,
    ROUND(SUM(CASE WHEN roi_quartile = 1 THEN acquisition_cost ELSE 0 END) / 1e6, 2) AS top_quartile_spend_m,
    ROUND(SUM(CASE WHEN roi_quartile = 4 THEN acquisition_cost ELSE 0 END) / 1e6, 2) AS bottom_quartile_spend_m,
    -- Proposed 20% Budget Shift from Quartile 4 to Quartile 1
    ROUND((SUM(CASE WHEN roi_quartile = 4 THEN acquisition_cost ELSE 0 END) * 0.20) / 1e6, 2) AS recommended_budget_reallocation_m,
    ROUND(AVG(CASE WHEN roi_quartile = 1 THEN roi END), 2) AS top_quartile_avg_roi,
    ROUND(AVG(CASE WHEN roi_quartile = 4 THEN roi END), 2) AS bottom_quartile_avg_roi
FROM Ranked_Campaigns
GROUP BY channel_used
ORDER BY recommended_budget_reallocation_m DESC;


-- Step 9 :- Multi-Touch Revenue Contribution & Moving Average Smoothing (3-Month Rolling Frame)

WITH Monthly_Channel_Summary AS (
    SELECT 
        TO_CHAR(date, 'YYYY-MM') AS month_year,
        channel_used,
        SUM(calculated_revenue) AS monthly_revenue,
        SUM(net_profit) AS monthly_profit
    FROM marketing_campaigns
    GROUP BY TO_CHAR(date, 'YYYY-MM'), channel_used
)
SELECT 
    month_year,
    channel_used,
    ROUND(monthly_revenue / 1e6, 2) AS revenue_m,
    -- 3-Month Rolling Average Window Frame
    ROUND(AVG(monthly_revenue) OVER (
        PARTITION BY channel_used 
        ORDER BY month_year 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) / 1e6, 2) AS rolling_3mo_avg_revenue_m,
    -- Channel Market Share vs Total Monthly Market
    ROUND(
        (monthly_revenue / SUM(monthly_revenue) OVER (PARTITION BY month_year)) * 100, 2
    ) AS monthly_market_share_percent
FROM Monthly_Channel_Summary
ORDER BY channel_used, month_year;








