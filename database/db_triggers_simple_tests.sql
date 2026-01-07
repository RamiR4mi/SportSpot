-- SPORTSPOT TRIGGERS - SIMPLE TESTS
-- Run each section ONE BY ONE
-- NO @ VARIABLES USED
USE SportSpot;

-- ============================================================
-- TEST 1: trg_protect_user_with_active_bookings
-- ============================================================
-- This FAILS (user 1 has bookings)
DELETE FROM Users WHERE user_id = 1;

-- ============================================================
-- TEST 2: trg_user_validate_phone_insert
-- ============================================================
-- This FAILS (9 digits)
INSERT INTO Users (uname, email, password, phone, type) 
VALUES ('Test2', 'test2@x.com', 'pass', '061234567', 'customer');

-- This SUCCEEDS (10 digits)
INSERT INTO Users (uname, email, password, phone, type) 
VALUES ('Test2OK', 'test2ok@x.com', 'pass', '0612345678', 'customer');

-- ============================================================
-- TEST 3: trg_user_validate_phone_update
-- ============================================================
-- This FAILS (7 digits)
UPDATE Users SET phone = '0612345' WHERE user_id = 1;

-- This SUCCEEDS (10 digits)
UPDATE Users SET phone = '0698765432' WHERE user_id = 1;

-- ============================================================
-- TEST 4: trg_fo_validate_phone_insert
-- ============================================================
-- This FAILS (5 digits)
INSERT INTO FieldOwners (user_id, business_name, phone, address) 
VALUES (1, 'TestBiz', '06123', 'Address');

-- This SUCCEEDS (10 digits)
INSERT INTO FieldOwners (user_id, business_name, phone, address) 
VALUES (2, 'TestBiz', '0612345678', 'Address');

-- ============================================================
-- TEST 5: trg_fo_validate_phone_update
-- ============================================================
-- This FAILS (5 digits)
UPDATE FieldOwners SET phone = '06123' WHERE owner_id = 1;

-- This SUCCEEDS (10 digits)
UPDATE FieldOwners SET phone = '0698765432' WHERE owner_id = 1;

-- ============================================================
-- TEST 6: trg_cancel_bookings_on_maintenance
-- ============================================================
-- First make field 4 available and create pending booking
UPDATE SportFields SET status = 'available' WHERE field_id = 4;

INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (2, 4, '10:00:00', '11:00:00', 'pending');

-- Check booking is pending
SELECT booking_id, status FROM Bookings WHERE field_id = 4 ORDER BY booking_id DESC LIMIT 1;

-- Set to maintenance - booking should auto-cancel
UPDATE SportFields SET status = 'maintenance' WHERE field_id = 4;

-- Check booking is now cancelled
SELECT booking_id, status FROM Bookings WHERE field_id = 4 ORDER BY booking_id DESC LIMIT 1;

-- Reset
UPDATE SportFields SET status = 'available' WHERE field_id = 4;

-- ============================================================
-- TEST 7: trg_prevent_booking_overlap_insert
-- ============================================================
-- Field 1 has booking 10:00-12:00 already

-- This FAILS (same slot)
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (2, 1, '10:00:00', '12:00:00', 'pending');

-- This FAILS (overlapping)
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (2, 1, '11:00:00', '13:00:00', 'pending');

-- This SUCCEEDS (no overlap)
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (2, 1, '13:00:00', '14:00:00', 'confirmed');

-- ============================================================
-- TEST 8: trg_prevent_booking_overlap_update
-- ============================================================
-- Get the booking_id of 13:00-14:00 we just created
SELECT booking_id FROM Bookings WHERE field_id = 1 AND start_time = '13:00:00';

-- This FAILS (overlapping with 10:00-12:00) - REPLACE 4 with actual booking_id
UPDATE Bookings SET start_time = '11:00:00', end_time = '12:30:00' WHERE booking_id = 4;    

-- This SUCCEEDS - REPLACE 4 with actual booking_id
UPDATE Bookings SET start_time = '15:00:00', end_time = '16:00:00' WHERE booking_id = 4;

-- ============================================================
-- TEST 9: trg_prevent_booking_maintenance_field
-- ============================================================
-- Field 3 is in maintenance

-- This FAILS
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (2, 3, '10:00:00', '11:00:00', 'pending');

-- ============================================================
-- TEST 10: trg_check_field_operating_hours
-- ============================================================
-- Field 1 operates 08:00-22:00

-- This FAILS (before opening)
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (2, 1, '06:00:00', '07:00:00', 'pending');

-- This FAILS (after closing)
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (2, 1, '22:30:00', '23:30:00', 'pending');

-- ============================================================
-- TEST 11: trg_auto_refund_on_booking_cancel
-- ============================================================
-- Check wallet before
SELECT * FROM UserWallets WHERE user_id = 2;

-- Create booking and payment
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (2, 4, '12:00:00', '13:00:00', 'confirmed');

-- Get booking_id
SELECT booking_id FROM Bookings WHERE user_id = 2 AND field_id = 4 AND start_time = '12:00:00';

