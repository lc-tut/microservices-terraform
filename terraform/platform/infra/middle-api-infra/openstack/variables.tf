variable "vm_config" {
  description = "lcn-infra-api 用 VM 1台。image_id・flavor_id・subnet_id・keypair は接続先の実値を指定する。"
  type = object({
    image_id          = string
    flavor_id         = string
    subnet_id         = string
    keypair_name      = string
    root_volume_size  = number
    floating_ip_pool  = optional(string)
    ssh_allowed_cidrs = set(string)
    # 認証済み reverse proxy の実送信元だけを指定。空なら API 非公開。
    api_allowed_cidrs = optional(set(string), [])
    # billing の管理 API を利用する Terraform 実行元だけを指定。
    admin_allowed_cidrs = optional(set(string), [])
  })
  nullable = false

  validation {
    condition = alltrue([for vm in [var.vm_config] : alltrue([
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", vm.image_id)),
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", vm.subnet_id)),
      length(trimspace(vm.flavor_id)) > 0,
      length(trimspace(vm.keypair_name)) > 0,
      vm.root_volume_size >= 1 && floor(vm.root_volume_size) == vm.root_volume_size,
      vm.floating_ip_pool == null ? true : length(trimspace(vm.floating_ip_pool)) > 0,
    ])])
    error_message = "image_id / subnet_id は UUID、flavor_id / keypair_name / 指定する pool は空以外、root_volume_size は正の整数 GB にしてください。"
  }

  validation {
    condition = alltrue([for vm in [var.vm_config] :
      length(vm.ssh_allowed_cidrs) > 0 && alltrue([
        for cidr in setunion(vm.ssh_allowed_cidrs, vm.api_allowed_cidrs, vm.admin_allowed_cidrs) :
        can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) > 0, false)
      ])
    ])
    error_message = "SSH 送信元を1件以上指定してください。許可元は IPv4 CIDR に限定し、全世界向け /0 は指定できません。"
  }

  validation {
    condition     = length(var.vm_config.admin_allowed_cidrs) == 0
    error_message = "admin_allowed_cidrs (8081) は billing のみ指定できます。"
  }
}
