# ============================================================================
# PocketBoss - Interactive Personal Finance Console (Oracle PL/SQL)
# ============================================================================

$conn = "bankuser/bankuser@//localhost:1521/XEPDB1"

function Invoke-PlSql([string]$plsqlBlock) {
    $script = @"
SET DEFINE OFF;
SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 160;
SET PAGESIZE 1000;
SET FEEDBACK OFF;
$plsqlBlock
EXIT;
"@
    $output = $script | sqlplus -s $conn
    return $output
}

function Prompt-Default([string]$message, [string]$defaultVal) {
    $val = Read-Host "$message [$defaultVal]"
    if ([string]::IsNullOrWhiteSpace($val)) {
        return $defaultVal
    }
    return $val.Trim()
}

$curMonth = (Get-Date).ToString("yyyy-MM")

while ($true) {
    Clear-Host
    Write-Host "============================================================================" -ForegroundColor Cyan
    Write-Host "                     POCKETBOSS - PERSONAL FINANCE MANAGER                  " -ForegroundColor Yellow
    Write-Host "                           Powered by Oracle PL/SQL                         " -ForegroundColor DarkGray
    Write-Host "============================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1]  Initialize DB & Run Full Demo Suite (Reset DB, run tests, show all reports)" -ForegroundColor White
    Write-Host ""
    Write-Host "  --- DAILY FINANCIAL OPERATIONS ---" -ForegroundColor DarkCyan
    Write-Host "  [2]  Check Account Dashboard & Balance" -ForegroundColor Green
    Write-Host "  [3]  Deposit Money into Account" -ForegroundColor Green
    Write-Host "  [4]  Record an Itemized Purchase (with Budget Checks)" -ForegroundColor Green
    Write-Host "  [5]  Transfer Money Between Accounts" -ForegroundColor Green
    Write-Host "  [6]  Set / Update Monthly Category Budget" -ForegroundColor Green
    Write-Host ""
    Write-Host "  --- EXECUTIVE FINANCIAL REPORTS (FOR SCREENSHOTS) ---" -ForegroundColor DarkCyan
    Write-Host "  [7]  View Monthly Budget Report (Budget vs Actual with Progress Bars)" -ForegroundColor Yellow
    Write-Host "  [8]  View Itemized Purchases Ledger (Items, Categories, Merchants)" -ForegroundColor Yellow
    Write-Host "  [9]  View Full Official Account Statement (All Transactions)" -ForegroundColor Yellow
    Write-Host "  [10] Simulate Savings Compound Growth (WHILE Loop Simulation)" -ForegroundColor Yellow
    Write-Host "  [11] Run Batch Monthly Interest on Savings Accounts" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [12] Launch Direct SQL*Plus Command Line" -ForegroundColor Magenta
    Write-Host "  [0]  Exit PocketBoss" -ForegroundColor Red
    Write-Host "============================================================================" -ForegroundColor Cyan
    
    $choice = Read-Host "Select an option [0-12]"
    Write-Host ""

    switch ($choice) {
        "1" {
            Write-Host "--> Running PocketBoss Full Setup & Demo Suite..." -ForegroundColor Cyan
            $output = @"
@PocketBoss.sql
EXIT;
"@ | sqlplus -s $conn
            $output | Out-Host
            Read-Host "Demo finished. Press Enter to return to menu"
        }
        "2" {
            $acc = Prompt-Default "Enter Account Number" "PB-1001"
            Write-Host "Fetching Account Dashboard for $acc..." -ForegroundColor Cyan
            $block = @"
BEGIN
  pkg_pocketboss.show_account_summary('$acc');
END;
/
"@
            (Invoke-PlSql $block) | Out-Host
            Read-Host "Press Enter to return to menu"
        }
        "3" {
            $acc = Prompt-Default "Enter Account Number" "PB-1001"
            $amt = Prompt-Default "Enter Deposit Amount" "500.00"
            $note = Prompt-Default "Enter Description" "Direct Cash Deposit"
            Write-Host "Processing Deposit..." -ForegroundColor Cyan
            $block = @"
BEGIN
  pkg_pocketboss.deposit_funds('$acc', $amt, '$note');
END;
/
"@
            (Invoke-PlSql $block) | Out-Host
            Read-Host "Press Enter to return to menu"
        }
        "4" {
            $acc = Prompt-Default "Enter Account Number" "PB-1001"
            $item = Prompt-Default "Enter Item Name" "Wireless Mechanical Keyboard"
            Write-Host "Available Categories: Groceries, Dining & Cafes, Tech & Electronics, Utilities & Bills, Transportation, Entertainment, Miscellaneous" -ForegroundColor DarkGray
            $cat = Prompt-Default "Enter Category Name" "Tech & Electronics"
            $qty = Prompt-Default "Enter Quantity" "1"
            $price = Prompt-Default "Enter Unit Price ($)" "85.00"
            $merch = Prompt-Default "Enter Merchant/Store" "Keychron Store"
            $notes = Prompt-Default "Enter Notes" "Office gear upgrade"
            
            Write-Host "Recording Purchase & Checking Budget Thresholds..." -ForegroundColor Cyan
            $block = @"
BEGIN
  pkg_pocketboss.record_purchase('$acc', '$item', '$cat', $qty, $price, '$merch', '$notes');
END;
/
"@
            (Invoke-PlSql $block) | Out-Host
            Read-Host "Press Enter to return to menu"
        }
        "5" {
            $fromAcc = Prompt-Default "Enter Sender Account Number" "PB-1001"
            $toAcc = Prompt-Default "Enter Recipient Account Number" "PB-1002"
            $amt = Prompt-Default "Enter Transfer Amount ($)" "250.00"
            $note = Prompt-Default "Enter Transfer Description" "Project consulting share"
            
            Write-Host "Processing Atomic Peer-to-Peer Transfer..." -ForegroundColor Cyan
            $block = @"
BEGIN
  pkg_pocketboss.transfer_funds('$fromAcc', '$toAcc', $amt, '$note');
END;
/
"@
            (Invoke-PlSql $block) | Out-Host
            Read-Host "Press Enter to return to menu"
        }
        "6" {
            $acc = Prompt-Default "Enter Account Number" "PB-1001"
            Write-Host "Available Categories: Groceries, Dining & Cafes, Tech & Electronics, Utilities & Bills, Transportation, Entertainment, Miscellaneous" -ForegroundColor DarkGray
            $cat = Prompt-Default "Enter Category Name" "Dining & Cafes"
            $month = Prompt-Default "Enter Month (YYYY-MM)" $curMonth
            $limit = Prompt-Default "Enter Monthly Budget Limit ($)" "700.00"
            $thresh = Prompt-Default "Enter Alert Threshold Percentage (%)" "80"
            
            Write-Host "Setting Category Budget..." -ForegroundColor Cyan
            $block = @"
BEGIN
  pkg_pocketboss.set_budget('$acc', '$cat', '$month', $limit, $thresh);
END;
/
"@
            (Invoke-PlSql $block) | Out-Host
            Read-Host "Press Enter to return to menu"
        }
        "7" {
            $acc = Prompt-Default "Enter Account Number" "PB-1001"
            $month = Prompt-Default "Enter Month (YYYY-MM)" $curMonth
            Write-Host "Generating Monthly Budget Performance Report..." -ForegroundColor Cyan
            $block = @"
BEGIN
  pkg_pocketboss.show_budget_report('$acc', '$month');
END;
/
"@
            (Invoke-PlSql $block) | Out-Host
            Read-Host "Press Enter to return to menu"
        }
        "8" {
            $acc = Prompt-Default "Enter Account Number" "PB-1001"
            $month = Read-Host "Enter Month [Format YYYY-MM or leave blank for ALL TIME]"
            if ([string]::IsNullOrWhiteSpace($month)) {
                $monthArg = "NULL"
            } else {
                $monthArg = "'$($month.Trim())'"
            }
            Write-Host "Generating Itemized Purchases Ledger..." -ForegroundColor Cyan
            $block = @"
BEGIN
  pkg_pocketboss.show_purchases_report('$acc', $monthArg);
END;
/
"@
            (Invoke-PlSql $block) | Out-Host
            Read-Host "Press Enter to return to menu"
        }
        "9" {
            $acc = Prompt-Default "Enter Account Number" "PB-1001"
            Write-Host "Generating Official Account Statement..." -ForegroundColor Cyan
            $block = @"
BEGIN
  pkg_pocketboss.show_account_statement('$acc');
END;
/
"@
            (Invoke-PlSql $block) | Out-Host
            Read-Host "Press Enter to return to menu"
        }
        "10" {
            $acc = Prompt-Default "Enter Account Number" "PB-1002"
            $months = Prompt-Default "Enter Duration in Months" "6"
            $monthlyAdd = Prompt-Default "Enter Monthly Deposit ($)" "1000.00"
            $rate = Prompt-Default "Enter Annual Interest Rate (%)" "6.5"
            
            Write-Host "Running Savings Compound Growth Simulation (WHILE Loop)..." -ForegroundColor Cyan
            $block = @"
BEGIN
  pkg_pocketboss.simulate_savings_growth('$acc', $months, $monthlyAdd, $rate);
END;
/
"@
            (Invoke-PlSql $block) | Out-Host
            Read-Host "Press Enter to return to menu"
        }
        "11" {
            $rate = Prompt-Default "Enter Annual Interest Rate (%)" "5.0"
            Write-Host "Executing Batch Monthly Interest Processing..." -ForegroundColor Cyan
            $block = @"
BEGIN
  pkg_pocketboss.batch_apply_interest($rate);
END;
/
"@
            (Invoke-PlSql $block) | Out-Host
            Read-Host "Press Enter to return to menu"
        }
        "12" {
            Write-Host "Launching SQL*Plus terminal... Type EXIT to return to menu." -ForegroundColor Magenta
            sqlplus $conn
        }
        "0" {
            Write-Host "Thank you for using PocketBoss! Goodbye." -ForegroundColor Green
            Start-Sleep -Seconds 1
            exit
        }
        default {
            Write-Host "Invalid choice, please select an option between 0 and 12." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
