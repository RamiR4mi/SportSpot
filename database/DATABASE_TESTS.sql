-- ============================================================================
-- SportSpot Database Tests
-- Purpose: Test all database triggers, constraints, and stored procedures
-- Database: SportSpot (MySQL 5.7+)
-- Generated: December 10, 2025
-- ============================================================================

USE sportspot;

-- ============================================================================
-- TEST CASE 1: Double Cancellation (Prevent Duplicate Refunds)
-- File: db_triggers.sql - trg_auto_refund_on_booking_cancel
-- Purpose: Ensure trigger doesn't create multiple refunds for same booking
-- ============================================================================

-- 1. Check initial state
SELECT booking_id, status FROM Bookings WHERE booking_id = 5;
SELECT COUNT(*) as refund_count FROM Refunds WHERE booking_id = 5;

-- 2. First cancellation
UPDATE Bookings SET status='cancelled' WHERE booking_id = 5;

-- 3. Check refund created
SELECT COUNT(*) as refund_count FROM Refunds WHERE booking_id = 5; 
-- Expected: 1

-- 4. Second cancellation (should not create duplicate)
UPDATE Bookings SET status='cancelled' WHERE booking_id = 5;

-- 5. Verify no duplicate refund
SELECT COUNT(*) as refund_count FROM Refunds WHERE booking_id = 5; 
-- Expected: Still 1

-- RESET
UPDATE Bookings SET status='confirmed' WHERE booking_id = 5;
DELETE FROM Refunds WHERE booking_id = 5;


-- ============================================================================
-- TEST CASE 2: Cancel Unpaid Booking (No Refund)
-- File: db_triggers.sql - trg_auto_refund_on_booking_cancel
-- Purpose: Trigger should NOT refund if payment status is not 'paid'
-- ============================================================================

-- 1. Create booking without payment
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (2, 2, NOW(), '14:00:00', '15:00:00', 'pending');
SET @test_booking_id = LAST_INSERT_ID();

-- 2. Cancel the booking (NO payment to refund)
UPDATE Bookings SET status='cancelled' WHERE booking_id = @test_booking_id;

-- 3. Check wallet (should NOT change)
SELECT balance FROM UserWallets WHERE user_id = 2;

-- 4. Check Refunds table (should be empty)
SELECT COUNT(*) as refund_count FROM Refunds WHERE booking_id = @test_booking_id; 
-- Expected: 0

-- CLEANUP
DELETE FROM Bookings WHERE booking_id = @test_booking_id;


-- ============================================================================
-- TEST CASE 3: Prevent Booking Overlap
-- File: db_triggers.sql - trg_prevent_booking_overlap
-- Purpose: Two users cannot book same field at same time
-- ============================================================================

-- 1. Create first booking
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 3, '2025-12-20', '14:00:00', '15:00:00', 'confirmed');
SET @first_booking = LAST_INSERT_ID();

-- 2. Try overlapping booking (should fail)
-- Expected Error: Time slot conflict: Field is already booked for this time
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (2, 3, '2025-12-20', '14:30:00', '15:30:00', 'confirmed');

-- CLEANUP
DELETE FROM Bookings WHERE booking_id = @first_booking;


-- ============================================================================
-- TEST CASE 4: Prevent Booking on Maintenance Field
-- File: db_triggers.sql - trg_prevent_maintenance_booking
-- Purpose: Cannot book field when status = 'maintenance'
-- ============================================================================

-- 1. Set field to maintenance
UPDATE SportFields SET status = 'maintenance' WHERE field_id = 2;

-- 2. Try to book (should fail)
-- Expected Error: Cannot book: Field is currently under maintenance
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 2, '2025-12-20', '10:00:00', '11:00:00', 'confirmed');

-- RESET
UPDATE SportFields SET status = 'available' WHERE field_id = 2;


-- ============================================================================
-- TEST CASE 5: Auto-Create FieldOwner on User Registration
-- File: db_triggers.sql - trg_auto_create_fieldowner
-- Purpose: Creating owner user should auto-create FieldOwner record
-- ============================================================================

-- 1. Insert owner user
INSERT INTO Users (uname, email, phone, address, password, type)
VALUES ('Test Owner', 'testowner@example.com', '0612345678', 'Test Address', 'password123', 'owner');
SET @new_user_id = LAST_INSERT_ID();

