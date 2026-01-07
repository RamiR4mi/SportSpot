const express = require("express");
const mysql = require("mysql2");
const cors = require("cors");
const bcrypt = require("bcrypt");
require('dotenv').config();

const app = express();
app.use(express.json({ limit: '10mb' }));
app.use(cors({
  origin: process.env.CLIENT_URL || "http://localhost:3000",
  credentials: true
}));

// Database connection with environment variables
const db = mysql.createPool({
  host: process.env.DB_HOST || "localhost",
  user: process.env.DB_USER || "root",
  password: process.env.DB_PASSWORD || "",
  database: process.env.DB_NAME || "sportspot",
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

const dbAsync = db.promise();
const WALLET_METHOD = 'wallet';
const allowedPaymentMethods = ['visa', 'mastercard', 'paypal'];

// Logger utility
const logger = {
  error: (msg, err = '') => console.error(`[ERROR] ${new Date().toISOString()} - ${msg}`, err),
  info: (msg) => console.log(`[INFO] ${new Date().toISOString()} - ${msg}`),
  warn: (msg) => console.warn(`[WARN] ${new Date().toISOString()} - ${msg}`)
};

// Ensure wallet-related tables and payment method exist
const ensureWalletInfrastructure = async () => {
  try {
    await dbAsync.query(`
      CREATE TABLE IF NOT EXISTS UserWallets (
        user_id INT PRIMARY KEY,
        balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
        preferred_method ENUM('visa','mastercard','paypal') DEFAULT NULL,
        card_last4 VARCHAR(4),
        card_exp_month TINYINT,
        card_exp_year SMALLINT,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        CONSTRAINT fk_wallet_user FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE ON UPDATE CASCADE
      ) ENGINE=InnoDB;
    `);

    await dbAsync.query(`
      CREATE TABLE IF NOT EXISTS WalletTransactions (
        tx_id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        amount DECIMAL(10,2) NOT NULL,
        type ENUM('deposit','debit') NOT NULL,
        reference VARCHAR(100),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT fk_wallet_tx_user FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE ON UPDATE CASCADE
      ) ENGINE=InnoDB;
    `);

    await dbAsync.query(
      `INSERT INTO PaymentMethods (method_name) VALUES (?) ON DUPLICATE KEY UPDATE method_name = VALUES(method_name)`,
      [WALLET_METHOD]
    );

    logger.info('Wallet infrastructure ensured');
  } catch (err) {
    logger.error('Wallet infrastructure setup failed', err);
  }
};

db.getConnection((err, connection) => {
  if (err) {
    logger.error("❌ Database connection failed:", err.message);
    process.exit(1);
  }
  logger.info("✓ Connected to SportSpot database (pool)!");
  connection.release();
  ensureWalletInfrastructure();
});

// Error handling middleware
process.on('unhandledRejection', (err) => {
  logger.error('Unhandled Rejection:', err);
});

process.on('uncaughtException', (err) => {
  logger.error('Uncaught Exception:', err);
  process.exit(1);
});

const toMySQLDatetime = (dt) => new Date(dt).toISOString().slice(0, 19).replace('T', ' ');
const timeToMinutes = (timeStr) => {
  const [h, m] = timeStr.split(':').map(Number);
  return h * 60 + m;
};
const calculateAmount = (start, end, pricePerHour) => {
  const diffMinutes = timeToMinutes(end) - timeToMinutes(start);
  if (diffMinutes <= 0) return null;
  const amount = (parseFloat(pricePerHour) * diffMinutes) / 60;
  return Number(amount.toFixed(2));
};


app.get("/", (req, res) => {
    res.json("Hello this is the backend");
})

app.get("/SportFields", (req, res) => {
  const query = `
    SELECT 
      sf.field_id,
      sf.owner_id,
      sf.name,
      sf.sport_type,
      sf.address,
      sf.opening_hour,
      sf.closing_hour,
      sf.price_per_hour,
      sf.status,
      sf.description,
      sf.capacity,
      sf.cover,
      ROUND(AVG(CASE WHEN r.status = 'published' THEN r.rating END), 2) AS avg_rating,
      COUNT(CASE WHEN r.status = 'published' THEN r.review_id END) AS total_reviews,
      (SELECT r2.comment FROM Reviews r2 WHERE r2.field_id = sf.field_id AND r2.status = 'published' ORDER BY r2.created_at DESC LIMIT 1) AS latest_comment,
      (SELECT r3.rating FROM Reviews r3 WHERE r3.field_id = sf.field_id AND r3.status = 'published' ORDER BY r3.created_at DESC LIMIT 1) AS latest_rating
    FROM SportFields sf
    LEFT JOIN Reviews r ON sf.field_id = r.field_id
    GROUP BY sf.field_id
    ORDER BY sf.name ASC
  `;
  db.query(query, (err, data) => { 
    if (err) {
      logger.error("SportFields query error:", err);
      return res.status(500).json({ error: "Failed to fetch fields" });
    }
    return res.json(data);
  });
});

// Get fields by owner user_id (for owner dashboard)
app.get("/SportFields/owner/:userId", (req, res) => {
  const userId = req.params.userId;
  const query = `
    SELECT 
      sf.field_id,
      sf.owner_id,
      sf.name,
      sf.sport_type,
      sf.address,
      sf.opening_hour,
      sf.closing_hour,
      sf.price_per_hour,
      sf.status,
      sf.description,
      sf.capacity,
      sf.cover,
      ROUND(AVG(CASE WHEN r.status = 'published' THEN r.rating END), 2) AS avg_rating,
      COUNT(CASE WHEN r.status = 'published' THEN r.review_id END) AS total_reviews,
      (SELECT r2.comment FROM Reviews r2 WHERE r2.field_id = sf.field_id AND r2.status = 'published' ORDER BY r2.created_at DESC LIMIT 1) AS latest_comment,
      (SELECT r3.rating FROM Reviews r3 WHERE r3.field_id = sf.field_id AND r3.status = 'published' ORDER BY r3.created_at DESC LIMIT 1) AS latest_rating
    FROM SportFields sf
    JOIN FieldOwners fo ON sf.owner_id = fo.owner_id
    LEFT JOIN Reviews r ON sf.field_id = r.field_id
    WHERE fo.user_id = ?
    GROUP BY sf.field_id
    ORDER BY sf.name ASC
  `;
  db.query(query, [userId], (err, data) => {
    if (err) {
      logger.error("Owner fields query error:", err);
      return res.status(500).json({ error: "Failed to fetch owner fields" });
    }
    return res.json(data);
  });
});

// Helper function to auto-create FieldOwners entry if missing
const autoCreateFieldOwnerSync = (userId, callback) => {
  const checkQuery = "SELECT owner_id FROM FieldOwners WHERE user_id = ?";
  
  db.query(checkQuery, [userId], (err, data) => {
    if (err) {
      console.error("Check FieldOwners error:", err);
      return callback(err, null);
    }
    
    // If exists, return the owner_id
    if (data && data.length > 0) {
      console.log("FieldOwners entry already exists for user", userId);
      return callback(null, data[0].owner_id);
    }
    
    // If not exists, create it with minimal info
    const createQuery = "INSERT INTO FieldOwners (user_id, business_name) VALUES (?, ?)";
    const businessName = `Field Business - User ${userId}`;
    
    db.query(createQuery, [userId, businessName], (err, result) => {
      if (err) {
        console.error("Create FieldOwners error:", err);
        return callback(err, null);
      }
      
      console.log("FieldOwners entry auto-created with owner_id:", result.insertId);
      return callback(null, result.insertId);
    });
  });
};

app.post("/SportFields", (req, res) => {
  const query = `INSERT INTO SportFields 
  (
  owner_id, 
  name, 
  sport_type, 
  address, 
  opening_hour, 
  closing_hour, 
  price_per_hour, 
  status, 
  description, 
  capacity,
  cover)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `;
  const values = [
      req.body.owner_id,
      req.body.name,
      req.body.sport_type,
      req.body.address,
      req.body.opening_hour, 
      req.body.closing_hour, 
      req.body.price_per_hour, 
      req.body.status, 
      req.body.description, 
      req.body.capacity,
      req.body.cover];

  console.log("Creating SportField with values:", values);
  db.query(query, values, (err, data) => {
    if (err) {
      // Check if it's a foreign key constraint error
      if (err.code === 'ER_NO_REFERENCED_ROW_2' || err.code === 'ER_NO_REFERENCED_ROW') {
        console.warn("Foreign key constraint failed for owner_id:", req.body.owner_id);
        console.log("Attempting to auto-create FieldOwners entry...");
        
        // Try to auto-create the FieldOwners entry and retry
        autoCreateFieldOwnerSync(req.body.user_id, (autoErr, newOwnerId) => {
          if (autoErr) {
            console.error("Failed to auto-create FieldOwners:", autoErr);
            return res.status(500).json({ 
              error: "Failed to create owner profile. Please contact support.", 
              details: autoErr.message 
            });
          }
          
          // Retry with the new owner_id
          const retryValues = [
            newOwnerId,
            req.body.name,
            req.body.sport_type,
            req.body.address,
            req.body.opening_hour, 
            req.body.closing_hour, 
            req.body.price_per_hour, 
            req.body.status, 
            req.body.description, 
            req.body.capacity,
            req.body.cover
          ];
          
          console.log("Retrying SportField creation with new owner_id:", newOwnerId);
          db.query(query, retryValues, (retryErr, retryData) => {
            if (retryErr) {
              console.error("Error on retry:", retryErr);
              return res.status(500).json({ 
                error: "Failed to create field after auto-creating owner profile", 
                details: retryErr.message 
              });
            }
            
            console.log("SportField created successfully after auto-create fallback");
            return res.json({ 
              message: "Field created successfully", 
              data: retryData,
              note: "Owner profile was auto-created"
            });
          });
        });
      } else {
        console.error("Error inserting SportField:", err);
        return res.status(500).json({ error: err.message, code: err.code });
      }
    } else {
      console.log("SportField created successfully");
      return res.json({ message: "Field created successfully", data });
    }
  });
});

app.delete("/SportFields/:id", (req, res) => {
  const fieldId = req.params.id;
  const query = "DELETE FROM SportFields WHERE field_id = ?";

  db.query(query, [fieldId], (err, data) => {
    if (err) return res.json(err);
    return res.json({ message: "Field deleted successfully", data });
})
});

app.put("/SportFields/:id", (req, res) => {
  console.log("Request body:", req.body); // Debugging line
  const fieldId = req.params.id;
  const query = "UPDATE SportFields SET owner_id = ?, name = ?, sport_type = ?, address = ?, opening_hour = ?, closing_hour = ?, price_per_hour = ?, status = ?, description = ?, capacity = ?, cover = ? WHERE field_id = ?";
  const values =[
    req.body.owner_id,
    req.body.name,
    req.body.sport_type,
    req.body.address,
    req.body.opening_hour,
    req.body.closing_hour,
    req.body.price_per_hour,
    req.body.status,
    req.body.description,
    req.body.capacity,
    req.body.cover,
  ]



  db.query(query, [...values,fieldId], (err, data) => {
    if (err) return res.json(err);
    return res.json({ message: "Field has been updated successfully", data });
})
});


// ==================== USERS ENDPOINTS ====================
app.get("/Users", (req, res) => {
  const query = "SELECT * FROM Users";
  db.query(query, (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json(data);
  });
});

app.post("/Users", (req, res) => {
  const query = "INSERT INTO Users (uname, email, phone, address) VALUES (?, ?, ?, ?)";
  const values = [req.body.uname, req.body.email, req.body.phone, req.body.address];
  db.query(query, values, (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.status(201).json({ message: "User created", user_id: data.insertId });
  });
});

app.put("/Users/:id", (req, res) => {
  const userId = req.params.id;
  const query = "UPDATE Users SET uname = ?, email = ?, phone = ?, address = ? WHERE user_id = ?";
  const values = [req.body.uname, req.body.email, req.body.phone, req.body.address];
  db.query(query, [...values, userId], (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json({ message: "User updated" });
  });
});

app.delete("/Users/:id", (req, res) => {
  const userId = req.params.id;
  const query = "DELETE FROM Users WHERE user_id = ?";
  db.query(query, [userId], (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json({ message: "User deleted" });
  });
});

// ==================== AUTH ENDPOINTS ====================

// Register endpoint
app.post("/register", async (req, res) => {
  const { uname, email, phone, address, password, type } = req.body;
  if (!uname || !email || !password) {
    return res.status(400).json({ error: "Missing required fields" });
  }
  
  // Validate user type
  const validTypes = ['admin', 'owner', 'customer'];
  const userType = type && validTypes.includes(type) ? type : 'customer';
  
  try {
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(password, salt);
    const query = "INSERT INTO Users (uname, email, phone, address, password, type) VALUES (?, ?, ?, ?, ?, ?)";
    const values = [uname, email, phone, address, hashedPassword, userType];
    db.query(query, values, (err, data) => {
      if (err) {
        if (err.code === "ER_DUP_ENTRY") {
          return res.status(409).json({ error: "Email already registered" });
        }
        return res.status(500).json({ error: err.message });
      }
      return res.status(201).json({ message: "User registered", user_id: data.insertId, type: userType });
    });
  } catch (err) {
    return res.status(500).json({ error: "Server error" });
  }
});

// Login endpoint
app.post("/login", (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    return res.status(400).json({ error: "Missing email or password" });
  }
  const query = "SELECT * FROM Users WHERE email = ?";
  db.query(query, [email], async (err, results) => {
    if (err) return res.status(500).json({ error: err.message });
    if (results.length === 0) {
      return res.status(401).json({ error: "Invalid email or password" });
    }
    const user = results[0];
    const valid = await bcrypt.compare(password, user.password);
    if (!valid) {
      return res.status(401).json({ error: "Invalid email or password" });
    }
    // Don't send password back
    const { password: _, ...userData } = user;
    return res.json({ message: "Login successful", user: userData });
  });
});

// ==================== FIELD OWNERS ENDPOINTS ====================
app.get("/FieldOwners", (req, res) => {
  const query = "SELECT * FROM FieldOwners";
  db.query(query, (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    console.log("All FieldOwners:", data);
    return res.json(data);
  });
});

// Get FieldOwners entry by user_id
app.get("/FieldOwners/user/:userId", (req, res) => {
  const userId = req.params.userId;
  const query = "SELECT * FROM FieldOwners WHERE user_id = ?";
  db.query(query, [userId], (err, data) => {
    if (err) {
      console.error("FieldOwners lookup error:", err);
      return res.status(500).json({ error: err.message });
    }
    console.log(`FieldOwners entry for user ${userId}:`, data);
    return res.json(data);
  });
});

// Auto-create FieldOwners entry if it doesn't exist
app.post("/FieldOwners/auto-create/:userId", (req, res) => {
  const userId = req.params.userId;
  const { uname, phone, address } = req.body;
  
  console.log(`Auto-create FieldOwners for user ${userId}`);
  
  // First check if entry already exists
  const checkQuery = "SELECT * FROM FieldOwners WHERE user_id = ?";
  db.query(checkQuery, [userId], (err, data) => {
    if (err) {
      console.error("Check error:", err);
      return res.status(500).json({ error: "Database error" });
    }
    
    // If exists, return it
    if (data && data.length > 0) {
      console.log("FieldOwners entry already exists:", data[0]);
      return res.json({ created: false, owner_id: data[0].owner_id, data: data[0] });
    }
    
    // If not, create it
    const createQuery = "INSERT INTO FieldOwners (user_id, business_name, phone, address) VALUES (?, ?, ?, ?)";
    const businessName = `Field Business - ${uname || 'Owner'}`;
    const values = [userId, businessName, phone || null, address || null];
    
    db.query(createQuery, values, (err, result) => {
      if (err) {
        console.error("Create error:", err);
        return res.status(500).json({ error: "Failed to create FieldOwners entry" });
      }
      
      console.log("FieldOwners entry created with owner_id:", result.insertId);
      return res.json({ 
        created: true, 
        owner_id: result.insertId,
        message: "FieldOwners entry created successfully"
      });
    });
  });
});

app.post("/FieldOwners", (req, res) => {
  const query = "INSERT INTO FieldOwners (business_name, phone, address) VALUES (?, ?, ?)";
  const values = [req.body.business_name, req.body.phone, req.body.address];
  db.query(query, values, (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.status(201).json({ message: "Field Owner created", owner_id: data.insertId });
  });
});

app.put("/FieldOwners/:id", (req, res) => {
  const ownerId = req.params.id;
  const query = "UPDATE FieldOwners SET business_name = ?, phone = ?, address = ? WHERE owner_id = ?";
  const values = [req.body.business_name, req.body.phone, req.body.address];
  db.query(query, [...values, ownerId], (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json({ message: "Field Owner updated" });
  });
});

app.delete("/FieldOwners/:id", (req, res) => {
  const ownerId = req.params.id;
  const query = "DELETE FROM FieldOwners WHERE owner_id = ?";
  db.query(query, [ownerId], (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json({ message: "Field Owner deleted" });
  });
});

// ==================== BOOKINGS ENDPOINTS ====================
app.get("/Bookings", (req, res) => {
  const query = "SELECT * FROM Bookings";
  db.query(query, (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json(data);
  });
});

app.post("/Bookings", async (req, res) => {
  const connection = await dbAsync.getConnection();
  try {
    const { user_id, field_id, booking_datetime, start_time, end_time, status } = req.body;
    if (!user_id || !field_id || !booking_datetime || !start_time || !end_time) {
      connection.release();
      return res.status(400).json({ error: "Missing required fields" });
    }

    const bookingDatetime = toMySQLDatetime(booking_datetime);

    await connection.beginTransaction();

    // Check for booking conflicts
    const conflictQuery = `
      SELECT * FROM Bookings 
      WHERE field_id = ? 
      AND DATE(booking_datetime) = DATE(?)
      AND status IN ('pending', 'confirmed')
      AND (
        (start_time < ? AND end_time > ?) OR
        (start_time < ? AND end_time > ?)
      )
    `;
    const [conflicts] = await connection.query(conflictQuery, [field_id, bookingDatetime, end_time, start_time, end_time, start_time]);
    if (conflicts.length > 0) {
      await connection.rollback();
      connection.release();
      return res.status(409).json({ error: "This time slot is already booked. Please choose another time." });
    }

    // Get field price
    const [fieldRows] = await connection.query("SELECT price_per_hour FROM SportFields WHERE field_id = ?", [field_id]);
    if (fieldRows.length === 0) {
      await connection.rollback();
      connection.release();
      return res.status(404).json({ error: "Field not found" });
    }
    const amount = calculateAmount(start_time, end_time, fieldRows[0].price_per_hour);
    if (!amount || amount <= 0) {
      await connection.rollback();
      connection.release();
      return res.status(400).json({ error: "Invalid time range" });
    }

    // Ensure wallet row exists then lock balance
    await connection.query("INSERT IGNORE INTO UserWallets (user_id) VALUES (?)", [user_id]);
    const [walletRows] = await connection.query("SELECT balance FROM UserWallets WHERE user_id = ? FOR UPDATE", [user_id]);
    if (walletRows.length === 0) {
      await connection.rollback();
      connection.release();
      return res.status(404).json({ error: "Wallet not found for user" });
    }

    const currentBalance = parseFloat(walletRows[0].balance);
    if (currentBalance < amount) {
      await connection.rollback();
      connection.release();
      return res.status(402).json({ error: "Insufficient balance. Please add funds to your wallet." });
    }

    // Create booking
    const bookingInsert = "INSERT INTO Bookings (user_id, field_id, booking_datetime, start_time, end_time, status) VALUES (?, ?, ?, ?, ?, ?)";
    const [bookingData] = await connection.query(bookingInsert, [user_id, field_id, bookingDatetime, start_time, end_time, status || 'pending']);
    const bookingId = bookingData.insertId;

    // Deduct balance
    await connection.query("UPDATE UserWallets SET balance = balance - ? WHERE user_id = ?", [amount, user_id]);
    await connection.query("INSERT INTO WalletTransactions (user_id, amount, type, reference) VALUES (?, ?, 'debit', ?)", [user_id, amount, `booking:${bookingId}`]);

    // Ensure wallet payment method exists and record payment
    const [methodRows] = await connection.query("SELECT method_id FROM PaymentMethods WHERE method_name = ?", [WALLET_METHOD]);
    let methodId = methodRows.length ? methodRows[0].method_id : null;
    if (!methodId) {
      const [newMethod] = await connection.query("INSERT INTO PaymentMethods (method_name) VALUES (?)", [WALLET_METHOD]);
      methodId = newMethod.insertId;
    }
    await connection.query(
      "INSERT INTO Payments (booking_id, user_id, method_id, amount, payment_datetime) VALUES (?, ?, ?, ?, NOW())",
      [bookingId, user_id, methodId, amount]
    );

    await connection.commit();
    connection.release();
    logger.info(`Booking created: ID ${bookingId}, User ${user_id}, Field ${field_id}, Amount ${amount}`);
    return res.status(201).json({ message: "Booking created", booking_id: bookingId, amount });
  } catch (err) {
    try {
      await connection.rollback();
    } catch (_) {}
    connection.release();
    logger.error("Booking endpoint error:", err);
    res.status(500).json({ error: "Server error" });
  }
});

app.put("/Bookings/:id", async (req, res) => {
  const bookingId = req.params.id;
  const { user_id, field_id, booking_datetime, start_time, end_time, status } = req.body;
  
  const connection = await dbAsync.getConnection();
  try {
    await connection.beginTransaction();

    // Get current booking status and payment info
    const [bookings] = await connection.query(
      "SELECT b.status as old_status, b.user_id, p.payment_id, p.amount, p.method_id FROM Bookings b LEFT JOIN Payments p ON b.booking_id = p.booking_id WHERE b.booking_id = ?",
      [bookingId]
    );

    if (bookings.length === 0) {
      await connection.rollback();
      return res.status(404).json({ error: "Booking not found" });
    }

    const booking = bookings[0];
    const oldStatus = booking.old_status;
    
    // PROBLEM SOLVED: Status-only updates vs Full booking updates
    // ISSUE: When owner clicks "Confirm" or "Cancel" button, the frontend sends only { status: "confirmed"|"cancelled" }
    // The original code always executed: UPDATE Bookings SET user_id = ?, field_id = ?, booking_datetime = ?, ... 
    // Since user_id, field_id, etc. were undefined in the request body, they got set to NULL in the UPDATE statement.
    // This caused error: "ER_BAD_NULL_ERROR: Column 'user_id' cannot be null" because user_id is NOT NULL in schema.
    // SOLUTION: Check if request contains full booking details (user_id, field_id, etc.) or just a status update.
    // If only status is provided, execute a status-only UPDATE query. If full details are provided, update all fields.
    // This allows the same endpoint to handle both partial (owner action) and complete (admin edit) updates.
    
    // Update booking - only update fields that are provided
    if (user_id !== undefined || field_id !== undefined || booking_datetime !== undefined || start_time !== undefined || end_time !== undefined) {
      // Full update when all booking details are provided
      await connection.query(
        "UPDATE Bookings SET user_id = ?, field_id = ?, booking_datetime = ?, start_time = ?, end_time = ?, status = ? WHERE booking_id = ?",
        [user_id, field_id, booking_datetime, start_time, end_time, status, bookingId]
      );
    } else if (status !== undefined) {
      // Status-only update for owner actions (confirm/cancel)
      await connection.query(
        "UPDATE Bookings SET status = ? WHERE booking_id = ?",
        [status, bookingId]
      );
    } else {
      await connection.rollback();
      return res.status(400).json({ error: "No fields to update" });
    }

    // If booking is being cancelled and was previously paid, process refund
    if (status === 'cancelled' && oldStatus !== 'cancelled' && booking.payment_id && booking.amount) {
      const refundAmount = parseFloat(booking.amount);
      const userId = booking.user_id;

      // Get wallet method_id
      const [walletMethod] = await connection.query("SELECT method_id FROM PaymentMethods WHERE method_name = 'wallet'");
      
      if (walletMethod.length === 0) {
        await connection.rollback();
        return res.status(500).json({ error: "Wallet payment method not found" });
      }

      // Refund to wallet
      await connection.query(
        "INSERT IGNORE INTO UserWallets (user_id, balance) VALUES (?, 0.00)",
        [userId]
      );
      await connection.query(
        "UPDATE UserWallets SET balance = balance + ? WHERE user_id = ?",
        [refundAmount, userId]
      );

      // Record refund transaction in WalletTransactions
      await connection.query(
        "INSERT INTO WalletTransactions (user_id, amount, type, reference) VALUES (?, ?, 'deposit', ?)",
        [userId, refundAmount, `refund:booking:${bookingId}`]
      );

      // Update original payment status to refunded
      await connection.query(
        "UPDATE Payments SET status = 'refunded' WHERE payment_id = ?",
        [booking.payment_id]
      );
    }

    await connection.commit();
    return res.json({ message: "Booking updated" + (status === 'cancelled' && oldStatus !== 'cancelled' && booking.payment_id ? " and refund processed" : "") });
  } catch (err) {
    await connection.rollback();
    logger.error("Booking update error:", err);
    return res.status(500).json({ error: err.message });
  } finally {
    connection.release();
  }
});

app.delete("/Bookings/:id", (req, res) => {
  const bookingId = req.params.id;
  const query = "DELETE FROM Bookings WHERE booking_id = ?";
  db.query(query, [bookingId], (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json({ message: "Booking deleted" });
  });
});

// ==================== PAYMENT METHODS ENDPOINTS ====================
app.get("/PaymentMethods", (req, res) => {
  const query = "SELECT * FROM PaymentMethods";
  db.query(query, (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json(data);
  });
});

app.post("/PaymentMethods", (req, res) => {
  const query = "INSERT INTO PaymentMethods (method_name) VALUES (?)";
  const values = [req.body.method_name];
  db.query(query, values, (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.status(201).json({ message: "Payment Method created", method_id: data.insertId });
  });
});

app.put("/PaymentMethods/:id", (req, res) => {
  const methodId = req.params.id;
  const query = "UPDATE PaymentMethods SET method_name = ? WHERE method_id = ?";
  const values = [req.body.method_name];
  db.query(query, [...values, methodId], (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json({ message: "Payment Method updated" });
  });
});

app.delete("/PaymentMethods/:id", (req, res) => {
  const methodId = req.params.id;
  const query = "DELETE FROM PaymentMethods WHERE method_id = ?";
  db.query(query, [methodId], (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json({ message: "Payment Method deleted" });
  });
});

// ==================== PAYMENTS ENDPOINTS ====================
app.get("/Payments", async (req, res) => {
  try {
    const { user_id } = req.query;
    const params = [];
    let query = `
      SELECT p.payment_id, p.booking_id, p.user_id, p.method_id, p.amount, p.payment_datetime, p.status,
             pm.method_name
      FROM Payments p
      LEFT JOIN PaymentMethods pm ON p.method_id = pm.method_id
    `;
    if (user_id) {
      query += " WHERE p.user_id = ?";
      params.push(user_id);
    }
    query += " ORDER BY p.payment_datetime DESC";

    const [rows] = await dbAsync.query(query, params);
    return res.json(rows);
  } catch (err) {
    logger.error("Payments fetch error:", err);
    return res.status(500).json({ error: "Failed to fetch payments" });
  }
});

app.post("/Payments", (req, res) => {
  const query = "INSERT INTO Payments (booking_id, user_id, method_id, amount, payment_datetime) VALUES (?, ?, ?, ?, ?)";
  const values = [req.body.booking_id, req.body.user_id, req.body.method_id, req.body.amount, req.body.payment_datetime];
  db.query(query, values, (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.status(201).json({ message: "Payment created", payment_id: data.insertId });
  });
});

app.put("/Payments/:id", (req, res) => {
  const paymentId = req.params.id;
  const query = "UPDATE Payments SET booking_id = ?, user_id = ?, method_id = ?, amount = ?, payment_datetime = ? WHERE payment_id = ?";
  const values = [req.body.booking_id, req.body.user_id, req.body.method_id, req.body.amount, req.body.payment_datetime];
  db.query(query, [...values, paymentId], (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json({ message: "Payment updated" });
  });
});

app.delete("/Payments/:id", (req, res) => {
  const paymentId = req.params.id;
  const query = "DELETE FROM Payments WHERE payment_id = ?";
  db.query(query, [paymentId], (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json({ message: "Payment deleted" });
  });
});

// ==================== REVIEWS ENDPOINTS ====================
app.get("/Reviews", (req, res) => {
  const query = "SELECT * FROM Reviews";
  db.query(query, (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json(data);
  });
});

app.post("/Reviews", async (req, res) => {
  const { booking_id, user_id, field_id, rating, comment, status } = req.body;
  if (!booking_id || !user_id || !field_id || !rating || !comment) {
    return res.status(400).json({ error: "Missing required fields" });
  }

  try {
    // Upsert to avoid duplicate error on unique booking_id
    const [existing] = await dbAsync.query("SELECT review_id FROM Reviews WHERE booking_id = ?", [booking_id]);

    if (existing.length > 0) {
      const reviewId = existing[0].review_id;
      await dbAsync.query(
        "UPDATE Reviews SET user_id = ?, field_id = ?, rating = ?, comment = ?, status = ? , updated_at = NOW() WHERE review_id = ?",
        [user_id, field_id, rating, comment, status || "published", reviewId]
      );
      return res.json({ message: "Review updated", review_id: reviewId });
    }

    const [insert] = await dbAsync.query(
      "INSERT INTO Reviews (booking_id, user_id, field_id, rating, comment, status) VALUES (?, ?, ?, ?, ?, ?)",
      [booking_id, user_id, field_id, rating, comment, status || "published"]
    );
    return res.status(201).json({ message: "Review created", review_id: insert.insertId });
  } catch (err) {
    logger.error("Review insert error:", err);
    return res.status(500).json({ error: "Failed to submit review" });
  }
});

app.put("/Reviews/:id", (req, res) => {
  const reviewId = req.params.id;
  const query = "UPDATE Reviews SET booking_id = ?, user_id = ?, field_id = ?, rating = ?, comment = ?, status = ? WHERE review_id = ?";
  const values = [req.body.booking_id, req.body.user_id, req.body.field_id, req.body.rating, req.body.comment, req.body.status];
  db.query(query, [...values, reviewId], (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json({ message: "Review updated" });
  });
});

app.delete("/Reviews/:id", (req, res) => {
  const reviewId = req.params.id;
  const query = "DELETE FROM Reviews WHERE review_id = ?";
  db.query(query, [reviewId], (err, data) => {
    if (err) return res.status(500).json({ error: err.message });
    return res.json({ message: "Review deleted" });
  });
});

// ==================== AUTHENTICATION ENDPOINTS ====================
// Validation helpers
const validateEmail = (email) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
const validatePhone = (phone) => /^(06|07)\d{8}$/.test(phone);

app.post("/register", async (req, res) => {
  try {
    const { uname, email, phone, address, password, type } = req.body;

    // Comprehensive validation
    if (!uname || !email || !password) {
      return res.status(400).json({ error: "Username, email, and password are required" });
    }
    if (uname.length < 3) {
      return res.status(400).json({ error: "Username must be at least 3 characters" });
    }
    if (!validateEmail(email)) {
      return res.status(400).json({ error: "Invalid email format" });
    }
    if (password.length < 8) {
      return res.status(400).json({ error: "Password must be at least 8 characters" });
    }
    if (phone && !validatePhone(phone)) {
      return res.status(400).json({ error: "Phone must be in format 06xxxxxxxx or 07xxxxxxxx" });
    }

    // Check if user already exists
    db.query("SELECT user_id FROM Users WHERE email = ?", [email], async (err, data) => {
      if (err) {
        logger.error("Email check error:", err);
        return res.status(500).json({ error: "Database error" });
      }
      if (data.length > 0) {
        return res.status(409).json({ error: "Email already registered" });
      }

      // Validate user type
      const validTypes = ['admin', 'owner', 'customer'];
      const userType = type && validTypes.includes(type) ? type : 'customer';

      // Hash password with salt
      const salt = await bcrypt.genSalt(12);
      const hashedPassword = await bcrypt.hash(password, salt);

      // Insert new user with specified type (trigger will auto-create FieldOwners if type='owner')
      const query = "INSERT INTO Users (uname, email, phone, address, password, type) VALUES (?, ?, ?, ?, ?, ?)";
      const values = [uname, email, phone || null, address || null, hashedPassword, userType];

      db.query(query, values, (err, data) => {
        if (err) {
          logger.error("User registration error:", err);
          return res.status(500).json({ error: "Failed to register user" });
        }
        const newUserId = data.insertId;
        logger.info(`New user registered: ${email} (ID: ${newUserId}, Type: ${userType})`);
        
        // If owner, verify FieldOwners entry was created by trigger
        if (userType === 'owner') {
          db.query("SELECT * FROM FieldOwners WHERE user_id = ?", [newUserId], (err, fieldOwners) => {
            if (err) {
              logger.warn("Could not verify FieldOwners entry:", err);
            } else {
              logger.info(`FieldOwners entry for user ${newUserId}:`, fieldOwners);
            }
          });
        }
        
        return res.status(201).json({ 
          message: "User registered successfully",
          user_id: newUserId,
          type: userType,
          email: email
        });
      });
    });
  } catch (error) {
    logger.error("Registration error:", error);
    res.status(500).json({ error: "Server error" });
  }
});

app.post("/login", async (req, res) => {
  try {
    const { email, password } = req.body;

    // Input validation
    if (!email || !password) {
      return res.status(400).json({ error: "Email and password are required" });
    }

    // Check if user exists
    db.query("SELECT * FROM Users WHERE email = ?", [email], async (err, data) => {
      if (err) {
        logger.error("Login query error:", err);
        return res.status(500).json({ error: "Database error" });
      }
      
      if (data.length === 0) {
        logger.warn(`Login attempt with non-existent email: ${email}`);
        return res.status(401).json({ error: "Invalid email or password" });
      }

      const user = data[0];

      // Compare passwords
      const passwordMatch = await bcrypt.compare(password, user.password);
      if (!passwordMatch) {
        logger.warn(`Failed login attempt for user: ${email}`);
        return res.status(401).json({ error: "Invalid email or password" });
      }

      // Return user data (without password)
      logger.info(`User logged in: ${email} (Type: ${user.type})`);
      return res.json({
        message: "Login successful",
        user_id: user.user_id,
        uname: user.uname,
        email: user.email,
        phone: user.phone,
        address: user.address,
        type: user.type
      });
    });
  } catch (error) {
    logger.error("Login error:", error);
    res.status(500).json({ error: "Server error" });
  }
});

// ==================== ADMIN/ROLE MANAGEMENT ====================
// Admin-only endpoint to change user role
app.put("/Users/:id/role", (req, res) => {
  try {
    const { id } = req.params;
    const { type } = req.body;

    if (!['admin', 'customer'].includes(type)) {
      return res.status(400).json({ error: "Invalid user type. Must be 'admin' or 'customer'" });
    }

    const query = "UPDATE Users SET type = ? WHERE user_id = ?";
    db.query(query, [type, id], (err, data) => {
      if (err) {
        logger.error("Role update error:", err);
        return res.status(500).json({ error: "Failed to update user role" });
      }
      if (data.affectedRows === 0) {
        return res.status(404).json({ error: "User not found" });
      }
      logger.info(`User role changed: ID ${id}, New type: ${type}`);
      return res.json({ message: "User role updated successfully" });
    });
  } catch (err) {
    logger.error("Role endpoint error:", err);
    res.status(500).json({ error: "Server error" });
  }
});

// Get user by ID (for admin dashboard)
app.get("/Users/:id", (req, res) => {
  try {
    const { id } = req.params;
    const query = "SELECT user_id, uname, email, phone, address, type FROM Users WHERE user_id = ?";
    db.query(query, [id], (err, data) => {
      if (err) {
        logger.error("User fetch error:", err);
        return res.status(500).json({ error: "Failed to fetch user" });
      }
      if (data.length === 0) {
        return res.status(404).json({ error: "User not found" });
      }
      return res.json(data[0]);
    });
  } catch (err) {
    logger.error("User endpoint error:", err);
    res.status(500).json({ error: "Server error" });
  }
});

// Get all users with pagination (for admin dashboard)
app.get("/Users", (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = 10;
    const offset = (page - 1) * limit;
    
    const query = "SELECT user_id, uname, email, phone, type FROM Users LIMIT ? OFFSET ?";
    db.query(query, [limit, offset], (err, data) => {
      if (err) {
        logger.error("Users list error:", err);
        return res.status(500).json({ error: "Failed to fetch users" });
      }
      return res.json(data);
    });
  } catch (err) {
    logger.error("Users list endpoint error:", err);
    res.status(500).json({ error: "Server error" });
  }
});

