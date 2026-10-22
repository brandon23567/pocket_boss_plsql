# PocketBoss - Personal Finance & Expense Manager (Oracle PL/SQL)

**PocketBoss** is a complete, enterprise-grade personal finance and expense management system implemented in **Oracle PL/SQL**. It is specifically designed to meet academic lab and real-world project requirements, demonstrating advanced database concepts including stored procedures, functions, explicit and parameterized cursors, loops (`FOR`, `WHILE`, `LOOP ... FETCH`), conditionals (`IF-ELSIF-ELSE`, `CASE`), database triggers, user-defined exception handling, and ASCII financial reports.

---

## 🌟 Key Features

1. **Account Management & Net Worth**:
   - Multi-account support (Checking, Savings, Wallet, Investment).
   - Real-time balance inquiry and health rating (Platinum, Gold, Silver, Bronze).
   - Deposit and balance tracking.

2. **Category-Based Budgeting**:
   - Monthly category budget configuration (e.g., Groceries, Tech & Electronics, Dining, Utilities).
   - Customizable warning threshold (e.g., alert at 80% utilization).
   - Real-time budget warning and over-budget alert notifications upon recording any expense.

3. **Itemized Purchases Ledger**:
   - Track purchased items with item name, category, quantity, unit price, total price, merchant, notes, and timestamp.
   - Automatic integration with general ledger transactions and budget checks.

4. **Peer-to-Peer Fund Transfers**:
   - Transfer money between accounts using unique account numbers (e.g., `PB-1001` -> `PB-1002`).
   - Row-level locking (`FOR UPDATE`) ensuring ACID compliance.
   - Dual-entry transaction recording (Transfer Out & Transfer In).

5. **Financial Growth Projections & Batch Jobs**:
   - **Savings Growth Compound Interest Simulation**: Computes monthly compound growth with regular additions over time.
   - **Batch Monthly Interest Processing**: Automatically calculates and deposits interest across all active savings accounts using cursor locks.

6. **Formatted Executive Reports**:
   - **Account Dashboard Card**: Formatted overview with lifetime metrics and health tier.
   - **Monthly Budget Performance Report**: Tabular comparison with visual ASCII progress bars `[=========  ] 73%`, actual spend, variance, and status tags (`SAFE`, `! WARNING !`, `!! EXCEEDED !!`).
   - **Itemized Purchases Ledger**: Detailed table of items, quantities, prices, merchants, and dates.
   - **Official Account Statement**: Full transaction journal with running balances.

---

## 📊 Database Schema Design

```
 +------------------+           +------------------+           +------------------+
 |     ACCOUNTS     | 1       * |     BUDGETS      | *       1 |    CATEGORIES    |
 +------------------+-----------+------------------+-----------+------------------+
 | PK account_id    |           | PK budget_id     |           | PK category_id   |
 |    account_no    |           | FK account_id    |           |    category_name |
 |    account_name  |           | FK category_id   |           |    category_type |
 |    account_type  |           |    period_month  |           |    description   |
 |    balance       |           |    budget_limit  |           +------------------+
 |    total_spent   |           |    alert_thresh  |                     | 1
 |    status        |           +------------------+                     |
 +------------------+                                                    |
          | 1                                                            |
          |                                                              |
          +-----------------------------+                                |
          | 1                           | 1                              |
          v *                           v *                              v *
 +------------------+           +------------------+                     |
 |   TRANSACTIONS   |           |    PURCHASES     |---------------------+
 +------------------+           +------------------+
 | PK txn_id        |           | PK purchase_id   |
 | FK account_id    |           | FK account_id    |
 |    txn_type      |           | FK category_id   |
 |    amount        |           |    item_name     |
 |    running_bal   |           |    quantity      |
 |    description   |           |    unit_price    |
 |    related_acc   |           |    total_price   |
 | FK purchase_id   |           |    merchant      |
 |    txn_date      |           |    purchase_date |
 +------------------+           +------------------+
```

---

## 🛠️ PL/SQL Core Concepts Showcase

