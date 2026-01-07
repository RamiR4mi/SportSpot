# SQL Final Exam Cheat Sheet

## 1. DISTINCT & ORDER BY
```sql
-- Get unique departments (removes duplicates)
SELECT DISTINCT department FROM employees;

-- List employees ordered by salary descending (highest salary first)
SELECT name, salary FROM employees ORDER BY salary DESC;
```

## 2. CREATE TABLE: DEFAULT, CHECK, ON UPDATE CASCADE
```sql
-- Create a table with default values, check constraint, and cascading update on foreign key
CREATE TABLE users (
  id INT PRIMARY KEY, -- unique identifier
  username VARCHAR(50) NOT NULL, -- cannot be null
  status VARCHAR(10) DEFAULT 'active', -- default value if not provided
  age INT CHECK (age >= 18), -- only allow age 18 or older
  ref_id INT,
  FOREIGN KEY (ref_id) REFERENCES users(id) ON UPDATE CASCADE -- update ref_id if referenced id changes
);
```

## 3. Aggregation & Grouping
```sql
-- Count all employees in the table
SELECT COUNT(*) FROM employees;

-- Count number of employees in each department
SELECT department, COUNT(*) FROM employees GROUP BY department;

-- Show only departments with more than 5 employees (using HAVING)
SELECT department, COUNT(*) FROM employees GROUP BY department HAVING COUNT(*) > 5;
```

## 4. Subqueries
```sql
-- In SELECT: For each employee, also show the maximum salary in the company (as a column)
SELECT name, (SELECT MAX(salary) FROM employees) AS max_salary FROM employees;

-- In FROM (derived table): Get the average salary from a derived table (subquery in FROM)
SELECT avg_salary FROM (SELECT AVG(salary) AS avg_salary FROM employees) AS sub;

-- In WHERE: Find names of employees who work in departments located in NY (subquery filters department_id)
SELECT name FROM employees WHERE department_id IN (SELECT id FROM departments WHERE location = 'NY');

-- In HAVING: Show departments with more employees than the average department size (uses subquery in HAVING)
SELECT department, COUNT(*) AS cnt FROM employees GROUP BY department HAVING COUNT(*) > (SELECT AVG(cnt) FROM (SELECT COUNT(*) AS cnt FROM employees GROUP BY department) AS sub);
```

## 5. Correlated Queries (IN, EXISTS)
```sql
-- EXISTS: For each employee, check if their department exists in NY (correlated subquery)
SELECT name FROM employees e WHERE EXISTS (SELECT 1 FROM departments d WHERE d.id = e.department_id AND d.location = 'NY');

-- IN: For each employee, check if their department_id is in the list of NY departments
SELECT name FROM employees e WHERE e.department_id IN (SELECT d.id FROM departments d WHERE d.location = 'NY');
```

## 6. Common Table Expressions (CTE)
```sql
-- CTE: Create a temporary result (dept_count) to use in the main query
-- what this query does is : 
WITH dept_count AS (
  SELECT department, COUNT(*) AS cnt FROM employees GROUP BY department
)
SELECT * FROM dept_count WHERE cnt > 5; -- use the CTE to filter departments
```

## 7. Views
```sql
/* */
-- Create a view for employees with salary > 50000
CREATE VIEW high_salary AS SELECT name, salary FROM employees WHERE salary > 50000;
-- Use the view like a table
SELECT * FROM high_salary;
```

## 8. Indexes
```sql
-- Create an index on the salary column to speed up queries
CREATE INDEX idx_salary ON employees(salary);
```

## 9. Stored Procedures
```sql
-- Stored procedure with no parameters: returns total employee count
CREATE PROCEDURE GetEmployeeCount()
BEGIN
  SELECT COUNT(*) FROM employees;
END;

-- Stored procedure with a parameter: returns employees in a given department
CREATE PROCEDURE GetEmployeeByDept(IN dept_id INT)
BEGIN
  SELECT * FROM employees WHERE department_id = dept_id;
END;
```

## 10. Triggers
```sql
-- Before inserting a new employee, set created_at to current time
CREATE TRIGGER before_insert_employee
BEFORE INSERT ON employees
FOR EACH ROW
SET NEW.created_at = NOW();

-- After updating an employee, log the salary change in another table
CREATE TRIGGER update_salary
AFTER UPDATE ON employees
FOR EACH ROW
INSERT INTO salary_changes(emp_id, old_salary, new_salary) VALUES (NEW.id, OLD.salary, NEW.salary);
```

## 11. ACID & Transactions
-- **Atomicity**: All or nothing (transaction is fully completed or not at all)
-- **Consistency**: Only valid data is written to the database
-- **Isolation**: Transactions do not affect each other
-- **Durability**: Once committed, changes are permanent

```sql
-- Start a transaction
START TRANSACTION;
-- Example 1: Transfer money between two accounts
UPDATE accounts SET balance = balance - 100 WHERE id = 1; -- deduct from sender
UPDATE accounts SET balance = balance + 100 WHERE id = 2; -- add to receiver
COMMIT; -- both updates succeed together, or none if error

-- Example 2: Insert and rollback
START TRANSACTION;
INSERT INTO employees (name, department) VALUES ('Alice', 'HR');
ROLLBACK; -- the insert is undone, no new row is added

-- Example 3: Delete with error handling
START TRANSACTION;
DELETE FROM employees WHERE id = 10;
-- Suppose an error occurs here
ROLLBACK; -- undo the delete

-- Example 4: Multiple statements
START TRANSACTION;
UPDATE products SET stock = stock - 1 WHERE id = 5;
INSERT INTO sales (product_id, sold_at) VALUES (5, NOW());
COMMIT; -- both succeed or both are undone
```

## 12. Project Tools Example

-- Backend: Node.js, Express (server-side logic)
-- Frontend: React.js (user interface)
-- Database: MySQL/SQL (data storage)
-- Version Control: Git (code management)
-- Others: Postman (API testing), VS Code (code editor)

## 13. Normalization
-- **1NF**: Atomic values, unique rows (no repeating groups)
-- **2NF**: 1NF + no partial dependency (all non-key attributes depend on the whole primary key)
-- **3NF**: 2NF + no transitive dependency (non-key attributes depend only on the primary key, not on other non-key attributes)
-- **BCNF**: Every determinant is a candidate key (stronger version of 3NF)
-- **4NF**: No multi-valued dependencies (no table contains two or more independent multi-valued facts about an entity)
