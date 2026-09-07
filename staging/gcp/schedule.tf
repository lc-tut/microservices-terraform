# 時刻ベースの自動起動・停止。
#
# アイドル検知（idle_shutdown_minutes）は「SSH が無い＝誰も使っていない」を
# 前提にしており、公開している staging では成り立たない。公開環境で稼働時間を
# 絞るならこちらを使う。**アクセスの有無は見ないので、使っている最中でも止まる。**

locals {
  # 公開しているときは既定でアイドル停止を無効にする。
  # 明示的に指定された値はそのまま尊重する
  idle_shutdown_minutes = (
    var.idle_shutdown_minutes != null
    ? var.idle_shutdown_minutes
    : (local.publish ? 0 : 45)
  )

  use_schedule = var.daily_start_time != "" || var.daily_stop_time != ""
}

resource "google_compute_resource_policy" "daily" {
  count  = local.use_schedule ? 1 : 0
  name   = "${var.name_prefix}-daily"
  region = var.region

  instance_schedule_policy {
    time_zone = var.schedule_time_zone

    dynamic "vm_start_schedule" {
      for_each = var.daily_start_time != "" ? [1] : []
      content {
        # 分 時 日 月 曜日
        schedule = "${split(":", var.daily_start_time)[1]} ${split(":", var.daily_start_time)[0]} * * *"
      }
    }

    dynamic "vm_stop_schedule" {
      for_each = var.daily_stop_time != "" ? [1] : []
      content {
        schedule = "${split(":", var.daily_stop_time)[1]} ${split(":", var.daily_stop_time)[0]} * * *"
      }
    }
  }
}

# インスタンススケジュールは Compute Engine のサービスエージェントが VM を
# start/stop するため、そのエージェントに権限が要る。付けないとスケジュールは
# 作成できても何も起きない（黙って効かない種類の設定）。
# https://cloud.google.com/compute/docs/instances/schedule-instance-start-stop
data "google_project" "this" {
  count      = local.use_schedule ? 1 : 0
  project_id = var.project_id
}

resource "google_project_iam_member" "compute_agent_instance_admin" {
  count   = local.use_schedule ? 1 : 0
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:service-${data.google_project.this[0].number}@compute-system.iam.gserviceaccount.com"
}
