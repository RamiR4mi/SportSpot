
use SportSpot;


DROP TRIGGER IF EXISTS trg_protect_user_with_active_bookings;
DROP TRIGGER IF EXISTS trg_user_validate_phone_insert;
DROP TRIGGER IF EXISTS trg_user_validate_phone_update;
DROP TRIGGER IF EXISTS trg_fo_validate_phone_insert;
DROP TRIGGER IF EXISTS trg_fo_validate_phone_update;
DROP TRIGGER IF EXISTS trg_cancel_bookings_on_maintenance;
DROP TRIGGER IF EXISTS trg_prevent_booking_overlap_insert;
DROP TRIGGER IF EXISTS trg_prevent_booking_overlap_update;
DROP TRIGGER IF EXISTS trg_prevent_booking_maintenance_field;
DROP TRIGGER IF EXISTS trg_check_field_operating_hours;
DROP TRIGGER IF EXISTS trg_cancel_payments_on_booking_cancel;
DROP TRIGGER IF EXISTS trg_auto_refund_on_booking_cancel;
DROP TRIGGER IF EXISTS trg_auto_activate_discount_on_booking;
DROP TRIGGER IF EXISTS trg_prevent_duplicate_payment;
DROP TRIGGER IF EXISTS trg_prevent_payment_on_cancelled_booking;
DROP TRIGGER IF EXISTS trg_check_wallet_balance_before_payment;
DROP TRIGGER IF EXISTS trg_prevent_review_on_invalid_booking;
DROP TRIGGER IF EXISTS trg_create_discount_for_new_user;
DROP TRIGGER IF EXISTS auto_create_fieldowner_on_user_insert;



-- TRIGGERS - ORGANIZED BY  CONCERNED TABLE

-- ========== USERS TABLE TRIGGERS ==========

-- Trigger 1: Prevent user deletion if they have active bookings

DELIMITER $$
CREATE TRIGGER trg_protect_user_with_active_bookings
BEFORE DELETE ON Users
FOR EACH ROW
BEGIN
  DECLARE v_active_bookings INT;
  
  SELECT COUNT(*) INTO v_active_bookings FROM Bookings WHERE user_id = OLD.user_id AND status IN ('pending', 'confirmed');
  
  IF v_active_bookings > 0 THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Cannot delete user with active bookings';
  END IF;
END $$
DELIMITER ;

-- Trigger 2: Validate phone format on insert

DELIMITER $$
CREATE TRIGGER trg_user_validate_phone_insert
BEFORE INSERT ON Users
FOR EACH ROW
BEGIN
  IF NEW.phone IS NOT NULL THEN
    IF LENGTH(NEW.phone) != 10 THEN
      SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Invalid phone format. Must be exactly 10 digits.';
    END IF;
  END IF;
END $$
DELIMITER ;

-- Trigger 3: Validate phone format on update

DELIMITER $$
CREATE TRIGGER trg_user_validate_phone_update
BEFORE UPDATE ON Users
FOR EACH ROW
BEGIN
  IF NEW.phone != OLD.phone THEN
    IF NEW.phone IS NOT NULL THEN
      IF LENGTH(NEW.phone) != 10 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid phone format. Must be exactly 10 digits.';
      END IF;
    END IF;
  END IF;
END $$
DELIMITER ;

-- ========== FIELD OWNERS TABLE TRIGGERS ==========

-- Trigger 1: Validate phone format on insert for FieldOwners

DELIMITER $$
CREATE TRIGGER trg_fo_validate_phone_insert
BEFORE INSERT ON FieldOwners
FOR EACH ROW
BEGIN
  IF NEW.phone IS NOT NULL THEN
    IF LENGTH(NEW.phone) != 10 THEN
      SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Invalid phone format for Field Owner. Must be exactly 10 digits.';
    END IF;
  END IF;
END $$
DELIMITER ;

-- Trigger 2: Validate phone format on update for FieldOwners

DELIMITER $$
CREATE TRIGGER trg_fo_validate_phone_update
BEFORE UPDATE ON FieldOwners
FOR EACH ROW
BEGIN
  IF NEW.phone != OLD.phone THEN
    IF NEW.phone IS NOT NULL THEN
      IF LENGTH(NEW.phone) != 10 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid phone format for Field Owner. Must be exactly 10 digits.';
      END IF;
    END IF;
  END IF;
END $$
DELIMITER ;

-- ========== SPORT FIELDS TABLE TRIGGERS ==========

-- Trigger 3: Cancel pending bookings when field goes into maintenance

DELIMITER $$
CREATE TRIGGER trg_cancel_bookings_on_maintenance
AFTER UPDATE ON SportFields
FOR EACH ROW
BEGIN
  IF NEW.status IN ('maintenance', 'unavailable') AND OLD.status NOT IN ('maintenance', 'unavailable') THEN
    UPDATE Bookings
    SET status = 'cancelled'
    WHERE field_id = NEW.field_id AND status = 'pending';
  END IF;
