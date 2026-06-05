# 家长 Web 运维手册（V0.6.1 – V0.6.7）

本文档面向运维 / on-call 工程师，覆盖家长账号 / 设备绑定 / 家庭词包 / 云端同步 /
礼品兑换 / 通知 / 删除账号等子版本上线后的标准操作流程。

> 适用范围：服务端版本 `0.6.7+`、客户端版本 `VC0.6.7+`。
>
> 涉及到的代码主目录：`server/app/{models,services,routers,templates}/`、
> `server/tests/`、`harmonyos/entry/src/main/ets/`。

---

## 1. 部署与回滚速记

| 场景 | 命令 | 备注 |
| --- | --- | --- |
| 本地完整测试 | `cd server && uv run pytest && uv run ruff check && uv run mypy app` | 全套必须 0 失败 0 警告 |
| 客户端构建 | `cd harmonyos && hvigorw assembleHap`（DevEco Studio CLI） | 需要校验 `cd harmonyos && codelinter -c ./code-linter.json5 . --fix` 通过 |
| 生产部署 | GitHub Actions `server-cloudbase-cd` | push `main` 后自动部署 CloudBase；也可手动 dispatch |
| 旧 Vercel 归档检查 | GitHub Actions `server-cd-legacy-vercel`（manual only） | 仅用于归档验证；生产回滚优先使用 CloudBase 上一个绿色 revision，数据库不会自动回滚，按 §6 数据修复流程处理 |

---

## 2. 第三方 OAuth 登录（V0.6.8+）

家长可在 **`/family/login`** 使用 Apple / 微信 / 支付宝登录（与邮箱 OTP 并列）。Google
登录在 CloudBase 中国大陆运行时暂时隐藏：服务器到 Google token/JWKS endpoint
不可稳定连通，除非后续引入境外 token broker。

### Google

| 项 | 值 |
| --- | --- |
| Canonical callback | `https://happyword.com.cn/v1/oauth/google/callback` |
| Fixed Preview callback | `https://happyword-zjumty-2580-terrymas-projects.vercel.app/v1/oauth/google/callback`（与 `OAUTH_PREVIEW_BASE_URL` 一致） |
| Runtime env | `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET` / `OAUTH_CANONICAL_BASE_URL` / `OAUTH_PREVIEW_BASE_URL` |
| 本地开发 | `http://localhost:8000` 在 `OAUTH_LOCAL_ORIGINS` 中；未配置 Preview base 时走生产 callback + `/finish` handoff |
| 固定 Vercel Preview | 同域 `start` → Google → **Preview callback** → 直接种 `wm_session`（无需 handoff） |
| 其它 `*.vercel.app` Preview | 仍用生产 callback + `/finish` ticket（需在 Google Console 单独登记才能直回） |

生产状态：Google Console callback 已配置为 `https://happyword.com.cn/v1/oauth/google/callback`，
但 CloudBase 中国大陆服务端无法稳定请求 Google token endpoint；生产登录页应保持隐藏
Google 按钮。恢复方案是把 code -> token 交换放到境外合规中继服务，再用签名 handoff
回 CloudBase。

### Apple

| 项 | 值 |
| --- | --- |
| Canonical callback | `https://happyword.com.cn/v1/oauth/apple/callback` |
| Fixed Preview callback | `https://happyword-zjumty-2580-terrymas-projects.vercel.app/v1/oauth/apple/callback`（与 `OAUTH_PREVIEW_BASE_URL` 一致） |
| Apple Developer | Services ID + Sign in with Apple；Website URLs 填 `happyword.com.cn` 和固定 Preview 域名；Return URLs 填上面两个 callback |
| Runtime env | `APPLE_OAUTH_CLIENT_ID`（Services ID）/ `APPLE_OAUTH_TEAM_ID` / `APPLE_OAUTH_KEY_ID` / `APPLE_OAUTH_PRIVATE_KEY` |

Apple callback 使用 `form_post`；未配置完整 Apple env 时登录页隐藏 Apple 按钮。

生产状态：Apple 登录已在 `happyword.com.cn` 实测通过。

### WeChat / Alipay

| Provider | Canonical callback | Fixed Preview callback | Env |
| --- | --- | --- | --- |
| WeChat | `https://happyword.com.cn/v1/oauth/wechat/callback` | `https://happyword-zjumty-2580-terrymas-projects.vercel.app/v1/oauth/wechat/callback` | `WECHAT_OAUTH_LOGIN_ENABLED=true` / `WECHAT_OAUTH_APP_ID` / `WECHAT_OAUTH_APP_SECRET` |
| Alipay | `https://happyword.com.cn/v1/oauth/alipay/callback` | `https://happyword-zjumty-2580-terrymas-projects.vercel.app/v1/oauth/alipay/callback` | `ALIPAY_OAUTH_APP_ID` / `ALIPAY_OAUTH_APP_PRIVATE_KEY` / `ALIPAY_OAUTH_PUBLIC_KEY` |

