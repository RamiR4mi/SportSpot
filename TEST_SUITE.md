# SportSpot Database & Application - Comprehensive Test Suite

**Project:** SportSpot - Sports Field Booking Platform  
**Date:** December 10, 2025  
**Test Purpose:** Validate all database triggers, application features, and business logic

---

## Table of Contents
1. [Trigger Edge Cases](#trigger-edge-cases)
2. [Data Integrity Tests](#data-integrity-tests)
3. [Refund System Tests](#refund-system-tests)
4. [Booking System Tests](#booking-system-tests)
5. [Payment & Wallet Tests](#payment--wallet-tests)
6. [Review System Tests](#review-system-tests)
7. [Field Management Tests](#field-management-tests)
8. [Performance Tests](#performance-tests)

---

## Trigger Edge Cases

### Test Case 1: Double Cancellation (Prevent Duplicate Refunds)
**Purpose:** Ensure trigger doesn't create multiple refunds for same booking  
**SQL:**
```sql
-- 1. Check initial state
SELECT booking_id, status FROM Bookings WHERE booking_id = 5;
SELECT COUNT(*) FROM Refunds WHERE booking_id = 5;

-- 2. First cancellation
UPDATE Bookings SET status='cancelled' WHERE booking_id = 5;

-- 3. Check refund created
SELECT COUNT(*) FROM Refunds WHERE booking_id = 5; -- Should be 1

-- 4. Second cancellation (should not create duplicate)
UPDATE Bookings SET status='cancelled' WHERE booking_id = 5;

-- 5. Verify no duplicate refund
SELECT COUNT(*) FROM Refunds WHERE booking_id = 5; -- Should still be 1
```
**Expected Result:** Only ONE refund record created, not two  
**Status:** ✅ PASS if count stays at 1

---

### Test Case 2: Cancel Unpaid Booking (No Refund)
**Purpose:** Trigger should NOT refund if payment status is not 'paid'  
**SQL:**
```sql
-- 1. Create booking without payment
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (2, 2, NOW(), '14:00:00', '15:00:00', 'pending');
SET @test_booking_id = LAST_INSERT_ID();

-- 2. Cancel the booking (NO payment to refund)
UPDATE Bookings SET status='cancelled' WHERE booking_id = @test_booking_id;

-- 3. Check wallet (should NOT change)
SELECT balance FROM UserWallets WHERE user_id = 2;

-- 4. Check Refunds table (should be empty)
SELECT COUNT(*) FROM Refunds WHERE booking_id = @test_booking_id; -- Should be 0
```
**Expected Result:** No refund created, wallet unchanged  
**Status:** ✅ PASS if refund count = 0

---

### Test Case 3: Prevent Booking Overlap
**Purpose:** Two users cannot book same field at same time  
**SQL:**
```sql
-- 1. Create first booking
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 3, '2025-12-20', '14:00:00', '15:00:00', 'confirmed');

-- 2. Try overlapping booking (should fail)
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (2, 3, '2025-12-20', '14:30:00', '15:30:00', 'confirmed');
-- ERROR: Time slot conflict: Field is already booked for this time
```
**Expected Result:** Second booking FAILS with error  
**Status:** ✅ PASS if error occurs

---

### Test Case 4: Prevent Booking on Maintenance Field
**Purpose:** Cannot book field when status = 'maintenance'  
**SQL:**
```sql
-- 1. Set field to maintenance
UPDATE SportFields SET status = 'maintenance' WHERE field_id = 2;

-- 2. Try to book (should fail)
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 2, '2025-12-20', '10:00:00', '11:00:00', 'confirmed');
-- ERROR: Cannot book: Field is currently under maintenance
```
**Expected Result:** Booking FAILS with error  
**Status:** ✅ PASS if error occurs

---

### Test Case 5: Auto-Create FieldOwner on User Registration
**Purpose:** Creating owner user should auto-create FieldOwner record  
**SQL:**
```sql
-- 1. Insert owner user
INSERT INTO Users (uname, email, phone, address, password, type)
VALUES ('Test Owner', 'testowner@example.com', '0612345678', 'Test Address', 'password123', 'owner');
SET @new_user_id = LAST_INSERT_ID();

-- 2. Check FieldOwners (should auto-create)
SELECT * FROM FieldOwners WHERE user_id = @new_user_id;
-- Should return 1 row with business_name like "Field Business - Test Owner"
```
**Expected Result:** FieldOwner record automatically created  
**Status:** ✅ PASS if 1 row returned

---

## Data Integrity Tests

### Test Case 6: Referential Integrity After Refund
**Purpose:** All related records exist after refund  
**SQL:**
```sql
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
SELECT 'Booking Status' AS check_item, status FROM Bookings WHERE booking_id = @booking_id
UNION ALL
SELECT 'Original Payment Status', status FROM Payments WHERE payment_id = @payment_id
UNION ALL
SELECT 'Refund Record Exists', COUNT(*) FROM Refunds WHERE booking_id = @booking_id
UNION ALL
SELECT 'Wallet Transaction Created', COUNT(*) FROM WalletTransactions WHERE reference = CONCAT('refund:booking:', @booking_id)
UNION ALL
SELECT 'Wallet Refunded Amount', CAST(balance AS CHAR) FROM UserWallets WHERE user_id = 1;
```
**Expected Result:**  
- Booking status = 'cancelled'
- Original payment status = 'refunded'
- Refund record exists = 1
- Wallet transaction created = 1
- Wallet balance = original balance (e.g., if 100, still 100)

**Status:** ✅ PASS if all match above

---

### Test Case 7: Cascade Delete (User with Bookings)
**Purpose:** Attempt to delete user with active bookings (should fail)  
**SQL:**
```sql
-- 1. Create booking for user
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (3, 1, '2025-12-20', '16:00:00', '17:00:00', 'confirmed');

-- 2. Try to delete user (should fail)
DELETE FROM Users WHERE user_id = 3;
-- ERROR: Cannot delete user with active bookings
```
**Expected Result:** Delete FAILS with error  
**Status:** ✅ PASS if error occurs

---

## Refund System Tests

### Test Case 8: Complete Refund Flow (Database Trigger)
**Purpose:** Test automatic refund via database trigger  
**SQL:**
```sql
-- 1. Get initial wallet
SELECT @initial := balance FROM UserWallets WHERE user_id = 1;

-- 2. Create booking with payment
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-22', '11:00:00', '12:00:00', 'confirmed');
SET @booking = LAST_INSERT_ID();

INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@booking, 1, 4, 50.00, 'paid');

-- 3. Cancel booking (TRIGGER FIRES HERE)
UPDATE Bookings SET status='cancelled' WHERE booking_id = @booking;

-- 4. Verify refund
SELECT balance FROM UserWallets WHERE user_id = 1; -- Should equal @initial
SELECT * FROM Refunds WHERE booking_id = @booking;
SELECT status FROM Payments WHERE booking_id = @booking;
```
**Expected Result:**
- Wallet balance restored to initial amount
- Refund record created in Refunds table
- Original payment marked as 'refunded'

**Status:** ✅ PASS if all conditions met

---

### Test Case 9: Refund via API (Application Layer)
**Purpose:** Test refund when user cancels via UI  
**Steps:**
1. Login as customer
2. Add $100 to wallet
3. Book a field ($25)
4. Wallet should show $75
5. Click "Cancel Booking"
6. Check "My Refunds" page - should show refund record
7. Check wallet - should show $100

**Expected Result:** Refund appears on "My Refunds" page, wallet restored  
**Status:** ✅ PASS if all steps work

---

## Booking System Tests

### Test Case 10: Booking Outside Operating Hours
**Purpose:** Cannot book field outside its operating hours  
**SQL:**
```sql
-- 1. Field opens at 8 AM, closes at 10 PM
SELECT opening_hour, closing_hour FROM SportFields WHERE field_id = 1;

-- 2. Try to book at 11 PM (after closing)
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (2, 1, '2025-12-20', '23:00:00', '00:00:00', 'confirmed');
-- ERROR: Booking time outside field operating hours
```
**Expected Result:** Booking FAILS with error  
**Status:** ✅ PASS if error occurs

---

### Test Case 11: Multiple Same-Day Bookings (No Overlap)
**Purpose:** User can book same field multiple times if no time overlap  
**SQL:**
```sql
-- 1. Book 10-11 AM
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-25', '10:00:00', '11:00:00', 'confirmed');

-- 2. Book 2-3 PM (same day, no overlap - should succeed)
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-25', '14:00:00', '15:00:00', 'confirmed');

-- 3. Verify both bookings exist
SELECT COUNT(*) FROM Bookings 
WHERE user_id = 1 AND field_id = 1 AND booking_date = '2025-12-25';
-- Should return 2
```
**Expected Result:** Both bookings created successfully  
**Status:** ✅ PASS if count = 2

---

## Payment & Wallet Tests

### Test Case 12: Insufficient Wallet Balance
**Purpose:** Cannot pay if wallet balance < booking amount  
**SQL:**
```sql
-- 1. Check user wallet (assume balance = $10)
SELECT balance FROM UserWallets WHERE user_id = 2; -- $10

-- 2. Try to book $50 field with wallet (should fail)
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (2, 1, '2025-12-20', '15:00:00', '16:00:00', 'confirmed');
SET @booking = LAST_INSERT_ID();

INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@booking, 2, 4, 50.00, 'paid');
-- ERROR: Insufficient wallet balance for this payment
```
**Expected Result:** Payment FAILS with error  
**Status:** ✅ PASS if error occurs

---

### Test Case 13: Wallet Transaction Audit Trail
**Purpose:** All wallet changes recorded in WalletTransactions  
**SQL:**
```sql
-- 1. Add balance to wallet
UPDATE UserWallets SET balance = balance + 100 WHERE user_id = 1;

-- 2. Book field ($25)
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-22', '12:00:00', '13:00:00', 'confirmed');
SET @booking = LAST_INSERT_ID();

INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@booking, 1, 4, 25.00, 'paid');

-- 3. Cancel and refund
UPDATE Bookings SET status='cancelled' WHERE booking_id = @booking;

-- 4. Check transaction history
SELECT user_id, amount, type, reference, created_at FROM WalletTransactions 
WHERE user_id = 1 
ORDER BY created_at DESC
LIMIT 5;
```
**Expected Result:** Multiple transactions recorded (deposits, debits, refunds)  
**Status:** ✅ PASS if transaction history shows all operations

---

## Review System Tests

### Test Case 14: One Review Per Booking (UNIQUE Constraint)
**Purpose:** Only one review allowed per booking  
**SQL:**
```sql
-- 1. Create confirmed booking
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-15', '10:00:00', '11:00:00', 'confirmed');
SET @booking = LAST_INSERT_ID();

-- 2. Create first review
INSERT INTO Reviews (booking_id, user_id, field_id, rating, comment)
VALUES (@booking, 1, 1, 5.0, 'Excellent field!');

-- 3. Try to create second review (should fail)
INSERT INTO Reviews (booking_id, user_id, field_id, rating, comment)
VALUES (@booking, 1, 1, 4.0, 'Changed my mind');
-- ERROR: Duplicate entry for key 'unique_booking_review'
```
**Expected Result:** Second review FAILS due to UNIQUE constraint  
**Status:** ✅ PASS if error occurs

---

### Test Case 15: Cannot Review Pending/Cancelled Booking
**Purpose:** Reviews only allowed on 'confirmed' bookings  
**SQL:**
```sql
-- 1. Create pending booking
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (2, 2, '2025-12-16', '14:00:00', '15:00:00', 'pending');
SET @pending_booking = LAST_INSERT_ID();

-- 2. Try to review pending booking (should fail)
INSERT INTO Reviews (booking_id, user_id, field_id, rating, comment)
VALUES (@pending_booking, 2, 2, 4.5, 'Test review');
-- ERROR: Can only review confirmed bookings
```
**Expected Result:** Review INSERT FAILS with error  
**Status:** ✅ PASS if error occurs

---

## Field Management Tests

### Test Case 16: Owner Can Add Fields
**Purpose:** Owner users can create fields for their business  
**Steps:**
1. Login as owner user
2. Navigate to Dashboard
3. Click "Add New Field" button
4. Fill form: Name, Sport Type, Hours (e.g., 7 PM to 12 AM), Price, Capacity
5. Click "Add Sport Field"

**Expected Result:** Field created successfully, redirects to "My Fields" page  
**Status:** ✅ PASS if field appears in list

---

### Test Case 17: Admin Can Create Fields for Any Owner
**Purpose:** Admins can create fields on behalf of owners  
**Steps:**
1. Login as admin
2. Navigate to Sport Fields page
3. Click "Add Sport Field"
4. Select owner from dropdown
5. Fill form and submit

**Expected Result:** Field created for selected owner  
**Status:** ✅ PASS if field assigned to correct owner

---

## Performance Tests

### Test Case 18: Query Performance - Owner Dashboard
**Purpose:** Dashboard loads quickly with multiple bookings  
**Steps:**
1. Create 50+ bookings in database
2. Login as owner
3. Navigate to Dashboard
4. Measure load time (should be < 2 seconds)

**Expected Result:** Dashboard loads without lag  
**Status:** ✅ PASS if response < 2s

---

### Test Case 19: Trigger Performance - Bulk Cancellations
**Purpose:** Refund trigger handles multiple simultaneous cancellations  
**SQL:**
```sql
-- 1. Create 10 bookings
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status) 
SELECT 1, field_id, NOW(), '10:00:00', '11:00:00', 'confirmed'
FROM (SELECT 1 AS field_id UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 
      UNION SELECT 5 UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) t;

-- 2. Pay for all
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
SELECT booking_id, user_id, 4, 50.00, 'paid' FROM Bookings 
WHERE status = 'confirmed' AND user_id = 1 LIMIT 10;

-- 3. Cancel all (measure time)
UPDATE Bookings SET status='cancelled' WHERE user_id = 1;

-- 4. Verify all refunds created
SELECT COUNT(*) FROM Refunds WHERE user_id = 1;
```
**Expected Result:** All refunds created without timeout or error  
**Status:** ✅ PASS if all 10 refunds created

---

## Summary & Checklist

| Test Case | Feature | Status |
|-----------|---------|--------|
| 1 | Double Cancellation Prevention | ⬜ |
| 2 | Unpaid Booking (No Refund) | ⬜ |
| 3 | Booking Overlap Prevention | ⬜ |
| 4 | Maintenance Field Block | ⬜ |
| 5 | Auto FieldOwner Creation | ⬜ |
| 6 | Referential Integrity | ⬜ |
| 7 | Cascade Delete Protection | ⬜ |
| 8 | Automatic Refund (Trigger) | ⬜ |
| 9 | API Refund Flow | ⬜ |
| 10 | Operating Hours Validation | ⬜ |
| 11 | Multiple Bookings (No Overlap) | ⬜ |
| 12 | Insufficient Wallet Balance | ⬜ |
| 13 | Wallet Audit Trail | ⬜ |
| 14 | One Review Per Booking | ⬜ |
| 15 | Review on Confirmed Only | ⬜ |
| 16 | Owner Add Field | ⬜ |
| 17 | Admin Create Field for Owner | ⬜ |
| 18 | Dashboard Performance | ⬜ |
| 19 | Bulk Cancellation Performance | ⬜ |

**Legend:** ✅ = PASS | ❌ = FAIL | ⬜ = PENDING

---

## Test Execution Instructions

1. **Database Tests:** Run SQL commands in MySQL
2. **UI Tests:** Follow step-by-step in browser
3. **Document Results:** Mark checkboxes after each test
4. **Report Issues:** If any test fails, note the error message and expected vs actual result

---

**Generated:** December 10, 2025  
**Project:** SportSpot Database Class  
**Team:** Rami Mazaoui, Yasmine Espachs Bouamoud, Rabab Saadeddine