-- Add payment - REPLACE 5 with actual booking_id
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (5, 2, 1, 100.00, 'paid');

-- Cancel booking - REPLACE 5 with actual booking_id
UPDATE Bookings SET status = 'cancelled' WHERE booking_id = 5;

-- Check wallet after (should increase)
SELECT * FROM UserWallets WHERE user_id = 2;

-- Check refund record - REPLACE 5 with actual booking_id
SELECT * FROM Refunds WHERE booking_id = 5;

-- ============================================================
-- TEST 12: trg_auto_activate_discount_on_booking
-- ============================================================
-- Create user
INSERT INTO Users (uname, email, password, phone, type) 
VALUES ('DiscUser', 'disc@x.com', 'pass', '0655555555', 'customer');

-- Get user_id
SELECT user_id FROM Users WHERE email = 'disc@x.com';

-- Check discount (inactive) - REPLACE 5 with user_id
SELECT * FROM Discounts WHERE user_id = 5;

-- Create 3 confirmed bookings - REPLACE 5 with user_id
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (5, 1, '08:00:00', '09:00:00', 'confirmed');

INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (5, 2, '11:00:00', '12:00:00', 'confirmed');

INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (5, 4, '14:00:00', '15:00:00', 'confirmed');

-- Check discount (should be active now) - REPLACE 5 with user_id
SELECT * FROM Discounts WHERE user_id = 5;

-- ============================================================
-- TEST 13: trg_prevent_duplicate_payment
-- ============================================================
-- Create booking
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (3, 2, '13:00:00', '14:00:00', 'confirmed');

-- Get booking_id
SELECT booking_id FROM Bookings WHERE user_id = 3 AND field_id = 2 AND start_time = '13:00:00';

-- First payment SUCCEEDS - REPLACE 8 with booking_id
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (8, 3, 1, 50.00, 'paid');

-- Second payment FAILS - REPLACE 8 with booking_id
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (8, 3, 1, 50.00, 'paid');

-- ============================================================
-- TEST 14: trg_prevent_payment_on_cancelled_booking
-- ============================================================
-- Booking 2 is cancelled

-- This FAILS
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (2, 2, 1, 50.00, 'pending');

-- ============================================================
-- TEST 15: trg_check_wallet_balance_before_payment
-- ============================================================
-- Set low balance
UPDATE UserWallets SET balance = 10.00 WHERE user_id = 3;

-- Create booking
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (3, 4, '16:00:00', '17:00:00', 'confirmed');

-- Get booking_id
SELECT booking_id FROM Bookings WHERE user_id = 3 AND field_id = 4 AND start_time = '16:00:00';

-- This FAILS (insufficient balance, method 4 = wallet) - REPLACE 9 with booking_id
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (9, 3, 4, 200.00, 'pending');

-- Add funds
UPDATE UserWallets SET balance = 500.00 WHERE user_id = 3;

-- This SUCCEEDS - REPLACE 9 with booking_id
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (9, 3, 4, 200.00, 'paid');

-- ============================================================
-- TEST 16: trg_prevent_review_on_invalid_booking
-- ============================================================
-- Create pending booking
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status)
VALUES (2, 4, '18:00:00', '19:00:00', 'pending');

-- Get booking_id
SELECT booking_id FROM Bookings WHERE user_id = 2 AND field_id = 4 AND start_time = '18:00:00';

-- This FAILS (pending booking) - REPLACE 10 with booking_id
INSERT INTO Reviews (booking_id, user_id, field_id, rating, comment)
VALUES (10, 2, 4, 5.0, 'Good');

-- Confirm booking - REPLACE 10 with booking_id
UPDATE Bookings SET status = 'confirmed' WHERE booking_id = 10;

-- This SUCCEEDS - REPLACE 10 with booking_id
INSERT INTO Reviews (booking_id, user_id, field_id, rating, comment)
VALUES (10, 2, 4, 5.0, 'Good');

-- ============================================================
-- TEST 17: trg_create_discount_for_new_user
-- ============================================================
-- Create user
INSERT INTO Users (uname, email, password, phone, type) 
VALUES ('NewCust', 'new@x.com', 'pass', '0666666666', 'customer');

-- Get user_id
SELECT user_id FROM Users WHERE email = 'new@x.com';

-- Check discount auto-created - REPLACE 6 with user_id
SELECT * FROM Discounts WHERE user_id = 6;

-- ============================================================
-- TEST 18: auto_create_fieldowner_on_user_insert
-- ============================================================
-- Create owner user
INSERT INTO Users (uname, email, password, phone, type) 
VALUES ('NewOwn', 'own@x.com', 'pass', '0677777777', 'owner');

-- Get user_id
SELECT user_id FROM Users WHERE email = 'own@x.com';

-- Check FieldOwner auto-created - REPLACE 7 with user_id
SELECT * FROM FieldOwners WHERE user_id = 7;

-- ============================================================
-- DONE
-- ============================================================
SELECT 'ALL TESTS COMPLETE' AS Result;