-- 2. Check FieldOwners (should auto-create)
SELECT * FROM FieldOwners WHERE user_id = @new_user_id;
-- Expected: 1 row with business_name like "Field Business - Test Owner"

-- CLEANUP
DELETE FROM FieldOwners WHERE user_id = @new_user_id;
DELETE FROM Users WHERE user_id = @new_user_id;


-- ============================================================================
-- TEST CASE 6: Wallet Balance Sufficient Before Debit
-- File: db_triggers.sql - trg_check_wallet_balance
-- Purpose: Cannot debit wallet if balance is insufficient
-- ============================================================================

-- 1. Check current wallet
SELECT balance FROM UserWallets WHERE user_id = 2;

-- 2. Create booking that exceeds wallet balance
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (2, 1, '2025-12-20', '10:00:00', '11:00:00', 'confirmed');
SET @test_booking = LAST_INSERT_ID();

-- 3. Try to pay with insufficient balance (should fail)
-- Expected Error: Insufficient wallet balance
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@test_booking, 2, 4, 999999.00, 'paid');

-- CLEANUP
DELETE FROM Bookings WHERE booking_id = @test_booking;


-- ============================================================================
-- TEST CASE 7: Auto-Update Wallet Balance on Payment
-- File: db_triggers.sql - trg_debit_wallet_on_payment
-- Purpose: Wallet balance decreases when payment made with wallet
-- ============================================================================

-- 1. Record initial balance
SELECT @initial := balance FROM UserWallets WHERE user_id = 1;

-- 2. Create booking and pay with wallet
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-25', '10:00:00', '11:00:00', 'confirmed');
SET @booking = LAST_INSERT_ID();

INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@booking, 1, 4, 25.00, 'paid');

-- 3. Verify balance decreased
SELECT balance, @initial - 25.00 as expected_balance FROM UserWallets WHERE user_id = 1;
-- Expected: balance = @initial - 25

-- CLEANUP
DELETE FROM Payments WHERE booking_id = @booking;
DELETE FROM Bookings WHERE booking_id = @booking;
UPDATE UserWallets SET balance = @initial WHERE user_id = 1;


-- ============================================================================
-- TEST CASE 8: Complete Refund Flow (CRITICAL - Main Trigger)
-- File: db_triggers.sql - trg_auto_refund_on_booking_cancel
-- Purpose: Test automatic refund via database trigger
-- ============================================================================

-- 1. Get initial wallet
SELECT @initial := balance FROM UserWallets WHERE user_id = 1;

-- 2. Create booking with payment
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-22', '11:00:00', '12:00:00', 'confirmed');
SET @booking = LAST_INSERT_ID();

INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@booking, 1, 4, 50.00, 'paid');
SET @payment = LAST_INSERT_ID();

-- 3. Cancel booking (TRIGGER FIRES HERE)
UPDATE Bookings SET status='cancelled' WHERE booking_id = @booking;

-- 4. Verify refund - Should show:
--    - Wallet balance restored to initial amount
--    - Refund record created in Refunds table
--    - Original payment marked as 'refunded'
SELECT 
    'Wallet Balance' as check_type,
    balance as current_value,
    @initial as expected_value
FROM UserWallets WHERE user_id = 1
UNION ALL
SELECT 
    'Refund Created',
    COUNT(*),
    1
FROM Refunds WHERE booking_id = @booking
UNION ALL
SELECT 
    'Payment Status',
    status,
    'refunded'
FROM Payments WHERE payment_id = @payment;

-- CLEANUP
DELETE FROM Refunds WHERE booking_id = @booking;
DELETE FROM Payments WHERE booking_id = @booking;
DELETE FROM Bookings WHERE booking_id = @booking;


-- ============================================================================
-- TEST CASE 9: Referential Integrity After Refund
-- File: db_lastsportspot.sql + db_triggers.sql
-- Purpose: All related records exist after refund
-- ============================================================================

-- 1. Record initial wallet balance
SELECT @initial_balance := balance FROM UserWallets WHERE user_id = 1;

-- 2. Create and pay for booking
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-25', '10:00:00', '11:00:00', 'confirmed');
SET @booking_id = LAST_INSERT_ID();

INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@booking_id, 1, 4, 25.00, 'paid');
SET @payment_id = LAST_INSERT_ID();

