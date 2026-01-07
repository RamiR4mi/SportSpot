-- ========== SPORTSPOT ADVANCED QUERIES ==========

use SportSpot;

DROP PROCEDURE IF EXISTS sp_get_available_fields;
DROP PROCEDURE IF EXISTS sp_process_payment;
DROP PROCEDURE IF EXISTS sp_cancel_booking;
DROP PROCEDURE IF EXISTS sp_get_user_booking_history;
DROP VIEW IF EXISTS v_booking_complete_summary;
DROP VIEW IF EXISTS v_field_performance;
DROP VIEW IF EXISTS v_user_spending;

-- ========== VIEWS ==========
/*views are virtual tables representing the result of a stored query*/

-- VIEW 1: Complete booking summary with all details and costs

CREATE VIEW v_booking_complete_summary AS
SELECT 
  b.booking_id,
  u.uname AS user_name,
  u.email,
  u.phone,
  sf.name AS field_name,
  sf.sport_type,
  fo.business_name AS owner_name,
  sf.address,
  b.start_time,
  b.end_time,
  TIMEDIFF(b.end_time, b.start_time) AS duration,
  sf.price_per_hour,
  (sf.price_per_hour * HOUR(TIMEDIFF(b.end_time, b.start_time))) AS total_cost,
  b.status,
  b.booking_datetime,
  COALESCE(p.amount, 0) AS payment_amount,
  p.status AS payment_status,
  pm.method_name
FROM Bookings b
JOIN Users u ON b.user_id = u.user_id
JOIN SportFields sf ON b.field_id = sf.field_id
JOIN FieldOwners fo ON sf.owner_id = fo.owner_id
LEFT JOIN Payments p ON b.booking_id = p.booking_id
LEFT JOIN PaymentMethods pm ON p.method_id = pm.method_id;

-- VIEW 2: Field performance and ratings

CREATE VIEW v_field_performance AS
SELECT 
  sf.field_id,
  sf.name AS field_name,
  sf.sport_type,
  sf.price_per_hour,
  sf.status,
  COUNT(DISTINCT b.booking_id) AS total_bookings,
  COUNT(DISTINCT CASE WHEN b.status = 'confirmed' THEN b.booking_id END) AS confirmed_bookings,
  ROUND(AVG(CASE WHEN r.rating IS NOT NULL THEN r.rating END), 2) AS avg_rating,
  COUNT(DISTINCT r.review_id) AS total_reviews,
  ROUND(SUM(CASE WHEN p.payment_id IS NOT NULL THEN p.amount ELSE 0 END), 2) AS total_revenue
FROM SportFields sf
LEFT JOIN Bookings b ON sf.field_id = b.field_id
LEFT JOIN Payments p ON b.booking_id = p.booking_id AND p.status = 'paid'
LEFT JOIN Reviews r ON b.booking_id = r.booking_id
GROUP BY sf.field_id, sf.name, sf.sport_type, sf.price_per_hour, sf.status;

-- VIEW 3: User Spending Summary

CREATE VIEW v_user_spending AS
SELECT 
  u.user_id,
  u.uname,
  u.email,
  COUNT(DISTINCT b.booking_id) AS total_bookings,
  ROUND(SUM(p.amount), 2) AS total_spent,
  ROUND(AVG(p.amount), 2) AS avg_booking_value,
  MAX(b.booking_datetime) AS last_booking_date
FROM Users u
LEFT JOIN Bookings b ON u.user_id = b.user_id
LEFT JOIN Payments p ON b.booking_id = p.booking_id AND p.status = 'paid'
GROUP BY u.user_id, u.uname, u.email;

-- ========== QUERIES USING CTE's ==========

/*--ctes are temporary result sets that can be referenced within a SELECT, INSERT, UPDATE, or DELETE statement*/

-- CTE 1: Categorizes users by spending and activity

