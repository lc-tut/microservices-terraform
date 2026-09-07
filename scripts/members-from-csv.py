#!/usr/bin/env python3
"""CSV から members.yaml / members_secrets.yaml を生成する。

新入部員リスト（CSV）を受け取り、コホート（卒業年度）ごとに
terraform/platform/members/<status>/grad-<year>/ 配下へ

  - members.yaml          … id + role（平文・コミットする）
  - members_secrets.yaml  … email + student_id（平文・.gitignore 対象）

を書き出す。既存メンバーの id は student_id（無ければ email）で突き合わせて
再利用するので、同じ CSV を複数回流しても id は変わらない。

CSV の列（ヘッダー名は大小文字・全角別名を吸収する）:

  student_id  学籍番号        必須
  email       メールアドレス   必須
  role        役割            省略時 member（active のみ有効）
  grad_year   卒業年度        省略時 --grad-year の値

  $ python3 scripts/members-from-csv.py --sample > new-members.csv

使い方:

  # 中身を確認（ファイルは書かない。email はマスクして表示）
  python3 scripts/members-from-csv.py new-members.csv --dry-run

  # 平文を書き出す
  python3 scripts/members-from-csv.py new-members.csv

  # 平文を書き出し、そのまま SOPS で .enc も更新する
  python3 scripts/members-from-csv.py new-members.csv --encrypt

既存コホートに追記する場合は members_secrets.yaml.enc を読むため
age 秘密鍵（SOPS_AGE_KEY_FILE / ~/.config/sops/age/keys.txt）が要る。
"""

from __future__ import annotations

import argparse
import csv
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
MEMBERS_DIR = REPO_ROOT / "terraform" / "platform" / "members"
STATUSES = ("active", "ob-og", "alumni")

# documents/terraform/10-roles-and-permissions.md の「ロール定義」。
# ob-og / alumni はフォルダ名で決まるため members.yaml には書かない。
ROLES = (
    "circle-admin",
    "tech-lead",
    "lc-cloud-infra",
    "lc-cloud-platform",
    "team-lead",
    "member",
)

COLUMN_ALIASES = {
    "student_id": ("student_id", "studentid", "student id", "学籍番号", "学生番号"),
    "email": ("email", "mail", "e-mail", "メール", "メールアドレス"),
    "role": ("role", "役割", "ロール"),
    "grad_year": (
        "grad_year",
        "gradyear",
        "grad",
        "卒業年度",
        "卒業年",
        "卒業予定年度",
    ),
}

ID_RE = re.compile(r"^lcn_[0-9a-f]{12}$")
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

AUTO_GEN_MEMBERS_STUB = """# 自動生成 - 手動編集禁止
# enrollment flow 完了時に Bot が書き込む
# キー: member id, 値: {username, display_name}
{}
"""


class Fail(Exception):
    """利用者向けのエラー（トレースバックは出さない）。"""


# --------------------------------------------------------------------------
# YAML 読み書き（PyYAML 非依存。このスクリプトが書く固定フォーマットのみ扱う）
# --------------------------------------------------------------------------


def parse_members_yaml(text: str, where: str) -> list[dict]:
    """members.yaml → [{"id": ..., "role": ...}]"""
    entries: list[dict] = []
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].rstrip() if not raw.lstrip().startswith("#") else ""
        if not line.strip():
            continue
        if line.strip() == "members:":
            continue
        m = re.match(r"^\s*-\s*id:\s*\"?([^\"\s]+)\"?\s*$", line)
        if m:
            entries.append({"id": m.group(1), "role": None})
            continue
        m = re.match(r"^\s*role:\s*\"?([^\"\s]+)\"?\s*$", line)
        if m and entries:
            entries[-1]["role"] = m.group(1)
            continue
        raise Fail(f"{where}:{lineno}: 解釈できない行です（手で書き換えた？）: {raw!r}")
    missing = [e["id"] for e in entries if not e["role"]]
    if missing:
        raise Fail(f"{where}: role が無いエントリがあります: {', '.join(missing)}")
    return entries


