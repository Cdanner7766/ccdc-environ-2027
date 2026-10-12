-- ============================================================================
-- Ashla — StarBar payments schema + seed  (ccdc-ashla-db role)
-- Imported into the payments DB. Idempotent: CREATE TABLE IF NOT EXISTS +
-- INSERT IGNORE on explicit primary keys, so re-import never duplicates.
--
-- INTENTIONAL TARGET DATA (static; no attack tooling):
--   - customers: synthetic PII (name/address/phone/email)  [packet -200]
--   - cards: PUBLIC TEST credit-card numbers only           [packet -50]
--   These PANs are the well-known vendor TEST numbers (Luhn-valid, never
--   issued to anyone). Do NOT replace with real card data.
-- ============================================================================

CREATE TABLE IF NOT EXISTS customers (
  id          INT PRIMARY KEY,
  first_name  VARCHAR(64)  NOT NULL,
  last_name   VARCHAR(64)  NOT NULL,
  address     VARCHAR(128) NOT NULL,
  city        VARCHAR(64)  NOT NULL,
  state       CHAR(2)      NOT NULL,
  zip         VARCHAR(10)  NOT NULL,
  phone       VARCHAR(20)  NOT NULL,
  email       VARCHAR(128) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cards (
  id           INT PRIMARY KEY,
  customer_id  INT NOT NULL,
  cardholder   VARCHAR(128) NOT NULL,
  pan          VARCHAR(19)  NOT NULL,   -- public TEST numbers only
  expiry       CHAR(5)      NOT NULL,   -- MM/YY
  cvv          CHAR(4)      NOT NULL,   -- synthetic
  brand        VARCHAR(16)  NOT NULL,
  CONSTRAINT fk_cards_customer FOREIGN KEY (customer_id) REFERENCES customers(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS payments (
  id           INT PRIMARY KEY,
  customer_id  INT NOT NULL,
  card_id      INT NOT NULL,
  amount_cents INT NOT NULL,
  ts           DATETIME NOT NULL,
  memo         VARCHAR(128) NOT NULL,
  CONSTRAINT fk_pay_customer FOREIGN KEY (customer_id) REFERENCES customers(id),
  CONSTRAINT fk_pay_card     FOREIGN KEY (card_id)     REFERENCES cards(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --- Customers (synthetic PII) ---------------------------------------------
INSERT IGNORE INTO customers (id, first_name, last_name, address, city, state, zip, phone, email) VALUES
 (1, 'Lando',  'Calrisco',  '12 Cloud Terrace',   'Bespin City', 'CA', '90210', '310-555-0142', 'lando@example.test'),
 (2, 'Dex',    'Jettster',  '88 Diner Row',       'Coco Town',   'CA', '90013', '213-555-0178', 'dex@example.test'),
 (3, 'Hera',   'Syndara',   '5 Phoenix Hangar',   'Lothal',      'NV', '89101', '702-555-0190', 'hera@example.test'),
 (4, 'Cassia', 'Andoran',   '41 Rebel Alley',     'Ferrix',      'AZ', '85001', '602-555-0133', 'cassia@example.test'),
 (5, 'Zev',    'Senesca',   '7 Echo Base Rd',     'Hothville',   'CO', '80202', '720-555-0166', 'zev@example.test'),
 (6, 'Bazine', 'Netalla',   '19 Takodana Lane',   'Niima',       'CA', '92101', '619-555-0155', 'bazine@example.test');

-- --- Cards (PUBLIC TEST PANs ONLY — never real numbers) --------------------
INSERT IGNORE INTO cards (id, customer_id, cardholder, pan, expiry, cvv, brand) VALUES
 (1, 1, 'LANDO CALRISCO', '4111111111111111', '04/28', '123', 'Visa'),
 (2, 2, 'DEX JETTSTER',   '4012888888881881', '09/27', '456', 'Visa'),
 (3, 3, 'HERA SYNDARA',   '5555555555554444', '11/29', '789', 'Mastercard'),
 (4, 4, 'CASSIA ANDORAN', '5105105105105100', '02/28', '321', 'Mastercard'),
 (5, 5, 'ZEV SENESCA',    '378282246310005',  '07/27', '1234','Amex'),
 (6, 6, 'BAZINE NETALLA', '6011111111111117', '12/28', '654', 'Discover');

-- --- Payments --------------------------------------------------------------
INSERT IGNORE INTO payments (id, customer_id, card_id, amount_cents, ts, memo) VALUES
 (1, 1, 1, 4200, '2026-01-10 21:14:00', 'Blue Milk x3 + cover charge'),
 (2, 2, 2, 1875, '2026-01-11 22:02:00', 'Pub menu - Pongs platter'),
 (3, 3, 3, 3300, '2026-01-12 20:40:00', 'Karaoke room - 1 hour'),
 (4, 4, 4, 2650, '2026-01-12 23:18:00', 'Bar tab'),
 (5, 5, 5, 5100, '2026-01-13 19:55:00', 'VIP booth + drinks'),
 (6, 6, 6, 1200, '2026-01-13 21:30:00', 'Encore fee');
