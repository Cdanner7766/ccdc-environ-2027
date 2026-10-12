<?php
// Database connection helper. Reads committed config.php.
function starbar_db() {
    $cfg = require __DIR__ . '/config.php';
    $db = @new mysqli($cfg['host'], $cfg['user'], $cfg['pass'], $cfg['name'], (int)$cfg['port']);
    if ($db->connect_errno) {
        http_response_code(500);
        die('DB connection failed');
    }
    return $db;
}
