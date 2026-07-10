resource "random_password" "postgres_app" {
  length  = 32
  special = false
}

resource "random_password" "redis" {
  length  = 32
  special = false
}

resource "random_password" "api_gateway_jwt" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "postgres_app" {
  name                    = local.postgres_secret_name
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "postgres_app" {
  secret_id = aws_secretsmanager_secret.postgres_app.id

  secret_string = jsonencode({
    username = "app"
    password = random_password.postgres_app.result
  })
}

resource "aws_secretsmanager_secret" "redis" {
  name                    = local.redis_secret_name
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id

  secret_string = jsonencode({
    password = random_password.redis.result
  })
}

resource "aws_secretsmanager_secret" "api_gateway" {
  name                    = local.api_gateway_secret_name
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "api_gateway" {
  secret_id = aws_secretsmanager_secret.api_gateway.id

  secret_string = jsonencode({
    JWT_SECRET = random_password.api_gateway_jwt.result
  })
}
