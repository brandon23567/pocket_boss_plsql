-- ============================================================================
-- PROJECT: PocketBoss - Personal Finance & Expense Management System
-- PLATFORM: Oracle PL/SQL (Oracle XE / 19c / 21c)
-- DESCRIPTION:
--   A complete enterprise-grade personal finance management system written
--   in PL/SQL. Provides full capabilities for multi-account management,
--   category budgeting, itemized purchase tracking, peer-to-peer fund
--   transfers, savings simulation, and rich ASCII financial statements.
--
-- PL/SQL FEATURES SHOWCASED:
--   1. Schema Design: Normalized tables, foreign keys, sequences, checks
--   2. Database Triggers: Automatic audit logging and integrity enforcement
--   3. PL/SQL Packages: Clean API separation with Specification and Body
--   4. Stored Procedures & Functions: Parameterized business operations
--   5. Conditionals: Nested IF-ELSIF-ELSE, CASE expressions and statements
--   6. Loops: Cursor FOR loop, Explicit LOOP with FETCH, WHILE loop, Numeric FOR
--   7. Cursors: Parameterized cursors, explicit cursors, cursor attributes (%NOTFOUND, %ROWCOUNT)
--   8. Exception Handling: User-defined exceptions, PRAGMA EXCEPTION_INIT,
--      system exceptions (NO_DATA_FOUND, DUP_VAL_ON_INDEX, ZERO_DIVIDE, OTHERS),
--      transaction control (COMMIT, SAVEPOINT, ROLLBACK)
--   9. Formatted ASCII Reporting: Beautiful terminal tables, visual progress bars,
--      aligned columns, and currency formatting suitable for project reports.
-- ============================================================================

SET DEFINE OFF;
SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 160;
SET PAGESIZE 1000;
SET FEEDBACK OFF;

PROMPT ============================================================================
PROMPT Initializing PocketBoss Database Schema...
PROMPT ============================================================================

-- ----------------------------------------------------------------------------
-- STEP 1: SAFE CLEANUP OF EXISTING OBJECTS
-- ----------------------------------------------------------------------------
BEGIN
  FOR t IN (SELECT table_name FROM user_tables WHERE table_name IN 
            ('AUDIT_LOG', 'TRANSACTIONS', 'PURCHASES', 'BUDGETS', 'ACCOUNTS', 'CATEGORIES')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS';
  END LOOP;

  FOR s IN (SELECT sequence_name FROM user_sequences WHERE sequence_name IN 
            ('ACC_SEQ', 'CAT_SEQ', 'BUDGET_SEQ', 'PURCHASE_SEQ', 'TXN_SEQ', 'AUDIT_SEQ')) LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE ' || s.sequence_name;
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
/

-- ----------------------------------------------------------------------------
-- STEP 2: TABLE DEFINITIONS & SEQUENCES
-- ----------------------------------------------------------------------------

-- Sequences
CREATE SEQUENCE ACC_SEQ START WITH 1001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE CAT_SEQ START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE BUDGET_SEQ START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE PURCHASE_SEQ START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE TXN_SEQ START WITH 5001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE AUDIT_SEQ START WITH 1 INCREMENT BY 1 NOCACHE;

-- 1. Accounts Table
CREATE TABLE accounts (
  account_id       NUMBER PRIMARY KEY,
  account_no       VARCHAR2(20) NOT NULL UNIQUE,
  account_name     VARCHAR2(100) NOT NULL,
  account_type     VARCHAR2(30) DEFAULT 'Checking' CHECK (account_type IN ('Checking', 'Savings', 'Wallet', 'Investment')),
  balance          NUMBER(12,2) DEFAULT 0.00 NOT NULL CHECK (balance >= 0),
  total_spent      NUMBER(12,2) DEFAULT 0.00 NOT NULL,
  total_deposited  NUMBER(12,2) DEFAULT 0.00 NOT NULL,
  status           VARCHAR2(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'FROZEN', 'CLOSED')),
  created_at       DATE DEFAULT SYSDATE NOT NULL
);

-- 2. Expense & Income Categories Table
CREATE TABLE categories (
  category_id      NUMBER PRIMARY KEY,
  category_name    VARCHAR2(50) NOT NULL UNIQUE,
  category_type    VARCHAR2(20) DEFAULT 'EXPENSE' CHECK (category_type IN ('EXPENSE', 'INCOME', 'TRANSFER')),
  description      VARCHAR2(200)
);

-- 3. Monthly Budgets Table
CREATE TABLE budgets (
  budget_id            NUMBER PRIMARY KEY,
  account_id           NUMBER NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
  category_id          NUMBER NOT NULL REFERENCES categories(category_id) ON DELETE CASCADE,
  period_month         VARCHAR2(7) NOT NULL, -- Format: YYYY-MM
  budget_limit         NUMBER(12,2) NOT NULL CHECK (budget_limit > 0),
  alert_threshold_pct  NUMBER(3) DEFAULT 80 CHECK (alert_threshold_pct BETWEEN 1 AND 100),
  CONSTRAINT uk_acc_cat_period UNIQUE (account_id, category_id, period_month)
);

-- 4. Itemized Purchases Table
CREATE TABLE purchases (
  purchase_id      NUMBER PRIMARY KEY,
  account_id       NUMBER NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
  category_id      NUMBER NOT NULL REFERENCES categories(category_id),
  item_name        VARCHAR2(100) NOT NULL,
  quantity         NUMBER(6) DEFAULT 1 CHECK (quantity > 0),
  unit_price       NUMBER(12,2) NOT NULL CHECK (unit_price >= 0),
  total_price      NUMBER(12,2) NOT NULL,
  merchant         VARCHAR2(100) DEFAULT 'General Store',
  purchase_date    DATE DEFAULT SYSDATE NOT NULL,
  notes            VARCHAR2(250)
);

-- 5. General Ledger Transactions Table
CREATE TABLE transactions (
  txn_id             NUMBER PRIMARY KEY,
  account_id         NUMBER NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
  txn_type           VARCHAR2(30) NOT NULL CHECK (txn_type IN ('DEPOSIT', 'PURCHASE', 'TRANSFER_OUT', 'TRANSFER_IN', 'INTEREST')),
  amount             NUMBER(12,2) NOT NULL CHECK (amount > 0),
  running_balance    NUMBER(12,2) NOT NULL,
  description        VARCHAR2(250),
  related_account_no VARCHAR2(20),
  purchase_id        NUMBER REFERENCES purchases(purchase_id) ON DELETE SET NULL,
  txn_date           DATE DEFAULT SYSDATE NOT NULL
);

-- 6. Audit & Event Log Table
CREATE TABLE audit_log (
  log_id           NUMBER PRIMARY KEY,
  account_no       VARCHAR2(20),
  action_type      VARCHAR2(50) NOT NULL,
  details          VARCHAR2(400),
  performed_at     TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
);

-- ----------------------------------------------------------------------------
-- STEP 3: DATABASE TRIGGERS
-- ----------------------------------------------------------------------------

-- Trigger 1: Automatic transaction audit logger (Safe if non-SYS user)
BEGIN
  IF USER <> 'SYS' THEN
    EXECUTE IMMEDIATE '
    CREATE OR REPLACE TRIGGER trg_transactions_audit
    AFTER INSERT ON transactions
    FOR EACH ROW
    DECLARE
      v_acc_no accounts.account_no%TYPE;
    BEGIN
      SELECT account_no INTO v_acc_no FROM accounts WHERE account_id = :NEW.account_id;
      INSERT INTO audit_log (log_id, account_no, action_type, details, performed_at)
      VALUES (
        AUDIT_SEQ.NEXTVAL,
        v_acc_no,
        :NEW.txn_type,
        ''Txn #'' || :NEW.txn_id || '': '' || :NEW.description || '' | Amount: $'' || TO_CHAR(:NEW.amount, ''FM999,990.00'') || '' | Post-Bal: $'' || TO_CHAR(:NEW.running_balance, ''FM999,990.00''),
        SYSTIMESTAMP
      );
    EXCEPTION
      WHEN OTHERS THEN
        NULL;
    END;';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
/

