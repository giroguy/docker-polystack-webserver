-- WordPress shared user (used by all WP sites via getenv in wp-config.php)
-- Update password to match MYSQL_PASSWORD in .env
CREATE USER IF NOT EXISTS 'wordpress'@'%' IDENTIFIED BY 'changeme';

-- Add one entry per WordPress site:
-- CREATE DATABASE IF NOT EXISTS `mysite` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
-- GRANT ALL PRIVILEGES ON `mysite`.* TO 'wordpress'@'%';

FLUSH PRIVILEGES;
