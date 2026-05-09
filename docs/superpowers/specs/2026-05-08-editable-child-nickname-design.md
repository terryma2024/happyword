# Editable child nickname (孩子档案 → 名字) — design

Date: 2026-05-08
Scope: small version change. Make the child's display name (`nickname`)
editable from the device on the **孩子档案** screen. Both server and
client need adjustments.

## Background

Today the bound child's `nickname` is set once during pair redeem
(`POST /api/v1/pair/redeem`) and can only be changed by a parent through
the parent-web UI:

- `PUT /api/v1/parent/children/{profile_id}` — parent JWT auth, accepts
  `{ nickname?, avatar_emoji? }`. Implemented by
  `child_profile_service.update` which already does `strip()`, max-32
  truncation, and `family_id` ownership scoping.

The HarmonyOS client renders the value read-only on
`pages/BoundDeviceInfoPage.ets`:

```
this.row('孩子档案', `${this.snap.avatarEmoji || '🦄'} ${this.snap.nickname || '宝贝'}`)
```

The device only holds a `device_token` (not a parent JWT), so it cannot
call the parent-side PUT. There is precedent for device-token-authed
mutations under `/api/v1/child/*`: `POST /api/v1/child/unbind`
(`current_device_binding` Bearer auth) revokes the binding from the
device.

## Goals

1. A user holding the device (already past the parent-PIN gate that
   guards `ConfigPage`) can change the child's display name from
   **孩子档案** without involving the parent web.
2. Server validates and persists the new name; the existing parent-web
   list/update flow keeps working unchanged.
3. The local credential cache (`CloudCredentials` preferences bag) is
   updated so the **🌙 \<nickname\>** badge on `HomePage` and the
   **孩子档案：…** button on `ConfigPage` reflect the new name on next
   `onPageShow`.

## Non-goals

- Avatar emoji editing (out of scope this version; stays read-only).
- Any new parent-side endpoint or schema change in
  `ChildProfileUpdateIn` / `ChildProfileOut`.
- Adding an extra parent-PIN gate on top of the existing one (the
  current `ConfigPage` PIN already gates the path into
  `BoundDeviceInfoPage`; the existing **解除绑定 (本地)** button on the
  same page also has no second gate).
- Soft-delete recovery, profile creation from device, or any change to
  the redeem / unbind flow.

## Server changes

### New endpoint: `PUT /api/v1/child/profile`

Auth: `Depends(current_device_binding)` — same Bearer device JWT used by
all `/api/v1/child/*` routes. Revoked bindings get the standard
`404 BINDING_REVOKED` from the dependency itself.

Request schema (`server/app/schemas/child_self.py`):

```
class ChildSelfProfileUpdateIn(BaseModel):
    nickname: str
```

Response schema (subset that mirrors the parent-side `ChildProfileOut`,
omitting `binding_id` and `created_at` which the device already
implicitly knows):

```
class ChildSelfProfileOut(BaseModel):
    profile_id: str
    family_id: str
    nickname: str
    avatar_emoji: str
    updated_at: datetime
```

Handler location: a new module `server/app/routers/child_profile.py`
(prefix `/api/v1/child`, tag `child-profile`) wired in `app/main.py`.
Keeping it separate from `child_wishlist.py` keeps each router focused
on one collection.

Handler outline:

```
@router.put("/profile", response_model=ChildSelfProfileOut)
async def put_self_profile(
    payload: ChildSelfProfileUpdateIn,
    binding: DeviceBinding = Depends(current_device_binding),
) -> ChildSelfProfileOut:
    if not payload.nickname.strip():
        raise HTTPException(400, {"error": {"code": "INVALID_NICKNAME",
                                            "message": "Nickname must not be empty"}})
    try:
        profile = await child_profile_service.update(
            profile_id=binding.child_profile_id,
            family_id=binding.family_id,
            nickname=payload.nickname,
        )
    except ChildProfileNotFound as e:
        raise HTTPException(404, {"error": {"code": "CHILD_NOT_FOUND",
                                            "message": "Child profile not found"}}) from e
    return ChildSelfProfileOut(...)
```

Reuses existing `child_profile_service.update` so:

- `strip()` and 32-char truncation already applied.
- `family_id` scoping already enforced (a tampered token to another
  family yields `ChildProfileNotFound` → 404).
- Whitespace-only handling: service treats it as no-op; we add an
  explicit 400 above so the device gets immediate feedback rather than
  a 200 with the old value.

### Tests (`server/tests/test_child_self_profile.py`)

Following the convey-style table test patterns already used in
`test_device_management.py`:

1. Happy path: redeem → device PUT with new nickname → 200 with stripped
   value; subsequent parent `GET /parent/children` shows the new name.
2. Whitespace-only nickname → 400 `INVALID_NICKNAME`.
3. Long nickname (>32 chars) → 200; stored value is truncated to 32.
4. Revoked binding → 404 `BINDING_REVOKED` (from the dep, no new code).
5. Tampered / wrong-family token (negative path via the existing dep):
   covered transitively because the dep returns 401 for an invalid
   token; no new test needed beyond what's already in
   `test_device_management.py`.

## Client changes

### New service: `entry/src/main/ets/services/ChildProfileApiClient.ets`

Mirrors the slim `BindingApiClient` / `DeviceUnbindClient` shape:

- Constructor `(adapter: ParentFetchAdapter, baseUrl: string)`
- `async updateNickname(deviceToken: string, nickname: string):
  Promise<UpdatedChildProfile>`
- Sends `PUT ${baseUrl}/api/v1/child/profile` with header
  `Authorization: Bearer ${deviceToken}` and body
  `{"nickname": ...}`.
- Error envelope parsed via the existing `parseErrorCode` style; throws
  `BindingHttpError`-equivalent (or new `ChildProfileHttpError` with the
  same `code` / `status` shape — TBD during implementation, lean on the
  simpler choice that keeps existing call sites happy).

### `BoundDeviceInfoPage.ets` updates

Replace the read-only **孩子档案** row with an interactive variant:

- Same row label/value layout, plus a small **✏️** button at the row's
  end. Tap → opens a transparent sheet / dialog overlay (a new
  lightweight `@Builder editDialog()` inside the page; no new top-level
  component needed for a single-field edit).
- Dialog content:
  - Title: **修改孩子的名字**
  - `TextInput` prefilled with current nickname, `maxLength(32)`,
    `placeholder('宝贝')`.
  - Buttons: **保存** (disabled while saving / when input is empty
    after trim), **取消**.
  - Inline red hint area for error text returned from the server.
- On **保存**:
  1. Trim input. Reject empty.
  2. Call `ChildProfileApiClient.updateNickname(snap.deviceToken,
     trimmed)`.
  3. On success: build a new `CloudCredentialsSnapshot` with the
     server-returned `nickname` (server may have truncated to 32),
     persist via `credentials.saveBinding(updatedSnap)`, close dialog,
     update `this.snap`.
  4. On HTTP error: show the server message (or a Chinese fallback
     mapped from the `error.code`), keep dialog open.
  5. On network error: show **网络错误，请稍后重试**.
- The avatar emoji portion of the value remains untouched.

### Persistence / cache invalidation

`CloudCredentials.saveBinding` already writes the full snapshot bag
(including `nickname`) to the `wordmagic_cloud` preferences and flushes.
Reusing it ensures every other reader (`HomePage` 🌙 badge,
`ConfigPage` `孩子档案：…` button label) picks the new value up on next
`onPageShow` without a code change in those pages.

### What does NOT change

- `BindingApiClient.redeem` — still seeds `nickname` from server response.
- `DeviceUnbindClient`, `ScanBindingPage` — unrelated.
- Parent-web flow at `PUT /api/v1/parent/children/{profile_id}` — still
  the canonical path for parent-side edits. Both clients write to the
  same `child_profiles` collection and respect the same 32-char cap.

## Validation rules (single source of truth)

| Rule           | Server                                  | Client                                   |
|----------------|-----------------------------------------|------------------------------------------|
| Min length     | 1 after `strip()` (else 400)            | Save button disabled when empty after trim |
| Max length     | Truncated to 32 by service              | `TextInput.maxLength(32)`                |
| Charset        | None (Unicode allowed)                  | None                                     |
| Whitespace-only| 400 INVALID_NICKNAME                    | Save disabled                            |

## Out-of-scope follow-ups (not this PR)

- Edit avatar emoji from device.
- Audit-log entry for device-side nickname edit (parent edits already
  audit via the parent path; we can add one here if QA wants the
  symmetry, but it is not required for the feature to ship).
- Live push to other devices in the same family (the next `onPageShow`
  on each surface re-reads local prefs, which is enough for V1).

## Testing summary

- Server: 4 new pytest cases in
  `server/tests/test_child_self_profile.py`; full
  `cd server && uv run pytest` must end with **0 errors / 0 warnings**.
- Client: per project AGENTS.md the HarmonyOS UI suite isn't run on
  cloud agents; manual verification on a paired emulator (set name,
  verify HomePage badge + ConfigPage button refresh after returning).
  No new ohos-test required for V1; the existing `BoundDeviceInfoPage`
  has no UI test today and the row is small.