-- Trigger 2: Prevent negative account balance at database engine level
BEGIN
  IF USER <> 'SYS' THEN
    EXECUTE IMMEDIATE '
    CREATE OR REPLACE TRIGGER trg_prevent_negative_balance
    BEFORE UPDATE OF balance ON accounts
    FOR EACH ROW
    BEGIN
      IF :NEW.balance < 0 THEN
        RAISE_APPLICATION_ERROR(-20010, ''CRITICAL ERROR: Account balance cannot be negative. Update rejected.'');
      END IF;
    END;';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
/

-- ----------------------------------------------------------------------------
-- STEP 4: SEED CORE CATEGORIES
-- ----------------------------------------------------------------------------
INSERT INTO categories (category_id, category_name, category_type, description) VALUES (CAT_SEQ.NEXTVAL, 'Groceries', 'EXPENSE', 'Daily supermarket, food ingredients, snacks');
INSERT INTO categories (category_id, category_name, category_type, description) VALUES (CAT_SEQ.NEXTVAL, 'Dining & Cafes', 'EXPENSE', 'Restaurants, coffee shops, takeout');
INSERT INTO categories (category_id, category_name, category_type, description) VALUES (CAT_SEQ.NEXTVAL, 'Tech & Electronics', 'EXPENSE', 'Hardware, accessories, gadgets, software');
INSERT INTO categories (category_id, category_name, category_type, description) VALUES (CAT_SEQ.NEXTVAL, 'Utilities & Bills', 'EXPENSE', 'Electricity, water, internet, cell phone');
INSERT INTO categories (category_id, category_name, category_type, description) VALUES (CAT_SEQ.NEXTVAL, 'Transportation', 'EXPENSE', 'Fuel, public transit, cab fares, vehicle repairs');
INSERT INTO categories (category_id, category_name, category_type, description) VALUES (CAT_SEQ.NEXTVAL, 'Entertainment', 'EXPENSE', 'Movies, concerts, streaming services, games');
INSERT INTO categories (category_id, category_name, category_type, description) VALUES (CAT_SEQ.NEXTVAL, 'Salary & Income', 'INCOME', 'Primary income, freelance, bonuses');
INSERT INTO categories (category_id, category_name, category_type, description) VALUES (CAT_SEQ.NEXTVAL, 'Miscellaneous', 'EXPENSE', 'Other unclassified expenses');
COMMIT;

-- ============================================================================
-- STEP 5: POCKETBOSS PACKAGE SPECIFICATION
-- ============================================================================
CREATE OR REPLACE PACKAGE pkg_pocketboss AS

  -- Custom User-Defined Exceptions
  e_insufficient_funds    EXCEPTION;
  e_invalid_amount        EXCEPTION;
  e_account_not_found     EXCEPTION;
  e_same_account_transfer EXCEPTION;
  e_account_inactive      EXCEPTION;
  e_category_not_found    EXCEPTION;

  PRAGMA EXCEPTION_INIT(e_insufficient_funds, -20001);
  PRAGMA EXCEPTION_INIT(e_invalid_amount,     -20002);
  PRAGMA EXCEPTION_INIT(e_account_not_found,  -20003);
  PRAGMA EXCEPTION_INIT(e_same_account_transfer, -20004);
  PRAGMA EXCEPTION_INIT(e_account_inactive,   -20005);
  PRAGMA EXCEPTION_INIT(e_category_not_found, -20006);

  -- Account Management Procedures
  PROCEDURE create_account(
    p_account_name    IN  VARCHAR2,
    p_initial_deposit IN  NUMBER,
    p_account_type    IN  VARCHAR2 DEFAULT 'Checking',
    o_account_no      OUT VARCHAR2
  );

  PROCEDURE deposit_funds(
    p_account_no      IN  VARCHAR2,
    p_amount          IN  NUMBER,
    p_description     IN  VARCHAR2 DEFAULT 'Cash/Bank Deposit'
  );

  PROCEDURE transfer_funds(
    p_from_acc_no     IN  VARCHAR2,
    p_to_acc_no       IN  VARCHAR2,
    p_amount          IN  NUMBER,
    p_description     IN  VARCHAR2 DEFAULT 'Peer-to-Peer Transfer'
  );

  -- Budgeting & Expense Procedures
  PROCEDURE set_budget(
    p_account_no      IN  VARCHAR2,
    p_category_name   IN  VARCHAR2,
    p_period_month    IN  VARCHAR2, -- Format: 'YYYY-MM'
    p_budget_limit    IN  NUMBER,
    p_threshold_pct   IN  NUMBER DEFAULT 80
  );

  PROCEDURE record_purchase(
    p_account_no      IN  VARCHAR2,
    p_item_name       IN  VARCHAR2,
    p_category_name   IN  VARCHAR2,
    p_quantity        IN  NUMBER,
    p_unit_price      IN  NUMBER,
    p_merchant        IN  VARCHAR2 DEFAULT 'Merchant',
    p_notes           IN  VARCHAR2 DEFAULT NULL
  );

  -- Reporting & Presentation Procedures (Formatted ASCII Tables)
  PROCEDURE show_account_summary(
    p_account_no      IN  VARCHAR2
  );

  PROCEDURE show_budget_report(
    p_account_no      IN  VARCHAR2,
    p_period_month    IN  VARCHAR2
  );

  PROCEDURE show_purchases_report(
    p_account_no      IN  VARCHAR2,
    p_period_month    IN  VARCHAR2 DEFAULT NULL
  );

  PROCEDURE show_account_statement(
    p_account_no      IN  VARCHAR2
  );

  -- Advanced Simulation & Batch Processing
  PROCEDURE simulate_savings_growth(
    p_account_no          IN  VARCHAR2,
    p_months              IN  NUMBER,
    p_monthly_deposit     IN  NUMBER,
    p_annual_rate_pct     IN  NUMBER
  );

  PROCEDURE batch_apply_interest(
    p_annual_rate_pct IN  NUMBER
  );

  -- Utility Functions
  FUNCTION fn_get_balance(p_account_no IN VARCHAR2) RETURN NUMBER;
  FUNCTION fn_get_category_spent(p_account_no IN VARCHAR2, p_category_id IN NUMBER, p_period_month IN VARCHAR2) RETURN NUMBER;
  FUNCTION fn_format_currency(p_amount IN NUMBER) RETURN VARCHAR2;
  FUNCTION fn_progress_bar(p_current IN NUMBER, p_total IN NUMBER, p_bar_length IN NUMBER DEFAULT 15) RETURN VARCHAR2;
  FUNCTION fn_get_health_badge(p_balance IN NUMBER, p_total_spent IN NUMBER) RETURN VARCHAR2;

END pkg_pocketboss;
/

