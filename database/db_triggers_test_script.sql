-- ============================================================
-- SPORTSPOT TRIGGERS TEST SCRIPT
-- For Video Demonstration
-- ============================================================
-- This script tests all triggers in your database.
-- Run each section one at a time to demonstrate trigger behavior.
-- ============================================================

USE SportSpot;

-- ============================================================
-- PREPARATION: First, let's check existing data
-- ============================================================

-- View current users
SELECT * FROM Users LIMIT 5;

-- View current field owners
SELECT * FROM FieldOwners LIMIT 5;

-- View current sport fields
SELECT * FROM SportFields LIMIT 5;

-- View current bookings
SELECT * FROM Bookings LIMIT 5;


-- ============================================================
-- TEST 4: trg_protect_user_with_active_bookings
-- Purpose: Prevent deletion of users with active (pending/confirmed) bookings
-- ============================================================

-- First, let's find a user with active bookings
SELECT u.user_id, u.uname, COUNT(b.booking_id) as active_bookings
FROM Users u
JOIN Bookings b ON u.user_id = b.user_id
WHERE b.status IN ('pending', 'confirmed')
GROUP BY u.user_id, u.uname
LIMIT 1;

-- If found, try to delete that user (save the user_id first)
-- TEST 4A: This should FAIL
-- DELETE FROM Users WHERE user_id = [user_id_with_active_bookings];
-- Expected Error: "Cannot delete user with active bookings"

-- TEST 4B: Create a user with no bookings and delete them (should succeed)
INSERT INTO Users (uname, email, password, phone, type) 
VALUES ('Delete Me', 'deleteme@test.com', 'password123', '5555555555', 'customer');

SET @delete_user_id = (SELECT user_id FROM Users WHERE email = 'deleteme@test.com');

-- This should SUCCEED (no active bookings)
DELETE FROM Users WHERE user_id = @delete_user_id;

-- Verify deletion
SELECT * FROM Users WHERE email = 'deleteme@test.com'; -- Should return empty

-- ============================================================

-- ============================================================
-- TEST 1: trg_user_validate_phone_insert
-- Purpose: Validates phone must be exactly 10 digits on INSERT
-- ============================================================

-- TEST 1A: This should FAIL (phone too short - 9 digits)
INSERT INTO Users (uname, email, password, phone, type) 
VALUES ('Test User 1', 'testuser1@test.com', 'password123', '123456789', 'customer');
-- Expected Error: "Invalid phone format. Must be exactly 10 digits."

-- TEST 1B: This should FAIL (phone too long - 11 digits)
INSERT INTO Users (uname, email, password, phone, type) 
VALUES ('Test User 2', 'testuser2@test.com', 'password123', '12345678901', 'customer');
-- Expected Error: "Invalid phone format. Must be exactly 10 digits."



-- ============================================================
-- TEST 2: trg_user_validate_phone_update
-- Purpose: Validates phone must be exactly 10 digits on UPDATE
-- ============================================================

-- TEST 1C: This should SUCCEED (exactly 10 digits)
INSERT INTO Users (uname, email, password, phone, type) 
VALUES ('Test User Valid', 'testvalid@test.com', 'password123', '1234567890', 'customer');
-- Expected: Successfully inserted (should be blocked by check constraint)

-- Verify the insert worked
SELECT * FROM Users WHERE email = 'testvalid@test.com';


-- First, find the user we just created
SET @test_user_id = (SELECT user_id FROM Users WHERE email = 'testvalid@test.com');

-- TEST 2A: This should FAIL (updating to invalid phone)
UPDATE Users SET phone = '123' WHERE user_id = @test_user_id;
-- Expected Error: "Invalid phone format. Must be exactly 10 digits."

-- TEST 2B: This should SUCCEED (valid 10-digit phone)
UPDATE Users SET phone = '9876543210' WHERE user_id = @test_user_id;
-- Expected: Successfully updated

-- Verify the update worked
SELECT * FROM Users WHERE user_id = @test_user_id;

-- ============================================================
-- TEST 3: trg_fo_validate_phone_insert
-- Purpose: Validates FieldOwner phone must be exactly 10 digits
-- ============================================================

-- First, create an owner user
INSERT INTO Users (uname, email, password, phone, type) 
VALUES ('Owner Test', 'ownertest@test.com', 'password123', '1112223333', 'owner');

