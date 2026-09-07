# terraform/platform/openstack/network を staging に向けて apply するときの変数。
#   staging/terraform/tf.sh platform/openstack/network plan

# DevStack が作る外部ネットワークの名前。本番は ext-net
external_network_name = "public"