WITH user_activity AS (
  SELECT 
    u.user_id,
    u.uname,
    COUNT(b.booking_id) AS total_bookings,
    ROUND(SUM(p.amount), 2) AS total_spent,
    MAX(b.booking_datetime) AS last_booking,
    DATEDIFF(NOW(), MAX(b.booking_datetime)) AS days_inactive
  FROM Users u
  LEFT JOIN Bookings b ON u.user_id = b.user_id
  LEFT JOIN Payments p ON b.booking_id = p.booking_id AND p.status = 'paid'
  GROUP BY u.user_id, u.uname
)
SELECT 
  user_id,
  uname,
  total_bookings,
  total_spent,
  CASE 
    WHEN total_spent >= 5000 THEN 'Platinum'
    WHEN total_spent >= 3000 THEN 'Gold'
    WHEN total_spent >= 1500 THEN 'Silver'
    ELSE 'Standard'
  END AS loyalty_tier,
  CASE 
    WHEN days_inactive <= 30 THEN 'Active'
    WHEN days_inactive <= 90 THEN 'At risk'
    ELSE 'Inactive'
  END AS status
FROM user_activity
WHERE total_bookings > 0
ORDER BY total_spent DESC;


-- CTE 2: Identifies best performing fields with revenue percentage

WITH field_stats AS (
  SELECT 
    sf.field_id,
    sf.name,
    sf.sport_type,
    COUNT(b.booking_id) AS bookings,
    ROUND(SUM(p.amount), 2) AS revenue,
    ROUND(AVG(r.rating), 2) AS avg_rating
  FROM SportFields sf
  LEFT JOIN Bookings as b ON sf.field_id = b.field_id
  LEFT JOIN Payments p ON b.booking_id = p.booking_id AND p.status = 'paid'
  LEFT JOIN Reviews as r ON b.booking_id = r.booking_id
  GROUP BY sf.field_id, sf.name, sf.sport_type
)

SELECT 
  /*ROW_NUMBER(): A window function that assigns a unique number to each row*/
  ROW_NUMBER() OVER (ORDER BY revenue DESC) AS 'rank', 
  name,
  sport_type,
  bookings,
  revenue,
  avg_rating,
  ROUND(revenue / SUM(revenue) OVER () * 100, 2) AS revenue_percent
FROM field_stats
WHERE bookings > 0
ORDER BY `rank`;

-- ========== CORRELATED QUERIES ==========

-- CORRELATED QUERY 1: Shows users who spend more than overall average per booking

SELECT 
  u.user_id,
  u.uname,
  (SELECT COUNT(*) FROM Bookings as b WHERE b.user_id = u.user_id) AS total_bookings,
  (SELECT ROUND(AVG(p.amount), 2) FROM Payments as p 
   JOIN Bookings as b ON p.booking_id = b.booking_id 
   WHERE b.user_id = u.user_id AND p.status = 'paid') AS user_avg_spend
FROM Users as u
WHERE (SELECT ROUND(AVG(p.amount), 2) 
FROM Payments as p JOIN Bookings as b ON p.booking_id = b.booking_id 
WHERE b.user_id = u.user_id AND p.status = 'paid') > (SELECT AVG(amount) FROM Payments WHERE status = 'paid')
ORDER BY user_avg_spend DESC;

-- CORRELATED QUERY 2: Identifies underperforming fields that need improvement

SELECT 
  sf.field_id,
  sf.name,
  (SELECT ROUND(AVG(rating), 2) FROM Reviews as r 
   WHERE r.field_id = sf.field_id) AS field_rating,
  (SELECT COUNT(*) FROM Reviews as r WHERE r.field_id = sf.field_id) AS review_count,
  (SELECT ROUND(AVG(rating), 2) FROM Reviews) AS overall_avg_rating
FROM SportFields as sf
WHERE (SELECT ROUND(AVG(rating), 2) 
FROM Reviews as r 
WHERE 
r.field_id = sf.field_id) < (SELECT AVG(rating) FROM Reviews) 
AND (SELECT COUNT(*) FROM Reviews r WHERE r.field_id = sf.field_id) > 0
ORDER BY field_rating ASC;

