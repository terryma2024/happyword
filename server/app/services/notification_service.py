"""V0.6.1 — notification orchestration over an EmailProvider.

This layer formats user-facing email bodies (Chinese-only per spec §14 r3
lock-in #1) and translates underlying provider failures into the
`EmailDeliveryDegraded` soft-failure that callers persist alongside their
state and surface to users as `EMAIL_DELIVERY_DEGRADED`.

V0.6.7 extends the layer with `write_inbox_msg` and
`send_redemption_email` so a single notification gesture creates an inbox
row + (best-effort) email.
"""

import logging
import secrets
from datetime import UTC, datetime
from typing import Any

from app.config import get_settings
from app.models.parent_inbox_msg import ParentInboxKind, ParentInboxMsg
from app.services.email_provider import EmailDeliveryError, EmailProvider

logger = logging.getLogger(__name__)


class EmailDeliveryDegraded(Exception):
    """Soft failure signalling the email did not go out but state should persist.

    Routers should still write the OTP / inbox row / notification record and
    return success to the caller, but include `EMAIL_DELIVERY_DEGRADED` in the
    response so the UI can offer a retry hint.
    """


async def send_email(
    provider: EmailProvider,
    *,
    to: str,
    subject: str,
    html: str,
    text: str,
) -> None:
    """Single funnel for all outbound mail; raises EmailDeliveryDegraded on failure."""
    try:
        await provider.send(to=to, subject=subject, html=html, text=text)
    except EmailDeliveryError as e:
        logger.warning("email delivery degraded to=%s subject=%r: %s", to, subject, e)
        raise EmailDeliveryDegraded(str(e)) from e


async def send_otp_email(
    provider: EmailProvider,
    *,
    to: str,
    code: str,
    expires_in_minutes: int,
) -> None:
    """Send the parent-account OTP. Body is Chinese-only by spec r3 lock-in #1."""
    subject = f"快乐背单词 - 验证码 {code}"
    text = (
        f"您的快乐背单词验证码是：{code}\n\n"
        f"验证码有效期 {expires_in_minutes} 分钟。如非本人操作，请忽略本邮件。\n\n"
        "如果未在收件箱看到本邮件，请检查垃圾邮件文件夹，并将本发件地址加入通讯录，避免后续邮件被拦截。\n"
    )
    html = (
        '<div style="font-family:system-ui,-apple-system,sans-serif;max-width:480px;'
        'margin:0 auto;padding:24px;color:#222">'
        '<h2 style="margin:0 0 16px;font-size:18px">快乐背单词</h2>'
        '<p style="font-size:14px;color:#444;margin:0 0 8px">您的验证码：</p>'
        '<p style="font-size:32px;font-weight:700;letter-spacing:8px;color:#111;'
        f'margin:8px 0">{code}</p>'
        '<p style="font-size:12px;color:#888;margin:8px 0">'
        f"有效期 {expires_in_minutes} 分钟。如非本人操作，请忽略本邮件。</p>"
        '<p style="font-size:12px;color:#888;margin:8px 0">'
        "如果未在收件箱看到本邮件，请检查垃圾邮件文件夹。</p>"
        "</div>"
    )
    await send_email(provider, to=to, subject=subject, html=html, text=text)


# ---------------------------------------------------------------------------
# V0.6.7 — inbox + redemption notifications
# ---------------------------------------------------------------------------


def _gen_msg_id() -> str:
    return f"msg-{secrets.token_hex(4)}"


async def write_inbox_msg(
    *,
    family_id: str,
    parent_user_id: str,
    kind: ParentInboxKind | str,
    title: str,
    body_md: str,
    related_resource: dict[str, Any] | None = None,
) -> ParentInboxMsg:
    """Create a single ParentInboxMsg row. Used by every alert gesture."""
    msg = ParentInboxMsg(
        msg_id=_gen_msg_id(),
        family_id=family_id,
        parent_user_id=parent_user_id,
        kind=ParentInboxKind(kind) if not isinstance(kind, ParentInboxKind) else kind,
        title=title.strip()[:200],
        body_md=body_md[:2048],
        related_resource=related_resource,
        created_at=datetime.now(tz=UTC),
    )
    await msg.insert()
    return msg


async def send_redemption_email(
    provider: EmailProvider,
    *,
    to: str,
    child_nickname: str,
    item_display_name: str,
    cost_coins: int,
    request_id: str,
) -> None:
    """Notify parent that the child requested a redemption.

    Subject line is fixed by spec §V0.6.7 contract #2:
    `[Word Magic] <nickname> 想兑换 <item>`. Body is Chinese-only and
    deep-links into the parent web inbox.
    """
    settings = get_settings()
    subject = f"[Word Magic] {child_nickname} 想兑换 {item_display_name}"
    inbox_url = f"{settings.parent_web_base_url.rstrip('/')}/parent/redemptions"
    text = (
        f"{child_nickname} 想兑换 {item_display_name}（{cost_coins} 金币）。\n\n"
        f"请前往家长后台审批：\n{inbox_url}\n\n"
        f"申请编号：{request_id}\n"
    )
    html = (
        '<div style="font-family:system-ui,-apple-system,sans-serif;max-width:480px;'
        'margin:0 auto;padding:24px;color:#222">'
        '<h2 style="margin:0 0 16px;font-size:18px">快乐背单词</h2>'
        f"<p>{child_nickname} 想兑换 <strong>{item_display_name}</strong>"
        f"（{cost_coins} 金币）。</p>"
        '<p style="margin:16px 0">'
        f'<a href="{inbox_url}" style="display:inline-block;background:#0ea5e9;'
        'color:#fff;padding:8px 16px;border-radius:6px;text-decoration:none">'
        "前往审批"
        "</a></p>"
        f'<p style="color:#888;font-size:12px">申请编号：{request_id}</p>'
        "</div>"
    )
    await send_email(provider, to=to, subject=subject, html=html, text=text)


def send_weekly_digest_stub() -> None:
    """Placeholder for the V0.7 weekly digest job; kept here so feature
    flags can flip it on without yet another module."""
    return None
