# Schema Index

The first contract pass keeps canonical JSON Schema definitions inside `../openapi/happyword-api.openapi.json` under `components.schemas`.

Use this index when mapping native models:

- Auth: `LoginRequest`, `LoginResponse`, `MeResponse`
- Public packs: `PackResponse`, `PackWord`
- Global packs: `GlobalPackCreateIn`, `GlobalPackDefinitionOut`, `GlobalPacksLatestOut`
- Family packs: `FamilyPackCreateIn`, `FamilyPackDefinitionOut`, `FamilyPackDraftOut`, `FamilyPacksMergedOut`
- Pairing: `PairCreateOut`, `PairStatusOut`, `PairRedeemIn`, `PairRedeemOut`
- Child profile: `ChildSelfProfileUpdateIn`, `ChildSelfProfileOut`
- Word stats: `WordStatsSyncIn`, `WordStatsSyncOut`, `WordStatsListOut`
- Wishlist and redemptions: `CloudWishlistListOut`, `ChildWishlistSyncIn`, `RedemptionRequestOut`, `RedemptionPollOut`
- Parent auth and account: `RequestCodeIn`, `VerifyCodeIn`, `ParentMeOut`, `AccountStatusOut`, `AccountExportOut`
- Admin content: `WordCreateIn`, `WordOut`, `CategoryOut`, `PublishOut`, `LessonDraftOut`, `DraftOut`, `StatsOut`

Do not hand-edit schema copies in this directory until the project needs per-language code generation. When that happens, add an extraction script and drift test in the same change.
