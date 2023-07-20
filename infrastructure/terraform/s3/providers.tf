provider "minio" {
  alias  = "nas"
  minio_server   = "s3econline.local"
  minio_user     = module.onepassword_item_minio.fields.username
  minio_password = module.onepassword_item_minio.fields.password
}
