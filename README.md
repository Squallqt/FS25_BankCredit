# FS25_BankCredit

Fractional-reserve banking system for Farming Simulator 25.

[![Version](https://img.shields.io/badge/version-1.0.0.0-blue.svg)](https://github.com/Squallqt/FS25_BankCredit/releases)
[![FS25](https://img.shields.io/badge/FS25-compatible-green.svg)](https://farming-simulator.com/)
[![Multiplayer](https://img.shields.io/badge/multiplayer-supported-success.svg)](#)
[![Languages](https://img.shields.io/badge/languages-25-blue.svg)](#)

## Overview

FS25_BankCredit adds a standalone fractional-reserve bank to Farming Simulator 25. Borrow money, manage your debt, and grow your credit capacity by farming. Credit is not granted automatically: it is evaluated based on your income history and asset base.

The bank is a virtual entity with its own equity, funded by the interest it collects. It operates under a configurable leverage ratio and enforces both borrower-level and concentration limits. This mod replaces the vanilla loan system entirely. Any existing vanilla loan balance is automatically cleared at game start.

> **Compatible with FS25_Invoices** (invoice income counts toward credit scoring) and **FS25_RedTape** (subsidy and grant income counts toward credit scoring).

## Features

### Loan Types

- **Annuity**: fixed monthly payment splitting principal and interest over the full duration
- **Bullet**: interest-only monthly payments, full principal repaid at maturity
- **Revolving**: open credit line; draw and repay freely at any time, no fixed term
- Revolving lines charge a **1%/year commitment fee** on the undrawn portion
- Revolving lines can be closed voluntarily when the balance reaches zero

### Credit Scoring

- **DSCR** (Debt-Service Coverage Ratio): decay-weighted average of your 12-month income history divided by the monthly payment
- **LTV** (Loan-to-Value): requested amount divided by liquidated asset value
- Five risk levels based on combined DSCR and LTV thresholds:

| Risk Level | DSCR | LTV |
|---|---|---|
| LOW | >= 1.50 | <= 60% |
| MODERATE | >= 1.25 | <= 75% |
| HIGH | >= 1.00 | <= 90% |
| CRITICAL | >= 0.80 | <= 95% |
| REFUSED | below thresholds | N/A |

- Explicit refusal reasons and transparent rate breakdowns shown at application time
- CRITICAL risk loans are capped at 50% of the requested amount

### Asset Valuation

Asset liquidation value is computed across all farm asset categories with per-category haircuts:

| Category | Haircut |
|---|---|
| Farmland | 70% |
| Livestock | 60% |
| Buildings | 55% |
| Inventory | 50% |
| Tools | 50% |
| Tractors | 40% |
| Cash | 30% |

### Borrower & Concentration Limits

- **Borrower limit**: liquidated asset value plus 24-month income projection, minus existing outstanding debt
- **Concentration cap**: a single farm cannot exceed 25% of the bank's total lending capacity

### Interest Rate Model

- Base rate with mean-reversion, updated quarterly (every 3 in-game periods) when dynamic rate is enabled
- Range: 1% to 12% in 0.25% steps; configurable anchor
- Risk surcharges applied on top of base rate: LOW +0%, MODERATE +0.75%, HIGH +2.0%, CRITICAL +5.0%
- Type spreads: Annuity +0%, Bullet +0.75%, Revolving +5%
- Rate history (last 5 updates) displayed with direction indicator

### Early Repayment

- Available on Annuity and Bullet loans
- Full repayment or partial by number of months
- Configurable penalty from 0% to 5% (default 3%)
- Remaining duration recalculated automatically on partial Annuity repayment

### Bank Health Dashboard

- Equity, leverage ratio, total outstanding portfolio
- Loss provision by risk tier (LOW 0.5%, MODERATE 1.5%, HIGH 4.0%, CRITICAL 10.0%)
- Coverage ratio (equity to loss provision)
- Portfolio composition by risk tier

### Loan Detail View

- Annuity and Bullet: full amortisation schedule with interest and principal breakdown per period
- Revolving: draw and repayment panel with current drawn balance, available capacity, and estimated monthly interest

### Annual Financial Report

Per-farm yearly summary: interest paid, principal repaid, loans opened, loans closed.

### Finance Tab Integration

Separate **Interest** and **Principal** entries in the Finance tab (`bankLoanInterest`, `bankLoanPrincipal`). The vanilla `loanInterest` entry is removed.

### Income Tracking

Tracks recurring operating income for DSCR scoring: crop sales, processed products, wood, livestock, milk, passive building income, biogas, contract missions, bales. Invoice income (FS25_Invoices) and subsidy/grant income (FS25_RedTape) are included automatically when those mods are active. Asset sales are excluded to avoid inflating the score.

### Multiplayer

- Full multiplayer support: bank equity and portfolio are shared server-side across all farms
- Server-authoritative loan creation, payment collection, draws, and repayments
- Late-join support with automatic full state sync for connecting players
- 10 custom network events

### Settings

All settings are server-only and accessible under **Game Settings**:

| Setting | Default | Range |
|---|---|---|
| Starting capital | 500 k€ | 100 k€ to 5 M€ |
| Leverage ratio | 10x | 5x to 20x |
| Dynamic rate | On | On / Off |
| Base interest rate | 3.50% | 1% to 12% (0.25% steps) |
| Early repayment penalty | 3.0% | 0% to 5% (0.5% steps) |

Changing the starting capital mid-save recapitalizes the bank by the delta, without resetting it.

### Localization
25 languages: English, French, German, Spanish, Italian, Portuguese (BR/PT), Dutch, Polish, Russian, Czech, Chinese (Simplified), Chinese (Traditional), Hungarian, Romanian, Turkish, Danish, Norwegian, Swedish, Finnish, Ukrainian, Japanese, Korean, Vietnamese, Indonesian

## Installation

### From ModHub
Download from the official [Farming Simulator ModHub](https://www.farming-simulator.com/mod.php?mod_id=361360&title=fs2025).

### Manual Installation
1. Extract `FS25_BankCredit.zip` to your FS25 mods directory
2. Launch Farming Simulator 25
3. Activate the mod in mod selection
4. Access via the **Bank** tab in InGame Menu (ESC)

## Usage

### Taking a Loan

1. Open InGame Menu (ESC), **Bank** tab
2. Click **New Loan**
3. Select loan type: Annuity, Bullet, or Revolving
4. Enter the amount and duration (Annuity and Bullet only)
5. Review the credit assessment: DSCR, LTV, risk level, effective rate, and monthly payment
6. Confirm to disburse

### Managing Loans

- **Active tab**: lists all open loans with remaining balance, remaining duration, and monthly payment
- **Paid tab**: archive of fully repaid loans
- **Detail view**: opens the full amortisation schedule (Annuity, Bullet) or the draw/repay panel (Revolving)
- **Early repayment**: available from the detail view; enter a number of months to prepay
- **Revolving draw/repay**: enter an amount to draw against the credit line, or repay part of the outstanding balance
- **Close revolving**: available from the detail view when the drawn balance is zero

### Bank Health

Click **Bank Health** from the main Bank tab to open the bank dashboard: equity, leverage ratio, outstanding portfolio, loss provision per risk tier, and coverage ratio.

### Annual Report

Click **Annual Report** to view per-year summaries of interest paid, principal repaid, and loan activity for your farm.

## Technical

### Architecture

- **Service layer**: `BankService` (reserves, equity, portfolio), `CreditService` (DSCR, LTV, scoring, limits), `LoanService` (disbursement, collection, repayment, revolving), `InterestRateModel` (mean-reversion rate), `IncomeTracker` (12-period rolling income history), `AnnualReport` (per-farm yearly stats)
- **Persistence**: `BankRepository` and `BankLedger` with XML serialization; state saved per savegame directory
- **GUI**: `BankFrame` (main tab), `TakeLoanWizard` (loan creation), `LoanDetailDialog` (amortisation / revolving panel), `BankHealthDialog` (dashboard), `AnnualReportDialog`
- **Events**: 10 custom network events (`LoanCreateEvent`, `LoanPaymentEvent`, `BankSyncEvent`, `BankSettingsEvent`, `LoanRequestEvent`, `LoanRepayEvent`, `RevolvingDrawEvent`, `VanillaLoanClearedEvent`, `VanillaLoanSyncEvent`, `BankPeriodSyncEvent`)

### Annuity Formula

```
r = annualRate / 100 / 12
monthlyPayment = principal * r * (1 + r)^n / ((1 + r)^n - 1)
```

where `n` is the duration in months.

### DSCR Calculation

```
weightedIncome = decay-weighted average over 12 periods (decay = 0.8 per period)
DSCR = weightedIncome / monthlyPayment
```

Recent periods carry more weight; income naturally decays when the farm stops earning.

### Interest Rate Mean-Reversion

The base rate moves +0.25%, 0%, or -0.25% each quarter. The probability distribution shifts toward the configured anchor: the further the current rate deviates, the stronger the pull back. Range is clamped to [1%, 12%].

### Bank Capacity

```
totalCapacity     = equity * leverageRatio
availableCapacity = totalCapacity - totalOutstanding - lossProvision
lossProvision     = sum(portfolioByRisk[tier] * lossRate[tier])
```

## Changelog

### v1.0.0.0
- Initial release

## Support

- **Issues**: [GitHub Issues](https://github.com/Squallqt/FS25_BankCredit/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Squallqt/FS25_BankCredit/discussions)

## License

All Rights Reserved © 2026 Squallqt

## Author

**Squallqt**
Systems Administrator & FS25 Mod Developer

*Not affiliated with or endorsed by GIANTS Software GmbH*
