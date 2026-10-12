<?php
// -----------------------------------------------------------------------------
// Payment lookup endpoint.
//
// INTENTIONALLY VULNERABLE (SQL injection via the `id` parameter) for use as a
// static blue-team training target inside an isolated CCDC range. The user
// input is concatenated directly into the query with no parameterization.
// This file contains NO attack code — it is a vulnerable service, not an
// exploit. Do not deploy outside the range.
// -----------------------------------------------------------------------------
require __DIR__ . '/db.php';
$db = starbar_db();

$id = isset($_GET['id']) ? $_GET['id'] : '1';

// Vulnerable: unsanitized string concatenation (the training defect).
$sql = "SELECT p.id, c.first_name, c.last_name, p.amount_cents, p.memo "
     . "FROM payments p JOIN customers c ON c.id = p.customer_id "
     . "WHERE p.customer_id = " . $id;

$res = $db->query($sql);
header('Content-Type: text/plain');
if (!$res) {
    echo "Query error: " . $db->error;
    exit;
}
while ($row = $res->fetch_assoc()) {
    printf("#%d  %s %s  \$%.2f  %s\n",
        $row['id'], $row['first_name'], $row['last_name'],
        $row['amount_cents'] / 100, $row['memo']);
}