-- ============================================================================
-- STEP 6: POCKETBOSS PACKAGE BODY IMPLEMENTATION
-- ============================================================================
CREATE OR REPLACE PACKAGE BODY pkg_pocketboss AS

  -- --------------------------------------------------------------------------
  -- UTILITY FUNCTIONS
  -- --------------------------------------------------------------------------

  FUNCTION fn_format_currency(p_amount IN NUMBER) RETURN VARCHAR2 IS
  BEGIN
    IF p_amount IS NULL THEN
      RETURN '$0.00';
    END IF;
    RETURN '$' || TO_CHAR(p_amount, 'FM999,999,990.00');
  END fn_format_currency;

  FUNCTION fn_progress_bar(p_current IN NUMBER, p_total IN NUMBER, p_bar_length IN NUMBER DEFAULT 15) RETURN VARCHAR2 IS
    v_ratio       NUMBER;
    v_fill_count  NUMBER;
    v_empty_count NUMBER;
    v_bar         VARCHAR2(60) := '[';
    v_pct         NUMBER;
  BEGIN
    IF p_total <= 0 THEN
      v_ratio := 0;
      v_pct := 0;
    ELSE
      v_ratio := p_current / p_total;
      v_pct := ROUND(v_ratio * 100);
    END IF;

    IF v_ratio > 1 THEN
      v_fill_count := p_bar_length;
      v_empty_count := 0;
    ELSE
      v_fill_count := ROUND(v_ratio * p_bar_length);
      v_empty_count := p_bar_length - v_fill_count;
    END IF;

    -- Numeric FOR loops to generate bar fills
    FOR i IN 1..v_fill_count LOOP
      v_bar := v_bar || '=';
    END LOOP;
    FOR i IN 1..v_empty_count LOOP
      v_bar := v_bar || ' ';
    END LOOP;

    v_bar := v_bar || '] ' || LPAD(TO_CHAR(v_pct), 3) || '%';
    RETURN v_bar;
  END fn_progress_bar;

  FUNCTION fn_get_health_badge(p_balance IN NUMBER, p_total_spent IN NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE
      WHEN p_balance >= 50000 THEN 'PLATINUM (Excellent)'
      WHEN p_balance >= 20000 THEN 'GOLD (Strong)'
      WHEN p_balance >= 5000  THEN 'SILVER (Moderate)'
      WHEN p_balance > 0      THEN 'BRONZE (Watch Out)'
      ELSE                         'CRITICAL (Overdrawn/Empty)'
    END;
  END fn_get_health_badge;

  FUNCTION fn_get_balance(p_account_no IN VARCHAR2) RETURN NUMBER IS
    v_bal accounts.balance%TYPE;
  BEGIN
    SELECT balance INTO v_bal FROM accounts WHERE account_no = p_account_no;
    RETURN v_bal;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN NULL;
  END fn_get_balance;

  FUNCTION fn_get_category_spent(
    p_account_no   IN VARCHAR2,
    p_category_id  IN NUMBER,
    p_period_month IN VARCHAR2
  ) RETURN NUMBER IS
    v_spent NUMBER := 0;
  BEGIN
    SELECT NVL(SUM(p.total_price), 0)
    INTO v_spent
    FROM purchases p
    JOIN accounts a ON p.account_id = a.account_id
    WHERE a.account_no = p_account_no
      AND p.category_id = p_category_id
      AND TO_CHAR(p.purchase_date, 'YYYY-MM') = p_period_month;
    RETURN v_spent;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN 0;
  END fn_get_category_spent;

  -- --------------------------------------------------------------------------
  -- PROCEDURE: create_account
  -- --------------------------------------------------------------------------
  PROCEDURE create_account(
    p_account_name    IN  VARCHAR2,
    p_initial_deposit IN  NUMBER,
    p_account_type    IN  VARCHAR2 DEFAULT 'Checking',
    o_account_no      OUT VARCHAR2
  ) IS
    v_acc_id  NUMBER;
    v_acc_no  VARCHAR2(20);
  BEGIN
    IF p_account_name IS NULL OR LENGTH(TRIM(p_account_name)) = 0 THEN
      RAISE_APPLICATION_ERROR(-20007, 'Account holder name is required.');
    END IF;

    IF p_initial_deposit < 0 THEN
      RAISE e_invalid_amount;
    END IF;

    v_acc_id := ACC_SEQ.NEXTVAL;
    v_acc_no := 'PB-' || TO_CHAR(v_acc_id);
    o_account_no := v_acc_no;

    INSERT INTO accounts (account_id, account_no, account_name, account_type, balance, total_spent, total_deposited, status, created_at)
    VALUES (v_acc_id, v_acc_no, TRIM(p_account_name), p_account_type, p_initial_deposit, 0, p_initial_deposit, 'ACTIVE', SYSDATE);

    IF p_initial_deposit > 0 THEN
      INSERT INTO transactions (txn_id, account_id, txn_type, amount, running_balance, description, related_account_no, purchase_id, txn_date)
      VALUES (TXN_SEQ.NEXTVAL, v_acc_id, 'DEPOSIT', p_initial_deposit, p_initial_deposit, 'Initial Account Opening Deposit', NULL, NULL, SYSDATE);
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('>>> Account successfully opened: ' || v_acc_no || ' (' || p_account_name || ') with initial balance ' || fn_format_currency(p_initial_deposit));

  EXCEPTION
    WHEN e_invalid_amount THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[ERROR] Initial deposit cannot be negative.');
      RAISE_APPLICATION_ERROR(-20002, 'Initial deposit cannot be negative.');
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[ERROR] Failed to create account: ' || SQLERRM);
      RAISE;
  END create_account;

  -- --------------------------------------------------------------------------
  -- PROCEDURE: deposit_funds
  -- --------------------------------------------------------------------------
  PROCEDURE deposit_funds(
    p_account_no      IN  VARCHAR2,
    p_amount          IN  NUMBER,
    p_description     IN  VARCHAR2 DEFAULT 'Cash/Bank Deposit'
  ) IS
    v_acc_id   accounts.account_id%TYPE;
    v_bal      accounts.balance%TYPE;
    v_status   accounts.status%TYPE;
    v_new_bal  NUMBER;
  BEGIN
    IF p_amount <= 0 THEN
      RAISE e_invalid_amount;
    END IF;

    BEGIN
      SELECT account_id, balance, status
      INTO v_acc_id, v_bal, v_status
      FROM accounts
      WHERE account_no = p_account_no
      FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE e_account_not_found;
    END;

    IF v_status <> 'ACTIVE' THEN
      RAISE e_account_inactive;
    END IF;

    v_new_bal := v_bal + p_amount;

    UPDATE accounts
    SET balance = v_new_bal,
        total_deposited = total_deposited + p_amount
    WHERE account_id = v_acc_id;

    INSERT INTO transactions (txn_id, account_id, txn_type, amount, running_balance, description, related_account_no, purchase_id, txn_date)
    VALUES (TXN_SEQ.NEXTVAL, v_acc_id, 'DEPOSIT', p_amount, v_new_bal, p_description, NULL, NULL, SYSDATE);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('>>> Deposit of ' || fn_format_currency(p_amount) || ' to [' || p_account_no || '] successful. New Balance: ' || fn_format_currency(v_new_bal));

  EXCEPTION
    WHEN e_invalid_amount THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[ERROR] Deposit amount must be greater than zero.');
    WHEN e_account_not_found THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[ERROR] Account [' || p_account_no || '] not found.');
    WHEN e_account_inactive THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[ERROR] Account [' || p_account_no || '] is inactive/frozen. Deposit rejected.');
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[ERROR] Deposit failed: ' || SQLERRM);
  END deposit_funds;

  -- --------------------------------------------------------------------------
  -- PROCEDURE: transfer_funds
  -- --------------------------------------------------------------------------
  PROCEDURE transfer_funds(
    p_from_acc_no     IN  VARCHAR2,
    p_to_acc_no       IN  VARCHAR2,
    p_amount          IN  NUMBER,
    p_description     IN  VARCHAR2 DEFAULT 'Peer-to-Peer Transfer'
  ) IS
    v_from_id       accounts.account_id%TYPE;
    v_from_bal      accounts.balance%TYPE;
    v_from_status   accounts.status%TYPE;
    v_to_id         accounts.account_id%TYPE;
    v_to_bal        accounts.balance%TYPE;
    v_to_status     accounts.status%TYPE;
    v_from_new_bal  NUMBER;
    v_to_new_bal    NUMBER;
  BEGIN
    IF p_from_acc_no = p_to_acc_no THEN
      RAISE e_same_account_transfer;
    END IF;

    IF p_amount <= 0 THEN
      RAISE e_invalid_amount;
    END IF;

    BEGIN
      SELECT account_id, balance, status
      INTO v_from_id, v_from_bal, v_from_status
      FROM accounts
      WHERE account_no = p_from_acc_no
      FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] Sender account [' || p_from_acc_no || '] does not exist.');
        RAISE e_account_not_found;
    END;

    IF v_from_status <> 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('[ERROR] Sender account [' || p_from_acc_no || '] is not active.');
      RAISE e_account_inactive;
    END IF;

    IF v_from_bal < p_amount THEN
      RAISE e_insufficient_funds;
    END IF;

    BEGIN
      SELECT account_id, balance, status
      INTO v_to_id, v_to_bal, v_to_status
      FROM accounts
      WHERE account_no = p_to_acc_no
      FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] Recipient account [' || p_to_acc_no || '] does not exist.');
        RAISE e_account_not_found;
    END;

    IF v_to_status <> 'ACTIVE' THEN
      DBMS_OUTPUT.PUT_LINE('[ERROR] Recipient account [' || p_to_acc_no || '] is not active.');
      RAISE e_account_inactive;
    END IF;

    v_from_new_bal := v_from_bal - p_amount;
    UPDATE accounts SET balance = v_from_new_bal WHERE account_id = v_from_id;

    v_to_new_bal := v_to_bal + p_amount;
    UPDATE accounts SET balance = v_to_new_bal WHERE account_id = v_to_id;

    INSERT INTO transactions (txn_id, account_id, txn_type, amount, running_balance, description, related_account_no, purchase_id, txn_date)
    VALUES (TXN_SEQ.NEXTVAL, v_from_id, 'TRANSFER_OUT', p_amount, v_from_new_bal, p_description || ' (To ' || p_to_acc_no || ')', p_to_acc_no, NULL, SYSDATE);

    INSERT INTO transactions (txn_id, account_id, txn_type, amount, running_balance, description, related_account_no, purchase_id, txn_date)
    VALUES (TXN_SEQ.NEXTVAL, v_to_id, 'TRANSFER_IN', p_amount, v_to_new_bal, p_description || ' (From ' || p_from_acc_no || ')', p_from_acc_no, NULL, SYSDATE);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('>>> Transfer SUCCESSFUL: ' || fn_format_currency(p_amount) || ' transferred from [' || p_from_acc_no || '] to [' || p_to_acc_no || '].');
    DBMS_OUTPUT.PUT_LINE('    Sender New Balance: ' || fn_format_currency(v_from_new_bal) || ' | Recipient New Balance: ' || fn_format_currency(v_to_new_bal));

  EXCEPTION
    WHEN e_same_account_transfer THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[TRANSFER FAILED] Sender and recipient accounts cannot be the same (' || p_from_acc_no || ').');
    WHEN e_invalid_amount THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[TRANSFER FAILED] Transfer amount must be positive.');
    WHEN e_insufficient_funds THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[TRANSFER FAILED] Insufficient funds in [' || p_from_acc_no || ']. Current Balance: ' || fn_format_currency(v_from_bal) || ', Requested: ' || fn_format_currency(p_amount));
    WHEN e_account_not_found THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[TRANSFER FAILED] Transaction aborted: Account verification failed.');
    WHEN e_account_inactive THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[TRANSFER FAILED] Transaction aborted: One or both accounts are not active.');
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[TRANSFER FAILED] System Error (' || SQLCODE || '): ' || SQLERRM);
  END transfer_funds;

  -- --------------------------------------------------------------------------
  -- PROCEDURE: set_budget
  -- --------------------------------------------------------------------------
  PROCEDURE set_budget(
    p_account_no      IN  VARCHAR2,
    p_category_name   IN  VARCHAR2,
    p_period_month    IN  VARCHAR2,
    p_budget_limit    IN  NUMBER,
    p_threshold_pct   IN  NUMBER DEFAULT 80
  ) IS
    v_acc_id  accounts.account_id%TYPE;
    v_cat_id  categories.category_id%TYPE;
    v_count   NUMBER;
  BEGIN
    IF p_budget_limit <= 0 THEN
      RAISE e_invalid_amount;
    END IF;

    BEGIN
      SELECT account_id INTO v_acc_id FROM accounts WHERE account_no = p_account_no;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE e_account_not_found;
    END;

    BEGIN
      SELECT category_id INTO v_cat_id FROM categories WHERE UPPER(category_name) = UPPER(TRIM(p_category_name));
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE e_category_not_found;
    END;

    SELECT COUNT(*) INTO v_count
    FROM budgets
    WHERE account_id = v_acc_id AND category_id = v_cat_id AND period_month = p_period_month;

    IF v_count > 0 THEN
      UPDATE budgets
      SET budget_limit = p_budget_limit,
          alert_threshold_pct = p_threshold_pct
      WHERE account_id = v_acc_id AND category_id = v_cat_id AND period_month = p_period_month;
      DBMS_OUTPUT.PUT_LINE('>>> Budget updated for [' || p_account_no || '], Category: ' || p_category_name || ', Month: ' || p_period_month || ' -> Limit: ' || fn_format_currency(p_budget_limit));
    ELSE
      INSERT INTO budgets (budget_id, account_id, category_id, period_month, budget_limit, alert_threshold_pct)
      VALUES (BUDGET_SEQ.NEXTVAL, v_acc_id, v_cat_id, p_period_month, p_budget_limit, p_threshold_pct);
      DBMS_OUTPUT.PUT_LINE('>>> New budget created for [' || p_account_no || '], Category: ' || p_category_name || ', Month: ' || p_period_month || ' -> Limit: ' || fn_format_currency(p_budget_limit));
    END IF;

    COMMIT;

  EXCEPTION
    WHEN e_invalid_amount THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[ERROR] Budget limit must be positive.');
    WHEN e_account_not_found THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[ERROR] Account [' || p_account_no || '] not found.');
    WHEN e_category_not_found THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[ERROR] Category "' || p_category_name || '" does not exist.');
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[ERROR] Could not set budget: ' || SQLERRM);
  END set_budget;

  -- --------------------------------------------------------------------------
  -- PROCEDURE: record_purchase
  -- --------------------------------------------------------------------------
  PROCEDURE record_purchase(
    p_account_no      IN  VARCHAR2,
    p_item_name       IN  VARCHAR2,
    p_category_name   IN  VARCHAR2,
    p_quantity        IN  NUMBER,
    p_unit_price      IN  NUMBER,
    p_merchant        IN  VARCHAR2 DEFAULT 'Merchant',
    p_notes           IN  VARCHAR2 DEFAULT NULL
  ) IS
    v_acc_id          accounts.account_id%TYPE;
    v_bal             accounts.balance%TYPE;
    v_status          accounts.status%TYPE;
    v_cat_id          categories.category_id%TYPE;
    v_total_cost      NUMBER;
    v_new_bal         NUMBER;
    v_purchase_id     NUMBER;
    v_month           VARCHAR2(7);

    v_has_budget      NUMBER := 0;
    v_budget_limit    NUMBER;
    v_threshold_pct   NUMBER;
    v_already_spent   NUMBER;
    v_new_spent       NUMBER;
    v_limit_pct       NUMBER;
  BEGIN
    IF p_quantity <= 0 OR p_unit_price < 0 THEN
      RAISE e_invalid_amount;
    END IF;

    v_total_cost := p_quantity * p_unit_price;
    v_month := TO_CHAR(SYSDATE, 'YYYY-MM');

    BEGIN
      SELECT account_id, balance, status
      INTO v_acc_id, v_bal, v_status
      FROM accounts
      WHERE account_no = p_account_no
      FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE e_account_not_found;
    END;

    IF v_status <> 'ACTIVE' THEN
      RAISE e_account_inactive;
    END IF;

    IF v_bal < v_total_cost THEN
      RAISE e_insufficient_funds;
    END IF;

    BEGIN
      SELECT category_id INTO v_cat_id
      FROM categories
      WHERE UPPER(category_name) = UPPER(TRIM(p_category_name));
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE e_category_not_found;
    END;

    v_new_bal := v_bal - v_total_cost;
    v_purchase_id := PURCHASE_SEQ.NEXTVAL;

    INSERT INTO purchases (purchase_id, account_id, category_id, item_name, quantity, unit_price, total_price, merchant, purchase_date, notes)
    VALUES (v_purchase_id, v_acc_id, v_cat_id, p_item_name, p_quantity, p_unit_price, v_total_cost, p_merchant, SYSDATE, p_notes);

    UPDATE accounts
    SET balance = v_new_bal,
        total_spent = total_spent + v_total_cost
    WHERE account_id = v_acc_id;

    INSERT INTO transactions (txn_id, account_id, txn_type, amount, running_balance, description, related_account_no, purchase_id, txn_date)
    VALUES (TXN_SEQ.NEXTVAL, v_acc_id, 'PURCHASE', v_total_cost, v_new_bal, 'Purchased ' || p_item_name || ' (' || p_category_name || ') from ' || p_merchant, NULL, v_purchase_id, SYSDATE);

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('>>> PURCHASE RECORDED: [' || p_item_name || '] x' || p_quantity || ' @ ' || fn_format_currency(p_unit_price) || ' = ' || fn_format_currency(v_total_cost));
    DBMS_OUTPUT.PUT_LINE('    Merchant: ' || p_merchant || ' | Account: ' || p_account_no || ' | Remaining Bal: ' || fn_format_currency(v_new_bal));

    SELECT COUNT(*) INTO v_has_budget
    FROM budgets
    WHERE account_id = v_acc_id AND category_id = v_cat_id AND period_month = v_month;

    IF v_has_budget > 0 THEN
      SELECT budget_limit, alert_threshold_pct
      INTO v_budget_limit, v_threshold_pct
      FROM budgets
      WHERE account_id = v_acc_id AND category_id = v_cat_id AND period_month = v_month;

      v_new_spent := fn_get_category_spent(p_account_no, v_cat_id, v_month);
      v_limit_pct := ROUND((v_new_spent / v_budget_limit) * 100);

      IF v_new_spent > v_budget_limit THEN
        DBMS_OUTPUT.PUT_LINE('    [BUDGET ALERT - EXCEEDED!] Category "' || p_category_name || '" spending is ' || fn_format_currency(v_new_spent) || ' / ' || fn_format_currency(v_budget_limit) || ' (' || v_limit_pct || '%). Over budget by ' || fn_format_currency(v_new_spent - v_budget_limit) || '!');
      ELSIF v_limit_pct >= v_threshold_pct THEN
        DBMS_OUTPUT.PUT_LINE('    [BUDGET WARNING - THRESHOLD REACHED!] Category "' || p_category_name || '" is at ' || v_limit_pct || '% of monthly budget limit (' || fn_format_currency(v_new_spent) || ' / ' || fn_format_currency(v_budget_limit) || ').');
      ELSE
        DBMS_OUTPUT.PUT_LINE('    [Budget Status: OK] ' || fn_format_currency(v_new_spent) || ' spent of ' || fn_format_currency(v_budget_limit) || ' (' || v_limit_pct || '%).');
      END IF;
    END IF;

  EXCEPTION
    WHEN e_invalid_amount THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[PURCHASE REJECTED] Quantity must be >= 1 and Unit Price >= 0.');
    WHEN e_account_not_found THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[PURCHASE REJECTED] Account [' || p_account_no || '] not found.');
    WHEN e_account_inactive THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[PURCHASE REJECTED] Account [' || p_account_no || '] is inactive/frozen.');
    WHEN e_insufficient_funds THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[PURCHASE REJECTED] Insufficient funds! Needed: ' || fn_format_currency(v_total_cost) || ', Available: ' || fn_format_currency(v_bal));
    WHEN e_category_not_found THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[PURCHASE REJECTED] Unknown category: "' || p_category_name || '".');
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[PURCHASE REJECTED] Error: ' || SQLERRM);
  END record_purchase;

  -- --------------------------------------------------------------------------
  -- PROCEDURE: show_account_summary
  -- --------------------------------------------------------------------------
  PROCEDURE show_account_summary(p_account_no IN VARCHAR2) IS
    r_acc accounts%ROWTYPE;
    v_total_txns NUMBER;
    v_badge      VARCHAR2(50);
  BEGIN
    SELECT * INTO r_acc FROM accounts WHERE account_no = p_account_no;
    SELECT COUNT(*) INTO v_total_txns FROM transactions WHERE account_id = r_acc.account_id;
    v_badge := fn_get_health_badge(r_acc.balance, r_acc.total_spent);

    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('+------------------------------------------------------------------------------+');
    DBMS_OUTPUT.PUT_LINE('|                       POCKETBOSS ACCOUNT DASHBOARD                           |');
    DBMS_OUTPUT.PUT_LINE('+------------------------------------------------------------------------------+');
    DBMS_OUTPUT.PUT_LINE('| Account Number     : ' || RPAD(r_acc.account_no, 55) || '|');
    DBMS_OUTPUT.PUT_LINE('| Account Holder     : ' || RPAD(r_acc.account_name, 55) || '|');
    DBMS_OUTPUT.PUT_LINE('| Account Type       : ' || RPAD(r_acc.account_type, 55) || '|');
    DBMS_OUTPUT.PUT_LINE('| Account Status     : ' || RPAD(r_acc.status, 55) || '|');
    DBMS_OUTPUT.PUT_LINE('| Created Date       : ' || RPAD(TO_CHAR(r_acc.created_at, 'DD-MON-YYYY HH24:MI'), 55) || '|');
    DBMS_OUTPUT.PUT_LINE('+------------------------------------------------------------------------------+');
    DBMS_OUTPUT.PUT_LINE('| Current Balance    : ' || RPAD(fn_format_currency(r_acc.balance), 55) || '|');
    DBMS_OUTPUT.PUT_LINE('| Lifetime Deposited : ' || RPAD(fn_format_currency(r_acc.total_deposited), 55) || '|');
    DBMS_OUTPUT.PUT_LINE('| Lifetime Spent     : ' || RPAD(fn_format_currency(r_acc.total_spent), 55) || '|');
    DBMS_OUTPUT.PUT_LINE('| Total Transactions : ' || RPAD(TO_CHAR(v_total_txns), 55) || '|');
    DBMS_OUTPUT.PUT_LINE('| Financial Tier     : ' || RPAD(v_badge, 55) || '|');
    DBMS_OUTPUT.PUT_LINE('+------------------------------------------------------------------------------+');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('[ERROR] Account [' || p_account_no || '] not found.');
  END show_account_summary;

  -- --------------------------------------------------------------------------
  -- PROCEDURE: show_budget_report
  -- --------------------------------------------------------------------------
  PROCEDURE show_budget_report(
    p_account_no   IN VARCHAR2,
    p_period_month IN VARCHAR2
  ) IS
    v_acc_id       accounts.account_id%TYPE;
    v_acc_name     accounts.account_name%TYPE;

    CURSOR c_budgets IS
      SELECT b.budget_id,
             c.category_name,
             b.budget_limit,
             b.alert_threshold_pct,
             NVL((SELECT SUM(p.total_price)
                  FROM purchases p
                  WHERE p.account_id = v_acc_id
                    AND p.category_id = c.category_id
                    AND TO_CHAR(p.purchase_date, 'YYYY-MM') = p_period_month), 0) AS actual_spent
      FROM budgets b
      JOIN categories c ON b.category_id = c.category_id
      WHERE b.account_id = v_acc_id
        AND b.period_month = p_period_month
      ORDER BY c.category_name;

    v_total_budget  NUMBER := 0;
    v_total_spent   NUMBER := 0;
    v_variance      NUMBER := 0;
    v_pct           NUMBER := 0;
    v_status_label  VARCHAR2(20);
    v_count         NUMBER := 0;
  BEGIN
    SELECT account_id, account_name INTO v_acc_id, v_acc_name
    FROM accounts WHERE account_no = p_account_no;

    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('===================================================================================================================');
    DBMS_OUTPUT.PUT_LINE('                               POCKETBOSS MONTHLY BUDGET PERFORMANCE REPORT                                        ');
    DBMS_OUTPUT.PUT_LINE(' Account: ' || p_account_no || ' (' || v_acc_name || ')       Period: ' || p_period_month || '       Generated: ' || TO_CHAR(SYSDATE, 'DD-MON-YYYY HH24:MI'));
    DBMS_OUTPUT.PUT_LINE('===================================================================================================================');
    DBMS_OUTPUT.PUT_LINE('+----------------------+---------------+---------------+---------------+----------------------+-------------------+');
    DBMS_OUTPUT.PUT_LINE('| Category Name        |  Budget Limit |  Actual Spent |   Variance    |  Budget Utilization  | Status            |');
    DBMS_OUTPUT.PUT_LINE('+----------------------+---------------+---------------+---------------+----------------------+-------------------+');

    FOR r IN c_budgets LOOP
      v_count := v_count + 1;
      v_variance := r.budget_limit - r.actual_spent;
      IF r.budget_limit > 0 THEN
        v_pct := ROUND((r.actual_spent / r.budget_limit) * 100);
      ELSE
        v_pct := 0;
      END IF;

      IF r.actual_spent > r.budget_limit THEN
        v_status_label := '!! EXCEEDED !!';
      ELSIF v_pct >= r.alert_threshold_pct THEN
        v_status_label := '! WARNING !';
      ELSE
        v_status_label := 'SAFE (On Track)';
      END IF;

      v_total_budget := v_total_budget + r.budget_limit;
      v_total_spent  := v_total_spent + r.actual_spent;

      DBMS_OUTPUT.PUT_LINE('| ' ||
        RPAD(SUBSTR(r.category_name, 1, 20), 20) || ' | ' ||
        LPAD(fn_format_currency(r.budget_limit), 13) || ' | ' ||
        LPAD(fn_format_currency(r.actual_spent), 13) || ' | ' ||
        LPAD(fn_format_currency(v_variance), 13) || ' | ' ||
        RPAD(fn_progress_bar(r.actual_spent, r.budget_limit, 12), 20) || ' | ' ||
        RPAD(v_status_label, 17) || ' |'
      );
    END LOOP;

    IF v_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('|                              NO BUDGETS CONFIGURED FOR THIS PERIOD                                               |');
    END IF;

    DBMS_OUTPUT.PUT_LINE('+----------------------+---------------+---------------+---------------+----------------------+-------------------+');
    DBMS_OUTPUT.PUT_LINE('| TOTALS               | ' ||
      LPAD(fn_format_currency(v_total_budget), 13) || ' | ' ||
      LPAD(fn_format_currency(v_total_spent), 13) || ' | ' ||
      LPAD(fn_format_currency(v_total_budget - v_total_spent), 13) || ' | ' ||
      RPAD(fn_progress_bar(v_total_spent, v_total_budget, 12), 20) || ' | ' ||
      RPAD(CASE WHEN v_total_spent > v_total_budget THEN 'OVERALL EXCEEDED' ELSE 'OVERALL HEALTHY' END, 17) || ' |'
    );
    DBMS_OUTPUT.PUT_LINE('+----------------------+---------------+---------------+---------------+----------------------+-------------------+');

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('[ERROR] Account [' || p_account_no || '] not found.');
  END show_budget_report;

  -- --------------------------------------------------------------------------
  -- PROCEDURE: show_purchases_report
  -- --------------------------------------------------------------------------
  PROCEDURE show_purchases_report(
    p_account_no   IN VARCHAR2,
    p_period_month IN VARCHAR2 DEFAULT NULL
  ) IS
    v_acc_id   accounts.account_id%TYPE;
    v_acc_name accounts.account_name%TYPE;

    CURSOR c_purchases (cp_acc_id NUMBER, cp_month VARCHAR2) IS
      SELECT p.purchase_id,
             p.item_name,
             c.category_name,
             p.quantity,
             p.unit_price,
             p.total_price,
             p.merchant,
             p.purchase_date
      FROM purchases p
      JOIN categories c ON p.category_id = c.category_id
      WHERE p.account_id = cp_acc_id
        AND (cp_month IS NULL OR TO_CHAR(p.purchase_date, 'YYYY-MM') = cp_month)
      ORDER BY p.purchase_date DESC, p.purchase_id DESC;

    r_item c_purchases%ROWTYPE;
    v_grand_total NUMBER := 0;
    v_total_items NUMBER := 0;
  BEGIN
    SELECT account_id, account_name INTO v_acc_id, v_acc_name
    FROM accounts WHERE account_no = p_account_no;

    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('===================================================================================================================');
    DBMS_OUTPUT.PUT_LINE('                               POCKETBOSS ITEMIZED PURCHASES & EXPENSE LEDGER                                      ');
    DBMS_OUTPUT.PUT_LINE(' Account: ' || p_account_no || ' (' || v_acc_name || ')       Period: ' || NVL(p_period_month, 'ALL TIME') || '       Generated: ' || TO_CHAR(SYSDATE, 'DD-MON-YYYY HH24:MI'));
    DBMS_OUTPUT.PUT_LINE('===================================================================================================================');
    DBMS_OUTPUT.PUT_LINE('+------+----------------------+----------------------+-----+-------------+-------------+------------------+-------------+');
    DBMS_OUTPUT.PUT_LINE('| ID   | Item Description     | Category             | Qty |  Unit Price | Total Price | Merchant         | Date        |');
    DBMS_OUTPUT.PUT_LINE('+------+----------------------+----------------------+-----+-------------+-------------+------------------+-------------+');

    OPEN c_purchases(v_acc_id, p_period_month);
    LOOP
      FETCH c_purchases INTO r_item;
      EXIT WHEN c_purchases%NOTFOUND;

      v_grand_total := v_grand_total + r_item.total_price;
      v_total_items := v_total_items + r_item.quantity;

      DBMS_OUTPUT.PUT_LINE('| ' ||
        LPAD(TO_CHAR(r_item.purchase_id), 4) || ' | ' ||
        RPAD(SUBSTR(r_item.item_name, 1, 20), 20) || ' | ' ||
        RPAD(SUBSTR(r_item.category_name, 1, 20), 20) || ' | ' ||
        LPAD(TO_CHAR(r_item.quantity), 3) || ' | ' ||
        LPAD(fn_format_currency(r_item.unit_price), 11) || ' | ' ||
        LPAD(fn_format_currency(r_item.total_price), 11) || ' | ' ||
        RPAD(SUBSTR(r_item.merchant, 1, 16), 16) || ' | ' ||
        RPAD(TO_CHAR(r_item.purchase_date, 'DD-MON-YYYY'), 11) || ' |'
      );
    END LOOP;

    IF c_purchases%ROWCOUNT = 0 THEN
      DBMS_OUTPUT.PUT_LINE('|                                        NO PURCHASES RECORDED YET                                                 |');
    END IF;

    CLOSE c_purchases;

    DBMS_OUTPUT.PUT_LINE('+------+----------------------+----------------------+-----+-------------+-------------+------------------+-------------+');
    DBMS_OUTPUT.PUT_LINE('| TOTAL PURCHASES: ' || LPAD(TO_CHAR(v_total_items), 4) || ' items' ||
      LPAD('GRAND TOTAL: ' || fn_format_currency(v_grand_total), 93) || ' |');
    DBMS_OUTPUT.PUT_LINE('+------------------------------------------------------------------------------------------------------------------+');

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('[ERROR] Account [' || p_account_no || '] not found.');
  END show_purchases_report;

  -- --------------------------------------------------------------------------
  -- PROCEDURE: show_account_statement
  -- --------------------------------------------------------------------------
  PROCEDURE show_account_statement(p_account_no IN VARCHAR2) IS
    v_acc_id   accounts.account_id%TYPE;
    v_acc_name accounts.account_name%TYPE;
    v_cur_bal  accounts.balance%TYPE;

    CURSOR c_txns IS
      SELECT txn_id, txn_type, amount, running_balance, description, related_account_no, txn_date
      FROM transactions
      WHERE account_id = v_acc_id
      ORDER BY txn_id ASC;

    v_count NUMBER := 0;
  BEGIN
    SELECT account_id, account_name, balance INTO v_acc_id, v_acc_name, v_cur_bal
    FROM accounts WHERE account_no = p_account_no;

    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('===================================================================================================================');
    DBMS_OUTPUT.PUT_LINE('                              POCKETBOSS OFFICIAL ACCOUNT STATEMENT & LEDGER                                       ');
    DBMS_OUTPUT.PUT_LINE(' Account: ' || p_account_no || ' (' || v_acc_name || ')       Closing Balance: ' || fn_format_currency(v_cur_bal) || '       Statement Date: ' || TO_CHAR(SYSDATE, 'DD-MON-YYYY'));
    DBMS_OUTPUT.PUT_LINE('===================================================================================================================');
    DBMS_OUTPUT.PUT_LINE('+-------+-------------+--------------+---------------+------------------------------------------+------------------+');
    DBMS_OUTPUT.PUT_LINE('| Txn # | Date        | Type         |        Amount | Description                              | Running Balance  |');
    DBMS_OUTPUT.PUT_LINE('+-------+-------------+--------------+---------------+------------------------------------------+------------------+');

    FOR r IN c_txns LOOP
      v_count := v_count + 1;
      DBMS_OUTPUT.PUT_LINE('| ' ||
        LPAD(TO_CHAR(r.txn_id), 5) || ' | ' ||
        RPAD(TO_CHAR(r.txn_date, 'DD-MON-YYYY'), 11) || ' | ' ||
        RPAD(r.txn_type, 12) || ' | ' ||
        LPAD(fn_format_currency(r.amount), 13) || ' | ' ||
        RPAD(SUBSTR(r.description, 1, 40), 40) || ' | ' ||
        LPAD(fn_format_currency(r.running_balance), 16) || ' |'
      );
    END LOOP;

    IF v_count = 0 THEN
      DBMS_OUTPUT.PUT_LINE('|                                        NO TRANSACTIONS RECORDED                                                  |');
    END IF;

    DBMS_OUTPUT.PUT_LINE('+-------+-------------+--------------+---------------+------------------------------------------+------------------+');
    DBMS_OUTPUT.PUT_LINE('| Total Entries: ' || LPAD(TO_CHAR(v_count), 4) ||
      LPAD('CURRENT BALANCE: ' || fn_format_currency(v_cur_bal), 96) || ' |');
    DBMS_OUTPUT.PUT_LINE('+------------------------------------------------------------------------------------------------------------------+');

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('[ERROR] Account [' || p_account_no || '] not found.');
  END show_account_statement;

  -- --------------------------------------------------------------------------
  -- PROCEDURE: simulate_savings_growth
  -- --------------------------------------------------------------------------
  PROCEDURE simulate_savings_growth(
    p_account_no          IN  VARCHAR2,
    p_months              IN  NUMBER,
    p_monthly_deposit     IN  NUMBER,
    p_annual_rate_pct     IN  NUMBER
  ) IS
    v_cur_bal        NUMBER;
    v_projected_bal  NUMBER;
    v_month_counter  NUMBER := 1;
    v_monthly_rate   NUMBER;
    v_monthly_int    NUMBER;
    v_total_interest NUMBER := 0;
    v_total_invested NUMBER := 0;
  BEGIN
    v_cur_bal := fn_get_balance(p_account_no);
    IF v_cur_bal IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('[ERROR] Account [' || p_account_no || '] does not exist.');
      RETURN;
    END IF;

    v_projected_bal := v_cur_bal;
    v_monthly_rate := (p_annual_rate_pct / 100) / 12;

    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('===================================================================================================');
    DBMS_OUTPUT.PUT_LINE('                    POCKETBOSS SAVINGS COMPOUND GROWTH PROJECTION (WHILE LOOP DEMO)                 ');
    DBMS_OUTPUT.PUT_LINE(' Base Balance: ' || fn_format_currency(v_cur_bal) || ' | Monthly Add: ' || fn_format_currency(p_monthly_deposit) || ' | Annual Rate: ' || p_annual_rate_pct || '% | Duration: ' || p_months || ' Months');
    DBMS_OUTPUT.PUT_LINE('===================================================================================================');
    DBMS_OUTPUT.PUT_LINE('+--------+-------------------+--------------------+--------------------+---------------------------+');
    DBMS_OUTPUT.PUT_LINE('| Month  | Starting Balance  | Monthly Addition   | Interest Earned    | End of Month Balance      |');
    DBMS_OUTPUT.PUT_LINE('+--------+-------------------+--------------------+--------------------+---------------------------+');

    WHILE v_month_counter <= p_months LOOP
      v_monthly_int := (v_projected_bal + p_monthly_deposit) * v_monthly_rate;
      v_total_interest := v_total_interest + v_monthly_int;
      v_total_invested := v_total_invested + p_monthly_deposit;

      DBMS_OUTPUT.PUT_LINE('| ' ||
        LPAD(TO_CHAR(v_month_counter), 6) || ' | ' ||
        LPAD(fn_format_currency(v_projected_bal), 17) || ' | ' ||
        LPAD(fn_format_currency(p_monthly_deposit), 18) || ' | ' ||
        LPAD(fn_format_currency(v_monthly_int), 18) || ' | ' ||
        LPAD(fn_format_currency(v_projected_bal + p_monthly_deposit + v_monthly_int), 25) || ' |'
      );

      v_projected_bal := v_projected_bal + p_monthly_deposit + v_monthly_int;
      v_month_counter := v_month_counter + 1;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('+--------+-------------------+--------------------+--------------------+---------------------------+');
    DBMS_OUTPUT.PUT_LINE('| FINAL PROJECTED BALANCE: ' || fn_format_currency(v_projected_bal) ||
      ' | Total Interest Earned: ' || fn_format_currency(v_total_interest) || ' |');
    DBMS_OUTPUT.PUT_LINE('+--------------------------------------------------------------------------------------------------+');

  END simulate_savings_growth;

  -- --------------------------------------------------------------------------
  -- PROCEDURE: batch_apply_interest
  -- --------------------------------------------------------------------------
  PROCEDURE batch_apply_interest(p_annual_rate_pct IN NUMBER) IS
    v_monthly_rate NUMBER;
    v_int_earned   NUMBER;
    v_new_bal      NUMBER;
    v_count        NUMBER := 0;
  BEGIN
    v_monthly_rate := (p_annual_rate_pct / 100) / 12;

    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('>>> Starting Batch Monthly Interest Processing @ ' || p_annual_rate_pct || '% p.a. ...');

    FOR acc IN (SELECT account_id, account_no, account_name, balance 
                FROM accounts 
                WHERE account_type = 'Savings' AND status = 'ACTIVE' AND balance > 0
                FOR UPDATE) LOOP

      v_int_earned := ROUND(acc.balance * v_monthly_rate, 2);

      IF v_int_earned > 0 THEN
        v_new_bal := acc.balance + v_int_earned;

        UPDATE accounts
        SET balance = v_new_bal
        WHERE account_id = acc.account_id;

        INSERT INTO transactions (txn_id, account_id, txn_type, amount, running_balance, description, related_account_no, purchase_id, txn_date)
        VALUES (TXN_SEQ.NEXTVAL, acc.account_id, 'INTEREST', v_int_earned, v_new_bal, 'Monthly Savings Interest Credited', NULL, NULL, SYSDATE);

        v_count := v_count + 1;
        DBMS_OUTPUT.PUT_LINE('    * Credited ' || fn_format_currency(v_int_earned) || ' interest to [' || acc.account_no || '] (' || acc.account_name || '). New Bal: ' || fn_format_currency(v_new_bal));
      END IF;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('>>> Batch Interest Completed. Total Accounts Credited: ' || v_count);

  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('[ERROR] Batch interest processing failed: ' || SQLERRM);
  END batch_apply_interest;

