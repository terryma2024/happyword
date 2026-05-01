"""V0.6.1 — notification orchestration over an EmailProvider.

This layer formats user-facing email bodies (Chinese-only per spec §14 r3
lock-in #1) and translates underlying provider failures into the
`EmailDeliveryDegraded` soft-failure that callers persist alongside their
state and surface to users as `EMAIL_DELIVERY_DEGRADED`.
"""

import logging

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
