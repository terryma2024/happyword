# CloudBase Run Operations Runbook

## Current State

- Runtime owner: CloudBase Run
- Current production domain: happyword.cool
- Tencent-owned candidate production domain: happyword.com.cn
- Production service name: happyword-server
- Staging service name: happyword-server-staging
- MongoDB provider: MongoDB Atlas
- Asset storage provider during Wave A: Vercel Blob
- Asset storage provider during Wave B: undecided, CloudBase Storage or Tencent COS

## CloudBase Environment

- Environment name: happyword
- Environment tier: 体验版
- Environment ID: happyword-d5g66zmq8ef2430b8
- Region: ap-shanghai
- HTTP Access Service: enabled
- Production default domain: happyword-d5g66zmq8ef2430b8-1429584068.ap-shanghai.app.tcloudbase.com
- Staging default domain:
- Custom domains: none
- Routes: none

## Domain and DNS Management

### Domain Strategy

- Current production and rollback domain: `happyword.cool`
- Tencent-owned candidate production domain: `happyword.com.cn`
- Additional Tencent-registered reserve domain: `happyword.cloud`
- Cutover rule: do not change `happyword.cool` DNS until CloudBase staging and
  production smoke checks are ready.
- Open decision: whether the final mainland production host remains
  `happyword.cool` or moves to `happyword.com.cn`.

### Tencent Cloud Domain Console Findings

Snapshot date: 2026-05-17.

| Domain | Service status | DNS status | Owner | Registrar | Registered at | Expires at | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `happyword.com.cn` | 正常 | DNSPod | 马天一 | 腾讯云 | 2026-05-17 18:07:10 | 2027-05-17 18:07:10 | New Tencent candidate production domain. Apex DNS has no answer yet. |
| `happyword.cloud` | 正常 | DNSPod | 马天一 | 帝思普 | 2026-05-17 18:07:12 | 2027-05-17 18:07:12 | Reserve or secondary domain. |
| `happyword.cool` | Existing production | Vercel DNS | Not checked in Tencent console | Vercel | Not checked | Not checked | Current production and rollback domain. |

Tencent Cloud real-name template:

- Owner template: 马天一
- Status: 已实名审核
- Progress: 100%
- Submitted at: 2026-05-17 17:36:27

### DNS Lookup Snapshot

Snapshot date: 2026-05-17.

| Domain | Query | Result |
| --- | --- | --- |
| `happyword.cool` | `NS` | `ns1.vercel-dns.com`, `ns2.vercel-dns.com` |
| `happyword.cool` | apex A | `216.150.16.65`, `216.150.1.65` |
| `happyword.com.cn` | `NS` | `cob.dnspod.net`, `user.dnspod.net` |
| `happyword.com.cn` | apex A/CNAME | no answer yet |

### CloudBase Console Findings

Snapshot date: 2026-05-17.

- Environment name: `happyword`
- Environment tier: `体验版`
- Environment ID: `happyword-d5g66zmq8ef2430b8`
- Region: `ap-shanghai`
- HTTP Access Service: enabled
- Default HTTP Access domain:
  `happyword-d5g66zmq8ef2430b8-1429584068.ap-shanghai.app.tcloudbase.com`
- Custom domain table: empty
- Route table: empty
- Cloud functions: none
- Web security domains currently include the CloudBase default domains and
  Tencent console defaults.

Snapshot date: 2026-05-18.

- CloudBase CLI version checked through `npx --package @cloudbase/cli tcb`:
  `3.3.3`.
- CLI device authorization completed from the logged-in Tencent Cloud console.
- Cloud Run service list: empty; `happyword-server-staging` has not been
  created yet.
- Cloud Run deploy options visible in console: Git repository, container image,
  public Git repository, and local code upload.
- Cloud Run fixed public IP: disabled.
- Image repository: personal image repository selected.
- Package: CloudBase free trial tier, valid until 2026-11-08.
- Package resource points consumed: 0.07 / 3000.
- Pay-as-you-go toggle: off.
- Cloud Run current usage: 0 CPU seconds, 0 GBs memory, 0 Byte outbound traffic.
- Attempted to enable pay-as-you-go on 2026-05-18. Tencent CloudBase blocked the
  action with: free trial tier does not support resource-pack add-ons or
  pay-as-you-go; upgrade to a paid package first if needed.

M2 staging is blocked until the operator confirms whether to upgrade from the
free trial tier. Do not create `happyword-server-staging` with dummy or
production values.

Required staging secrets:

- `MONGODB_URI` - present in local `~/.env.tcb` on 2026-05-18
- `MONGO_DB_NAME` - not present in local `~/.env.tcb`; use
  `happyword_cloudbase_staging` unless the operator specifies another value
- `JWT_SECRET` - present in local `~/.env.tcb` on 2026-05-18
- `ADMIN_BOOTSTRAP_USER` - present in local `~/.env.tcb` on 2026-05-18
- `ADMIN_BOOTSTRAP_PASS` - present in local `~/.env.tcb` on 2026-05-18
- `CRON_SECRET` - not present in local `~/.env.tcb`; generate a new staging-only
  value before configuring CloudBase
- `OPENAI_API_KEY` - present in local `~/.env.tcb` on 2026-05-18
- `PREVIEW_MANIFEST_BLOB_URL` - not present in local `~/.env.tcb`; required only
  if staging must validate `/api/v1/public/preview-urls.json`
- `BLOB_READ_WRITE_TOKEN`, only if upload paths must be tested during staging

Required operator decisions:

- Whether to upgrade the CloudBase environment from free trial to a paid package
  so pay-as-you-go can be enabled.