END pkg_pocketboss;
/

-- ============================================================================
-- STEP 7: STANDALONE CONVENIENCE PROCEDURES
-- ============================================================================
CREATE OR REPLACE PROCEDURE create_account(
  p_name IN VARCHAR2, p_deposit IN NUMBER, p_type IN VARCHAR2 DEFAULT 'Checking'
) IS
  v_dummy VARCHAR2(20);
BEGIN
  pkg_pocketboss.create_account(p_name, p_deposit, p_type, v_dummy);
END;
/

CREATE OR REPLACE PROCEDURE check_balance(p_acc_no IN VARCHAR2) IS
  v_bal NUMBER;
BEGIN
  v_bal := pkg_pocketboss.fn_get_balance(p_acc_no);
  IF v_bal IS NOT NULL THEN
    DBMS_OUTPUT.PUT_LINE('Account [' || p_acc_no || '] Balance: ' || pkg_pocketboss.fn_format_currency(v_bal));
  ELSE
    DBMS_OUTPUT.PUT_LINE('[ERROR] Account [' || p_acc_no || '] not found.');
  END IF;
END;
/

CREATE OR REPLACE PROCEDURE deposit_money(p_acc_no IN VARCHAR2, p_amt IN NUMBER, p_note IN VARCHAR2 DEFAULT 'Cash Deposit') IS
BEGIN
  pkg_pocketboss.deposit_funds(p_acc_no, p_amt, p_note);
