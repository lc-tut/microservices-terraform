# terraform/platform/openstack/network を staging に向けて apply するときの変数。
#   staging/terraform/tf.sh platform/openstack/network plan
#
# この root は int-router・internal-net・subnetpool・ext-subnet を**すべて作る**ので、
# staging 用に仮のルーターを別途用意する必要はない。本番と同じ実装をそのまま使い、
# DevStack に合わせた値だけをここで上書きする。

# DevStack が作る外部ネットワークの名前。本番は ext-net
external_network_name = "public"

# ext-subnet は DevStack が既に public-subnet として作っている（FLOATING_RANGE）。
# 同じネットワーク上に CIDR の重なるサブネットは作れないので、
# **既存のものを import して管理下に置く**（本番で RBAC ポリシーを import するのと同じ形）:
#
#   SUBNET=$(openstack subnet show public-subnet -f value -c id)
#   staging/terraform/tf.sh platform/openstack/network \
#     import openstack_networking_subnet_v2.external "$SUBNET"
#
#   RBAC=$(openstack network rbac list --type network --action access_as_external -f value -c ID | head -1)
#   staging/terraform/tf.sh platform/openstack/network \
#     import openstack_networking_rbac_policy_v2.ext_net_external "$RBAC"
#
# import したあとの plan が空になるまで、下の値を実機に合わせて直すこと。
# DevStack の既定はこの値だが、FLOATING_RANGE を変えていればずれる。
external_subnet_cidr       = "172.24.4.0/24"
external_subnet_gateway    = "172.24.4.1"
external_subnet_pool_start = "172.24.4.2"
external_subnet_pool_end   = "172.24.4.254"

# 内部側は DevStack の既定（private 10.0.0.0/26・trove-mgmt 192.168.254.0/24・
# br-ex 172.24.4.0/24）と重ならないので、本番と同じ既定のまま使える。
# internal_subnet_cidr = "172.16.192.0/19"
# subnetpool_prefix    = "172.16.224.0/19"

# DevStack の bootstrap がサブネットに設定しているものに揃える
dns_nameservers = ["8.8.8.8"]