// ==================== WALLET / PROFILE ====================
app.get("/Users/:id/wallet", async (req, res) => {
  try {
    const { id } = req.params;
    const [rows] = await dbAsync.query(
      "SELECT balance, preferred_method, card_last4, card_exp_month, card_exp_year, updated_at FROM UserWallets WHERE user_id = ?",
      [id]
    );
    if (rows.length === 0) {
      await dbAsync.query("INSERT INTO UserWallets (user_id, balance) VALUES (?, 0.00)", [id]);
      return res.json({ balance: 0.0 });
    }
    return res.json(rows[0]);
  } catch (err) {
    logger.error("Wallet fetch error:", err);
    res.status(500).json({ error: "Failed to fetch wallet" });
  }
});

app.post("/Users/:id/wallet/deposit", async (req, res) => {
  try {
    const { id } = req.params;
    const { amount, method, card_last4, card_exp_month, card_exp_year } = req.body;

    const value = parseFloat(amount);
    if (!Number.isFinite(value) || value <= 0) {
      return res.status(400).json({ error: "Amount must be greater than 0" });
    }

    if (!allowedPaymentMethods.includes(method)) {
      return res.status(400).json({ error: "Invalid payment method" });
    }

    if (['visa', 'mastercard'].includes(method)) {
      if (!card_last4 || card_last4.length !== 4 || !/^[0-9]{4}$/.test(card_last4)) {
        return res.status(400).json({ error: "Provide last 4 digits for card" });
      }
      if (!card_exp_month || !card_exp_year) {
        return res.status(400).json({ error: "Provide card expiry month and year" });
      }
    }

    await dbAsync.query(
      `INSERT INTO UserWallets (user_id, balance, preferred_method, card_last4, card_exp_month, card_exp_year)
       VALUES (?, 0.00, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE preferred_method = VALUES(preferred_method), card_last4 = VALUES(card_last4), card_exp_month = VALUES(card_exp_month), card_exp_year = VALUES(card_exp_year)`,
      [id, method, card_last4 || null, card_exp_month || null, card_exp_year || null]
    );

    await dbAsync.query("UPDATE UserWallets SET balance = balance + ? WHERE user_id = ?", [value, id]);
    await dbAsync.query("INSERT INTO WalletTransactions (user_id, amount, type, reference) VALUES (?, ?, 'deposit', ?)", [id, value, method]);

    const [wallet] = await dbAsync.query(
      "SELECT balance, preferred_method, card_last4, card_exp_month, card_exp_year FROM UserWallets WHERE user_id = ?",
      [id]
    );

    return res.json({ message: "Balance added", wallet: wallet[0] });
  } catch (err) {
    logger.error("Wallet deposit error:", err);
    res.status(500).json({ error: "Failed to add balance" });
  }
});