END;
/

CREATE OR REPLACE PROCEDURE transfer_money(p_from IN VARCHAR2, p_to IN VARCHAR2, p_amt IN NUMBER, p_note IN VARCHAR2 DEFAULT 'Transfer') IS
BEGIN
  pkg_pocketboss.transfer_funds(p_from, p_to, p_amt, p_note);
END;
/

CREATE OR REPLACE PROCEDURE purchase_item(
  p_acc_no IN VARCHAR2, p_item IN VARCHAR2, p_cat IN VARCHAR2, p_qty IN NUMBER, p_price IN NUMBER, p_merchant IN VARCHAR2 DEFAULT 'Store', p_note IN VARCHAR2 DEFAULT NULL
) IS
BEGIN
  pkg_pocketboss.record_purchase(p_acc_no, p_item, p_cat, p_qty, p_price, p_merchant, p_note);
END;
/

CREATE OR REPLACE PROCEDURE set_budget(
  p_acc_no IN VARCHAR2, p_cat IN VARCHAR2, p_limit IN NUMBER, p_month IN VARCHAR2, p_thresh IN NUMBER DEFAULT 80
) IS
BEGIN
  pkg_pocketboss.set_budget(p_acc_no, p_cat, p_month, p_limit, p_thresh);
END;
/