SET @owner_user_id = (SELECT user_id FROM Users WHERE email = 'ownertest@test.com');

-- Note: The auto_create_fieldowner_on_user_insert trigger already created a FieldOwner
-- So let's test manual insert with invalid phone

-- TEST 3A: This should FAIL (invalid phone)
INSERT INTO FieldOwners (user_id, business_name, phone, address) 
VALUES (@owner_user_id, 'Test Business', '12345', 'Test Address');
-- Expected Error: "Invalid phone format for Field Owner. Must be exactly 10 digits."
-- Note: This might also fail due to duplicate user_id since auto-trigger already created one


-- TEST 5: trg_prevent_booking_maintenance_field
-- Purpose: Prevent booking on fields under maintenance
-- ============================================================

-- First, find or create a field under maintenance
UPDATE SportFields SET status = 'maintenance' WHERE field_id = 1;

-- Find a valid user for booking
SET @booking_user_id = (SELECT user_id FROM Users WHERE type = 'customer' LIMIT 1);

-- TEST 5A: This should FAIL (field is under maintenance)
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@booking_user_id, 1, '08:00:00', '09:00:00', 'pending', 100.00);
-- Expected Error: "Cannot book: Field is currently under maintenance"

-- Restore field to available for further tests
UPDATE SportFields SET status = 'available' WHERE field_id = 1;

-- ============================================================
-- TEST 6: trg_check_field_operating_hours
-- Purpose: Prevent booking outside field operating hours
-- ============================================================

-- First, check field operating hours
SELECT field_id, field_name, opening_hour, closing_hour FROM SportFields WHERE field_id = 1;

-- TEST 6A: This should FAIL (booking before opening hours)
-- Assuming field opens at 08:00
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@booking_user_id, 1, '05:00:00', '06:00:00', 'pending', 100.00);
-- Expected Error: "Booking time outside field operating hours"

-- TEST 6B: This should FAIL (booking after closing hours)
-- Assuming field closes at 22:00
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@booking_user_id, 1, '23:00:00', '23:59:00', 'pending', 100.00);
-- Expected Error: "Booking time outside field operating hours"

-- ============================================================
-- TEST 7: trg_prevent_booking_overlap_insert
-- Purpose: Prevent double booking (time slot conflict)
-- ============================================================

-- First, create a valid booking
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@booking_user_id, 1, '10:00:00', '11:00:00', 'confirmed', 100.00);

SET @first_booking_id = LAST_INSERT_ID();

-- TEST 7A: This should FAIL (exact same time slot)
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@booking_user_id, 1, '10:00:00', '11:00:00', 'pending', 100.00);
-- Expected Error: "Time slot conflict: Field is already booked for this time"

-- TEST 7B: This should FAIL (overlapping time - starts during existing booking)
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@booking_user_id, 1, '10:30:00', '11:30:00', 'pending', 100.00);
-- Expected Error: "Time slot conflict: Field is already booked for this time"

-- TEST 7C: This should SUCCEED (different time slot - no overlap)
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@booking_user_id, 1, '12:00:00', '13:00:00', 'pending', 100.00);
-- Expected: Successfully inserted

-- ============================================================
-- TEST 8: trg_prevent_booking_overlap_update
-- Purpose: Prevent rescheduling to overlapping time
-- ============================================================

SET @second_booking_id = LAST_INSERT_ID();

-- TEST 8A: This should FAIL (rescheduling to overlap with first booking)
UPDATE Bookings SET start_time = '10:15:00', end_time = '11:15:00' 
WHERE booking_id = @second_booking_id;
-- Expected Error: "Time slot conflict: Field is already booked for this time"

-- TEST 8B: This should SUCCEED (rescheduling to non-overlapping time)
UPDATE Bookings SET start_time = '14:00:00', end_time = '15:00:00' 
WHERE booking_id = @second_booking_id;
-- Expected: Successfully updated

-- ============================================================
-- TEST 9: trg_cancel_bookings_on_maintenance
-- Purpose: Auto-cancel pending bookings when field goes to maintenance
-- ============================================================

-- Create a pending booking on field 2
UPDATE SportFields SET status = 'available' WHERE field_id = 2;

-- Check field 2 operating hours first
SELECT opening_hour, closing_hour FROM SportFields WHERE field_id = 2;

INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@booking_user_id, 2, '09:00:00', '10:00:00', 'pending', 100.00);

SET @pending_booking_id = LAST_INSERT_ID();

