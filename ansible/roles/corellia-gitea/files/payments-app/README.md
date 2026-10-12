# StarBar Payments

Internal payment-lookup service for the Cantina POS. PHP + MariaDB.

## Configuration

Database settings live in `config.php` (host, database, and the application
DB account credentials). Deployed to the Tython web host.

## Endpoints

- `index.php` — landing page
- `pay.php?id=<customer_id>` — list a customer's payments