| Concept | Implementation in PocketBoss |
| :--- | :--- |
| **PL/SQL Package** | Encapsulated in `pkg_pocketboss` (Specification & Body) with public APIs and private utility helpers. |
| **Stored Procedures** | `create_account`, `deposit_funds`, `transfer_funds`, `set_budget`, `record_purchase`, `simulate_savings_growth`, `batch_apply_interest`, `show_account_summary`, `show_budget_report`, `show_purchases_report`, `show_account_statement`. |
| **Functions** | `fn_format_currency`, `fn_progress_bar`, `fn_get_health_badge`, `fn_get_balance`, `fn_get_category_spent`. |
| **Conditionals** | Nested `IF-ELSIF-ELSE` for balance validation, budget utilization thresholds, transfer constraints; `CASE` expressions for financial tiers and status badges. |
| **Cursor FOR Loop** | Used in `show_budget_report` and `batch_apply_interest` for iteration through active records. |
| **Explicit Cursor** | Used in `show_purchases_report` with `OPEN`, `FETCH`, `EXIT WHEN %NOTFOUND`, and `CLOSE`. |
| **Parameterized Cursor** | `CURSOR c_purchases (cp_acc_id NUMBER, cp_month VARCHAR2) IS ...` |
| **WHILE Loop** | Used in `simulate_savings_growth` to project compound interest month-by-month. |
| **Numeric FOR Loop** | Used in `fn_progress_bar` to dynamically render ASCII bar segments `[========  ]`. |
| **User Exceptions** | `e_insufficient_funds`, `e_invalid_amount`, `e_account_not_found`, `e_same_account_transfer`, `e_account_inactive`, `e_category_not_found` mapped to Oracle error codes via `PRAGMA EXCEPTION_INIT`. |
| **System Exceptions** | Handled `NO_DATA_FOUND`, `DUP_VAL_ON_INDEX`, `ZERO_DIVIDE`, and `OTHERS` with `SQLCODE` & `SQLERRM`. |
| **Transaction Control** | Row locking (`SELECT ... FOR UPDATE`), atomic `COMMIT`, and safe `ROLLBACK` on failures. |
| **Database Triggers** | `trg_transactions_audit` for automatic audit logging and `trg_prevent_negative_balance` for database-level balance constraints. |

---

## 🚀 How to Run & Test the Project