-- Verify booking is pending
SELECT booking_id, status FROM Bookings WHERE booking_id = @pending_booking_id;

-- TEST 9A: Set field to maintenance - booking should auto-cancel
UPDATE SportFields SET status = 'maintenance' WHERE field_id = 2;

-- Verify booking is now cancelled
SELECT booking_id, status FROM Bookings WHERE booking_id = @pending_booking_id;
-- Expected: status should now be 'cancelled'

-- Restore field status
UPDATE SportFields SET status = 'available' WHERE field_id = 2;

-- ============================================================
-- TEST 10: trg_prevent_duplicate_payment
-- Purpose: Prevent multiple payments for same booking
-- ============================================================

-- First, create a new booking for payment testing
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@booking_user_id, 2, '11:00:00', '12:00:00', 'confirmed', 150.00);

SET @payment_booking_id = LAST_INSERT_ID();

-- Create first payment (should succeed)
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@payment_booking_id, @booking_user_id, 1, 150.00, 'paid');

-- TEST 10A: Try to create second payment (should FAIL)
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@payment_booking_id, @booking_user_id, 1, 150.00, 'paid');
-- Expected Error: "Payment already exists for this booking"

-- ============================================================
-- TEST 11: trg_prevent_payment_on_cancelled_booking
-- Purpose: Prevent payment for cancelled bookings
-- ============================================================

-- Create a cancelled booking
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@booking_user_id, 2, '15:00:00', '16:00:00', 'cancelled', 100.00);

SET @cancelled_booking_id = LAST_INSERT_ID();

-- TEST 11A: Try to pay for cancelled booking (should FAIL)
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@cancelled_booking_id, @booking_user_id, 1, 100.00, 'pending');
-- Expected Error: "Cannot process payment for cancelled booking"

-- ============================================================
-- TEST 12: trg_check_wallet_balance_before_payment
-- Purpose: Check wallet balance when paying with wallet
-- ============================================================

-- First, check what payment method is 'wallet'
SELECT * FROM PaymentMethods WHERE method_name = 'wallet';

-- Set wallet method ID (adjust based on your data)
SET @wallet_method_id = (SELECT method_id FROM PaymentMethods WHERE method_name = 'wallet');

-- Create/Update user wallet with low balance
INSERT INTO UserWallets (user_id, balance) VALUES (@booking_user_id, 10.00)
ON DUPLICATE KEY UPDATE balance = 10.00;

-- Create a new booking
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@booking_user_id, 2, '17:00:00', '18:00:00', 'confirmed', 200.00);

SET @wallet_test_booking_id = LAST_INSERT_ID();

-- TEST 12A: This should FAIL (insufficient wallet balance)
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@wallet_test_booking_id, @booking_user_id, @wallet_method_id, 200.00, 'pending');
-- Expected Error: "Insufficient wallet balance for this payment"

-- Add funds to wallet and try again
UPDATE UserWallets SET balance = 500.00 WHERE user_id = @booking_user_id;

-- TEST 12B: This should SUCCEED (sufficient balance)
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@wallet_test_booking_id, @booking_user_id, @wallet_method_id, 200.00, 'paid');
-- Expected: Successfully inserted

-- ============================================================
-- TEST 13: trg_auto_refund_on_booking_cancel
-- Purpose: Auto-process refund when paid booking is cancelled
-- ============================================================

-- Check wallet balance before cancellation
SELECT * FROM UserWallets WHERE user_id = @booking_user_id;

-- Cancel the booking we just paid for
UPDATE Bookings SET status = 'cancelled' WHERE booking_id = @wallet_test_booking_id;

-- Verify:
-- 1. Wallet balance increased by refund amount
SELECT * FROM UserWallets WHERE user_id = @booking_user_id;

-- 2. Payment status changed to 'refunded'
SELECT * FROM Payments WHERE booking_id = @wallet_test_booking_id;

-- 3. Refund record created
SELECT * FROM Refunds WHERE booking_id = @wallet_test_booking_id;

-- 4. Wallet transaction recorded
SELECT * FROM WalletTransactions WHERE user_id = @booking_user_id ORDER BY created_at DESC LIMIT 5;

-- ============================================================
-- TEST 14: trg_prevent_review_on_invalid_booking
-- Purpose: Only allow reviews on confirmed bookings
-- ============================================================