微信网站应用使用 `snsapi_login`；支付宝网站登录使用 `auth_user`。两者首次登录通常不返回可验证邮箱，因此流程为：OAuth 回调 → `/family/oauth/bind-email?ticket=...` → 邮箱 OTP 验证 → 写入 `oauth_identities` → 种 `wm_session`。已绑定过的用户下次直接登录。

生产状态：支付宝已在开发者平台手动配置并实测通过；微信仍等待平台审核。

WeChat 登录默认隐藏。只有 `WECHAT_OAUTH_LOGIN_ENABLED=true` 且 AppID/Secret 都已配置时，登录页才显示 WeChat 按钮，`/v1/oauth/wechat/start` 才会跳转到微信授权页。

设计说明：[`docs/superpowers/specs/2026-05-16-parent-oauth-login-design.md`](../superpowers/specs/2026-05-16-parent-oauth-login-design.md)

---

## 3. 家长重置（忘记或更换邮箱）

家长账号靠邮箱 OTP 登录，没有密码。家长换邮箱时按下列顺序执行：

1. 在生产 Mongo 上：

   ```
   db.users.updateOne(
     { username: "<old-username>" },
     { $set: { email: "<new-email>", display_name: "<new-display-name>" } }
   )
   ```

2. 让家长在新邮箱发起 `/api/v1/family/{family_id}/auth/request-code`。
3. 家长收到验证码后即可登录新邮箱。绑定的设备 token 不变，孩子档案 / 学习数据
   保留不变。

> 没有"管理员代登录"功能。运维不能直接生成家长 cookie；只能通过 OTP 流程。

---

## 3. 配对恢复（家长说"二维码过期了"）

* 配对 token 默认 15 分钟过期。
* 家长重新进入"添加新设备"页 → 点击"重新生成"会创建新的 PairToken。
* 旧 token 可通过 `POST /family/{family_id}/devices/add/cancel` 显式失效。
* 客户端扫码失败时引导家长输入 6 位短码，短码与 token 同源（数据库 `pair_tokens.short_code`）。
* 如果 `dev-id-source = preferences_fallback`，提示家长在"设置 → 应用 → 持久化标识符"开启权限并重启 App。

---

## 4. 家庭词包（V0.6.3）

* 单个 family 上限：每个 pack ≤ 50 词，pack 数量无上限。
* 家长在 web 页面新建草稿、添加 / 编辑词、点击"发布"创建一个 `family_word_packs` 版本。
* 客户端通过 `GET /api/v1/family/{family_id}/family-packs/merged.json`（带 ETag）拉取合并 JSON。
* `published_packs.list` 视图：`{ pack_id, current_version, schema_version, word_count, updated_at }`。

### 回滚指定 pack 到上一个版本

* 家长 web → 词包详情 → "回滚到上一个版本" 按钮调用
  `POST /api/v1/family/{family_id}/family-packs/{pack_id}/rollback`，将 `pointer.current_version` 切回
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

1. 让家长在 web 端 `GET /api/v1/family/{family_id}/children/{id}/wishlist`（任意端点）确认 family / 设备绑定状态。
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

* 家长端 → 账号设置 → "删除账号" 调用 `POST /api/v1/family/{family_id}/account/delete`，
  写入 `users.scheduled_deletion_at = now + 7d`。
* 宽限期内任何时候可调用 `POST /api/v1/family/{family_id}/account/cancel-delete` 撤销。
* 后台需要每日跑：

  ```
  await account_deletion_service.sweep_scheduled_deletes(now=datetime.now(tz=UTC))
  ```

  推荐通过 CloudBase 定时函数或外部定时器调用一个内部端点。

* 级联删除顺序见 `account_deletion_service.cascade_delete_user`：
  redemption_requests → cloud_wishlist_items → synced_word_stats → child_profiles
  → device_bindings → family_pack_pointers → family_word_packs → family_pack_drafts
  → family_pack_definitions → families → parent_inbox_msgs → email_verifications
  → pair_tokens → users。每一步都会写 `audit_log` `account.delete_commit`。

---

## 8. 数据导出

* `POST /api/v1/family/{family_id}/account/export` 返回 `Content-Disposition: attachment` 的
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

* 客户端 ConfigPage → "解除设备绑定" → 弹出 PIN 校验 → `POST /api/v1/family/{family_id}/unbind`。
* 服务端把 `device_bindings.revoked_at = now` 并写 audit `device.unbind`。
* 客户端清空 `wordmagic_cloud` preferences（设备 token / family_id / child_profile_id）。
* 家长 web 上该设备会从"已绑定的设备"列表中消失（dashboard 过滤 `revoked_at IS NULL`）。

---

## 10. Inbox / 消息中心