def parse_secrets_yaml(text: str, where: str) -> dict[str, dict]:
    """members_secrets.yaml → {id: {"email": ..., "student_id": ...}}"""
    secrets: dict[str, dict] = {}
    current: str | None = None
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.strip() == "members:":
            continue
        m = re.match(r"^\s{2}([A-Za-z0-9_\-]+):\s*$", line)
        if m:
            current = m.group(1)
            secrets[current] = {"email": "", "student_id": ""}
            continue
        m = re.match(r"^\s{4}(email|student_id):\s*\"?(.*?)\"?\s*$", line)
        if m and current:
            secrets[current][m.group(1)] = m.group(2)
            continue
        raise Fail(f"{where}:{lineno}: 解釈できない行です（手で書き換えた？）: {raw!r}")
    return secrets


def render_members_yaml(entries: list[dict]) -> str:
    blocks = [f'  - id: "{e["id"]}"\n    role: "{e["role"]}"' for e in entries]
    return "members:\n" + "\n\n".join(blocks) + "\n"


def render_secrets_yaml(secrets: dict[str, dict]) -> str:
    out = ["members:"]
    for member_id, s in secrets.items():
        out.append(f"  {member_id}:")
        out.append(f'    email: "{s["email"]}"')
        out.append(f'    student_id: "{s["student_id"]}"')
    return "\n".join(out) + "\n"


# --------------------------------------------------------------------------
# SOPS
# --------------------------------------------------------------------------


def require_sops() -> str:
    sops = shutil.which("sops")
    if not sops:
        raise Fail("sops が見つかりません（brew install sops）")
    return sops


