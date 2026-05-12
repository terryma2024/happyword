# Server Device Unbind Design

## Goal

Add a parent-facing device unbind flow that requires email OTP verification before unlinking a child device, while keeping the data recoverable for admin restore and future same-device reactivation.

## User Flow

On the parent dashboard, each active device card shows a red "解除绑定" link beside "查看学习报告". The link opens a confirmation page for that binding and sends a 6-digit OTP to the current parent email. The parent must submit the OTP before the system performs the unbind.

If the OTP is missing, invalid, expired, or over the attempt limit, the binding remains active and the confirmation page shows an error. On success, the parent returns to the dashboard with a success flash.

## Data Semantics

Unbinding is a soft delete of both sides of the relationship:

- `DeviceBinding.revoked_at` is set to the current UTC time.
- The matching `ChildProfile.deleted_at` is set to the same current UTC time.

After unbind, parent dashboard lists and report pages must treat the device/profile as inactive. Existing learning history remains queryable by administrators and can be restored.

## Restore And Reactivation

Admin restore clears `DeviceBinding.revoked_at` and `ChildProfile.deleted_at`, unless another active binding already owns the same device id. Same-family rebinding with the same `device_id` reuses the previous revoked binding and child profile, clearing both soft-delete fields and updating the device metadata.

## Testing

Use TDD for the semantic gap:

- First update the parent unbind test to assert that a successful OTP unbind also sets `ChildProfile.deleted_at`.
- Run the narrow test and confirm it fails because current code only revokes the binding.
- Implement the smallest code change in the parent unbind POST handler.
- Run targeted server tests for parent unbind, admin restore, and same-device reactivation.
