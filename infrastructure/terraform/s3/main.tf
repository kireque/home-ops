terraform {
  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "0.9.0"
    }

    minio = {
      source = "aminueza/minio"
      version = "2.5.1"
    }
  }
}