END $$
DELIMITER ;

-- ========== BOOKINGS TABLE TRIGGERS ==========

-- Trigger 1: Prevent double booking on insert (time slot conflict)

DELIMITER $$
CREATE TRIGGER trg_prevent_booking_overlap_insert
BEFORE INSERT ON Bookings
FOR EACH ROW
BEGIN
  DECLARE overlap_count INT;
  SELECT COUNT(*) INTO overlap_count
  FROM Bookings
  WHERE field_id = NEW.field_id
  AND status IN ('confirmed','pending')
  AND NEW.start_time < end_time 
  AND NEW.end_time > start_time;
  IF overlap_count > 0 THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Time slot conflict: Field is already booked for this time';
  END IF;
END $$
DELIMITER ;

-- Trigger 2: Prevent double booking on update (reschedule conflict)

DELIMITER $$
CREATE TRIGGER trg_prevent_booking_overlap_update
BEFORE UPDATE ON Bookings
FOR EACH ROW
BEGIN
  DECLARE overlap_count INT;
  IF NEW.start_time != OLD.start_time OR NEW.end_time != OLD.end_time THEN
    SELECT COUNT(*) INTO overlap_count
    FROM Bookings
    WHERE field_id = NEW.field_id
    AND booking_id != NEW.booking_id
    AND status IN ('confirmed', 'pending')
    AND NEW.start_time < end_time 
    AND NEW.end_time > start_time;

    IF overlap_count > 0 THEN
      SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Time slot conflict: Field is already booked for this time';
    END IF;
  END IF;
END $$
DELIMITER ;

-- Trigger 3: Prevent booking on fields under maintenance

DELIMITER $$
CREATE TRIGGER trg_prevent_booking_maintenance_field
BEFORE INSERT ON Bookings
FOR EACH ROW
BEGIN
  DECLARE v_field_status VARCHAR(20);
  SELECT status INTO v_field_status
  FROM SportFields WHERE field_id = NEW.field_id;
  IF v_field_status = 'maintenance' THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Cannot book: Field is currently under maintenance';
  END IF;
END $$
DELIMITER ;

-- Trigger 4: Prevent booking outside field operating hours

DELIMITER $$
CREATE TRIGGER trg_check_field_operating_hours
BEFORE INSERT ON Bookings
FOR EACH ROW
BEGIN
  DECLARE v_opening_time TIME;
  DECLARE v_closing_time TIME;
  
  SELECT opening_hour, closing_hour INTO v_opening_time, v_closing_time
  FROM SportFields WHERE field_id = NEW.field_id;
  
  IF NEW.start_time < v_opening_time OR NEW.end_time > v_closing_time THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Booking time outside field operating hours';
  END IF;
END $$
DELIMITER ;


-- Trigger 5: Comprehensive Refund Processing on Booking Cancellation