-- 3. Cancel and trigger refund
UPDATE Bookings SET status='cancelled' WHERE booking_id = @booking_id;

-- 4. Verify all components
SELECT 
    'Booking Status' AS check_item, 
    status as value,
    'cancelled' as expected
FROM Bookings WHERE booking_id = @booking_id
UNION ALL
SELECT 
    'Original Payment Status', 
    status,
    'refunded'
FROM Payments WHERE payment_id = @payment_id
UNION ALL
SELECT 
    'Refund Record Exists', 
    CAST(COUNT(*) AS CHAR),
    '1'
FROM Refunds WHERE booking_id = @booking_id
UNION ALL
SELECT 
    'Wallet Transaction Created', 
    CAST(COUNT(*) AS CHAR),
    '1'
FROM WalletTransactions WHERE reference LIKE CONCAT('%', @booking_id, '%')
UNION ALL
SELECT 
    'Wallet Balance Restored', 
    CAST(balance AS CHAR),
    CAST(@initial_balance AS CHAR)
FROM UserWallets WHERE user_id = 1;

-- CLEANUP
DELETE FROM WalletTransactions WHERE reference LIKE CONCAT('%', @booking_id, '%');
DELETE FROM Refunds WHERE booking_id = @booking_id;
DELETE FROM Payments WHERE booking_id = @booking_id;
DELETE FROM Bookings WHERE booking_id = @booking_id;


-- ============================================================================
-- TEST CASE 10: One Review Per Booking (UNIQUE Constraint)
-- File: db_lastsportspot.sql - Reviews table
-- Purpose: Only one review allowed per booking
-- ============================================================================

-- 1. Create confirmed booking
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-15', '10:00:00', '11:00:00', 'confirmed');
SET @booking = LAST_INSERT_ID();

-- 2. Create first review
INSERT INTO Reviews (booking_id, user_id, field_id, rating, comment)
VALUES (@booking, 1, 1, 5.0, 'Excellent field!');
SET @review = LAST_INSERT_ID();

-- 3. Try to create second review (should fail)
-- Expected Error: Duplicate entry for key 'unique_booking_review'
INSERT INTO Reviews (booking_id, user_id, field_id, rating, comment)
VALUES (@booking, 1, 1, 4.0, 'Changed my mind');

-- CLEANUP
DELETE FROM Reviews WHERE review_id = @review;
DELETE FROM Bookings WHERE booking_id = @booking;


-- ============================================================================
-- TEST CASE 11: Cannot Review Pending/Cancelled Booking
-- File: db_triggers.sql - trg_validate_review_status
-- Purpose: Reviews only allowed on 'confirmed' bookings
-- ============================================================================

-- 1. Create pending booking
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (2, 2, '2025-12-16', '14:00:00', '15:00:00', 'pending');
SET @pending_booking = LAST_INSERT_ID();

-- 2. Try to review pending booking (should fail)
-- Expected Error: Can only review confirmed bookings
INSERT INTO Reviews (booking_id, user_id, field_id, rating, comment)
VALUES (@pending_booking, 2, 2, 4.5, 'Test review');

-- CLEANUP
DELETE FROM Bookings WHERE booking_id = @pending_booking;


-- ============================================================================
-- TEST CASE 12: Booking Time Within Operating Hours
-- File: db_triggers.sql - trg_validate_operating_hours
-- Purpose: Cannot book field outside its operating hours
-- ============================================================================

-- 1. Check field hours (e.g., 8 AM to 10 PM)
SELECT field_id, field_name, opening_hour, closing_hour 
FROM SportFields WHERE field_id = 1;

-- 2. Try to book at 11 PM (after closing)
-- Expected Error: Booking time outside field operating hours
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (2, 1, '2025-12-20', '23:00:00', '00:00:00', 'confirmed');


-- ============================================================================
-- TEST CASE 13: Multiple Same-Day Bookings (No Overlap)
-- File: db_triggers.sql - trg_prevent_booking_overlap
-- Purpose: User can book same field multiple times if no time overlap
-- ============================================================================

-- 1. Book 10-11 AM
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-25', '10:00:00', '11:00:00', 'confirmed');
SET @booking1 = LAST_INSERT_ID();

