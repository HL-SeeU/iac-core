output "hostname" {
  value       = "${var.sub_domain}.${var.main_domain}"
  description = "Dockhand hostname used by the HTTPS router and DNS record."
}