def sops_decrypt(enc_path: Path) -> str:
    require_sops()
    proc = subprocess.run(
        ["sops", "--decrypt", str(enc_path.relative_to(REPO_ROOT))],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise Fail(
            f"{enc_path.relative_to(REPO_ROOT)} の復号に失敗しました。age 秘密鍵を確認してください。\n"
            "  local/setup.sh は ~/.config/sops/age/keys.txt に置くが、macOS の sops は\n"
            "  そこを自動では見ない（~/Library/Application Support/sops/age/keys.txt を見る）ため\n"
            "  export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt が要る。\n"
            f"--- sops ---\n{proc.stderr.strip()}"
        )
    return proc.stdout


def sops_encrypt(plain_path: Path, enc_path: Path) -> None:
    """既存 .enc と同じ binary フォーマットで暗号化する。

    creation_rules（.sops.yaml）は「入力ファイルのパス」に対して評価されるため、
    入力が members_secrets.yaml のままだと `.*_secrets\\.yaml\\.enc$` に
    マッチせず "no matching creation rules found" になる。
    --filename-override で .enc のパスを渡してルールにマッチさせる。
    """
    require_sops()
    rel_plain = plain_path.relative_to(REPO_ROOT)
    rel_enc = enc_path.relative_to(REPO_ROOT)
    proc = subprocess.run(
        [
            "sops",
            "--encrypt",
            "--filename-override",
            str(rel_enc),
            "--input-type",
            "binary",
            "--output-type",
            "binary",
            "--output",
            str(rel_enc),
            str(rel_plain),
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise Fail(f"{rel_enc} の暗号化に失敗しました。\n--- sops ---\n{proc.stderr.strip()}")


# --------------------------------------------------------------------------
# CSV
# --------------------------------------------------------------------------

SAMPLE_CSV = """student_id,email,role,grad_year
C0A24001AA,c0a24001aa@edu.teu.ac.jp,member,2028
C0A24002BB,c0a24002bb@edu.teu.ac.jp,circle-admin,2028
"""


def normalize_header(name: str) -> str | None:
    key = name.strip().lstrip("﻿").lower()
    for canonical, aliases in COLUMN_ALIASES.items():
        if key in aliases:
            return canonical
    return None


def sniff_delimiter(path: Path) -> str:
    """ヘッダー行を見てタブ / カンマ / セミコロンを判定する。

    Excel やスプレッドシートからコピペした表はタブ区切りになることが多い。
    """
    with path.open(newline="", encoding="utf-8-sig") as f:
        header = f.readline()
    counts = {d: header.count(d) for d in ("\t", ",", ";")}
    delimiter = max(counts, key=lambda d: counts[d])
    return delimiter if counts[delimiter] else ","


def read_csv(path: Path, default_grad_year: int | None, delimiter: str | None) -> list[dict]:
    delimiter = delimiter or sniff_delimiter(path)
    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f, delimiter=delimiter)
        try:
            header = next(reader)
        except StopIteration:
            raise Fail(f"{path}: 空の CSV です")

        mapping: dict[int, str] = {}
        ignored: list[str] = []
        for i, name in enumerate(header):
            canonical = normalize_header(name)
            if canonical:
                mapping[i] = canonical
            elif name.strip():
                ignored.append(name.strip())
        if ignored:
            print(f"注意: 無視した列: {', '.join(ignored)}", file=sys.stderr)
        for required in ("student_id", "email"):
            if required not in mapping.values():
                raise Fail(f"{path}: 必須の列 {required} が見つかりません（ヘッダー: {header}）")

        rows: list[dict] = []
        for lineno, raw_row in enumerate(reader, 2):
            if not any(cell.strip() for cell in raw_row):
                continue
            row = {canonical: "" for canonical in COLUMN_ALIASES}
            for i, value in enumerate(raw_row):
                if i in mapping:
                    row[mapping[i]] = value.strip()

            student_id = row["student_id"].upper()
            email = row["email"].lower()
            role = row["role"] or "member"
            grad_year_raw = row["grad_year"]

            if not student_id:
                raise Fail(f"{path}:{lineno}: student_id が空です")
            if not EMAIL_RE.match(email):
                raise Fail(f"{path}:{lineno}: email の形式が不正です: {row['email']!r}")
            if role not in ROLES:
                raise Fail(
                    f"{path}:{lineno}: 不明な role: {role!r}\n"
                    f"使えるのは {', '.join(ROLES)}"
                )
            if grad_year_raw:
                if not re.fullmatch(r"\d{4}", grad_year_raw):
                    raise Fail(f"{path}:{lineno}: grad_year は西暦4桁で: {grad_year_raw!r}")
                grad_year = int(grad_year_raw)
            elif default_grad_year:
                grad_year = default_grad_year
            else:
                raise Fail(
                    f"{path}:{lineno}: grad_year 列が無い行です。"
                    "CSV に列を足すか --grad-year を指定してください"
                )

            rows.append(
                {
                    "student_id": student_id,
                    "email": email,
                    "role": role,
                    "grad_year": grad_year,
                    "lineno": lineno,
                }
            )

    seen: dict[str, int] = {}
    for row in rows:
        if row["student_id"] in seen:
            raise Fail(
                f"{path}: student_id {row['student_id']} が "
                f"{seen[row['student_id']]} 行目と {row['lineno']} 行目で重複しています"
            )
        seen[row["student_id"]] = row["lineno"]
    return rows


# --------------------------------------------------------------------------
# 本体
# --------------------------------------------------------------------------


def collect_existing_ids() -> set[str]:
    """全 status・全コホートの members.yaml から id を集める（衝突回避用）。"""
    ids: set[str] = set()
    for status in STATUSES:
        for path in sorted((MEMBERS_DIR / status).glob("*/members.yaml")):
            for entry in parse_members_yaml(path.read_text(encoding="utf-8"), str(path)):
                ids.add(entry["id"])
    return ids


def new_member_id(taken: set[str]) -> str:
    while True:
        candidate = "lcn_" + uuid.uuid4().hex[:12]
        if candidate not in taken:
            taken.add(candidate)
            return candidate


def load_cohort(cohort_dir: Path) -> tuple[list[dict], dict[str, dict]]:
    members_path = cohort_dir / "members.yaml"
    entries: list[dict] = []
    if members_path.exists():
        entries = parse_members_yaml(members_path.read_text(encoding="utf-8"), str(members_path))

    plain_path = cohort_dir / "members_secrets.yaml"
    enc_path = cohort_dir / "members_secrets.yaml.enc"
    if plain_path.exists():
        secrets = parse_secrets_yaml(plain_path.read_text(encoding="utf-8"), str(plain_path))
    elif enc_path.exists():
        secrets = parse_secrets_yaml(sops_decrypt(enc_path), f"{enc_path}(復号後)")
    else:
        secrets = {}

    known = {e["id"] for e in entries}
    orphan = [i for i in secrets if i not in known]
    if orphan:
        raise Fail(
            f"{cohort_dir}: members.yaml に無い id が secrets 側にあります: {', '.join(orphan)}"
        )
    return entries, secrets


def warn_if_tracked(csv_path: Path) -> None:
    """入力 CSV が .gitignore 対象外ならコミット事故の前に警告する。

    CSV には学籍番号とメールアドレスが平文で入るため、リポジトリ内に
    置く場合は必ず ignore されていること（.gitignore の `*.csv`）。
    """
    resolved = csv_path.resolve()
    try:
        resolved.relative_to(REPO_ROOT)
    except ValueError:
        return  # リポジトリ外なら問題なし
    if not shutil.which("git"):
        return
    ignored = subprocess.run(
        ["git", "check-ignore", "-q", str(resolved)],
        cwd=REPO_ROOT,
        capture_output=True,
    )
    if ignored.returncode != 0:
        print(
            f"警告: {resolved.relative_to(REPO_ROOT)} は .gitignore 対象外です。\n"
            "  この CSV には学籍番号・メールアドレスが平文で入ります。"
            "コミットしないよう注意するか、リポジトリ外に置いてください。",
            file=sys.stderr,
        )


def mask_email(email: str) -> str:
    local, _, domain = email.partition("@")
    head = local[:2] if len(local) > 2 else local[:1]
    return f"{head}***@{domain}"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="CSV から members.yaml / members_secrets.yaml を生成する",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("csv", nargs="?", type=Path, help="入力 CSV / TSV")
    parser.add_argument(
        "--status",
        choices=STATUSES,
        default="active",
        help="書き出し先の status フォルダ（既定: active）",
    )
    parser.add_argument("--grad-year", type=int, help="CSV に grad_year 列が無いときの卒業年度")
    parser.add_argument(
        "--delimiter",
        help="区切り文字（既定: ヘッダー行から自動判定。タブは $'\\t' で指定）",
    )
    parser.add_argument("--dry-run", action="store_true", help="書き込まず結果を表示する")
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="既存の members.yaml / .enc を読まずに CSV の内容だけで書き直す（id は全て再発行）",
    )
    parser.add_argument("--encrypt", action="store_true", help="書き出し後に SOPS で .enc も更新する")
    parser.add_argument("--sample", action="store_true", help="CSV のテンプレートを表示して終了")
    args = parser.parse_args()

    if args.sample:
        sys.stdout.write(SAMPLE_CSV)
        return 0
    if not args.csv:
        parser.error("CSV を指定してください（テンプレートは --sample）")
    if not args.csv.exists():
        raise Fail(f"{args.csv} が見つかりません")

    warn_if_tracked(args.csv)
    rows = read_csv(args.csv, args.grad_year, args.delimiter)
    taken_ids = collect_existing_ids()

    by_cohort: dict[int, list[dict]] = {}
    for row in rows:
        by_cohort.setdefault(row["grad_year"], []).append(row)

    failures: list[str] = []
    for grad_year in sorted(by_cohort):
        cohort_dir = MEMBERS_DIR / args.status / f"grad-{grad_year}"
        is_new_cohort = not cohort_dir.exists()
        # --overwrite は既存ファイルを読まない＝ id は全て新規発行になる。Authentik /
        # OpenStack のリソースは member id をキーにしているため、既存メンバーが消えると
        # authentik_user（prevent_destroy）で apply が止まる点に注意
        if args.overwrite:
            entries, secrets = [], {}
        else:
            # 1コホートの失敗で他のコホートを巻き添えにしない（.enc を復号できない等）
            try:
                entries, secrets = load_cohort(cohort_dir)
            except Fail as e:
                print(f"\n=== {cohort_dir.relative_to(REPO_ROOT)} ===")
                print("  スキップ（下記のエラー）")
                failures.append(f"{cohort_dir.relative_to(REPO_ROOT)}: {e}")
                continue

        by_student_id = {s["student_id"].upper(): i for i, s in secrets.items() if s["student_id"]}
        by_email = {s["email"].lower(): i for i, s in secrets.items() if s["email"]}
        roles = {e["id"]: e["role"] for e in entries}

        added, updated, unchanged = [], [], []
        for row in by_cohort[grad_year]:
            member_id = by_student_id.get(row["student_id"]) or by_email.get(row["email"])
            if member_id:
                changes = []
                if secrets[member_id]["email"] != row["email"]:
                    changes.append(f"email {secrets[member_id]['email']} → {row['email']}")
                    secrets[member_id]["email"] = row["email"]
                if secrets[member_id]["student_id"] != row["student_id"]:
                    changes.append(
                        f"student_id {secrets[member_id]['student_id']} → {row['student_id']}"
                    )
                    secrets[member_id]["student_id"] = row["student_id"]
                if args.status == "active" and roles.get(member_id) != row["role"]:
                    changes.append(f"role {roles.get(member_id)} → {row['role']}")
                    roles[member_id] = row["role"]
                    for entry in entries:
                        if entry["id"] == member_id:
                            entry["role"] = row["role"]
                (updated if changes else unchanged).append((member_id, row, changes))
                continue

            member_id = new_member_id(taken_ids)
            entries.append({"id": member_id, "role": row["role"]})
            secrets[member_id] = {"email": row["email"], "student_id": row["student_id"]}
            added.append((member_id, row, []))

        members_text = render_members_yaml(entries)
        # 出力順を members.yaml に合わせる
        secrets_text = render_secrets_yaml({e["id"]: secrets[e["id"]] for e in entries})

        rel = cohort_dir.relative_to(REPO_ROOT)
        print(f"\n=== {rel} ===")
        if args.overwrite and not is_new_cohort:
            print("  上書きモード: 既存の members.yaml / .enc は読まずに作り直します")
        for label, items in (("追加", added), ("更新", updated), ("変更なし", unchanged)):
            for member_id, row, changes in items:
                suffix = f"  [{'; '.join(changes)}]" if changes else ""
                print(f"  {label}: {member_id}  {row['student_id']}  {mask_email(row['email'])}{suffix}")
        if not (added or updated or unchanged):
            print("  対象なし")

        if args.dry_run:
            print(f"\n--- {rel}/members.yaml ---")
            print(members_text, end="")
            print(f"--- {rel}/members_secrets.yaml --- (PII のため非表示。{len(secrets)} 件)")
            continue

        cohort_dir.mkdir(parents=True, exist_ok=True)
        (cohort_dir / "members.yaml").write_text(members_text, encoding="utf-8")
        (cohort_dir / "members_secrets.yaml").write_text(secrets_text, encoding="utf-8")
        print(f"  書き出し: {rel}/members.yaml, {rel}/members_secrets.yaml（平文・.gitignore 対象）")

        auto_gen = cohort_dir / "auto-gen-members.yaml"
        if is_new_cohort and args.status == "active" and not auto_gen.exists():
            auto_gen.write_text(AUTO_GEN_MEMBERS_STUB, encoding="utf-8")
            print(f"  新規作成: {rel}/auto-gen-members.yaml")
        elif is_new_cohort and args.status != "active":
            print(
                f"  注意: {args.status} は auto-gen-*.yaml も暗号化対象です。"
                "documents/authentik/02-membership-lifecycle.md を参照して手当てしてください"
            )

        if args.encrypt:
            sops_encrypt(cohort_dir / "members_secrets.yaml", cohort_dir / "members_secrets.yaml.enc")
            print(f"  暗号化: {rel}/members_secrets.yaml.enc")

    if failures:
        print("\n以下のコホートは処理できませんでした:", file=sys.stderr)
        for f in failures:
            print(f"\n{f}", file=sys.stderr)

    if not args.dry_run:
        steps = []
        if not args.encrypt:
            steps.append(
                "sops で暗号化する（--encrypt を付けて再実行するか、各コホートで下記）\n"
                "     sops --encrypt --filename-override <path>.enc --input-type binary"
                " --output-type binary --output <path>.enc <path>"
            )
        steps.append("git add は members.yaml と members_secrets.yaml.enc のみ（平文は .gitignore 済み）")
        steps.append("PR → circle-admin / tech-lead の承認 → apply（apply 前に scripts/decrypt-members.sh）")
        print("\n次の手順:")
        for i, step in enumerate(steps, 1):
            print(f"  {i}. {step}")
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Fail as e:
        print(f"エラー: {e}", file=sys.stderr)
        sys.exit(1)