CREATE OR REPLACE PROCEDURE account_report(p_acc_no IN VARCHAR2) IS
BEGIN
  pkg_pocketboss.show_account_summary(p_acc_no);
END;
/

CREATE OR REPLACE PROCEDURE budget_report(p_acc_no IN VARCHAR2, p_month IN VARCHAR2) IS
BEGIN
  pkg_pocketboss.show_budget_report(p_acc_no, p_month);
END;
/

CREATE OR REPLACE PROCEDURE purchase_report(p_acc_no IN VARCHAR2, p_month IN VARCHAR2 DEFAULT NULL) IS
BEGIN
  pkg_pocketboss.show_purchases_report(p_acc_no, p_month);
END;
/

CREATE OR REPLACE PROCEDURE transaction_history(p_acc_no IN VARCHAR2) IS
BEGIN
  pkg_pocketboss.show_account_statement(p_acc_no);
END;
/

-- ============================================================================
-- STEP 8: COMPREHENSIVE TEST HARNESS & DEMONSTRATION RUNNER
-- ============================================================================
PROMPT
PROMPT ============================================================================
PROMPT RUNNING POCKETBOSS COMPLETE DEMONSTRATION & TEST HARNESS
PROMPT ============================================================================

DECLARE
  v_jeremy_acc VARCHAR2(20);
  v_alice_acc   VARCHAR2(20);
  v_bob_acc     VARCHAR2(20);
  v_cur_month   VARCHAR2(7);
