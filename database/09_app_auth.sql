CREATE TABLE IF NOT EXISTS app_user (
    user_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(32) NOT NULL UNIQUE,
    password_hash CHAR(97) NOT NULL,
    role ENUM('admin', 'warehouse', 'procurement', 'logistics') NOT NULL,
    failed_attempts INT UNSIGNED NOT NULL DEFAULT 0,
    retry_after DATETIME NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_session (
    token_hash BINARY(32) PRIMARY KEY,
    user_id INT UNSIGNED NOT NULL,
    expires_at DATETIME NOT NULL,
    INDEX idx_session_expiry (expires_at),
    FOREIGN KEY (user_id) REFERENCES app_user (user_id) ON DELETE CASCADE
) ENGINE=InnoDB;
