locals {
  webhook_url     = "https://api.github.com/repos/${var.github_repo_owner}/${var.github_repo_name}/dispatches"
  webhook_enabled = var.webhook_secret != ""
}

# enrollment 完了 → auto-gen-members.yaml 更新
resource "authentik_event_transport" "enrollment_webhook" {
  count = local.webhook_enabled ? 1 : 0

  name = "enrollment-completed-webhook"
  mode = "webhook"

  webhook_url          = local.webhook_url
  webhook_mapping_body = authentik_property_mapping_notification.enrollment_payload[0].id
  send_once            = false
}

resource "authentik_property_mapping_notification" "enrollment_payload" {
  count = local.webhook_enabled ? 1 : 0

  name       = "enrollment-dispatch-payload"
  expression = <<-PYTHON
    return {
      "event_type": "authentik-enrollment-completed",
      "client_payload": {
        "username":     notification.event.context.get("model", {}).get("username", ""),
        "display_name": notification.event.context.get("model", {}).get("name", ""),
        "email":        notification.event.context.get("model", {}).get("email", ""),
      }
    }
  PYTHON
}

# GitHub 連携変更（source_linked / source_unlinked）→ auto-gen-github-usernames.yaml 更新
resource "authentik_event_transport" "github_link_webhook" {
  count = local.webhook_enabled ? 1 : 0

  name = "github-source-linked-webhook"
  mode = "webhook"

  webhook_url          = local.webhook_url
  webhook_mapping_body = authentik_property_mapping_notification.github_link_payload[0].id
  send_once            = false
}

resource "authentik_property_mapping_notification" "github_link_payload" {
  count = local.webhook_enabled ? 1 : 0

  name       = "github-link-dispatch-payload"
  expression = <<-PYTHON
    event_type = notification.event.action  # source_linked or source_unlinked
    return {
      "event_type": f"authentik-{event_type}",
      "client_payload": {
        "username":          notification.event.user.get("username", ""),
        "source":            notification.event.context.get("source", {}).get("slug", ""),
        "github_identifier": str(notification.event.context.get("identifier", "")),
      }
    }
  PYTHON
}