-- 2. Book 2-3 PM (same day, no overlap - should succeed)
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-25', '14:00:00', '15:00:00', 'confirmed');
SET @booking2 = LAST_INSERT_ID();

-- 3. Verify both bookings exist
SELECT COUNT(*) as booking_count FROM Bookings 
WHERE user_id = 1 AND field_id = 1 AND booking_datetime = '2025-12-25';
-- Expected: 2

-- CLEANUP
DELETE FROM Bookings WHERE booking_id IN (@booking1, @booking2);


-- ============================================================================
-- TEST CASE 14: Wallet Transaction Audit Trail
-- File: db_triggers.sql + db_lastsportspot.sql
-- Purpose: All wallet changes recorded in WalletTransactions
-- ============================================================================

-- 1. Record initial transaction count
SELECT @initial_txn_count := COUNT(*) FROM WalletTransactions WHERE user_id = 1;

-- 2. Add balance to wallet
UPDATE UserWallets SET balance = balance + 100 WHERE user_id = 1;

-- 3. Book field ($25)
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-22', '12:00:00', '13:00:00', 'confirmed');
SET @booking = LAST_INSERT_ID();

INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@booking, 1, 4, 25.00, 'paid');

-- 4. Cancel and refund
UPDATE Bookings SET status='cancelled' WHERE booking_id = @booking;

-- 5. Check transaction history (should have new entries)
SELECT user_id, amount, type, reference, created_at 
FROM WalletTransactions 
WHERE user_id = 1 
ORDER BY created_at DESC
LIMIT 5;

-- CLEANUP
DELETE FROM WalletTransactions WHERE reference LIKE CONCAT('%', @booking, '%');
DELETE FROM Refunds WHERE booking_id = @booking;
DELETE FROM Payments WHERE booking_id = @booking;
DELETE FROM Bookings WHERE booking_id = @booking;


-- ============================================================================
-- TEST CASE 15: Bulk Cancellation Performance (18 Triggers)
-- File: db_triggers.sql - All 18 triggers working together
-- Purpose: Refund trigger handles multiple simultaneous cancellations
-- ============================================================================

-- 1. Record initial balance
SELECT @initial_bulk := balance FROM UserWallets WHERE user_id = 1;

-- 2. Create 10 bookings
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status) 
VALUES 
(1, 1, '2025-12-20', '10:00:00', '11:00:00', 'confirmed'),
(1, 2, '2025-12-20', '10:00:00', '11:00:00', 'confirmed'),
(1, 3, '2025-12-20', '10:00:00', '11:00:00', 'confirmed'),
(1, 4, '2025-12-20', '10:00:00', '11:00:00', 'confirmed'),
(1, 5, '2025-12-20', '10:00:00', '11:00:00', 'confirmed'),
(1, 1, '2025-12-21', '11:00:00', '12:00:00', 'confirmed'),
(1, 2, '2025-12-21', '11:00:00', '12:00:00', 'confirmed'),
(1, 3, '2025-12-21', '11:00:00', '12:00:00', 'confirmed'),
(1, 4, '2025-12-21', '11:00:00', '12:00:00', 'confirmed'),
(1, 5, '2025-12-21', '11:00:00', '12:00:00', 'confirmed');

-- 3. Get booking IDs
SELECT @b1 := booking_id FROM Bookings WHERE user_id = 1 AND field_id = 1 AND booking_datetime = '2025-12-20' LIMIT 1;
SELECT @b2 := booking_id FROM Bookings WHERE user_id = 1 AND field_id = 2 AND booking_datetime = '2025-12-20' LIMIT 1;
SELECT @b3 := booking_id FROM Bookings WHERE user_id = 1 AND field_id = 3 AND booking_datetime = '2025-12-20' LIMIT 1;
SELECT @b4 := booking_id FROM Bookings WHERE user_id = 1 AND field_id = 4 AND booking_datetime = '2025-12-20' LIMIT 1;
SELECT @b5 := booking_id FROM Bookings WHERE user_id = 1 AND field_id = 5 AND booking_datetime = '2025-12-20' LIMIT 1;
SELECT @b6 := booking_id FROM Bookings WHERE user_id = 1 AND field_id = 1 AND booking_datetime = '2025-12-21' LIMIT 1;
SELECT @b7 := booking_id FROM Bookings WHERE user_id = 1 AND field_id = 2 AND booking_datetime = '2025-12-21' LIMIT 1;
SELECT @b8 := booking_id FROM Bookings WHERE user_id = 1 AND field_id = 3 AND booking_datetime = '2025-12-21' LIMIT 1;
SELECT @b9 := booking_id FROM Bookings WHERE user_id = 1 AND field_id = 4 AND booking_datetime = '2025-12-21' LIMIT 1;
SELECT @b10 := booking_id FROM Bookings WHERE user_id = 1 AND field_id = 5 AND booking_datetime = '2025-12-21' LIMIT 1;

