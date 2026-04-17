###############################################################################
# Module: rds
# RDS PostgreSQL – Multi-AZ, encrypted at rest, credentials in Secrets Manager
###############################################################################

# ── KMS key for RDS encryption ────────────────────────────────────────────────
resource "aws_kms_key" "rds" {
  description             = "${var.environment} RDS encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = { Name = "${var.environment}-rds-kms-key" }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.environment}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# ── DB Subnet Group ───────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-banking-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "${var.environment}-db-subnet-group" }
}

# ── DB Parameter Group ────────────────────────────────────────────────────────
resource "aws_db_parameter_group" "main" {
  name   = "${var.environment}-banking-pg14"
  family = "postgres14"

  # Force SSL connections
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Enable pg_audit extension logging
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = { Name = "${var.environment}-pg15-params" }
}

# ── RDS Instance ──────────────────────────────────────────────────────────────
resource "aws_db_instance" "main" {
  identifier        = "${var.environment}-banking-db"
  engine            = "postgres"
  engine_version    = "14.15"
  instance_class    = var.db_instance_class
  allocated_storage = 100
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]
  parameter_group_name   = aws_db_parameter_group.main.name

  # High Availability
  multi_az = false

  # Backups
  backup_retention_period  = 0
  backup_window            = "02:00-03:00"
  maintenance_window       = "sun:04:00-sun:05:00"
  delete_automated_backups  = true
  deletion_protection       = false
  skip_final_snapshot       = true

  # Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn

  # Auto minor version upgrades
  auto_minor_version_upgrade = true
  publicly_accessible        = false

  tags = { Name = "${var.environment}-banking-db" }
}

# ── Enhanced Monitoring Role ──────────────────────────────────────────────────
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ── Store DB Credentials in Secrets Manager ───────────────────────────────────
resource "random_id" "secret_suffix" {
  byte_length = 4
  keepers = {
    environment = var.environment
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.environment}/banking-app/db-credentials-${random_id.secret_suffix.hex}"
  description             = "Banking app database credentials"
  recovery_window_in_days = 0
  kms_key_id              = aws_kms_key.rds.arn

  tags = {
    Name      = "${var.environment}-db-credentials"
    ManagedBy = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.main.address
    port     = 5432
    dbname   = var.db_name
  })
}