// ==================== REFUNDS ENDPOINTS ====================

// Get all refunds (admin) or user's refunds (customer)
app.get("/Refunds", async (req, res) => {
  try {
    const { user_id } = req.query;
    const params = [];
    let query = `
      SELECT r.refund_id, r.booking_id, r.user_id, r.payment_id, r.amount, r.reason, 
             r.status, r.requested_by, r.requested_at, r.processed_at,
             u.uname as user_name, req.uname as requested_by_name
      FROM Refunds r
      LEFT JOIN Users u ON r.user_id = u.user_id
      LEFT JOIN Users req ON r.requested_by = req.user_id
    `;
    if (user_id) {
      query += " WHERE r.user_id = ?";
      params.push(user_id);
    }
    query += " ORDER BY r.requested_at DESC";

    const [rows] = await dbAsync.query(query, params);
    return res.json(rows);
  } catch (err) {
    logger.error("Refunds fetch error:", err);
    return res.status(500).json({ error: "Failed to fetch refunds" });
  }
});

// Create refund request
app.post("/Refunds", async (req, res) => {
  try {
    const { booking_id, user_id, payment_id, amount, reason, requested_by } = req.body;

    if (!booking_id || !user_id || !payment_id || !amount || !reason || !requested_by) {
      return res.status(400).json({ error: "All fields are required" });
    }

    const [result] = await dbAsync.query(
      "INSERT INTO Refunds (booking_id, user_id, payment_id, amount, reason, requested_by, status) VALUES (?, ?, ?, ?, ?, ?, 'pending')",
      [booking_id, user_id, payment_id, amount, reason, requested_by]
    );

    return res.status(201).json({ message: "Refund request created", refund_id: result.insertId });
  } catch (err) {
    logger.error("Refund creation error:", err);
    return res.status(500).json({ error: "Failed to create refund request" });
  }
});

