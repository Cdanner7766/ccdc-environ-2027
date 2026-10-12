<?php
// Menu page — reads the shared menu table from Ashla (DB read path #2).
// No user input: this page is NOT injectable. Wookie's weakness is the FTP
// service + the DB credential sitting in config.php, not a second SQLi.
require __DIR__ . '/db.php';
$db = starbar_db();
$res = $db->query("SELECT name, description, price_cents, category FROM menu ORDER BY category, name");
echo "<!doctype html><html><head><title>STAR BARS Menu</title></head><body>";
echo "<h1>Menu</h1><table border='1' cellpadding='6'><tr><th>Item</th><th>Category</th><th>Description</th><th>Price</th></tr>";
if ($res) {
    while ($row = $res->fetch_assoc()) {
        printf("<tr><td>%s</td><td>%s</td><td>%s</td><td>\$%.2f</td></tr>",
            htmlspecialchars($row['name']), htmlspecialchars($row['category']),
            htmlspecialchars($row['description']), $row['price_cents'] / 100);
    }
}
echo "</table></body></html>";
