-- bdev-trucking-company schema (also auto-created on resource start)

CREATE TABLE IF NOT EXISTS `truckco_companies` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(64) NOT NULL,
    `owner` VARCHAR(64) NOT NULL,
    `property` VARCHAR(64) NOT NULL,
    `balance` BIGINT NOT NULL DEFAULT 0,
    `reputation` INT NOT NULL DEFAULT 50,
    `upgrades` LONGTEXT NULL,
    `settings` LONGTEXT NULL,
    `layout` LONGTEXT NULL,
    `signs` LONGTEXT NULL,
    `last_payroll` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_property` (`property`),
    UNIQUE KEY `uq_owner` (`owner`)
);

CREATE TABLE IF NOT EXISTS `truckco_employees` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `company_id` INT NOT NULL,
    `kind` VARCHAR(8) NOT NULL DEFAULT 'npc',
    `citizenid` VARCHAR(64) NULL,
    `name` VARCHAR(64) NOT NULL,
    `role` VARCHAR(16) NOT NULL DEFAULT 'driver',
    `skill` INT NOT NULL DEFAULT 10,
    `wage` INT NOT NULL DEFAULT 500,
    `certs` LONGTEXT NULL,
    `status` VARCHAR(16) NOT NULL DEFAULT 'idle',
    `training_cert` VARCHAR(32) NULL,
    `training_until` INT NULL,
    `pending_pay` INT NOT NULL DEFAULT 0,
    `jobs_done` INT NOT NULL DEFAULT 0,
    `hired_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_citizen` (`citizenid`),
    KEY `idx_company` (`company_id`),
    CONSTRAINT `fk_emp_company` FOREIGN KEY (`company_id`) REFERENCES `truckco_companies` (`id`) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS `truckco_trucks` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `company_id` INT NOT NULL,
    `model` VARCHAR(32) NOT NULL,
    `plate` VARCHAR(8) NOT NULL,
    `health` INT NOT NULL DEFAULT 100,
    `mileage` FLOAT NOT NULL DEFAULT 0,
    `insurance` VARCHAR(16) NOT NULL DEFAULT 'none',
    `status` VARCHAR(16) NOT NULL DEFAULT 'available',
    `price` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_plate` (`plate`),
    KEY `idx_company` (`company_id`),
    CONSTRAINT `fk_truck_company` FOREIGN KEY (`company_id`) REFERENCES `truckco_companies` (`id`) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS `truckco_contracts` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `cargo` VARCHAR(32) NOT NULL,
    `trailer` VARCHAR(32) NULL,
    `pickup` LONGTEXT NOT NULL,
    `dropoff` LONGTEXT NOT NULL,
    `distance` FLOAT NOT NULL,
    `max_pay` INT NOT NULL,
    `market_bid` INT NOT NULL,
    `status` VARCHAR(16) NOT NULL DEFAULT 'open',
    `bid_closes` INT NOT NULL,
    `company_id` INT NULL,
    `award_amount` INT NULL,
    `employee_id` INT NULL,
    `truck_id` INT NULL,
    `assigned_by` VARCHAR(16) NULL,
    `driver_kind` VARCHAR(8) NULL,
    `awarded_at` INT NULL,
    `deadline` INT NULL,
    `started_at` INT NULL,
    `eta` INT NULL,
    `finished_at` INT NULL,
    `created_at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_status` (`status`),
    KEY `idx_company` (`company_id`)
);

CREATE TABLE IF NOT EXISTS `truckco_bids` (
    `contract_id` INT NOT NULL,
    `company_id` INT NOT NULL,
    `amount` INT NOT NULL,
    `auto` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` INT NOT NULL,
    PRIMARY KEY (`contract_id`, `company_id`),
    CONSTRAINT `fk_bid_contract` FOREIGN KEY (`contract_id`) REFERENCES `truckco_contracts` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_bid_company` FOREIGN KEY (`company_id`) REFERENCES `truckco_companies` (`id`) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS `truckco_ledger` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `company_id` INT NOT NULL,
    `amount` BIGINT NOT NULL,
    `reason` VARCHAR(128) NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_company` (`company_id`),
    CONSTRAINT `fk_ledger_company` FOREIGN KEY (`company_id`) REFERENCES `truckco_companies` (`id`) ON DELETE CASCADE
);
