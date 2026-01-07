/*Welcome to SportSpot Database */
/* Members in the project*/
/*Rami Mazaoui
Yasmine Espachs Bouamoud
Rabab Saadeddine
*/

DROP DATABASE IF EXISTS sportspot;
CREATE DATABASE sportspot;
USE sportspot;

-- USERS
CREATE TABLE Users (
  user_id    INT AUTO_INCREMENT PRIMARY KEY,
  uname      VARCHAR(50)   NOT NULL,
  email      VARCHAR(100)  NOT NULL,
  phone      VARCHAR(15),
  address    VARCHAR(255),
  password   VARCHAR(255) NOT NULL DEFAULT 'temp_password',
  type       ENUM('admin', 'owner', 'customer') NOT NULL DEFAULT 'customer',
  CHECK (phone LIKE '06%' OR phone LIKE '07%'),
  CHECK (email LIKE '%@%')
);

/* 
     Normalization proof:
     1NF: all columns atomic (each field holds exactly one value). No lists or repeating groups.
     2NF: primary key is single column (user_id), so no partial key dependency possible.
     3NF: all non-key attributes (uname, email, phone, address) depend only on user_id, 
          and none depends on another non-key attribute, no transitive dependency.
  */

-- FIELD OWNERS
CREATE TABLE FieldOwners (
  owner_id      INT AUTO_INCREMENT PRIMARY KEY,
  user_id       INT,
  business_name VARCHAR(100) NOT NULL,
  phone         VARCHAR(15),
  address       VARCHAR(255),
  CONSTRAINT fieldowner_belongs_to_user FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
  CHECK (phone LIKE '06%' OR phone LIKE '07%')
);

  /* 
     Normalization proof:
     1NF: all columns atomic (each field holds exactly one value). No lists or repeating groups.
     2NF: primary key is single column (owner_id); user_id is foreign key linking to Users, non-key attributes depend on owner_id.
     3NF: non-key attributes (business_name, phone, address) depend only on owner_id, none depends on another non-key attribute.
          Referential integrity maintained via user_id FK to Users table.
  */

-- SPORT FIELDS
CREATE TABLE SportFields (
  field_id      INT AUTO_INCREMENT PRIMARY KEY,
  owner_id      INT NOT NULL,
  name          VARCHAR(100) NOT NULL,
  sport_type    VARCHAR(50),
  address       VARCHAR(255),
  opening_hour  TIME,
  closing_hour  TIME,
  price_per_hour DECIMAL(10,2) DEFAULT 0.00,
  status        VARCHAR(20) DEFAULT 'available',
  description   TEXT,
  capacity      INT,
  cover         VARCHAR(255),
  CONSTRAINT posts FOREIGN KEY (owner_id) REFERENCES FieldOwners(owner_id) ON DELETE CASCADE ON UPDATE CASCADE,
  CHECK (opening_hour<closing_hour)
);
  /*
     Normalization proof:
     1NF: all columns are atomic (TIME, VARCHAR, DECIMAL, INT, TEXT),no lists or nested data.
     2NF: primary key is single column (field_id), so no partial key dependency.
     3NF: no -key attributes (owner_id, name, sport_type, address, etc.) depend only on field_id,
          nothing depends on another non key. Referential data (owner_id) is a foreign key.
  */


CREATE TABLE Bookings (
  booking_id  INT AUTO_INCREMENT PRIMARY KEY,
  user_id     INT NOT NULL,
  field_id    INT NOT NULL,
  booking_datetime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  start_time  TIME NOT NULL,
  end_time    TIME NOT NULL,
  status      VARCHAR(20) DEFAULT 'pending',
  CONSTRAINT makes FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE  ON UPDATE CASCADE,
  CONSTRAINT booked FOREIGN KEY (field_id) REFERENCES SportFields(field_id) ON DELETE CASCADE ON UPDATE CASCADE,
  CHECK (end_time>start_time)
);
      
/*
     Normalization proof:
     1NF: atomic values only (INT, TIME, TIMESTAMP, VARCHAR).
     2NF: single column primary key (booking_id), so non key attributes fully depend on key.
     3NF: non key attributes (user_id, field_id, booking_datetime, start_time, end_time, status) 
          depend only on booking_id, no non key attribute determines another non key attribute.
     The foreign keys (user_id and field_id) properly normalize relationships, no redundancy.
  */


