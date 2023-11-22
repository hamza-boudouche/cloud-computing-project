variable "worker_no" {
  type    = number
  default = 2
}

resource "google_compute_firewall" "externalssh" {
  name    = "firewall-external-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["externalssh"]
}

resource "google_compute_firewall" "internal" {
  name    = "allow-all-internal"
  network = "default"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "tcp"
  }
  source_ranges = ["10.0.0.0/24"]
  target_tags   = ["internal"]
}

resource "google_compute_subnetwork" "default" {
  name          = "locust-subnet"
  network       = "default"
  ip_cidr_range = "10.0.0.0/24"
}

resource "google_compute_router" "router" {
  name    = "my-router"
  region  = google_compute_subnetwork.default.region
  network = "default"

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "nat" {
  name                               = "my-router-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_instance" "bastion" {
  name = "bastion"
  tags = ["externalssh", "internal"]
  labels = {
    "ansible" = "loadgen"
    "role"    = "master"
  }
  machine_type = "f1-micro"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  network_interface {
    network    = "default"
    subnetwork = google_compute_subnetwork.default.id
    access_config {
        }
  }

  metadata = {
    ssh-keys = "gcp:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling {
    provisioning_model = "SPOT"
    preemptible        = true
    automatic_restart  = false
  }

  depends_on = ["google_compute_firewall.externalssh", "google_compute_firewall.internal"]
}

resource "google_compute_instance" "locust_master" {
  name = "master"
  tags = ["internal"]
  labels = {
    "ansible" = "loadgen"
    "role"    = "master"
  }
  machine_type = "f1-micro"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  network_interface {
    network    = "default"
    subnetwork = google_compute_subnetwork.default.id
    network_ip = "10.0.0.10"
  }

  metadata = {
    ssh-keys = "gcp:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling {
    provisioning_model = "SPOT"
    preemptible        = true
    automatic_restart  = false
  }

  depends_on = ["google_compute_firewall.internal"]
}

resource "google_compute_instance" "locust_worker" {
  count = var.worker_no
  tags  = ["internal"]
  name  = "worder-${count.index}"
  labels = {
    "ansible" = "loadgen"
    "role"    = "worker"
  }
  machine_type = "f1-micro"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  network_interface {
    network    = "default"
    subnetwork = google_compute_subnetwork.default.id
    network_ip = "10.0.0.2${count.index}"
  }

  metadata = {
    ssh-keys = "gcp:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling {
    provisioning_model = "SPOT"
    preemptible        = true
    automatic_restart  = false
  }

  depends_on = ["google_compute_firewall.internal"]
}

// put these in the root module instead
output "worker_no" {
  value = var.worker_no
}

output "bastion_ip" {
  value = google_compute_instance.bastion.network_interface.0.access_config.0.nat_ip
}

