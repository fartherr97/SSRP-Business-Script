CREATE TABLE IF NOT EXISTS businesses (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(80) NOT NULL,
    type VARCHAR(60) NOT NULL,
    owner_discord_id VARCHAR(25) NOT NULL,
    owner_display_name VARCHAR(80) NOT NULL,
    created_by VARCHAR(120) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    PRIMARY KEY (id),
    INDEX idx_businesses_owner (owner_discord_id),
    INDEX idx_businesses_type (type),
    INDEX idx_businesses_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS business_employees (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    business_id INT UNSIGNED NOT NULL,
    discord_id VARCHAR(25) NOT NULL,
    display_name VARCHAR(80) NOT NULL,
    title VARCHAR(80) NOT NULL DEFAULT 'Employee',
    added_by VARCHAR(120) NULL,
    added_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    PRIMARY KEY (id),
    INDEX idx_business_employees_business (business_id),
    INDEX idx_business_employees_discord (discord_id),
    INDEX idx_business_employees_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS business_shifts (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    business_id INT UNSIGNED NOT NULL,
    discord_id VARCHAR(25) NOT NULL,
    display_name VARCHAR(80) NOT NULL,
    shift_start DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    shift_end DATETIME NULL,
    total_minutes INT UNSIGNED NOT NULL DEFAULT 0,
    afk_minutes INT UNSIGNED NOT NULL DEFAULT 0,
    is_afk TINYINT(1) NOT NULL DEFAULT 0,
    status VARCHAR(30) NOT NULL DEFAULT 'active',
    PRIMARY KEY (id),
    INDEX idx_business_shifts_business (business_id),
    INDEX idx_business_shifts_discord (discord_id),
    INDEX idx_business_shifts_status (status),
    INDEX idx_business_shifts_active_lookup (discord_id, shift_end, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
