<?php
// Sanitize and retrieve the submitted data
$username = htmlspecialchars($_POST['username']);
$password = htmlspecialchars($_POST['password']);

// Validate the data (optional, for security)
if (empty($username) || empty($password)) {
    echo "Please fill in all fields.";
    exit;
}

// Example: Hardcoded check (replace with database authentication)
if ($username === "admin" && $password === "password123") {
    echo "Login successful. Welcome, $username!";
} else {
    echo "Invalid username or password.";
}
?>