### Option 1: Double-Click `run_pocketboss.bat` (Recommended)
Simply double-click [`run_pocketboss.bat`](file:///c:/Users/Asus%20VivoBook/Desktop/pl_sql_lab_testing/mini_project/run_pocketboss.bat). It opens an **Interactive Menu**:

```text
============================================================================
                     POCKETBOSS - PERSONAL FINANCE MANAGER
                           Powered by Oracle PL/SQL
============================================================================

   --- PROJECT SUITE & SETUP ---
   [1]  Initialize DB & Run Full Demo Suite (Reset DB, run tests, show all reports)
   [2]  Open Interactive SQL*Plus Terminal (Run custom PL/SQL commands)

   --- FINANCIAL OPERATIONS (TEST INDIVIDUAL FEATURES) ---
   [3]  Check Account Dashboard & Balance
   [4]  Deposit Money into Account
   [5]  Record an Itemized Purchase (with Budget Checks)
   [6]  Transfer Money to Another Account
   [7]  Set Monthly Category Budget

   --- EXECUTIVE REPORTS (FOR SCREENSHOTS) ---
   [8]  View Monthly Budget Performance Report (Budget vs Actual)
   [9]  View Itemized Purchases Ledger
   [10] View Full Official Account Statement (Ledger Journal)
   [11] Simulate Savings Growth (Compound Interest WHILE Loop)

   [0]  Exit
============================================================================
Enter your choice [0-11]:
```

> [!TIP]
> - Choose **`[1]`** once to initialize the tables and run the full automated demonstration.
> - Afterwards, use **`[3]` through `[11]`** to test individual features interactively (depositing money, making purchases, transferring funds, generating reports). **You do NOT need to reset the database to test features; your balances, purchases, and budgets persist across operations!**

---

### Option 2: Test Individual Procedures in Oracle SQL Developer or SQL*Plus
Once the database is set up, you can execute individual PL/SQL procedures on the fly with single lines:

```sql
-- Check balance and dashboard
EXEC account_report('PB-1001');

-- Deposit money
EXEC deposit_money('PB-1001', 500.00, 'Freelance Pay');

-- Set a category budget for the month
EXEC set_budget('PB-1001', 'Dining & Cafes', 600.00, '2026-10', 80);

-- Make an itemized purchase (automatically checks balance & budget limit!)
EXEC purchase_item('PB-1001', 'Espresso Machine', 'Dining & Cafes', 1, 120.00, 'Breville', 'Office appliance');

-- Transfer money to another account
EXEC transfer_money('PB-1001', 'PB-1002', 300.00, 'Lunch Reimbursement');

-- View all reports on demand:
EXEC budget_report('PB-1001', '2026-10');       -- Budget vs Actual table
EXEC purchase_report('PB-1001', '2026-10');     -- Itemized purchases receipt
EXEC transaction_history('PB-1001');            -- Full bank statement with running balance
```

---

## 📷 Sample Terminal Output & Report Screenshots

### 1. Account Dashboard
```text
+------------------------------------------------------------------------------+
|                       POCKETBOSS ACCOUNT DASHBOARD                           |
+------------------------------------------------------------------------------+
| Account Number     : PB-1001                                                 |
| Account Holder     : Jeremy Davis                                            |
| Account Type       : Checking                                                |
| Account Status     : ACTIVE                                                  |
| Created Date       : 22-OCT-2026 08:37                                       |
+------------------------------------------------------------------------------+
| Current Balance    : $33,638.50                                              |
| Lifetime Deposited : $40,000.00                                              |
| Lifetime Spent     : $3,161.50                                               |
| Total Transactions : 9                                                       |
| Financial Tier     : GOLD (Strong)                                           |
+------------------------------------------------------------------------------+
```

### 2. Monthly Budget Performance Report (Budget vs Actual)
```text
===================================================================================================================
                               POCKETBOSS MONTHLY BUDGET PERFORMANCE REPORT                                        
 Account: PB-1001 (Jeremy Davis)       Period: 2026-10       Generated: 22-OCT-2026 08:37
===================================================================================================================
+----------------------+---------------+---------------+---------------+----------------------+-------------------+
| Category Name        |  Budget Limit |  Actual Spent |   Variance    |  Budget Utilization  | Status            |
+----------------------+---------------+---------------+---------------+----------------------+-------------------+
| Dining & Cafes       |       $600.00 |       $196.00 |       $404.00 | [====        ]  33%  | SAFE (On Track)   |
| Groceries            |       $800.00 |       $145.50 |       $654.50 | [==          ]  18%  | SAFE (On Track)   |
| Tech & Electronics   |     $2,500.00 |     $2,700.00 |      $-200.00 | [============] 108%  | !! EXCEEDED !!    |
| Utilities & Bills    |       $450.00 |       $120.00 |       $330.00 | [===         ]  27%  | SAFE (On Track)   |
+----------------------+---------------+---------------+---------------+----------------------+-------------------+
| TOTALS               |     $4,350.00 |     $3,161.50 |     $1,188.50 | [=========   ]  73%  | OVERALL HEALTHY   |
+----------------------+---------------+---------------+---------------+----------------------+-------------------+
```

### 3. Itemized Purchases & Expense Ledger
```text
===================================================================================================================
                               POCKETBOSS ITEMIZED PURCHASES & EXPENSE LEDGER                                      
 Account: PB-1001 (Jeremy Davis)       Period: 2026-10       Generated: 22-OCT-2026 08:37
===================================================================================================================
+------+----------------------+----------------------+-----+-------------+-------------+------------------+-------------+
| ID   | Item Description     | Category             | Qty |  Unit Price | Total Price | Merchant         | Date        |
+------+----------------------+----------------------+-----+-------------+-------------+------------------+-------------+
|    6 | Weekend Sushi Dinner | Dining & Cafes       |   1 |     $160.00 |     $160.00 | Sakura Bistro    | 22-OCT-2026 |
|    5 | Fiber Internet 1Gbps | Utilities & Bills    |   1 |     $120.00 |     $120.00 | Spectrum         | 22-OCT-2026 |
|    4 | Mechanical Gaming Ke | Tech & Electronics   |   1 |     $750.00 |     $750.00 | Keychron         | 22-OCT-2026 |
|    3 | UltraWide 34in Monit | Tech & Electronics   |   1 |   $1,950.00 |   $1,950.00 | Amazon           | 22-OCT-2026 |
|    2 | Espresso & Croissant | Dining & Cafes       |   2 |      $18.00 |      $36.00 | Artisan Roasters | 22-OCT-2026 |
|    1 | Organic Milk & Veget | Groceries            |   1 |     $145.50 |     $145.50 | WholeFoods       | 22-OCT-2026 |
+------+----------------------+----------------------+-----+-------------+-------------+------------------+-------------+
| TOTAL PURCHASES:    7 items                                                               GRAND TOTAL: $3,161.50 |
+------------------------------------------------------------------------------------------------------------------+
```

### 4. Official Account Statement (Full Transaction Journal)
```text
===================================================================================================================
                              POCKETBOSS OFFICIAL ACCOUNT STATEMENT & LEDGER                                       
 Account: PB-1001 (Jeremy Davis)       Closing Balance: $33,638.50       Statement Date: 22-OCT-2026
===================================================================================================================
+-------+-------------+--------------+---------------+------------------------------------------+------------------+
| Txn # | Date        | Type         |        Amount | Description                              | Running Balance  |
+-------+-------------+--------------+---------------+------------------------------------------+------------------+
|  5001 | 22-OCT-2026 | DEPOSIT      |    $35,000.00 | Initial Account Opening Deposit          |       $35,000.00 |
|  5004 | 22-OCT-2026 | DEPOSIT      |     $5,000.00 | Bonus Direct Deposit                     |       $40,000.00 |
|  5005 | 22-OCT-2026 | PURCHASE     |       $145.50 | Purchased Organic Milk & Vegetables (Gro |       $39,854.50 |
|  5006 | 22-OCT-2026 | PURCHASE     |        $36.00 | Purchased Espresso & Croissant (Dining & |       $39,818.50 |
|  5007 | 22-OCT-2026 | PURCHASE     |     $1,950.00 | Purchased UltraWide 34in Monitor (Tech & |       $37,868.50 |
|  5008 | 22-OCT-2026 | PURCHASE     |       $750.00 | Purchased Mechanical Gaming Keyboard (Te |       $37,118.50 |
|  5009 | 22-OCT-2026 | PURCHASE     |       $120.00 | Purchased Fiber Internet 1Gbps (Utilitie |       $36,998.50 |
|  5010 | 22-OCT-2026 | PURCHASE     |       $160.00 | Purchased Weekend Sushi Dinner (Dining & |       $36,838.50 |
|  5011 | 22-OCT-2026 | TRANSFER_OUT |     $3,200.00 | Project Consulting Reimbursement (To PB- |       $33,638.50 |
+-------+-------------+--------------+---------------+------------------------------------------+------------------+
| Total Entries:    9                                                                 CURRENT BALANCE: $33,638.50 |
+------------------------------------------------------------------------------------------------------------------+
```

### 5. Savings Compound Growth Simulation (WHILE Loop)
```text
===================================================================================================
                    POCKETBOSS SAVINGS COMPOUND GROWTH PROJECTION (WHILE LOOP DEMO)                 
 Base Balance: $15,700.00 | Monthly Add: $1,000.00 | Annual Rate: 6.5% | Duration: 6 Months
===================================================================================================
+--------+-------------------+--------------------+--------------------+---------------------------+
| Month  | Starting Balance  | Monthly Addition   | Interest Earned    | End of Month Balance      |
+--------+-------------------+--------------------+--------------------+---------------------------+
|      1 |        $15,700.00 |          $1,000.00 |             $90.46 |                $16,790.46 |
|      2 |        $16,790.46 |          $1,000.00 |             $96.36 |                $17,886.82 |
|      3 |        $17,886.82 |          $1,000.00 |            $102.30 |                $18,989.13 |
|      4 |        $18,989.13 |          $1,000.00 |            $108.27 |                $20,097.40 |
|      5 |        $20,097.40 |          $1,000.00 |            $114.28 |                $21,211.68 |
|      6 |        $21,211.68 |          $1,000.00 |            $120.31 |                $22,331.99 |
+--------+-------------------+--------------------+--------------------+---------------------------+
| FINAL PROJECTED BALANCE: $22,331.99 | Total Interest Earned: $631.99 |
+--------------------------------------------------------------------------------------------------+
```

---

## 📂 File Structure

- **[PocketBoss.sql](file:///c:/Users/Asus%20VivoBook/Desktop/pl_sql_lab_testing/mini_project/PocketBoss.sql)**: Complete all-in-one Oracle PL/SQL script (DDL, triggers, package, procedures, test harness).
- **[pocketboss_demo_output.txt](file:///c:/Users/Asus%20VivoBook/Desktop/pl_sql_lab_testing/mini_project/pocketboss_demo_output.txt)**: Verifiable console execution output log ready to be copied or referenced.
- **[run_pocketboss.bat](file:///c:/Users/Asus%20VivoBook/Desktop/pl_sql_lab_testing/mini_project/run_pocketboss.bat)**: One-click launcher for Windows.
- **[README.md](file:///c:/Users/Asus%20VivoBook/Desktop/pl_sql_lab_testing/mini_project/README.md)**: Project report manual and documentation.