-- Create a pending booking
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@booking_user_id, 2, '19:00:00', '20:00:00', 'pending', 100.00);

SET @pending_review_booking_id = LAST_INSERT_ID();

-- TEST 14A: This should FAIL (booking is pending, not confirmed)
INSERT INTO Reviews (booking_id, user_id, field_id, rating, review_text)
VALUES (@pending_review_booking_id, @booking_user_id, 2, 5, 'Great field!');
-- Expected Error: "Can only review confirmed bookings"

-- Change booking to confirmed
UPDATE Bookings SET status = 'confirmed' WHERE booking_id = @pending_review_booking_id;

-- TEST 14B: This should SUCCEED (booking is confirmed)
INSERT INTO Reviews (booking_id, user_id, field_id, rating, review_text)
VALUES (@pending_review_booking_id, @booking_user_id, 2, 5, 'Great field!');
-- Expected: Successfully inserted

-- ============================================================
-- TEST 15: trg_create_discount_for_new_user
-- Purpose: Auto-create discount record for new users
-- ============================================================

-- Create a new user
INSERT INTO Users (uname, email, password, phone, type) 
VALUES ('Discount Test User', 'discounttest@test.com', 'password123', '7777777777', 'customer');

SET @discount_user_id = LAST_INSERT_ID();

-- Verify discount was auto-created
SELECT * FROM Discounts WHERE user_id = @discount_user_id;
-- Expected: One row with booking_threshold=3, discount_percent=5.00, status='inactive'

-- ============================================================
-- TEST 16: auto_create_fieldowner_on_user_insert
-- Purpose: Auto-create FieldOwner when user type is 'owner'
-- ============================================================

-- Create a new owner user
INSERT INTO Users (uname, email, password, phone, type) 
VALUES ('Auto Owner Test', 'autoowner@test.com', 'password123', '8888888888', 'owner');

SET @auto_owner_user_id = LAST_INSERT_ID();

-- Verify FieldOwner was auto-created
SELECT * FROM FieldOwners WHERE user_id = @auto_owner_user_id;
-- Expected: One row with business_name like 'Field Business - Auto Owner Test'

-- ============================================================
-- TEST 17: trg_auto_activate_discount_on_booking
-- Purpose: Auto-activate discount when booking threshold reached
-- ============================================================

-- Check current discount status
SELECT * FROM Discounts WHERE user_id = @discount_user_id;

-- The threshold is 3 confirmed bookings
-- Create 3 confirmed bookings for the user
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@discount_user_id, 1, '08:00:00', '09:00:00', 'confirmed', 100.00);

INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@discount_user_id, 1, '09:00:00', '10:00:00', 'confirmed', 100.00);

-- This 3rd booking should trigger discount activation
INSERT INTO Bookings (user_id, field_id, start_time, end_time, status, total_price)
VALUES (@discount_user_id, 1, '11:00:00', '12:00:00', 'confirmed', 100.00);

-- Verify discount was activated
SELECT * FROM Discounts WHERE user_id = @discount_user_id;
-- Expected: status should now be 'active', activated_date should be set

-- ============================================================
-- CLEANUP: Remove test data (OPTIONAL - run after video)
-- ============================================================

-- Uncomment these lines to clean up test data
/*
DELETE FROM Reviews WHERE review_text = 'Great field!';
DELETE FROM Refunds WHERE reason LIKE '%automatic refund%';
DELETE FROM WalletTransactions WHERE reference LIKE 'refund:booking:%';
DELETE FROM Payments WHERE booking_id IN (SELECT booking_id FROM Bookings WHERE user_id IN 
    (SELECT user_id FROM Users WHERE email LIKE '%test.com'));
DELETE FROM Bookings WHERE user_id IN (SELECT user_id FROM Users WHERE email LIKE '%test.com');
DELETE FROM Discounts WHERE user_id IN (SELECT user_id FROM Users WHERE email LIKE '%test.com');
DELETE FROM FieldOwners WHERE user_id IN (SELECT user_id FROM Users WHERE email LIKE '%test.com');
DELETE FROM UserWallets WHERE user_id IN (SELECT user_id FROM Users WHERE email LIKE '%test.com');
DELETE FROM Users WHERE email LIKE '%test.com';

-- Restore field statuses
UPDATE SportFields SET status = 'available' WHERE field_id IN (1, 2);
*/

-- ============================================================
-- END OF TRIGGER TEST SCRIPT
-- ============================================================
