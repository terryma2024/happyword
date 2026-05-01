# 家长 Web 运维手册（V0.6.1 – V0.6.7）

本文档面向运维 / on-call 工程师，覆盖家长账号 / 设备绑定 / 家庭词包 / 云端同步 /
礼品兑换 / 通知 / 删除账号等子版本上线后的标准操作流程。

> 适用范围：服务端版本 `0.6.7+`、客户端版本 `VC0.6.7+`。
>
> 涉及到的代码主目录：`server/app/{models,services,routers,templates}/`、
> `server/tests/`、`entry/src/main/ets/`。

---

## 1. 部署与回滚速记

| 场景 | 命令 | 备注 |
| --- | --- | --- |
| 本地完整测试 | `cd server && uv run pytest && uv run ruff check && uv run mypy app` | 全套必须 0 失败 0 警告 |
| 客户端构建 | `hvigorw assembleHap`（DevEco Studio CLI） | 需要校验 `codelinter` 通过 |
| 生产部署 | `bash tools/vercel/deploy-prod.sh` | 部署前先做 `git pull --rebase` |
| 紧急回滚 | Vercel Dashboard → 选择上一个绿色 deployment → `Promote` | 数据库不会自动回滚，按 §6 数据修复流程处理 |

---

## 2. 家长重置（忘记或更换邮箱）

家长账号靠邮箱 OTP 登录，没有密码。家长换邮箱时按下列顺序执行：

1. 在生产 Mongo 上：

   ```
   db.users.updateOne(
     { username: "<old-username>" },
     { $set: { email: "<new-email>", display_name: "<new-display-name>" } }
   )
   ```

2. 让家长在新邮箱发起 `/api/v1/parent/auth/request-code`。
3. 家长收到验证码后即可登录新邮箱。绑定的设备 token 不变，孩子档案 / 学习数据
   保留不变。

> 没有"管理员代登录"功能。运维不能直接生成家长 cookie；只能通过 OTP 流程。

---

## 3. 配对恢复（家长说"二维码过期了"）

* 配对 token 默认 15 分钟过期。
* 家长重新进入"添加新设备"页 → 点击"重新生成"会创建新的 PairToken。
* 旧 token 可通过 `POST /parent/devices/add/cancel` 显式失效。
* 客户端扫码失败时引导家长输入 6 位短码，短码与 token 同源（数据库 `pair_tokens.short_code`）。
* 如果 `dev-id-source = preferences_fallback`，提示家长在"设置 → 应用 → 持久化标识符"开启权限并重启 App。

---

## 4. 家庭词包（V0.6.3）

* 单个 family 上限：每个 pack ≤ 50 词，pack 数量无上限。
* 家长在 web 页面新建草稿、添加 / 编辑词、点击"发布"创建一个 `family_word_packs` 版本。
* 客户端通过 `GET /api/v1/child/family-packs/merged.json`（带 ETag）拉取合并 JSON。
* `published_packs.list` 视图：`{ pack_id, current_version, schema_version, word_count, updated_at }`。

### 回滚指定 pack 到上一个版本

* 家长 web → 词包详情 → "回滚到上一个版本" 按钮调用
  `POST /api/v1/parent/family-packs/{pack_id}/rollback`，将 `pointer.current_version` 切回
  `pointer.previous_version`，新 ETag 自动生成。
* 应急回滚（绕过家长操作）：

  ```
  db.family_pack_pointers.updateOne(
    { pack_id: "pck-XXXXXXXX" },
    { $set: { current_version: <prev>, previous_version: <prev_prev>, updated_at: ISODate() } }
  )
  ```

---

## 5. 云端同步（V0.6.4）

* 客户端在 `BattlePage.aboutToDisappear` / `EntryAbility.onBackground` / `ConfigPage` 手动触发 `CloudSyncService.syncOnce()`。
* 同步幂等；冲突解决遵循 LWW（`last_answered_ms` 较大的一侧获胜）。
* 网络失败：客户端不更新 checkpoint，下次重试。

排查"同步失败"时：

1. 让家长在 web 端 `GET /api/v1/parent/children/{id}/wishlist`（任意端点）确认 family / 设备绑定状态。
2. 后端日志搜索 `CloudSync`/`sync_word_stats` 关键字，确认是否 401 / 404。
3. 如果 401：检查设备 token 是否撤销（`device_bindings.revoked_at`）；如果撤销，必须重新走绑定。

---

## 6. 礼品兑换审批（V0.6.6）

* 流程：孩子设备申请 → `redemption_requests.status=pending` → 家长 web 审批 → status flips。
* 7 天未审批自动 `expired`，由 `redemption_service.sweep_expired` 跑批处理。
* 紧急取消一个待审批申请：

  ```
  db.redemption_requests.updateOne(
    { request_id: "rdm-XXXXXXXX" },
    { $set: { status: "rejected", decided_at: ISODate(), decided_by: "ops" } }
  )
  ```

  这个动作不会写 `audit_log`，事后请补一行：

  ```
  db.audit_log.insertOne({
    actor_role: "system", actor_id: "ops",
    action: "redemption.reject_manual",
    target_collection: "redemption_requests",
    target_id: "rdm-XXXXXXXX",
    payload_summary: { reason: "..." },
    ts: new Date()
  })
  ```

---

## 7. 删除账号（V0.6.7）

* 家长端 → 账号设置 → "删除账号" 调用 `POST /api/v1/parent/account/delete`，
  写入 `users.scheduled_deletion_at = now + 7d`。
* 宽限期内任何时候可调用 `POST /api/v1/parent/account/cancel-delete` 撤销。
* 后台需要每日跑：

  ```
  await account_deletion_service.sweep_scheduled_deletes(now=datetime.now(tz=UTC))
  ```

  推荐通过 Vercel Cron 或外部定时器调用一个内部端点（V0.7 计划）。

