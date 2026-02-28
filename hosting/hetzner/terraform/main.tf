# =============================================================================
# CORE - Hetzner Cloud Infrastructure
# =============================================================================
# Provisions: Server, Firewall, Network, Volume, SSH Key
# Usage:
#   1. export HCLOUD_TOKEN="your-token"
#   2. terraform init
#   3. terraform plan
#   4. terraform apply
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

# =============================================================================
# Variables
# =============================================================================

variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "server_name" {
  description = "Name of the server"
  type        = string
  default     = "core-empire"
}

variable "server_type" {
  description = "Hetzner server type (CX22=2vCPU/4GB, CX32=4vCPU/8GB, CX42=8vCPU/16GB)"
  type        = string
  default     = "cx42"
}

variable "location" {
  description = "Hetzner datacenter location (nbg1=Nuremberg, fsn1=Falkenstein, hel1=Helsinki)"
  type        = string
  default     = "nbg1"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "domain" {
  description = "Domain name for the CORE instance (e.g. core.yourdomain.com)"
  type        = string
}

variable "volume_size" {
  description = "Size of the persistent data volume in GB"
  type        = number
  default     = 50
}

variable "image" {
  description = "OS image for the server"
  type        = string
  default     = "ubuntu-24.04"
}

# =============================================================================
# SSH Key
# =============================================================================

resource "hcloud_ssh_key" "core" {
  name       = "${var.server_name}-key"
  public_key = file(var.ssh_public_key_path)
}

# =============================================================================
# Network (Private)
# =============================================================================

resource "hcloud_network" "core" {
  name     = "${var.server_name}-network"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "core" {
  network_id   = hcloud_network.core.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

# =============================================================================
# Firewall
# =============================================================================

resource "hcloud_firewall" "core" {
  name = "${var.server_name}-firewall"

  # SSH
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTP
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

# =============================================================================
# Persistent Volume
# =============================================================================

resource "hcloud_volume" "data" {
  name     = "${var.server_name}-data"
  size     = var.volume_size
  location = var.location
  format   = "ext4"
}

# =============================================================================
# Server
# =============================================================================

resource "hcloud_server" "core" {
  name        = var.server_name
  server_type = var.server_type
  location    = var.location
  image       = var.image
  ssh_keys    = [hcloud_ssh_key.core.id]

  firewall_ids = [hcloud_firewall.core.id]

  user_data = templatefile("${path.module}/cloud-init.yaml", {
    domain = var.domain
  })

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  labels = {
    app     = "core"
    env     = "production"
    managed = "terraform"
  }
}

# Attach server to private network
resource "hcloud_server_network" "core" {
  server_id  = hcloud_server.core.id
  network_id = hcloud_network.core.id
  ip         = "10.0.1.10"
}

# Attach volume to server
resource "hcloud_volume_attachment" "data" {
  volume_id = hcloud_volume.data.id
  server_id = hcloud_server.core.id
  automount = true
}

# =============================================================================
# Outputs
# =============================================================================

output "server_ipv4" {
  description = "Public IPv4 address of the server"
  value       = hcloud_server.core.ipv4_address
}

output "server_ipv6" {
  description = "Public IPv6 address of the server"
  value       = hcloud_server.core.ipv6_address
}

output "server_status" {
  value = hcloud_server.core.status
}

output "volume_linux_device" {
  description = "Linux device path for the data volume"
  value       = hcloud_volume.data.linux_device
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh root@${hcloud_server.core.ipv4_address}"
}

output "deploy_command" {
  description = "Deploy command"
  value       = "cd hosting/hetzner && ./scripts/deploy.sh root@${hcloud_server.core.ipv4_address}"
}
