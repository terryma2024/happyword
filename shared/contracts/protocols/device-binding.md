# Device Binding Protocol

## Flow

1. Parent creates token with `POST /api/v1/family/{family_id}/pair/create`.
2. Parent shows QR or short code from `PairCreateOut`.
3. Child redeems via `POST /api/v1/public/pair/redeem` using token or 6-digit short code plus stable `device_id`.
4. Server returns device credentials and family context in `PairRedeemOut`.
5. Child stores device token in platform-secure storage where available.
6. Child uses device token for child-device APIs under `/api/v1/family/{family_id}/**`.

## Tenant Boundary

The server derives `family_id` from `DeviceBinding`. Clients may display family labels, but must not be treated as authoritative for authorization.