-- ========== REVIEW-FOCUSED QUERIES (NEW FEATURES) ========== 

-- REVIEW QUERY 1: Latest reviews with reviewer and field context (last 20)
SELECT 
  r.review_id,
  r.created_at,
  u.uname       AS reviewer,
  sf.name       AS field_name,
  sf.sport_type,
  r.rating,
  r.comment,
  r.status,
  r.helpful_count
FROM Reviews r
JOIN Users u       ON r.user_id = u.user_id
JOIN SportFields sf ON r.field_id = sf.field_id
ORDER BY r.created_at DESC
LIMIT 20;

-- REVIEW QUERY 2 (CTE): Owner moderation queue — pending reviews per owner, with impact metrics
WITH owner_pending AS (
  SELECT 
    fo.owner_id,
    fo.business_name,
    sf.field_id,
    sf.name AS field_name,
    COUNT(*) AS pending_reviews,
    ROUND(AVG(r.rating),2) AS pending_avg_rating,
    SUM(r.helpful_count) AS pending_helpful_votes
  FROM Reviews r
  JOIN SportFields sf ON r.field_id = sf.field_id
  JOIN FieldOwners fo ON sf.owner_id = fo.owner_id
  WHERE r.status = 'pending'
  GROUP BY fo.owner_id, fo.business_name, sf.field_id, sf.name
)
SELECT 
  owner_id,
  business_name,
  field_id,
  field_name,
  pending_reviews,
  pending_avg_rating,
  pending_helpful_votes
FROM owner_pending
ORDER BY pending_reviews DESC, pending_helpful_votes DESC;

-- REVIEW QUERY 3: Field reputation snapshot — average rating, review counts, and helpful votes
SELECT 
  sf.field_id,
  sf.name AS field_name,
  sf.sport_type,
  COUNT(r.review_id) AS total_reviews,
  ROUND(AVG(r.rating),2) AS avg_rating,
  SUM(r.helpful_count) AS total_helpful_votes,
  SUM(CASE WHEN r.status = 'pending' THEN 1 ELSE 0 END) AS pending_reviews,
  SUM(CASE WHEN r.status = 'published' THEN 1 ELSE 0 END) AS published_reviews
FROM SportFields sf
LEFT JOIN Reviews r ON sf.field_id = r.field_id
GROUP BY sf.field_id, sf.name, sf.sport_type
ORDER BY avg_rating IS NULL, avg_rating DESC, total_reviews DESC;

-- ========== AGGREGATE FUNCTIONS ==========

-- AGGREGATE QUERY 1: Summary of payments by payment method

SELECT 
  pm.method_name,
  COUNT(p.payment_id) AS transaction_count,
  ROUND(SUM(p.amount), 2) AS total_amount,
  ROUND(AVG(p.amount), 2) AS avg_amount,
  COUNT(DISTINCT b.user_id) AS unique_users,
  ROUND(SUM(p.amount) / (SELECT SUM(amount) FROM Payments) * 100, 2) AS revenue_percent
FROM PaymentMethods AS pm
LEFT JOIN Payments p ON pm.method_id = p.method_id
LEFT JOIN Bookings b ON p.booking_id = b.booking_id
GROUP BY pm.method_name
ORDER BY total_amount DESC;

-- ========== SPORTSPOT ESSENTIAL STORED PROCEDURES ==========

-- STORED PROCEDURE 1 : Finds available fields for booking on a specific date and time