-- PAYMENT METHODS: lookup table for payment method types
CREATE TABLE PaymentMethods (
    method_id   INT AUTO_INCREMENT PRIMARY KEY,
    method_name VARCHAR(50) NOT NULL UNIQUE
);

  /*
     Normalization proof:
     1NF: atomic values only (INT,VARCHAR). No lists or repeating groups.
     2NF & 3NF: trivial, single attribute PK, no extra dependencies.
  */

-- PAYMENTS
CREATE TABLE Payments (
  payment_id   INT AUTO_INCREMENT PRIMARY KEY,
  booking_id   INT NOT NULL,
  user_id      INT NOT NULL,
  method_id    INT NOT NULL,
  amount       DECIMAL(10,2) NOT NULL,
  payment_datetime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status VARCHAR(20) DEFAULT 'paid',
  CONSTRAINT payments_references_booking FOREIGN KEY (booking_id) REFERENCES Bookings(booking_id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT payments_belong_to_user FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT payments_use_method FOREIGN KEY (method_id) REFERENCES PaymentMethods(method_id) ON DELETE RESTRICT ON UPDATE CASCADE
);

/*
     Normalization proof:
     1NF: all columns atomic (INT,DECIMAL,TIMESTAMP). No repeating groups.
     2NF: PK is payment_id (single), so non key attributes fully depend on it.
     3NF: non key attributes (booking_id, method_id, amount, payment_datetime) depend only on payment_id, no attribute depends on another non key.
  */

-- DISCOUNTS (Loyalty Program)
CREATE TABLE Discounts (
  discount_id      INT AUTO_INCREMENT PRIMARY KEY,
  user_id          INT NOT NULL,
  booking_threshold INT NOT NULL,
  discount_percent DECIMAL(5,2) NOT NULL,
  status           VARCHAR(20) DEFAULT 'inactive',
  activated_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT discount_user FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
  CHECK (discount_percent > 0 AND discount_percent <= 100),
  CHECK (booking_threshold > 0),
  UNIQUE KEY unique_user_threshold (user_id, booking_threshold)
);

/*
   Normalization proof:
   1NF: atomic columns (INT, DECIMAL, VARCHAR, TIMESTAMP).
   2NF: single column PK (discount_id) ensures full dependency.
   3NF: all non key attributes (user_id, booking_threshold, discount_percent, status, activated_date)
        depend only on discount_id, no non key attribute determines another.
   Foreign key (user_id) maintains referential integrity.
*/


CREATE TABLE Reviews (
  review_id       INT AUTO_INCREMENT PRIMARY KEY,
  booking_id      INT NOT NULL,
  user_id         INT NOT NULL,
  field_id        INT NOT NULL,
  rating          DECIMAL(2,1) NOT NULL,
  comment         TEXT,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  helpful_count   INT DEFAULT 0,
  status          VARCHAR(20) DEFAULT 'published',
  CONSTRAINT review_booking FOREIGN KEY (booking_id) REFERENCES Bookings(booking_id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT review_user FOREIGN KEY (user_id)  REFERENCES Users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT review_field FOREIGN KEY (field_id)  REFERENCES SportFields(field_id)  ON DELETE CASCADE ON UPDATE CASCADE,
  CHECK (rating >= 1.0 AND rating <= 5.0),  
  UNIQUE KEY unique_booking_review (booking_id)
);

/*
   NORMALIZATION PROOF:
   1NF : All columns contain atomic values only
     - review_id, booking_id, user_id, field_id, rating, comment, created_at, updated_at, helpful_count, status
     - No repeating groups or multi valued attributes
     - Each field holds exactly one value
   2NF: Primary key is single-column (review_id)
     - Single column PK eliminates possibility of partial dependencies
     - All non key attributes fully depend on the entire key (review_id)
   3NF: No non-key attribute depends on another non-key
     - booking_id depends only on review_id (which booking does this review belong to?)
     - user_id depends only on review_id (who wrote this review?)
     - field_id depends only on review_id (which field is being reviewed?)
     - rating depends only on review_id (what rating was given?)
     - comment depends only on review_id (what text was provided?)
     - created_at, updated_at depend only on review_id (when was it created/edited?)
     - helpful_count depends only on review_id (how many found it helpful?)
     - status depends only on review_id (is it published or pending?)
     - No non-key determines another non-key:
       * booking_id does npt determine user_id, field_id, rating (multiple reviews possible)
       * user_id does not determine field_id (user can review multiple fields)
       * field_id does not determine rating (field can have multiple ratings)
       * comment does not determine helpful_count (votes independent of text)
     - No transitive chain exists.
     - UNIQUE constraint on booking_id reinforces one review per booking, preventing derived dependencies.
*/


-- USER WALLETS (Wallet System)
CREATE TABLE UserWallets (
  user_id INT PRIMARY KEY,
  balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  preferred_method ENUM('visa','mastercard','paypal') DEFAULT NULL,
  card_last4 VARCHAR(4),
  card_exp_month TINYINT,
  card_exp_year SMALLINT,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT wallet_belongs_to_user FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

/*
   Normalization proof:
   1NF: atomic columns (INT, DECIMAL, ENUM, VARCHAR, TINYINT, SMALLINT, TIMESTAMP).
   2NF: single column PK (user_id) ensures full dependency.
   3NF: all non-key attributes (balance, preferred_method, card_last4, card_exp_month, card_exp_year, updated_at)
        depend only on user_id, no non-key attribute determines another.
   Foreign key (user_id) maintains referential integrity with Users table.
*/

-- WALLET TRANSACTIONS (Transaction History)
CREATE TABLE WalletTransactions (
  tx_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  type ENUM('deposit','debit') NOT NULL,
  reference VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT wallet_tx_belongs_to_user FOREIGN KEY (user_id)  REFERENCES Users(user_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

/*
   Normalization proof:
   1NF: atomic columns (INT, DECIMAL, ENUM, VARCHAR, TIMESTAMP).
   2NF: single column PK (tx_id) ensures full dependency.
   3NF: all non-key attributes (user_id, amount, type, reference, created_at)
        depend only on tx_id, no transitive dependencies.
   Foreign key (user_id) maintains referential integrity with Users table.
*/

-- REFUNDS (Refund Management System)
CREATE TABLE Refunds (
  refund_id INT AUTO_INCREMENT PRIMARY KEY,
  booking_id INT NOT NULL,
  user_id INT NOT NULL,
  payment_id INT NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  reason VARCHAR(255) NOT NULL,
  status VARCHAR(20) DEFAULT 'pending',
  requested_by INT NOT NULL,
  requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  processed_at TIMESTAMP NULL,
  CONSTRAINT refund_booking FOREIGN KEY (booking_id) REFERENCES Bookings(booking_id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT refund_user FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT refund_payment FOREIGN KEY (payment_id) REFERENCES Payments(payment_id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT refund_requested_by FOREIGN KEY (requested_by) REFERENCES Users(user_id) ON DELETE CASCADE ON UPDATE CASCADE, CHECK (amount > 0),
  CHECK (status IN ('pending', 'approved', 'rejected', 'completed'))
) ENGINE=InnoDB;

/*
   Normalization proof:
   1NF: atomic columns (INT, DECIMAL, VARCHAR, TIMESTAMP).
     - refund_id, booking_id, user_id, payment_id, amount, reason, status, requested_by, requested_at, processed_at
     - Each field holds exactly one value, no repeating groups or multi-valued attributes
   
   2NF: Primary key is single-column (refund_id)
     - Single column PK eliminates possibility of partial dependencies
     - All non-key attributes fully depend on the entire key (refund_id)
   
   3NF: No non-key attribute depends on another non-key
     - booking_id depends only on refund_id (which booking is being refunded?)
     - user_id depends only on refund_id (who is receiving the refund?)
     - payment_id depends only on refund_id (which payment is being refunded?)
     - amount depends only on refund_id (how much is being refunded?)
     - reason depends only on refund_id (why is this refund requested?)
     - status depends only on refund_id (what is the refund status?)
     - requested_by depends only on refund_id (who requested the refund - admin or customer?)
     - requested_at depends only on refund_id (when was refund requested?)
     - processed_at depends only on refund_id (when was refund processed?)
     - No non-key determines another non-key:
       * booking_id does not determine user_id (booking already has user relationship)
       * payment_id does not determine amount (refund amount may differ from payment)
       * user_id does not determine status (status is independent of user)
       * requested_by does not determine reason (reason is independent of requester)
     - No transitive chain exists
     - Foreign keys properly maintain referential integrity
*/

-- ========== SAMPLE DATA INSERTS ==========

-- Insert Field Owners
INSERT INTO FieldOwners (business_name, phone, address)
VALUES
  ('Sporty Fields Co.', '0618394257', '123 Sport St.'),
  ('Active Grounds Ltd.', '0692784324', '456 Active Ave.'),
  ('Fitness Fields Inc.', '0627382134', '789 Fitness Blvd.'),
  ('Champion Courts', '0683294356', '101 Champion Rd.');

-- Insert Users
INSERT INTO Users (uname, email, phone, address, password, type)
VALUES
  ('JohnDoe', 'john@googlexsd.com', '0638549385', '12 Elm St.', 'temp_password', 'customer'),
  ('JaneSmith', 'jane@domain.com', '0638294532', '34 Oak Ave.', 'temp_password', 'customer'),
  ('BobBrown', 'bob@another.com', '0682954124', '56 Pine Rd.', 'temp_password', 'customer'),
  ('AdminUser', 'admin@sportspot.com', '0671234567', '1 Admin Plaza', 'admin_password', 'admin');

-- Insert Sport Fields
INSERT INTO SportFields (owner_id, name, sport_type, address, opening_hour, closing_hour, price_per_hour, status, description, capacity, cover)
VALUES
  (1, 'Main Soccer Arena', 'Soccer', '123 Sport St.', '08:00:00', '22:00:00', 25.00, 'available', 'Full size artificial turf', 22, 'soccer.jpg'),
  (1, 'Indoor Futsal Center', 'Futsal', '123 Sport St.', '10:00:00', '23:00:00', 18.50, 'available', 'Indoor climate-controlled futsal court', 10, 'futsal.jpg'),
  (2, 'Tennis Pro Court 1', 'Tennis', '456 Active Ave.', '07:00:00', '21:00:00', 30.00, 'maintenance', 'Clay court for pro training', 4, 'tennis.jpg'),
  (3, 'Basketball Hoops Arena', 'Basketball', '789 Fitness Blvd.', '09:00:00', '23:00:00', 20.00, 'available', 'Indoor court with 5 hoops', 10, 'basketball.jpg');

-- Insert Payment Methods (including wallet)
INSERT INTO PaymentMethods (method_name)
VALUES
  ('card'),
  ('cash'),
  ('bank_transfer'),
  ('wallet');

-- Insert Bookings
INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status)
VALUES
  (1, 1, '2025-11-10 10:00:00', '10:00:00', '12:00:00', 'confirmed'),
  (2, 2, '2025-11-12 12:00:00', '14:00:00', '15:30:00', 'cancelled'),
  (3, 4, '2025-11-15 15:00:00', '18:00:00', '20:00:00', 'confirmed');

-- Insert Payments
INSERT INTO Payments (booking_id, user_id, method_id, amount, payment_datetime, status)
VALUES
  (1, 1, 4, 50.00, '2025-11-10 10:05:00', 'paid'),
  (3, 3, 4, 40.00, '2025-11-15 15:05:00', 'paid');

-- Insert Reviews
INSERT INTO Reviews (booking_id, user_id, field_id, rating, comment)
VALUES
  (1, 1, 1, 4.5, 'Great field, had a wonderful time playing here!'),
  (3, 3, 4, 5.0, 'Excellent facilities and friendly staff.');

-- Insert User Wallets
INSERT INTO UserWallets (user_id, balance, preferred_method, card_last4, card_exp_month, card_exp_year)
VALUES
  (1, 150.00, 'visa', '4242', 12, 2027),
  (2, 200.00, 'mastercard', '5555', 6, 2026),
  (3, 100.00, 'paypal', NULL, NULL, NULL),
  (4, 500.00, 'visa', '1234', 3, 2028);

-- Insert Wallet Transactions
INSERT INTO WalletTransactions (user_id, amount, type, reference)
VALUES
  (1, 200.00, 'deposit', 'visa'),
  (1, 50.00, 'debit', 'booking:1'),
  (2, 200.00, 'deposit', 'mastercard'),
  (3, 150.00, 'deposit', 'paypal'),
  (3, 40.00, 'debit', 'booking:3'),
  (4, 500.00, 'deposit', 'visa');