BEGIN
  v_cur_month := TO_CHAR(SYSDATE, 'YYYY-MM');

  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('TEST 1: Creating Accounts with Initial Balances');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  pkg_pocketboss.create_account('Jeremy Davis', 35000.00, 'Checking', v_jeremy_acc);
  pkg_pocketboss.create_account('Alice Vance',   12500.00, 'Savings',  v_alice_acc);
  pkg_pocketboss.create_account('Bob Martinez',   2000.00, 'Checking', v_bob_acc);

  DBMS_OUTPUT.PUT_LINE(' ');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('TEST 2: Depositing Additional Funds');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  pkg_pocketboss.deposit_funds(v_jeremy_acc, 5000.00, 'Bonus Direct Deposit');

  DBMS_OUTPUT.PUT_LINE(' ');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('TEST 3: Setting Monthly Category Budgets for Jeremy (' || v_cur_month || ')');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  pkg_pocketboss.set_budget(v_jeremy_acc, 'Groceries',          v_cur_month, 800.00,  80);
  pkg_pocketboss.set_budget(v_jeremy_acc, 'Tech & Electronics', v_cur_month, 2500.00, 75);
  pkg_pocketboss.set_budget(v_jeremy_acc, 'Dining & Cafes',     v_cur_month, 600.00,  80);
  pkg_pocketboss.set_budget(v_jeremy_acc, 'Utilities & Bills',  v_cur_month, 450.00,  85);

  DBMS_OUTPUT.PUT_LINE(' ');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('TEST 4: Recording Itemized Purchases & Budget Monitoring');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  pkg_pocketboss.record_purchase(v_jeremy_acc, 'Organic Milk & Vegetables', 'Groceries', 1, 145.50, 'WholeFoods', 'Weekly grocery basket');
  pkg_pocketboss.record_purchase(v_jeremy_acc, 'Espresso & Croissant', 'Dining & Cafes', 2, 18.00, 'Artisan Roasters', 'Breakfast meeting');
  
  -- Tech Purchase that triggers budget warning (1950 is 78% of 2500, threshold is 75%)
  pkg_pocketboss.record_purchase(v_jeremy_acc, 'UltraWide 34in Monitor', 'Tech & Electronics', 1, 1950.00, 'Amazon', 'Workstation upgrade');

  -- Second tech purchase that intentionally exceeds the budget (1950 + 750 = 2700 > 2500)
  pkg_pocketboss.record_purchase(v_jeremy_acc, 'Mechanical Gaming Keyboard', 'Tech & Electronics', 1, 750.00, 'Keychron', 'RGB Custom Board');

  -- Additional purchases
  pkg_pocketboss.record_purchase(v_jeremy_acc, 'Fiber Internet 1Gbps', 'Utilities & Bills', 1, 120.00, 'Spectrum', 'Monthly broadband');
  pkg_pocketboss.record_purchase(v_jeremy_acc, 'Weekend Sushi Dinner', 'Dining & Cafes', 1, 160.00, 'Sakura Bistro', 'Dinner with team');

  DBMS_OUTPUT.PUT_LINE(' ');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('TEST 5: Peer-to-Peer Fund Transfers (Jeremy -> Alice)');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  pkg_pocketboss.transfer_funds(v_jeremy_acc, v_alice_acc, 3200.00, 'Project Consulting Reimbursement');

  DBMS_OUTPUT.PUT_LINE(' ');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('TEST 6: Exception Handling Demonstrations (Intentional Failures)');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('--> Case A: Attempting Transfer with Insufficient Funds:');
  pkg_pocketboss.transfer_funds(v_bob_acc, v_alice_acc, 99999.00, 'Overdraft Attempt');

  DBMS_OUTPUT.PUT_LINE('--> Case B: Attempting Transfer to the Same Account:');
  pkg_pocketboss.transfer_funds(v_jeremy_acc, v_jeremy_acc, 500.00, 'Self Transfer Attempt');

  DBMS_OUTPUT.PUT_LINE('--> Case C: Attempting Transfer to Non-Existent Account:');
  pkg_pocketboss.transfer_funds(v_jeremy_acc, 'PB-99999', 250.00, 'Ghost Account Transfer');

  DBMS_OUTPUT.PUT_LINE('--> Case D: Attempting Purchase with Insufficient Balance:');
  pkg_pocketboss.record_purchase(v_bob_acc, 'Luxury Diamond Watch', 'Tech & Electronics', 1, 50000.00, 'Rolex Store');

  DBMS_OUTPUT.PUT_LINE(' ');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('TEST 7: Savings Growth Simulation (Showcasing WHILE Loop)');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  pkg_pocketboss.simulate_savings_growth(v_alice_acc, 6, 1000.00, 6.5);

  DBMS_OUTPUT.PUT_LINE(' ');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('TEST 8: Batch Savings Interest Crediting (Showcasing Cursor Loop)');
  DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
  pkg_pocketboss.batch_apply_interest(5.0);

  DBMS_OUTPUT.PUT_LINE(' ');
  DBMS_OUTPUT.PUT_LINE('======================================================================');
  DBMS_OUTPUT.PUT_LINE('GENERATING ALL EXECUTIVE FINANCIAL REPORTS FOR SCREENSHOTS');
  DBMS_OUTPUT.PUT_LINE('======================================================================');
  
  -- Executive Reports
  pkg_pocketboss.show_account_summary(v_jeremy_acc);
  pkg_pocketboss.show_budget_report(v_jeremy_acc, v_cur_month);
  pkg_pocketboss.show_purchases_report(v_jeremy_acc, v_cur_month);
  pkg_pocketboss.show_account_statement(v_jeremy_acc);

  -- Alice's Statement
  pkg_pocketboss.show_account_summary(v_alice_acc);
  pkg_pocketboss.show_account_statement(v_alice_acc);

END;
/

PROMPT
PROMPT ============================================================================
PROMPT PocketBoss Build, Deployment, & Execution Completed Successfully!
PROMPT ============================================================================