DELIMITER $$
CREATE PROCEDURE sp_get_available_fields(
  IN p_sport_type VARCHAR(50),
  IN p_booking_date DATE,
  IN p_start_hour TIME,
  IN p_end_hour TIME
)
BEGIN
  SELECT 
    sf.field_id,
    sf.name,
    sf.price_per_hour,
    sf.capacity,
    sf.address,
    fo.business_name AS owner,
    fp.avg_rating,
    fp.total_reviews,
    (sf.price_per_hour * HOUR(TIMEDIFF(p_end_hour, p_start_hour))) AS estimated_cost
  FROM SportFields sf
  JOIN FieldOwners fo ON sf.owner_id = fo.owner_id
  JOIN v_field_performance fp ON sf.field_id = fp.field_id
  WHERE sf.sport_type = p_sport_type
    AND sf.status = 'available'
    AND sf.opening_hour <= p_start_hour
    AND sf.closing_hour >= p_end_hour
    AND sf.field_id NOT IN (
      SELECT DISTINCT field_id
      FROM Bookings
      WHERE DATE(booking_datetime) = p_booking_date
        AND status IN ('confirmed', 'pending')
        AND p_start_hour < end_time
        AND p_end_hour > start_time
    )
  ORDER BY fp.avg_rating DESC, sf.price_per_hour ASC;
END$$
DELIMITER ;

-- STORED PROCEDURE 2 : Records a payment for a booking and logs it to audit trail

DELIMITER $$
CREATE PROCEDURE sp_process_payment(
  IN p_booking_id INT,
  IN p_user_id INT,
  IN p_method_id INT,
  IN p_amount DECIMAL(10,2)
)
BEGIN
  DECLARE v_booking_status VARCHAR(20);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  
  START TRANSACTION;
  
  -- Validate booking exists and belongs to user
  SELECT status INTO v_booking_status
  FROM Bookings WHERE booking_id = p_booking_id AND user_id = p_user_id;
  IF v_booking_status IS NULL THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Booking not found';
  END IF;
  
  IF v_booking_status = 'cancelled' THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Cannot pay for cancelled booking';
  END IF;
  
  IF p_amount <= 0 THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Payment amount must be greater than zero';
  END IF;
  
  IF EXISTS (SELECT 1 FROM Payments WHERE booking_id = p_booking_id) THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Payment already exists for this booking';
  END IF;
  
  -- Insert payment
  INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
  VALUES (p_booking_id, p_user_id, p_method_id, p_amount, 'paid');
  
  UPDATE Bookings 
  SET status = 'confirmed' 
  WHERE booking_id = p_booking_id;
  COMMIT;
  
  SELECT 'Payment processed successfully' AS message,
         p_amount AS amount_paid,
         NOW() AS payment_time;
END$$
DELIMITER ;

-- STORED PROCEDURE 3 : Cancels a booking and triggers automatic refund

DELIMITER $$
CREATE PROCEDURE sp_cancel_booking(
  IN p_booking_id INT,
  IN p_user_id INT,
  IN p_reason VARCHAR(255)
)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  
  START TRANSACTION;
  
  -- Get current status
  SELECT status INTO v_status
  FROM Bookings WHERE booking_id = p_booking_id;
  
  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Booking not found';
  END IF;
  
  IF v_status = 'cancelled' THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Booking already cancelled';
  END IF;
  
  -- Update booking status (triggers automatic refund via trigger)
  UPDATE Bookings
  SET status = 'cancelled'
  WHERE booking_id = p_booking_id;
  
  COMMIT;
  
  SELECT 'Booking cancelled successfully' AS message,p_reason AS cancellation_reason,'Payment will be refunded automatically' AS note,NOW() AS cancelled_at;
END$$
DELIMITER ;

-- STORED PROCEDURE 4 : Retrieves user spending summary and booking details

DELIMITER $$
CREATE PROCEDURE sp_get_user_booking_history(
  IN p_user_id INT
)
BEGIN
  -- User spending summary from view
  SELECT * FROM v_user_spending 
  WHERE user_id = p_user_id;
  
  -- Detailed booking list with complete information
  SELECT * FROM v_booking_complete_summary 
  WHERE booking_id IN (
    SELECT booking_id FROM Bookings WHERE user_id = p_user_id
  )
  ORDER BY booking_datetime DESC;
END$$
DELIMITER ;