DELIMITER $$
CREATE TRIGGER trg_auto_refund_on_booking_cancel
AFTER UPDATE ON Bookings
FOR EACH ROW
BEGIN
  DECLARE v_payment_id INT;
  DECLARE v_payment_amount DECIMAL(10,2);
  DECLARE v_user_id INT;
  DECLARE v_payment_status VARCHAR(20);
  DECLARE v_wallet_method_id INT;
  
  -- Only process if booking status changed TO cancelled (and wasn't already cancelled)
  IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
    
    -- Get booking details
    SET v_user_id = NEW.user_id;
    
    -- Find the associated payment (if any)
    SELECT payment_id, amount, status INTO v_payment_id, v_payment_amount, v_payment_status
    FROM Payments
    WHERE booking_id = NEW.booking_id
    LIMIT 1;
    
    -- If payment exists and was paid, process refund
    IF v_payment_id IS NOT NULL AND v_payment_status = 'paid' AND v_payment_amount > 0 THEN
      
      -- Step 1: Update original payment status to 'refunded'
      UPDATE Payments SET status = 'refunded' WHERE payment_id = v_payment_id;
      
      -- Step 2: Refund amount back to wallet
      INSERT IGNORE INTO UserWallets (user_id, balance) VALUES (v_user_id, 0.00);
      UPDATE UserWallets SET balance = balance + v_payment_amount WHERE user_id = v_user_id;
      
      -- Step 3: Record wallet transaction for audit trail
      INSERT INTO WalletTransactions (user_id, amount, type, reference, created_at)
      VALUES (v_user_id, v_payment_amount, 'deposit', CONCAT('refund:booking:', NEW.booking_id), NOW());
      
      -- Step 4: Create a Refund record in the Refunds table (for tracking and 'My Refunds' page)
      INSERT INTO Refunds (booking_id, user_id, payment_id, amount, reason, status, requested_by, requested_at, processed_at)
      VALUES (NEW.booking_id, v_user_id, v_payment_id, v_payment_amount, 'Booking cancelled - automatic refund', 'completed', 4, NOW(), NOW());
    END IF;
  END IF;
END $$
DELIMITER ;

-- Trigger 7: Auto activate discount tier when booking threshold reached

DELIMITER $$
CREATE TRIGGER trg_auto_activate_discount_on_booking
AFTER INSERT ON Bookings
FOR EACH ROW
BEGIN
  DECLARE v_booking_count INT DEFAULT 0;
  DECLARE v_threshold INT DEFAULT NULL;
  -- This counts AFTER the insert
  SELECT COUNT(*) INTO v_booking_count
  FROM Bookings
  WHERE user_id = NEW.user_id AND status = 'confirmed';
  
  -- Then checks if threshold is met
  SELECT booking_threshold INTO v_threshold
  FROM Discounts
  WHERE user_id = NEW.user_id
  AND booking_threshold <= v_booking_count
  AND status = 'inactive'
  ORDER BY booking_threshold DESC
  LIMIT 1;
  
  IF v_threshold IS NOT NULL THEN
    UPDATE Discounts
    SET status = 'active', activated_date = NOW()
    WHERE user_id = NEW.user_id AND booking_threshold = v_threshold;
  END IF;
END $$

DELIMITER ;

-- ========== PAYMENTS TABLE TRIGGERS ==========

-- Trigger 1: Prevent multiple payments for same booking

DELIMITER $$
CREATE TRIGGER trg_prevent_duplicate_payment
BEFORE INSERT ON Payments
FOR EACH ROW
BEGIN
  DECLARE v_payment_exists INT;
  SELECT COUNT(*) INTO v_payment_exists
  FROM Payments
  WHERE booking_id = NEW.booking_id;
  IF v_payment_exists > 0 THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Payment already exists for this booking';
  END IF;
END $$
DELIMITER ;

-- Trigger 2: Prevent payment for cancelled bookings

DELIMITER $$
CREATE TRIGGER trg_prevent_payment_on_cancelled_booking
BEFORE INSERT ON Payments
FOR EACH ROW
BEGIN
  DECLARE v_booking_status VARCHAR(20);
  SELECT status INTO v_booking_status
  FROM Bookings WHERE booking_id = NEW.booking_id;
  IF v_booking_status = 'cancelled' THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Cannot process payment for cancelled booking';
  END IF;
END $$
DELIMITER ;

-- Trigger 3: Enforce wallet balance before payment

DELIMITER $$
CREATE TRIGGER trg_check_wallet_balance_before_payment
BEFORE INSERT ON Payments
FOR EACH ROW
BEGIN
  DECLARE v_method_name VARCHAR(50);
  DECLARE v_balance DECIMAL(10,2);

  -- Only enforce when payment method is wallet (column name is method_id)
  SELECT method_name INTO v_method_name
  FROM PaymentMethods
  WHERE method_id = NEW.method_id;

  IF v_method_name = 'wallet' THEN
    -- Payments.user_id stores the paying user (customer); check their wallet
    SELECT balance INTO v_balance FROM UserWallets WHERE user_id = NEW.user_id;

    IF v_balance IS NULL THEN
      SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Wallet not found for this user';
    END IF;

    IF v_balance < NEW.amount THEN
      SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Insufficient wallet balance for this payment';
    END IF;
  END IF;
END $$
DELIMITER ;

-- ========== REVIEWS TABLE TRIGGERS ==========

-- Trigger 1: Prevent review on cancelled or pending bookings (only confirmed bookings)

DELIMITER $$
CREATE TRIGGER trg_prevent_review_on_invalid_booking
BEFORE INSERT ON Reviews
FOR EACH ROW
BEGIN
  DECLARE v_booking_status VARCHAR(20);
  
  SELECT status INTO v_booking_status
  FROM Bookings WHERE booking_id = NEW.booking_id;
  
  IF v_booking_status NOT IN ('confirmed') THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Can only review confirmed bookings';
  END IF;
END $$
DELIMITER ;

-- ========== DISCOUNT TABLE TRIGGERS ==========

-- Trigger 1: Adds discount row for new customers with inactive status.


DELIMITER $$
CREATE TRIGGER trg_create_discount_for_new_user
AFTER INSERT ON Users
FOR EACH ROW
BEGIN
  -- Automatically create a discount record for the new user
  -- Default: 3 bookings required for 5% discount
  INSERT INTO Discounts (user_id, booking_threshold, discount_percent, status)
  VALUES (NEW.user_id, 3, 5.00, 'inactive');
END$$
DELIMITER ;

-- ========== AUTO-CREATE FIELDOWNERS TRIGGER ==========

-- Trigger: Auto-create FieldOwners entry when user registers with type='owner'
DELIMITER //
CREATE TRIGGER auto_create_fieldowner_on_user_insert
AFTER INSERT ON Users
FOR EACH ROW
BEGIN
  IF NEW.type = 'owner' THEN
    INSERT INTO FieldOwners (user_id, business_name, phone, address)
    VALUES (NEW.user_id, CONCAT('Field Business - ', NEW.uname), NEW.phone, NEW.address);
  END IF;
END//
DELIMITER ;