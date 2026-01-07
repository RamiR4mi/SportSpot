# SportSpot Database Tests

**Purpose:** Test all database triggers, constraints, and stored procedures  
**Location:** `/database` folder files  
**Database:** SportSpot (MySQL 5.7+)

---

## Test Case 1: Double Cancellation (Prevent Duplicate Refunds)
**File:** `db_triggers.sql` - `trg_auto_refund_on_booking_cancel`  
**Purpose:** Ensure trigger doesn't create multiple refunds for same booking

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
**Status:** ⬜ PENDING

---

## Test Case 2: Cancel Unpaid Booking (No Refund)
**File:** `db_triggers.sql` - `trg_auto_refund_on_booking_cancel`  
**Purpose:** Trigger should NOT refund if payment status is not 'paid'

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
**Status:** ⬜ PENDING

---

## Test Case 3: Prevent Booking Overlap
**File:** `db_triggers.sql` - `trg_prevent_booking_overlap`  
**Purpose:** Two users cannot book same field at same time

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
**Status:** ⬜ PENDING

---

## Test Case 4: Prevent Booking on Maintenance Field
**File:** `db_triggers.sql` - `trg_prevent_maintenance_booking`  
**Purpose:** Cannot book field when status = 'maintenance'

```sql
-- 1. Set field to maintenance
UPDATE SportFields SET status = 'maintenance' WHERE field_id = 2;

-- 2. Try to book (should fail)
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 2, '2025-12-20', '10:00:00', '11:00:00', 'confirmed');
-- ERROR: Cannot book: Field is currently under maintenance
```
**Expected Result:** Booking FAILS with error  
**Status:** ⬜ PENDING

---

## Test Case 5: Auto-Create FieldOwner on User Registration
**File:** `db_triggers.sql` - `trg_auto_create_fieldowner`  
**Purpose:** Creating owner user should auto-create FieldOwner record

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
**Status:** ⬜ PENDING

---

## Test Case 6: Wallet Balance Sufficient Before Debit
**File:** `db_triggers.sql` - `trg_check_wallet_balance`  
**Purpose:** Cannot debit wallet if balance is insufficient

```sql
-- 1. Check current wallet
SELECT balance FROM UserWallets WHERE user_id = 2;

-- 2. Simulate payment that exceeds wallet (should fail)
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (100, 2, 4, 999999.00, 'paid');
-- ERROR: Insufficient wallet balance
```
**Expected Result:** Payment FAILS if balance insufficient  
**Status:** ⬜ PENDING

---

## Test Case 7: Auto-Update Wallet Balance on Payment
**File:** `db_triggers.sql` - `trg_debit_wallet_on_payment`  
**Purpose:** Wallet balance decreases when payment made with wallet

```sql
-- 1. Record initial balance
SELECT @initial := balance FROM UserWallets WHERE user_id = 1;

-- 2. Create booking and pay with wallet
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-25', '10:00:00', '11:00:00', 'confirmed');
SET @booking = LAST_INSERT_ID();

INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
VALUES (@booking, 1, 4, 25.00, 'paid');

-- 3. Verify balance decreased
SELECT balance FROM UserWallets WHERE user_id = 1;
-- Should be @initial - 25
```
**Expected Result:** Wallet balance reduced by payment amount  
**Status:** ⬜ PENDING

---

## Test Case 8: Complete Refund Flow (Main Trigger)
**File:** `db_triggers.sql` - `trg_auto_refund_on_booking_cancel`  
**Purpose:** Test automatic refund via database trigger (CRITICAL)

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

**Status:** ⬜ PENDING

---

## Test Case 9: Referential Integrity After Refund
**File:** `db_lastsportspot.sql` + `db_triggers.sql`  
**Purpose:** All related records exist after refund

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
SELECT 'Wallet Transaction Created', COUNT(*) FROM WalletTransactions WHERE reference LIKE CONCAT('%', @booking_id, '%')
UNION ALL
SELECT 'Wallet Refunded Amount', CAST(balance AS CHAR) FROM UserWallets WHERE user_id = 1;
```
**Expected Result:**
- Booking status = 'cancelled'
- Original payment status = 'refunded'
- Refund record exists = 1
- Wallet transaction created = 1
- Wallet balance = original balance

**Status:** ⬜ PENDING

---

## Test Case 10: One Review Per Booking (UNIQUE Constraint)
**File:** `db_lastsportspot.sql` - Reviews table  
**Purpose:** Only one review allowed per booking

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
**Status:** ⬜ PENDING

---

## Test Case 11: Cannot Review Pending/Cancelled Booking
**File:** `db_triggers.sql` - `trg_validate_review_status`  
**Purpose:** Reviews only allowed on 'confirmed' bookings

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
**Status:** ⬜ PENDING

---

## Test Case 12: Booking Time Within Operating Hours
**File:** `db_triggers.sql` - `trg_validate_operating_hours`  
**Purpose:** Cannot book field outside its operating hours

```sql
-- 1. Check field hours (e.g., 8 AM to 10 PM)
SELECT opening_hour, closing_hour FROM SportFields WHERE field_id = 1;

