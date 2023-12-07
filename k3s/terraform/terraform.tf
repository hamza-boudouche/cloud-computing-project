terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  credentials = file(var.gcp_key)
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

resource "google_compute_network" "main_vpc" {
  name    = var.network_name
  project = var.project_id
}




resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22","80"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allowssh"]
}

resource "google_compute_router" "router" {
  name    = "${var.network_name}-router"
  network = "default"
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_instance" "master" {
  count        = var.master_instance_count
  name         = "master-instance-${count.index}"
  machine_type = var.instance_type
  zone         = var.zone
  tags = ["allowssh"]
  
  boot_disk {
    initialize_params {
      image = var.image_type
    }
  }

  metadata = {
    ssh-keys = "ansible:${file("../ssh_keys/ansible.pub")}"
  }

  scheduling {
    provisioning_model = "SPOT"
    preemptible        = true
    automatic_restart  = false
  }
  
  network_interface {
    network = "default"
    access_config {}
  }
  depends_on = [google_compute_firewall.allow_ssh]
}

resource "google_compute_instance" "node" {
  count        = var.nodes_instance_count
  name         = "node-instance-${count.index}"
  machine_type = var.instance_type
  zone         = var.zone
  tags = ["allowssh"]
  
  boot_disk {
    initialize_params {
      image = var.image_type
    }
  }

  metadata = {
    ssh-keys = "ansible:${file("../ssh_keys/ansible.pub")}"
  }

  scheduling {
    provisioning_model = "SPOT"
    preemptible        = true
    automatic_restart  = false
  }

  network_interface {
    network = "default"
    access_config {}
  }
  depends_on = [google_compute_firewall.allow_ssh]
}



output masters_ip {
  value = join(",",[for instance in google_compute_instance.master : instance.network_interface[0].access_config[0].nat_ip])
}

output workers_ip {
  value = join(",",[for instance in google_compute_instance.node : instance.network_interface[0].access_config[0].nat_ip])
}
