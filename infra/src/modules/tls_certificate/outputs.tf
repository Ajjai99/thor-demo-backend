output "certificate_pem" {
  description = "Leaf certificate (PEM), no chain — concatenate with certificate_chain_pem for the full chain nginx needs."
  value       = acme_certificate.sidecar.certificate_pem
  sensitive   = true
}

output "certificate_chain_pem" {
  description = "Let's Encrypt's intermediate certificate(s) (PEM)."
  value       = acme_certificate.sidecar.issuer_pem
  sensitive   = true
}

output "private_key_pem" {
  description = "Private key (PEM) for certificate_pem."
  value       = acme_certificate.sidecar.private_key_pem
  sensitive   = true
}