-- 2. Try to book at 11 PM (after closing)
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (2, 1, '2025-12-20', '23:00:00', '00:00:00', 'confirmed');
-- ERROR: Booking time outside field operating hours
```
**Expected Result:** Booking FAILS with error  
**Status:** ⬜ PENDING

---

## Test Case 13: Multiple Same-Day Bookings (No Overlap)
**File:** `db_triggers.sql` - `trg_prevent_booking_overlap`  
**Purpose:** User can book same field multiple times if no time overlap

```sql
-- 1. Book 10-11 AM
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-25', '10:00:00', '11:00:00', 'confirmed');

-- 2. Book 2-3 PM (same day, no overlap - should succeed)
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES (1, 1, '2025-12-25', '14:00:00', '15:00:00', 'confirmed');

-- 3. Verify both bookings exist
SELECT COUNT(*) FROM Bookings 
WHERE user_id = 1 AND field_id = 1 AND booking_datetime = '2025-12-25';
-- Should return 2
```
**Expected Result:** Both bookings created successfully  
**Status:** ⬜ PENDING

---

## Test Case 14: Wallet Transaction Audit Trail
**File:** `db_triggers.sql` + `db_lastsportspot.sql`  
**Purpose:** All wallet changes recorded in WalletTransactions

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
**Status:** ⬜ PENDING

---

## Test Case 15: Bulk Cancellation Performance (18 Triggers)
**File:** `db_triggers.sql` - All 18 triggers working together  
**Purpose:** Refund trigger handles multiple simultaneous cancellations

```sql
-- 1. Create 10 bookings
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status) 
VALUES 
(1, 1, '2025-12-20', '10:00:00', '11:00:00', 'confirmed'),
(1, 2, '2025-12-20', '10:00:00', '11:00:00', 'confirmed'),
(1, 3, '2025-12-20', '10:00:00', '11:00:00', 'confirmed'),
(1, 4, '2025-12-20', '10:00:00', '11:00:00', 'confirmed'),
(1, 5, '2025-12-20', '10:00:00', '11:00:00', 'confirmed'),
(1, 1, '2025-12-21', '10:00:00', '11:00:00', 'confirmed'),
(1, 2, '2025-12-21', '10:00:00', '11:00:00', 'confirmed'),
(1, 3, '2025-12-21', '10:00:00', '11:00:00', 'confirmed'),
(1, 4, '2025-12-21', '10:00:00', '11:00:00', 'confirmed'),
(1, 5, '2025-12-21', '10:00:00', '11:00:00', 'confirmed');

-- 2. Pay for all
INSERT INTO Payments (booking_id, user_id, method_id, amount, status)
SELECT booking_id, user_id, 4, 50.00, 'paid' FROM Bookings 
WHERE user_id = 1 AND status = 'confirmed' LIMIT 10;

-- 3. Cancel all (measure time - should be < 1 second)
UPDATE Bookings SET status='cancelled' WHERE user_id = 1;

-- 4. Verify all refunds created
SELECT COUNT(*) as refund_count FROM Refunds WHERE user_id = 1;
-- Should be 10
```
**Expected Result:** All 10 refunds created without timeout or error  
**Status:** ⬜ PENDING

---

## Summary & Checklist

| Test # | Feature | Trigger | Status |
|--------|---------|---------|--------|
| 1 | Double Cancellation Prevention | `trg_auto_refund_on_booking_cancel` | ⬜ |
| 2 | Unpaid Booking (No Refund) | `trg_auto_refund_on_booking_cancel` | ⬜ |
| 3 | Booking Overlap Prevention | `trg_prevent_booking_overlap` | ⬜ |
| 4 | Maintenance Field Block | `trg_prevent_maintenance_booking` | ⬜ |
| 5 | Auto FieldOwner Creation | `trg_auto_create_fieldowner` | ⬜ |
| 6 | Wallet Sufficient Balance | `trg_check_wallet_balance` | ⬜ |
| 7 | Wallet Debit on Payment | `trg_debit_wallet_on_payment` | ⬜ |
| 8 | **Complete Refund Flow** | `trg_auto_refund_on_booking_cancel` | ⬜ |
| 9 | Referential Integrity | Multiple Triggers | ⬜ |
| 10 | One Review Per Booking | UNIQUE constraint | ⬜ |
| 11 | Review Status Validation | `trg_validate_review_status` | ⬜ |
| 12 | Operating Hours Check | `trg_validate_operating_hours` | ⬜ |
| 13 | Non-Overlapping Bookings | `trg_prevent_booking_overlap` | ⬜ |
| 14 | Wallet Audit Trail | `trg_create_wallet_transaction` | ⬜ |
| 15 | Bulk Performance Test | All 18 Triggers | ⬜ |

**Legend:** ✅ = PASS | ❌ = FAIL | ⬜ = PENDING

---

## Instructions

1. **Connect to Database:** `mysql -u root -p sportspot`
2. **Run Tests:** Copy each SQL test and execute in MySQL
3. **Record Results:** Mark each test as ✅ PASS, ❌ FAIL, or ⚠️ ERROR
4. **Note Errors:** If a test fails, document the error message
5. **Critical Test:** Test Case #8 (Complete Refund Flow) is most important

---

**Database Files Tested:**
- `db_lastsportspot.sql` - Schema and initial data
- `db_triggers.sql` - 18 business logic triggers
- `db_queries_ctes_views_correlatedqueries_aggregatefcts.sql` - Views and stored procedures

**Generated:** December 10, 2025
