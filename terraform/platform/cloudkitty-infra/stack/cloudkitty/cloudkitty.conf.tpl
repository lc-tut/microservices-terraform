[DEFAULT]
debug = false
use_stderr = true
# api/processor 間 RPC は使わない。通知も出さない（Polaris は通知バス無効）。
transport_url = fake://

[oslo_messaging_notifications]
driver = noop

[api]
host_ip = 0.0.0.0
port = 8889

[database]
connection = mysql+pymysql://cloudkitty:__CK_DB_PASSWORD__@mariadb:3306/cloudkitty?charset=utf8

[keystone_authtoken]
# 受信トークンの検証先 = Polaris(Kolla) の Keystone。
# terraform/platform/cloudkitty/ は Polaris トークンでこの API を叩くので一致必須。
www_authenticate_uri = http://192.168.1.210:5000
auth_url = http://192.168.1.210:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = admin
username = admin
password = __OS_ADMIN_PASSWORD__
region_name = RegionOne
service_token_roles_required = false
memcache_servers =

[collect]
collector = prometheus
scope_key = project_id
metrics_conf = /etc/cloudkitty/metrics.yml
period = 3600
# 直近 period をすぐ処理させる（既定 2）
wait_periods = 0

[fetcher]
backend = keystone

[fetcher_keystone]
keystone_version = 3
ignore_rating_role = true
ignore_disabled_tenants = true
auth_type = password
auth_url = http://192.168.1.210:5000
project_domain_name = Default
user_domain_name = Default
project_name = admin
username = admin
password = __OS_ADMIN_PASSWORD__
region_name = RegionOne

[collector_prometheus]
prometheus_url = http://prometheus:9090/api/v1

[storage]
backend = influxdb
version = 2

[storage_influxdb]
host = influxdb
port = 8086
database = cloudkitty
version = 1
use_ssl = false

[rating]
# hashmap モジュールは deploy.sh が API 経由で enable する。
