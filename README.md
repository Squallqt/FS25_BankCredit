# FS25_BankCredit

Fractional-reserve banking system for Farming Simulator 25.

[![Version](https://img.shields.io/badge/version-1.1.0.0-blue.svg)](https://www.farming-simulator.com/mod.php?mod_id=361360&title=fs2025)
[![FS25](https://img.shields.io/badge/FS25-compatible-green.svg)](https://farming-simulator.com/)
[![Multiplayer](https://img.shields.io/badge/multiplayer-supported-success.svg)](#)
[![Languages](https://img.shields.io/badge/languages-27-blue.svg)](#)
[![License](https://img.shields.io/badge/license-proprietary-red.svg)](LICENSE)

## Overview

FS25_BankCredit adds a standalone banking and credit system to Farming Simulator 25.

It replaces the vanilla loan system with a bank-based credit model where loan applications are evaluated using farm income, assets, existing debt, and available bank capacity.

> **Important:** Existing vanilla loans are automatically cleared when the save starts. The remaining loan amount is deducted from the farm balance.

## Features

* Standalone banking system with configurable capital and lending capacity
* Three loan types: Annuity, Bullet, and Revolving
* Credit assessment based on farm income, assets, and existing debt
* Risk-based interest rates with refusal reasons
* Configurable base rate (1.25–5.75%) with persistent monthly market trends
* Early repayment support for Annuity and Bullet loans
* Revolving credit lines with draw, repayment, and close controls
* Bank indicators dashboard
* Annual financial report per farm
* Separate Interest and Principal entries in the Finance tab
* Multiplayer and dedicated server support
* 27 supported languages
* Compatible with FS25_Invoices and FS25_RedTape

## Installation

### From ModHub

Download from the official [Farming Simulator ModHub](https://www.farming-simulator.com/mod.php?mod_id=361360&title=fs2025).

### Manual Installation

1. Place the downloaded `FS25_BankCredit.zip` file into your Farming Simulator 25 `mods/` directory (do not extract)
2. Launch Farming Simulator 25
3. Activate the mod in the mod selection screen

## Usage

Once enabled, the mod adds a **Bank** tab to the InGame Menu.

From the Bank tab, you can:

* Apply for new loans
* View active and completed loans
* Review loan details and payment schedules
* Repay loans early
* Draw from or repay revolving credit lines
* Close revolving credit lines when their balance is zero
* Check bank indicators
* View annual farm reports

## Settings

Bank settings are available in the game settings menu and are server-controlled in multiplayer.

Configurable options include:

* Starting capital
* Leverage ratio
* Dynamic interest rate with persistent monthly market trends
* Base interest rate (1.25–5.75%)
* Early repayment penalty

Changing the starting capital during an existing save adjusts the bank capital without resetting the bank.

## Compatibility

FS25_BankCredit automatically integrates with:

* **FS25_Invoices**: invoice income counts toward credit scoring
* **FS25_RedTape**: subsidy and grant income counts toward credit scoring

## Storage

Bank data is saved with the current savegame in:

`bankCredit.xml`

## Changelog

### v1.1.0.0

* Revolving credit limits now follow leverage-ratio changes
* Reworked dynamic interest rates into persistent monthly market trends with stable, normal, strong, and exceptional movements
* Adjusted the configurable base-rate range to 1.25–5.75%
* Improved multiplayer safety: bank and loan state is now only synced from the host, preventing corrupted or tampered data on clients. Thanks to [**KeilerHirsch**](https://github.com/KeilerHirsch)
* Existing saved base rates above 5.75% are automatically capped at 5.75%
* Added compatibility with FS25_additionalCurrencies: amount fields for loans, repayments, and revolving draws now accept values in the active converted currency

### v1.0.1.0

* Fixed multiplayer synchronization of paid loans and annual reports
* Fixed Bank tab display in the menu
* Fixed repayment and draw amount fields accepting letters
* Added full translation coverage for all 27 supported languages

### v1.0.0.0

* Initial release

## Support

* [GitHub Issues](https://github.com/Squallqt/FS25_BankCredit/issues)
* [GitHub Discussions](https://github.com/Squallqt/FS25_BankCredit/discussions)

## License

Copyright © 2026 Squallqt. All rights reserved.

This project is proprietary software and is not distributed under an
open-source license.

Downloading an official release for private use with Farming Simulator 25 is
permitted. Copying, modifying, converting, redistributing, reuploading,
commercializing, or reusing any part of this project requires prior written
authorization.

See the [LICENSE](LICENSE) file for the complete terms.
