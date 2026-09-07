# billing: lcn-billing-api 用 VM

このディレクトリは lcn-billing-api 1台を管理する独立した Terraform root。
openstack/ の VM や state は変更しない。

- GCS prefix: `tfstate/terraform/platform/infra/middle-api-infra/billing`
- CI 入力: `MIDDLE_BILLING_VM_CONFIG`（1台分の JSON オブジェクト）
- ローカル入力: このディレクトリの `terraform.tfvars.example` を `terraform.tfvars` にコピー
- 出力: `terraform output vm`

認証情報なしで、このディレクトリから検証できる。

```sh
terraform init -backend=false -input=false
terraform fmt -check -recursive
terraform validate
terraform test
```

接続先の確認事項・実 plan / apply・受け入れ条件は [共通手順](../README.md) を参照。
