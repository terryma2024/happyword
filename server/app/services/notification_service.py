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
from collections.abc import Mapping
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
    template_key: str | None = None,
    template_data: Mapping[str, str] | None = None,
) -> None:
    """Single funnel for all outbound mail; raises EmailDeliveryDegraded on failure."""
    try:
        await provider.send(
            to=to,
            subject=subject,
            html=html,
            text=text,
            template_key=template_key,
            template_data=template_data,
        )
    except EmailDeliveryError as e:
        logger.warning("email delivery degraded to=%s subject=%r: %s", to, subject, e)
        raise EmailDeliveryDegraded(str(e)) from e
    except Exception as e:
        logger.warning(
            "email delivery degraded by unexpected provider error to=%s subject=%r: %s",
            to,
            subject,
            e,
        )
        raise EmailDeliveryDegraded(str(e)) from e


async def send_otp_email(
    provider: EmailProvider,
    *,
    to: str,
    code: str,
    expires_in_minutes: int,
) -> None:
    """Send the parent-account OTP. Body is Chinese-only by spec r3 lock-in #1."""
    subject = f"魔法背单词 - 验证码 {code}"
    text = (
        f"您的魔法背单词验证码是：{code}\n\n"
        f"验证码有效期 {expires_in_minutes} 分钟。如非本人操作，请忽略本邮件。\n\n"
        "如果未在收件箱看到本邮件，请检查垃圾邮件文件夹，并将本发件地址加入通讯录，避免后续邮件被拦截。\n"
    )
    html = (
        '<div style="font-family:system-ui,-apple-system,sans-serif;max-width:480px;'
        'margin:0 auto;padding:24px;color:#222">'
        '<h2 style="margin:0 0 16px;font-size:18px">魔法背单词</h2>'
        '<p style="font-size:14px;color:#444;margin:0 0 8px">您的验证码：</p>'
        '<p style="font-size:32px;font-weight:700;letter-spacing:8px;color:#111;'
        f'margin:8px 0">{code}</p>'
        '<p style="font-size:12px;color:#888;margin:8px 0">'
        f"有效期 {expires_in_minutes} 分钟。如非本人操作，请忽略本邮件。</p>"
        '<p style="font-size:12px;color:#888;margin:8px 0">'
        "如果未在收件箱看到本邮件，请检查垃圾邮件文件夹。</p>"
        "</div>"
    )
    await send_email(
        provider,
        to=to,
        subject=subject,
        html=html,
        text=text,
        template_key="otp",
        template_data={
            "code": code,
            "expires_in_minutes": str(expires_in_minutes),
        },
    )


async def send_device_unbind_otp_email(
    provider: EmailProvider,
    *,
    to: str,
    code: str,
    expires_in_minutes: int,
    child_nickname: str,
    device_tail: str,
) -> None:
    """OTP for parent-web device unbind; distinct copy from login OTP."""
    nickname = child_nickname.strip() or "孩子"
    tail = device_tail.strip() or "----"
    subject = f"魔法背单词 - 解除设备绑定验证码 {code}"
    text = (
        f"您正在家长后台申请解除「{nickname}」这台学习设备的绑定。\n\n"
        f"验证码：{code}\n"
        f"设备尾号：{tail}\n\n"
        f"请在「解除设备绑定」确认页输入以上 6 位验证码。\n"
        f"验证码有效期 {expires_in_minutes} 分钟。\n"
        "如非本人操作，请忽略本邮件，设备绑定将保持不变。\n\n"
        "如果未在收件箱看到本邮件，请检查垃圾邮件文件夹，并将本发件地址加入通讯录，避免后续邮件被拦截。\n"
    )
    html = (
        '<div style="font-family:system-ui,-apple-system,sans-serif;max-width:480px;'
        'margin:0 auto;padding:24px;color:#222">'
        '<h2 style="margin:0 0 16px;font-size:18px">解除设备绑定</h2>'
        f'<p style="font-size:14px;color:#444;margin:0 0 12px">'
        f"您正在家长后台申请解除 <strong>{nickname}</strong> 这台学习设备的绑定。</p>"
        '<p style="font-size:14px;color:#444;margin:0 0 4px">验证码：</p>'
        '<p style="font-size:32px;font-weight:700;letter-spacing:8px;color:#111;'
        f'margin:8px 0">{code}</p>'
        '<p style="font-size:13px;color:#555;margin:0 0 8px">设备尾号：'
        f'<span style="font-family:monospace">{tail}</span></p>'
        '<p style="font-size:12px;color:#888;margin:8px 0">'
        "请在「解除设备绑定」确认页输入以上 6 位验证码。"
        f"有效期 {expires_in_minutes} 分钟。如非本人操作，请忽略本邮件。</p>"
        '<p style="font-size:12px;color:#888;margin:8px 0">'
        "如果未在收件箱看到本邮件，请检查垃圾邮件文件夹。</p>"
        "</div>"
    )
    await send_email(
        provider,
        to=to,
        subject=subject,
        html=html,
        text=text,
        template_key="device_unbind_otp",
        template_data={
            "code": code,
            "expires_in_minutes": str(expires_in_minutes),
            "child_nickname": nickname,
            "device_tail": tail,
        },
    )


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
    family_id: str,
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
    fid = family_id.strip() or "_"
    subject = f"[Word Magic] {child_nickname} 想兑换 {item_display_name}"
    inbox_url = f"{settings.parent_web_base_url.rstrip('/')}/family/{fid}/redemptions"
    text = (
        f"{child_nickname} 想兑换 {item_display_name}（{cost_coins} 金币）。\n\n"
        f"请前往家长后台审批：\n{inbox_url}\n\n"
        f"申请编号：{request_id}\n"
    )
    html = (
        '<div style="font-family:system-ui,-apple-system,sans-serif;max-width:480px;'
        'margin:0 auto;padding:24px;color:#222">'
        '<h2 style="margin:0 0 16px;font-size:18px">魔法背单词</h2>'
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
    await send_email(
        provider,
        to=to,
        subject=subject,
        html=html,
        text=text,
        template_key="redemption",
        template_data={
            "child_nickname": child_nickname,
            "item_display_name": item_display_name,
            "cost_coins": str(cost_coins),
            "request_id": request_id,
            "inbox_url": inbox_url,
        },
    )


def send_weekly_digest_stub() -> None:
    """Placeholder for the V0.7 weekly digest job; kept here so feature
    flags can flip it on without yet another module."""
    return None