// Process refund (approve/reject/complete)
app.put("/Refunds/:id", async (req, res) => {
  const refundId = req.params.id;
  const { status } = req.body;

  if (!['approved', 'rejected', 'completed'].includes(status)) {
    return res.status(400).json({ error: "Invalid status" });
  }

  const connection = await dbAsync.getConnection();
  try {
    await connection.beginTransaction();

    // Get refund details
    const [refunds] = await connection.query(
      "SELECT * FROM Refunds WHERE refund_id = ?",
      [refundId]
    );

    if (refunds.length === 0) {
      await connection.rollback();
      return res.status(404).json({ error: "Refund not found" });
    }

    const refund = refunds[0];

    // Update refund status
    await connection.query(
      "UPDATE Refunds SET status = ?, processed_at = NOW() WHERE refund_id = ?",
      [status, refundId]
    );

    // If approved or completed, process the refund
    if (status === 'completed') {
      // Refund to wallet
      await connection.query(
        "INSERT IGNORE INTO UserWallets (user_id, balance) VALUES (?, 0.00)",
        [refund.user_id]
      );
      await connection.query(
        "UPDATE UserWallets SET balance = balance + ? WHERE user_id = ?",
        [refund.amount, refund.user_id]
      );

      // Record transaction
      await connection.query(
        "INSERT INTO WalletTransactions (user_id, amount, type, reference) VALUES (?, ?, 'deposit', ?)",
        [refund.user_id, refund.amount, `refund:${refundId}`]
      );

      // Update payment status
      await connection.query(
        "UPDATE Payments SET status = 'refunded' WHERE payment_id = ?",
        [refund.payment_id]
      );
    }

    await connection.commit();
    return res.json({ message: `Refund ${status}` });
  } catch (err) {
    await connection.rollback();
    logger.error("Refund update error:", err);
    return res.status(500).json({ error: "Failed to update refund" });
  } finally {
    connection.release();
  }
});

// Delete refund (admin only)
app.delete("/Refunds/:id", async (req, res) => {
  const refundId = req.params.id;
  try {
    await dbAsync.query("DELETE FROM Refunds WHERE refund_id = ?", [refundId]);
    return res.json({ message: "Refund deleted" });
  } catch (err) {
    logger.error("Refund deletion error:", err);
    return res.status(500).json({ error: "Failed to delete refund" });
  }
});

// ==================== SERVER STARTUP ====================
const PORT = process.env.PORT || 8800;

app.listen(PORT, () => {
  logger.info(`🚀 SportSpot Backend Server running on port ${PORT}`);
  logger.info(`Environment: ${process.env.NODE_ENV || 'development'}`);
  logger.info(`Database: ${process.env.DB_NAME || 'sportspot'}`);
});
