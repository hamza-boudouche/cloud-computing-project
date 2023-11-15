provider "google" {
    credentials = "${file("terraform.json")}"
        project     = var.project
        region      = var.region
        zone        = var.zone
}

variable "frontend_ip" {
    type= string
}

resource "google_compute_firewall" "externalssh" {
  name    = "gh-9564-firewall-externalssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["externalssh"]
}

resource "google_compute_instance" "vm_instance" {
    name         = "${var.instance-name}"
    tags         = ["externalssh"]
    labels = {
        "ansible" = "loadgen"
    }
    machine_type = "f1-micro"

    boot_disk {
        initialize_params {
            image = "ubuntu-os-cloud/ubuntu-2204-lts"
        }
    }

    network_interface {
        network       = "default"
        access_config {
        }
    }

    metadata = {
        ssh-keys = "gcp:${file("~/.ssh/id_rsa.pub")}"
    }

    scheduling {
        provisioning_model = "SPOT"
        preemptible = true
        automatic_restart = false
    }

    depends_on = ["google_compute_firewall.externalssh"]
}

output "ip" {
    value = "${google_compute_instance.vm_instance.network_interface.0.access_config.0.nat_ip}"
}

