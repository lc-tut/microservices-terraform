terraform {
  required_version = "~> 1.10"
  # provider を必要としない純ロジックモジュール（18-access-control.md 参照）。
  # required_providers を空にすることで、呼び出し側の provider 構成に一切依存しない。
}
