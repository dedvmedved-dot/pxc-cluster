terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.1"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_volume" "ubuntu_image" {
  name   = "ubuntu-22.04-server-cloudimg-amd64.img"
  source = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
  pool   = "default"
  format = "qcow2"
}

data "template_file" "user_data" {
  template = file("${path.module}/cloud-init.yaml")
  vars     = { ssh_key = file("~/.ssh/id_rsa.pub") }
}

locals {
  nodes = {
    pxc1 = { name = "pxc-node1", ip = "192.168.122.31" }
    pxc2 = { name = "pxc-node2", ip = "192.168.122.32" }
    pxc3 = { name = "pxc-node3", ip = "192.168.122.33" }
  }
}

resource "libvirt_volume" "disk" {
  for_each       = local.nodes
  name           = "${each.key}-disk.qcow2"
  base_volume_id = libvirt_volume.ubuntu_image.id
  pool           = "default"
  size           = 21474836480
}

resource "libvirt_cloudinit_disk" "init" {
  for_each  = local.nodes
  name      = "${each.key}-cloudinit.iso"
  pool      = "default"
  user_data = data.template_file.user_data.rendered
}

resource "libvirt_domain" "vm" {
  for_each  = local.nodes
  name      = each.value.name
  memory    = 2048
  vcpu      = 2
  cloudinit = libvirt_cloudinit_disk.init[each.key].id

  network_interface {
    network_name = "default"
  }

  disk {
    volume_id = libvirt_volume.disk[each.key].id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}