- Whether MongoDB Atlas will allow all CloudBase egress IPs for staging, or
  whether Cloud Run fixed public IP should be enabled and added to the Atlas
  allowlist first.

### Filing and Certificate Readiness

CloudBase filing page says mainland China servers used for websites or apps
must complete ICP filing and obtain an ICP filing number before opening access.

Current blockers shown for the `happyword` CloudBase environment:

- Current tier does not support filing: `体验版`
- Cloud Run fixed IP is not enabled

Required before production custom-domain binding:

- Upgrade the CloudBase environment to a filing-eligible tier, personal edition
  or above.
- Enable Cloud Run fixed IP.
- Complete ICP filing or access filing for the chosen production domain.
- Confirm SSL certificate availability in CloudBase custom-domain binding. The
  custom-domain table currently has certificate status columns, but no
  `happyword.cool` or `happyword.com.cn` binding exists yet, so no usable
  certificate is currently shown.

## Deployment Commands

```bash
cd server
tcb cloudrun deploy -e "$TCB_ENV_ID" -s happyword-server --port 8080 --source . --force
```

## Health Checks

```bash
curl -fsS "$CLOUDBASE_BASE_URL/api/v1/public/health"
curl -fsS -I "$CLOUDBASE_BASE_URL/api/v1/public/packs/latest.json"
curl -fsS -I "$CLOUDBASE_BASE_URL/privacy"
curl -fsS -I "$CLOUDBASE_BASE_URL/admin/login"
```

## Environment Variable Inventory

Record names only in this file. Store actual values in Vercel, CloudBase, GitHub
Actions secrets, Tencent Cloud Secret Manager, or the local operator password
manager.

### Core Runtime

| Variable | Required for | Notes |
| --- | --- | --- |
| `MONGODB_URI` | Staging, production | MongoDB connection string. Keep production and staging values separate. |
| `MONGO_DB_NAME` | Staging, production | Database name. Staging should use a non-production DB. |
| `JWT_SECRET` | Staging, production | Must match the old production value during cutover so existing sessions remain valid. |
| `ADMIN_BOOTSTRAP_USER` | Staging, production | Seeds or updates the bootstrap admin row at startup. |
| `ADMIN_BOOTSTRAP_PASS` | Staging, production | Seeds or updates the bootstrap admin password at startup. |
| `OPENAI_API_KEY` | Production, optional staging | Required for lesson image extraction and LLM-assisted admin flows. |
| `CORS_ALLOW_ORIGINS` | Staging, production | Current default can remain `*` unless tightened later. |
| `LOG_LEVEL` | Staging, production | Use `info` for normal deployment. |
| `PARENT_WEB_BASE_URL` | Staging, production | Canonical parent web shell base URL for the deployed environment. |
| `OAUTH_CANONICAL_BASE_URL` | Staging, production | Canonical OAuth host. Production should be `https://happyword.cool`. |
| `SESSION_COOKIE_DOMAIN` | Production | Use `.happyword.cool` for production; leave empty for staging default domains. |
| `ADMIN_SESSION_COOKIE_NAME` | Staging, production | Current value is `wm_admin_session`. |

### Cron

| Variable | Required for | Notes |
| --- | --- | --- |
| `CRON_SECRET` | Staging, production, cron caller | Shared bearer secret between CloudBase Run and the timer caller. |

### Wave A Vercel Blob Compatibility

| Variable | Required for | Notes |
| --- | --- | --- |
| `PREVIEW_MANIFEST_BLOB_URL` | Wave A staging, Wave A production | Keeps `/api/v1/public/preview-urls.json` working while Vercel Blob remains the manifest source. |
| `BLOB_READ_WRITE_TOKEN` | Wave A upload paths | Keeps existing asset upload code working until storage moves to CloudBase Storage or Tencent COS. |

### OAuth Providers

| Variable | Required for | Notes |
| --- | --- | --- |
| `GOOGLE_OAUTH_CLIENT_ID` | Google OAuth | Set only if Google OAuth remains enabled in the target environment. |
| `GOOGLE_OAUTH_CLIENT_SECRET` | Google OAuth | Set only if Google OAuth remains enabled in the target environment. |
| `APPLE_OAUTH_CLIENT_ID` | Sign in with Apple | Set only if Apple OAuth remains enabled in the target environment. |
| `APPLE_OAUTH_TEAM_ID` | Sign in with Apple | Set only if Apple OAuth remains enabled in the target environment. |
| `APPLE_OAUTH_KEY_ID` | Sign in with Apple | Set only if Apple OAuth remains enabled in the target environment. |
| `APPLE_OAUTH_PRIVATE_KEY` | Sign in with Apple | Keep escaped/newline formatting compatible with `server/app/config.py`. |
| `WECHAT_OAUTH_APP_ID` | WeChat OAuth | Set only if WeChat OAuth remains enabled in the target environment. |
| `WECHAT_OAUTH_APP_SECRET` | WeChat OAuth | Set only if WeChat OAuth remains enabled in the target environment. |
| `ALIPAY_OAUTH_APP_ID` | Alipay OAuth | Set only if Alipay OAuth remains enabled in the target environment. |
| `ALIPAY_OAUTH_APP_PRIVATE_KEY` | Alipay OAuth | Keep escaped/newline formatting compatible with `server/app/config.py`. |
| `ALIPAY_OAUTH_PUBLIC_KEY` | Alipay OAuth | Keep escaped/newline formatting compatible with `server/app/config.py`. |

## Rollback

- CloudBase version rollback:
- DNS rollback to Vercel: keep or restore `happyword.cool` nameservers to
  `ns1.vercel-dns.com` and `ns2.vercel-dns.com`.
- Known-good Vercel production URL: `https://happyword.cool`
