output "enabled" {
  value = local.observability_enabled
}

output "tracing_endpoint" {
  description = "Internal OTLP HTTP traces endpoint; empty when collection is disabled."
  value       = local.observability_enabled ? "http://${local.alloy_name}:4318/v1/traces" : ""
}
