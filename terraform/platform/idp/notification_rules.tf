resource "authentik_event_rule" "enrollment_completed" {
  count = local.webhook_enabled ? 1 : 0

  name              = "enrollment-completed"
  transports        = [authentik_event_transport.enrollment_webhook[0].id]
  severity          = "notice"
  destination_group = authentik_group.all_members.id
}

resource "authentik_policy_event_matcher" "enrollment_event" {
  count = local.webhook_enabled ? 1 : 0

  name   = "match-enrollment-model-created"
  action = "model_created"
  model  = "authentik_core.user"
}

resource "authentik_policy_binding" "enrollment_rule_policy" {
  count = local.webhook_enabled ? 1 : 0

  target = authentik_event_rule.enrollment_completed[0].id
  policy = authentik_policy_event_matcher.enrollment_event[0].id
  order  = 0
}

resource "authentik_event_rule" "github_source_change" {
  count = local.webhook_enabled ? 1 : 0

  name              = "github-source-change"
  transports        = [authentik_event_transport.github_link_webhook[0].id]
  severity          = "notice"
  destination_group = authentik_group.all_members.id
}

resource "authentik_policy_event_matcher" "source_linked_event" {
  count = local.webhook_enabled ? 1 : 0

  name   = "match-source-linked"
  action = "source_linked"
}

resource "authentik_policy_event_matcher" "source_unlinked_event" {
  count = local.webhook_enabled ? 1 : 0

  name   = "match-source-unlinked"
  action = "source_unlinked"
}

resource "authentik_policy_binding" "source_linked_rule" {
  count = local.webhook_enabled ? 1 : 0

  target = authentik_event_rule.github_source_change[0].id
  policy = authentik_policy_event_matcher.source_linked_event[0].id
  order  = 0
}

resource "authentik_policy_binding" "source_unlinked_rule" {
  count = local.webhook_enabled ? 1 : 0

  target = authentik_event_rule.github_source_change[0].id
  policy = authentik_policy_event_matcher.source_unlinked_event[0].id
  order  = 1
}
