# CloudBase Tools

Small operator scripts for the CloudBase Run migration.

## Default Domain Smoke

Run the public no-secret smoke against the CloudBase staging and production
default domains:

```bash
bash tools/cloudbase/smoke-default-domains.sh
```

Override the targets when needed:

```bash
CLOUDBASE_STAGING_BASE_URL=https://staging.example.tcloudbase.com \
CLOUDBASE_PROD_BASE_URL=https://prod.example.tcloudbase.com \
bash tools/cloudbase/smoke-default-domains.sh
```

After `PREVIEW_MANIFEST_INLINE_JSON` is configured on CloudBase Run, require the
M8A shared staging manifest row:

```bash
CLOUDBASE_EXPECT_PREVIEW_TITLE="CloudBase Staging" \
bash tools/cloudbase/smoke-default-domains.sh
```

The script only calls public endpoints and never reads CloudBase credentials or
application secrets.