* 每次孩子端发起兑换 → 写入 `parent_inbox_msgs`（kind=redemption_request）+ 尝试发邮件。
* 家长可以在 `/family/{family_id}/inbox` 看到全部消息，单条标记已读 `POST /api/v1/family/{family_id}/inbox/{id}/read`，
  全部标记已读 `POST /api/v1/family/{family_id}/inbox/mark-all-read`。
* 测试或调试时关闭邮件可以设置 `NOTIFICATION_EMAIL_ENABLED=false`，inbox 仍然写入。

---

## 11. 邮件 / Tencent SES 故障排查

| 症状 | 排查路径 |
| --- | --- |
| OTP 邮件没收到 | 生产先查 Tencent SES `SendEmail` 调用错误码 / CloudBase 日志；OTP 行已写入数据库 |
| `EMAIL_DELIVERY_DEGRADED` 在响应里出现 | provider raised `EmailDeliveryError`；查 Tencent SES 发送状态 / CloudBase 日志；用户可点"重新发送" |
| 兑换通知邮件丢失 | `NOTIFICATION_EMAIL_ENABLED` 是否被关；`Family.primary_email` / `User.email` 是否填 |
| Tencent SES `NotAuthenticatedSender` | 发信地址或域名未验证；检查 `TENCENT_SES_FROM_EMAIL` 和发信域名 SPF / DKIM / DMARC |
| Tencent SES `WithOutPermission` | 当前账号未开通非模板 `Simple` 发送；配置模板 ID 或申请特殊配置 |

### Tencent SES 切换 / 轮换流程

1. 在腾讯云邮件推送创建发信域名，建议 `mail.happyword.com.cn`。
2. 在 DNSPod 添加腾讯 SES 给出的 SPF / DKIM / DMARC 验证记录，直到控制台显示已验证。
3. 创建发信地址，例如 `noreply@mail.happyword.com.cn`。
4. 创建验证码模板，至少提供变量：`code`、`expires_in_minutes`。
5. 在 CloudBase Run 生产服务环境变量中设置
   `EMAIL_PROVIDER=tencent_ses_api`、`TENCENT_SES_SECRET_ID`、
   `TENCENT_SES_SECRET_KEY`、`TENCENT_SES_FROM_EMAIL`、
   `TENCENT_SES_OTP_TEMPLATE_ID`。
6. 触发 GitHub Actions `server-cloudbase-cd` 或在 CloudBase 控制台重启服务。
7. 用一个临时 `/api/v1/family/{family_id}/auth/request-code` 请求验证真发件成功。

---

## 12. 审计日志查询

`audit_log` 集合按 `(actor_id, ts desc)` 和 `(action, ts desc)` 双索引。常用查询：

* "谁删了 X 家庭"：`db.audit_log.find({ action: "account.delete_commit", target_id: "<family_id>" })`。
* "最近一周的兑换审批"：`db.audit_log.find({ action: { $in: ["redemption.approve", "redemption.reject"] }, ts: { $gte: ISODate("...") } })`。
* "某家长所有写动作"：`db.audit_log.find({ actor_id: "<parent_username>" }).sort({ ts: -1 }).limit(100)`。

---

## 13. 应急联系流程

1. 第一时间在 CloudBase Run 上确认是否有部署失败 / 实例不健康。
2. 若服务整体不可用：回滚到最近一个绿色 deployment。
3. 若仅某子模块出故障：临时关闭对应 feature flag（V0.7 引入），或在 Mongo 上修
   数据后让用户重试。
4. 若数据库被破坏：
   - 立刻禁止写流量（CloudBase env `READ_ONLY=true`，V0.7 计划）。
   - 从当前 Tencent-side MongoDB 备份恢复；Atlas 不再作为保留回滚路径。
   - 重放过期间隙的 `audit_log` 行（手工补 / 通知用户）。

---

## 14. 测试小贴士

* 服务端：`cd server && uv run pytest -k <substring>`，例：`-k cloud_wishlist`。
* 客户端：`hvigorw test --module entry@ohosTest`（要先连模拟器或真机）。
* 跑 OTP / SMTP 真发件：`uv run pytest -m live_smtp` 需在 `.env.local` 里配 SMTP 凭证。
* 永远在 PR / 部署前确认 `uv run ruff check`、`uv run mypy app`、`cd harmonyos && hvigorw assembleHap` 都通过。

---

## 15. 已知限制 / 后续 (V0.7 计划)

* 单家长账号；不支持夫妻协同审批。
* 邮件类通知；无 push（计划接 HarmonyOS Push Kit）。
* `cleanup_pending_deletions` 的运行时机靠运维定时调用；后续会集成到 CloudBase 定时函数。
* Inbox 还没有未读 badge 推送；前端 `unread_count` 仅靠刷新更新。
* 客户端 `PendingRedemptionOverlay` UI 实现仅有数据接口，可视化在 V0.7 完善。
