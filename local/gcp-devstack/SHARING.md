# DevStack VM を他のメンバーに渡す

`shared_vm_owner` に相手のメールアドレスを設定して apply すると、その人専用の
DevStack + Harbor VM と、到達するための IAP トンネル権限が作られます。

VM は複製元と同じ料金がかかります（n2-standard-4 で稼働中 約 40 円/時、
ディスク 100GB で 月約 2,000 円）。使い終わったら消してください。

---

## 1. 作る

```hcl
# terraform.tfvars
shared_vm_owner                = "someone@example.com"
shared_devstack_admin_password = "..."   # openssl rand -base64 24
shared_harbor_admin_password   = "..."   # openssl rand -base64 18
```

```bash
terraform apply
```

作られるもの:

| リソース | 用途 |
| --- | --- |
| `devstack-harbor-shared`（VM） | 相手に渡す VM |
| `devstack-harbor-shared`（静的 IP） | この VM 専用 |
| IAP トンネル権限 | 相手が VM に到達するため |

VM 作成後、`bootstrap.sh.tpl` が DevStack と Harbor を自動構築します（40 分程度）。

```bash
gcloud compute ssh devstack-harbor-shared --zone=<zone> --tunnel-through-iap \
  --command="tail -f /var/log/gcp-devstack-bootstrap.log"
```

構築が終わったら確認します。

```bash
systemctl --failed                          # 空であること
sudo grep -h ^virt_type /etc/nova/nova.conf # virt_type = kvm であること
```

---

## 2. 渡す

```bash
terraform output -json shared_vm_credentials
```

VM 名・ゾーン・外部 IP・OpenStack admin パスワード・Harbor admin パスワードが
まとめて出ます。チャットに貼らず、パスワードマネージャの共有機能など、
後から取り消せる経路で渡してください。

接続方法も添えます。

```bash
gcloud compute ssh devstack-harbor-shared --zone=<zone> --tunnel-through-iap
./local/gcp-devstack/start-tunnels.sh        # OpenStack API / Harbor に繋ぐ場合
```

**渡さないもの**:

- `local/polaris-access.md` — 本番 Polaris の実認証情報。DEV 環境の利用には不要
- `local/clouds.yaml` — Application Credential は相手に自分で発行してもらう。
  そのほうが誰の操作か追跡できる（`15-local-development.md` 参照）

---

## 3. 共有を終える

```hcl
shared_vm_owner = ""
```

```bash
terraform apply
```

VM・静的 IP・IAP 権限がまとめて消えます。

---

## なぜ既存 VM を複製しないのか

構築済み VM をマシンイメージで複製すれば 40 分の構築を省けそうに見えますが、
この方法は採っていません。DevStack は構築時のホスト IP とホスト名を
広範囲に焼き込むため、複製先で全て書き換える必要があります。

- 各サービスの設定ファイル（`/etc/nova`・`/etc/neutron` ほか十数ファイル）
- systemd ユニット（etcd の `--initial-cluster` にホスト名と IP が入る）
- etcd のデータディレクトリ（クラスタ ID が焼かれ、消して作り直しになる）
- iSCSI の initiator name（複製元と重複し `open-iscsi` が起動しない）
- Keystone のサービスカタログ

実際に試したところ、上記を一通り直してもサービスカタログが復元できず
（サービス 12 件・エンドポイント 19 件が 2 件・1 件に落ちた状態で、
原因を特定できなかった）、結局作り直すことになりました。

一から構築すれば最初から自分の IP とホスト名で構成され、この問題は起きません。
`bootstrap.sh.tpl` には Trove を動かすための修正が入っているため、
構築される環境は複製元と同じです。