* 级联删除顺序见 `account_deletion_service.cascade_delete_user`：
  redemption_requests → cloud_wishlist_items → synced_word_stats → child_profiles
  → device_bindings → family_pack_pointers → family_word_packs → family_pack_drafts
  → family_pack_definitions → families → parent_inbox_msgs → email_verifications
  → pair_tokens → users。每一步都会写 `audit_log` `account.delete_commit`。

---

## 8. 数据导出

* `POST /api/v1/parent/account/export` 返回 `Content-Disposition: attachment` 的
  JSON，结构：

  ```
  {
    "summary": {"user_id", "family_id", "items_count", "files": [...]},
    "data": {"child_profiles": [...], "device_bindings": [...], ...}
  }
  ```

* 文件命名：`happyword-export-<username>.json`。
* 出现"导出超时"：很可能是某个集合行数过大（>5MB）。可以临时把"分批导出"加进
  `export_account_data`（按 `family_id` 切片）。

---

## 9. 设备解绑

* 客户端 ConfigPage → "解除设备绑定" → 弹出 PIN 校验 → `POST /api/v1/child/unbind`。
* 服务端把 `device_bindings.revoked_at = now` 并写 audit `device.unbind`。
* 客户端清空 `wordmagic_cloud` preferences（设备 token / family_id / child_profile_id）。
* 家长 web 上该设备会从"已绑定的设备"列表中消失（dashboard 过滤 `revoked_at IS NULL`）。

---

## 10. Inbox / 消息中心

* 每次孩子端发起兑换 → 写入 `parent_inbox_msgs`（kind=redemption_request）+ 尝试发邮件。
* 家长可以在 `/parent/inbox` 看到全部消息，单条标记已读 `POST /api/v1/parent/inbox/{id}/read`，
  全部标记已读 `POST /api/v1/parent/inbox/mark-all-read`。
* 测试或调试时关闭邮件可以设置 `NOTIFICATION_EMAIL_ENABLED=false`，inbox 仍然写入。

---

## 11. 邮件 / SMTP 故障排查

| 症状 | 排查路径 |
| --- | --- |
| OTP 邮件没收到 | `aiosmtplib` 是否抛错 → 检查 `SMTP_USERNAME`/`SMTP_PASSWORD`；OTP 行已写入数据库 |
| `EMAIL_DELIVERY_DEGRADED` 在响应里出现 | provider raised `EmailDeliveryError`；查 SMTP 日志；用户可点"重新发送" |
| 兑换通知邮件丢失 | `NOTIFICATION_EMAIL_ENABLED` 是否被关；`Family.primary_email` / `User.email` 是否填 |
| Gmail 535 5.7.8 | App Password 失效 — 见下面"轮换流程" |

### Gmail App Password 轮换流程

1. 重新启用 2-Step Verification：<https://myaccount.google.com/security>。
2. 生成新 App Password：<https://myaccount.google.com/apppasswords>。
3. 在 Vercel Dashboard → Project → Settings → Environment Variables 更新
   `SMTP_PASSWORD` 字段（注意去掉空格）。
4. 重新部署 `bash tools/vercel/deploy-prod.sh` 或 Vercel Dashboard → Redeploy。
5. 用 `live_smtp` 标记的 pytest 集合或一个临时 `/api/v1/parent/auth/request-code`
   验证发件成功。
6. 第一次成功的请求即可关闭工单。

---

## 12. 审计日志查询

`audit_log` 集合按 `(actor_id, ts desc)` 和 `(action, ts desc)` 双索引。常用查询：

* "谁删了 X 家庭"：`db.audit_log.find({ action: "account.delete_commit", target_id: "<family_id>" })`。
* "最近一周的兑换审批"：`db.audit_log.find({ action: { $in: ["redemption.approve", "redemption.reject"] }, ts: { $gte: ISODate("...") } })`。
* "某家长所有写动作"：`db.audit_log.find({ actor_id: "<parent_username>" }).sort({ ts: -1 }).limit(100)`。

---

## 13. 应急联系流程

1. 第一时间在 Vercel 上确认是否有 deployment 在跑红 / 部分实例不健康。
2. 若服务整体不可用：回滚到最近一个绿色 deployment。
3. 若仅某子模块出故障：临时关闭对应 feature flag（V0.7 引入），或在 Mongo 上修
   数据后让用户重试。
4. 若数据库被破坏：
   - 立刻禁止写流量（Vercel env `READ_ONLY=true`，V0.7 计划）。
   - 从 MongoDB Atlas 备份点恢复。
   - 重放过期间隙的 `audit_log` 行（手工补 / 通知用户）。

---

## 14. 测试小贴士

* 服务端：`cd server && uv run pytest -k <substring>`，例：`-k cloud_wishlist`。
* 客户端：`hvigorw test --module entry@ohosTest`（要先连模拟器或真机）。
* 跑 OTP / SMTP 真发件：`uv run pytest -m live_smtp` 需在 `.env.local` 里配 SMTP 凭证。
* 永远在 PR / 部署前确认 `uv run ruff check`、`uv run mypy app`、`hvigorw assembleHap` 都通过。

---

## 15. 已知限制 / 后续 (V0.7 计划)

* 单家长账号；不支持夫妻协同审批。
* 邮件类通知；无 push（计划接 HarmonyOS Push Kit）。
* `cleanup_pending_deletions` 的运行时机靠运维定时调用；后续会集成到 Vercel Cron。
* Inbox 还没有未读 badge 推送；前端 `unread_count` 仅靠刷新更新。
* 客户端 `PendingRedemptionOverlay` UI 实现仅有数据接口，可视化在 V0.7 完善。
