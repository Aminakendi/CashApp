# CashApp: System Architecture & Technical Documentation

This document provides both high-level and low-level architectural details of the CashApp Personal Finance Tracker. It is designed to act as a living document for senior engineers, outlining design decisions, data flow, and core processing engines.

## 1. High-Level Architecture

The application follows a strictly **offline-first, localized processing model**. There is zero reliance on external banking APIs. Instead, financial data is sourced directly from the device's SMS inbox.

### Architectural Layers
1. **Presentation Layer (UI)**: Built with Flutter. Uses a reactive, component-based UI with Glassmorphism aesthetics.
2. **State Management**: Handled via **Riverpod**. UI components listen to `StreamProviders` that react directly to database changes.
3. **Business Logic / Service Layer**: Contains the SMS Parsing Engine, Categorization Engine, and Background Sync Coordinator.
4. **Data Access Layer (DAOs)**: Drift-generated Data Access Objects (e.g., `CategoryDao`, `AnalyticsDao`, `GoalsDao`) encapsulating complex SQL queries.
5. **Persistence Layer**: An AES-256 encrypted SQLite database (SQLCipher via Drift), ensuring financial data is safe at rest.

```mermaid
graph TD
    UI[Presentation Layer / Widgets] --> |Reads/Watches| State[Riverpod Providers]
    UI --> |Triggers| Services[Business Services]
    State --> |Streams| DAO[Data Access Objects]
    Services --> |Parses/Learns| SMS[SMS Inbox]
    Services --> |Writes| DAO
    DAO --> DB[(Encrypted SQLite)]
    Background[WorkManager (Headless)] --> |Syncs| Services
```

---

## 2. Low-Level Architecture & Components

### 2.1. Relational Database Schema (Drift)
The database enforces strict ACID properties with `PRAGMA foreign_keys = ON`.

*   **`transactions`**:
    *   `id` (Int, PK, Auto-increment)
    *   `amount` (Real, Not Null)
    *   `type` (Text, Enum: 'IN', 'OUT')
    *   `timestamp` (DateTime)
    *   `party` (Text) - Extracted Sender/Receiver/Merchant
    *   `reference` (Text, Unique) - The SMS transaction code (e.g., `PK98DF3L`). Enforced as unique to guarantee idempotency during background syncs.
    *   `balance` (Real)
    *   `categoryId` (Int, Nullable, FK -> `categories.id`)
*   **`categories`**:
    *   `id` (Int, PK). *Note: System categories use IDs 1-999. Custom user categories use IDs >= 1000.*
    *   `name` (Text), `iconName` (Text), `colorHex` (Text)
    *   `isSystem` (Bool) - Hard guard against accidental deletion.
*   **`category_rules`** (Auto-Learning Engine Persistence):
    *   `pattern` (Text, PK) - e.g., `DENNIS KIMANZI`
    *   `categoryId` (Int, FK -> `categories.id`)
*   **`savings_goals`** & **`budget_settings`**: Track user limits and targets.

### 2.2. SMS Ingestion & Sync Coordinator (`SmsSyncManager`)
*   **Mechanism**: Uses `workmanager` to register a headless background task.
*   **Flow**:
    1. OS wakes up the background task (approx. every 1-4 hours).
    2. Reads the `last_sync_timestamp` from `SharedPreferences`.
    3. Queries `flutter_sms_inbox` for messages from `MPESA` and `KCB` newer than the timestamp.
    4. Passes raw bodies to the **Parsing Engine**.
    5. Dispatches parsed data to the **Categorization Engine**.
    6. Executes `INSERT OR IGNORE` into the `transactions` table.
*   **Idempotency**: Because M-Pesa codes are universally unique, `INSERT OR IGNORE` guarantees that overlapping sync windows never duplicate a transaction.

### 2.3. Regex Parsing Engine
The parser utilizes sophisticated Regular Expressions to handle highly variable banking SMS formats.
*   **M-Pesa (`mpesa_parser.dart`)**:
    *   Handles "Send Money", "Paybill", "Buy Goods", "Fuliza M-Pesa", and incoming transfers.
    *   *Low-Level Regex Ex*: `(?<code=>[A-Z0-9]+) Confirmed\. Ksh(?<amount>[\d,.]+) paid to (?<party>.+?) on (?<date>\d{1,2}\/\d{1,2}\/\d{2}) at (?<time>\d{1,2}:\d{2} [AP]M)\.`
*   **KCB (`kcb_parser.dart`)**:
    *   Specifically handles bridging transactions between KCB Bank and M-Pesa.
    *   *Edge Cases Handled*: "transfered... from your KCB M-PESA account" (spelling errors present in actual bank SMS).

### 2.4. Auto-Learning Categorization Engine
This is a closed-loop feedback system ensuring the app adapts to the user's specific spending habits.

1.  **Ingestion Phase (`resolveCategoryForText`)**:
    *   When a transaction is parsed, the engine queries the `category_rules` table using the `party` string (e.g., `SELECT categoryId FROM category_rules WHERE pattern = 'NAIVAS SUPERMARKET'`).
    *   If a rule exists, it applies the associated `categoryId`.
    *   If no rule exists, it falls back to Hardcoded Regex Heuristics (e.g., `party.contains('KPLC') -> Bills`).
2.  **Learning Phase (`learnCategoryRule`)**:
    *   If a user manually edits a transaction and changes the category, the app fires an upsert:
        `INSERT INTO category_rules (pattern, categoryId) VALUES (party, new_category) ON CONFLICT(pattern) DO UPDATE SET categoryId = excluded.categoryId;`
    *   The next time this `party` is encountered, Phase 1 will automatically route it to the new category.

### 2.5. Category Lifecycle & Integrity Guards
To prevent orphaned transactions and data corruption, `CategoryDao` enforces strict low-level rules:
*   **Deletion Guard**: `deleteCategory()` checks `SELECT COUNT(*) FROM transactions WHERE categoryId = X`. If count > 0, it throws a `StateError`.
*   **Bulk Reassignment**: The UI requires the user to pick a new destination category. The DAO runs an atomic transaction:
    1. `UPDATE transactions SET categoryId = new_id WHERE categoryId = old_id;`
    2. `DELETE FROM categories WHERE id = old_id;`

## 3. DevOps & Contribution Guidelines
*   **Code Generation**: Modifying database schemas or providers requires running `dart run build_runner build --delete-conflicting-outputs`.
*   **Testing**: All parsers (`mpesa_parser_test.dart`, `kcb_parser_test.dart`) must have 100% test coverage against real-world SMS strings before merging to `main`.
*   **Building**: Do not use `flutter install` for testing. Use `flutter run` to perform in-place updates and preserve local SQLCipher databases. Release builds require proper keystore configurations as defined in `android/app/build.gradle`.

---
*Last Updated: 2026-09-21*
