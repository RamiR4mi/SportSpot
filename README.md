# SportSpot - Sports Field Booking Platform
# DATABASE SYSTEMS CLASS Dr.Nasser Assim

A full-stack web application for booking and managing sports facilities with role-based access control.

---

## 📋 Table of Contents
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Database Setup](#database-setup)
- [Backend Setup](#backend-setup)
- [Frontend Setup](#frontend-setup)
- [Running the Application](#running-the-application)
- [User Roles](#user-roles)
- [Features](#features)
- [Team Members](#team-members)

---

## 🛠️ Tech Stack

### **Backend**
- **Node.js** (v14+): JavaScript runtime for building fast, scalable server-side applications.
- **Express.js** (v4.18+): Web framework for Node.js to create APIs and handle HTTP requests easily.
- **MySQL** (v5.7+): Relational database system to store all app data securely.
- **bcrypt**: Library for securely hashing user passwords.
- **cors**: Middleware to allow safe cross-origin requests between frontend and backend.
- **dotenv**: Loads environment variables from a .env file for secure configuration.

### **Frontend**
- React (v18+): JavaScript library for building dynamic, interactive user interfaces.
- React Router DOM (v6+): Handles navigation and routing between pages in the app.
- Axios: Makes HTTP requests from the frontend to the backend API.
- CSS3: Used for styling and making the app look modern and responsive.

### **Database**
- **MySQL 5.7+** with InnoDB engine
- 10 normalized tables (3NF)
- 18 triggers for automation and validation
- 3 views for analytics
- 4 stored procedures for complex operations

---

## ✅ Prerequisites

Before running the project, ensure you have:

- **Node.js** (v14 or higher) - [Download here](https://nodejs.org/)
- **MySQL** (v5.7 or higher) - [Download here](https://dev.mysql.com/downloads/)
- **Git** (optional) - [Download here](https://git-scm.com/)
- **A code editor** (VS Code recommended)

---

## 🗄️ Database Setup

### Step 1: Start MySQL Server
Open MySQL and log in:
```bash
mysql -u root -p
```

### Step 2: Run Database Scripts **IN ORDER**

**IMPORTANT:** Execute the SQL files in this exact sequence:

#### 1. Create Database Schema and Tables
```bash
mysql -u root -p < database/db_lastsportspot.sql
```
This creates:
- Database `sportspot`
- 10 tables with sample data
- CHECK constraints and foreign keys

#### 2. Create Triggers
```bash
mysql -u root -p < database/db_triggers.sql
```
This creates 18 triggers for:
- Booking conflict prevention
- Wallet balance validation
- Maintenance blocking
- Review validation
- Auto field-owner creation
- And more...

#### 3. Create Views and Stored Procedures
```bash
mysql -u root -p < database/db_queries_ctes_views_correlatedqueries_aggregatefcts.sql
```
This creates:
- 3 analytical views
- 4 stored procedures
- CTEs for loyalty tiers
- Advanced queries

### Step 3: Verify Database
```sql
USE sportspot;
SHOW TABLES;
-- Should show: Users, FieldOwners, SportFields, Bookings, Payments, Reviews, etc.

SHOW TRIGGERS;
-- Should show 18 triggers

SHOW PROCEDURE STATUS WHERE Db = 'sportspot';
-- Should show 4 stored procedures
```

---

## ⚙️ Backend Setup

### Step 1: Navigate to Backend Directory
```bash
cd backend
```

### Step 2: Install Dependencies
```bash
npm install
```

This installs:
- express
- mysql2
- cors
- bcrypt
- dotenv
- nodemon (dev dependency)

### Step 3: Configure Environment Variables

go to the `.env` file in the `backend` folder: (I created it for you, to keep your db credentials secured, I'll leave mine as example to follow
, but it's not a good practice for security, but it's okay you're my teammates)

it's like this
```env
DB_HOST=localhost
DB_USER=root
DB_PASSWORD=your_mysql_password
DB_NAME=sportspot
PORT=8800
```

**Replace `your_mysql_password` with your actual MySQL password.**

### Step 4: Start Backend Server

**Development mode (with auto-restart):**
```bash
npm run dev
```

**Production mode:**
```bash
npm start
```

Backend will run on **http://localhost:8800**

---

## 💻 Frontend Setup

### Step 1: Navigate to Client Directory
```bash
cd client
```

### Step 2: Install Dependencies
```bash
npm install
```

This installs:
- react
- react-dom
- react-router-dom
- axios
- vite (build tool)

### Step 3: Start Frontend Server
```bash
npm run dev
```

Frontend will run on **http://localhost:5173**

---

## 🚀 Running the Application

### Quick Start (All-in-One)

1. **Start MySQL** (ensure it's running)

2. **Run database scripts** (if not done already):
   ```bash
   mysql -u root -p < database/db_lastsportspot.sql
   mysql -u root -p < database/db_triggers.sql
   mysql -u root -p < database/db_queries_ctes_views_correlatedqueries_aggregatefcts.sql
   ```

3. **Start Backend** (in one terminal):
   ```bash
   cd backend
   npm install
   npm run dev
   ```

4. **Start Frontend** (in another terminal):
   ```bash
   cd client
   npm install
   npm run dev
   ```

5. **Open Browser**: Navigate to **http://localhost:5173**

## 👨‍💻 Team Members

- **Rami Mazaoui**
- **Yasmine Espachs Bouamoud**
- **Rabab Saadeddine**


This project is developed for academic purposes as part of CSC3326 Database Course.
