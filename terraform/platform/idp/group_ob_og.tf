# Keystone federation mapping の対象外にすることで LC-Cloud アクセスを持たせない
resource "authentik_group" "ob_og" {
  name         = "ob-og"
  is_superuser = false
}