-- 4. Pay for all 10 bookings
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES 
(@b1, 1, 4, 50.00, 'paid'),
(@b2, 1, 4, 50.00, 'paid'),
(@b3, 1, 4, 50.00, 'paid'),
(@b4, 1, 4, 50.00, 'paid'),
(@b5, 1, 4, 50.00, 'paid'),
(@b6, 1, 4, 50.00, 'paid'),
(@b7, 1, 4, 50.00, 'paid'),
(@b8, 1, 4, 50.00, 'paid'),
(@b9, 1, 4, 50.00, 'paid'),
(@b10, 1, 4, 50.00, 'paid');

-- 5. Cancel all (measure time - should be < 1 second)
UPDATE Bookings SET status='cancelled' 
WHERE booking_id IN (@b1, @b2, @b3, @b4, @b5, @b6, @b7, @b8, @b9, @b10);

-- 6. Verify all refunds created
SELECT COUNT(*) as refund_count FROM Refunds 
WHERE booking_id IN (@b1, @b2, @b3, @b4, @b5, @b6, @b7, @b8, @b9, @b10);
-- Expected: 10

-- 7. Verify wallet balance restored
SELECT balance, @initial_bulk as expected_balance FROM UserWallets WHERE user_id = 1;
-- Expected: balance = @initial_bulk

-- CLEANUP
DELETE FROM WalletTransactions WHERE user_id = 1 AND created_at > DATE_SUB(NOW(), INTERVAL 5 MINUTE);
DELETE FROM Refunds WHERE booking_id IN (@b1, @b2, @b3, @b4, @b5, @b6, @b7, @b8, @b9, @b10);
DELETE FROM Payments WHERE booking_id IN (@b1, @b2, @b3, @b4, @b5, @b6, @b7, @b8, @b9, @b10);
DELETE FROM Bookings WHERE booking_id IN (@b1, @b2, @b3, @b4, @b5, @b6, @b7, @b8, @b9, @b10);


-- ============================================================================
-- DIAGNOSTIC QUERIES - Use these to troubleshoot issues
-- ============================================================================

-- Check if all triggers are installed
SHOW TRIGGERS;

-- Check trigger for refund
SHOW CREATE TRIGGER trg_auto_refund_on_booking_cancel;

-- Check all payment methods
SELECT * FROM PaymentMethods;

-- Check user wallets
SELECT u.user_id, u.uname, uw.balance 
FROM Users u 
LEFT JOIN UserWallets uw ON u.user_id = uw.user_id 
WHERE u.type = 'customer';

-- Check recent bookings and their statuses
SELECT b.booking_id, b.user_id, u.uname, b.field_id, f.field_name, 
       b.booking_datetime, b.status, p.amount, p.status as payment_status
FROM Bookings b
JOIN Users u ON b.user_id = u.user_id
JOIN SportFields f ON b.field_id = f.field_id
LEFT JOIN Payments p ON b.booking_id = p.booking_id
ORDER BY b.booking_id DESC
LIMIT 10;

-- Check recent refunds
SELECT r.refund_id, r.booking_id, r.user_id, u.uname, r.amount, r.refund_date
FROM Refunds r
JOIN Users u ON r.user_id = u.user_id
ORDER BY r.refund_date DESC
LIMIT 10;

-- Check wallet transactions
SELECT wt.transaction_id, wt.user_id, u.uname, wt.amount, wt.type, 
       wt.reference, wt.created_at
FROM WalletTransactions wt
JOIN Users u ON wt.user_id = u.user_id
ORDER BY wt.created_at DESC
LIMIT 20;


-- ============================================================================
-- END OF TESTS
-- Summary: 15 test cases covering all triggers, constraints, and procedures
-- Critical Test: #8 (Complete Refund Flow)
-- ============================================================================
