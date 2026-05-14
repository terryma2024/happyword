# Wishlist and Redemption Protocol

## Child Device

- Pull wishlist: `GET /api/v1/family/{family_id}/wishlist`
- Sync custom wishlist items: `POST /api/v1/family/{family_id}/wishlist/sync-custom`
- Create redemption request: `POST /api/v1/family/{family_id}/redemption-requests`
- Poll/list requests: `GET /api/v1/family/{family_id}/redemption-requests`, `GET /api/v1/family/{family_id}/redemption-requests/poll`

## Parent

- View child wishlist: `GET /api/v1/family/{family_id}/children/{profile_id}/wishlist`
- Mutate wishlist item: `POST|PUT|DELETE /api/v1/family/{family_id}/wishlist-items/{item_id}`
- Review redemption: `POST /api/v1/family/{family_id}/redemption-requests/{request_id}/approve|reject`

Client rules:

- Child UI can optimistically show pending redemption after local creation, but should reconcile with poll response.
- Parent decision is authoritative.
- Coin accounting remains local-first until a cloud wallet contract is introduced.
