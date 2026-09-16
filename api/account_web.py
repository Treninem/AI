from __future__ import annotations

import html
from urllib.parse import parse_qs

from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse

from api.account_store import AccountError, AccountStore, AuthenticationError


SECURITY_HEADERS = {
    "Cache-Control": "no-store",
    "Pragma": "no-cache",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Content-Security-Policy": (
        "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; "
        "base-uri 'none'; frame-ancestors 'none'"
    ),
}


def _page(title: str, body: str, *, status_code: int = 200) -> HTMLResponse:
    document = f"""<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title>
<style>
:root{{color-scheme:dark light}}body{{font-family:system-ui,-apple-system,sans-serif;max-width:560px;margin:8vh auto;padding:24px;line-height:1.5}}
main{{border:1px solid currentColor;border-radius:18px;padding:24px}}label{{display:block;margin-top:14px}}input{{box-sizing:border-box;width:100%;padding:12px;margin-top:6px;border-radius:10px;border:1px solid #888}}button{{margin-top:18px;padding:12px 18px;border-radius:10px;border:0;font-weight:700;cursor:pointer}}.muted{{opacity:.72}}
</style>
</head>
<body><main>{body}</main></body>
</html>"""
    return HTMLResponse(document, status_code=status_code, headers=SECURITY_HEADERS)


async def _form_fields(request: Request) -> dict[str, list[str]] | None:
    content_type = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
    if content_type != "application/x-www-form-urlencoded":
        return None
    raw = await request.body()
    try:
        return parse_qs(raw.decode("utf-8"), keep_blank_values=True, strict_parsing=False)
    except UnicodeDecodeError:
        return {}


def create_account_web_router(accounts: AccountStore) -> APIRouter:
    router = APIRouter(include_in_schema=False)

    @router.get("/verify-email", response_class=HTMLResponse)
    def verify_email_page(token: str = Query(min_length=16, max_length=512)) -> HTMLResponse:
        # GET is deliberately non-mutating. Mail security scanners and link preview
        # bots commonly prefetch URLs; consuming a verification credential on GET
        # could otherwise confirm an address without a deliberate user action.
        escaped = html.escape(token, quote=True)
        return _page(
            "AuroraFox — подтверждение email",
            f"""<h1>Подтвердите email</h1>
<p>Нажмите кнопку, чтобы подтвердить адрес для аккаунта AuroraFox.</p>
<form method="post" action="/verify-email" autocomplete="off">
<input type="hidden" name="token" value="{escaped}">
<button type="submit">Подтвердить email</button>
</form>""",
        )

    @router.post("/verify-email", response_class=HTMLResponse)
    async def verify_email_submit(request: Request) -> HTMLResponse:
        fields = await _form_fields(request)
        if fields is None:
            return _page("AuroraFox — ошибка", "<h1>Неверный формат запроса</h1>", status_code=415)
        token = str((fields.get("token") or [""])[0])
        if not token or len(token) > 512:
            return _page(
                "AuroraFox — подтверждение email",
                "<h1>Ссылка недействительна</h1><p>Ссылка истекла, уже использована или была отозвана.</p>",
                status_code=400,
            )
        try:
            accounts.verify_email(token)
        except AuthenticationError:
            return _page(
                "AuroraFox — подтверждение email",
                "<h1>Ссылка недействительна</h1><p>Ссылка истекла, уже использована или была отозвана.</p>",
                status_code=400,
            )
        return _page(
            "AuroraFox — email подтверждён",
            "<h1>Email подтверждён</h1><p>Аккаунт AuroraFox готов к использованию.</p>",
        )

    @router.get("/reset-password", response_class=HTMLResponse)
    def reset_password_page(token: str = Query(min_length=16, max_length=512)) -> HTMLResponse:
        escaped = html.escape(token, quote=True)
        return _page(
            "AuroraFox — новый пароль",
            f"""<h1>Новый пароль</h1>
<form method="post" action="/reset-password" autocomplete="off">
<input type="hidden" name="token" value="{escaped}">
<label>Новый пароль<input type="password" name="new_password" minlength="10" maxlength="1024" autocomplete="new-password" required></label>
<label>Повторите пароль<input type="password" name="confirm_password" minlength="10" maxlength="1024" autocomplete="new-password" required></label>
<button type="submit">Сменить пароль</button>
</form>
<p class="muted">После смены пароля активные сеансы аккаунта будут отозваны.</p>""",
        )

    @router.post("/reset-password", response_class=HTMLResponse)
    async def reset_password_submit(request: Request) -> HTMLResponse:
        fields = await _form_fields(request)
        if fields is None:
            return _page("AuroraFox — ошибка", "<h1>Неверный формат запроса</h1>", status_code=415)
        token = str((fields.get("token") or [""])[0])
        password = str((fields.get("new_password") or [""])[0])
        confirmation = str((fields.get("confirm_password") or [""])[0])
        if not token or len(token) > 512 or password != confirmation:
            return _page(
                "AuroraFox — ошибка",
                "<h1>Не удалось сменить пароль</h1><p>Проверьте введённые данные и повторите попытку.</p>",
                status_code=400,
            )
        try:
            accounts.reset_password(token, password)
        except (AuthenticationError, AccountError):
            return _page(
                "AuroraFox — ошибка",
                "<h1>Не удалось сменить пароль</h1><p>Ссылка недействительна либо пароль не соответствует требованиям.</p>",
                status_code=400,
            )
        return _page(
            "AuroraFox — пароль изменён",
            "<h1>Пароль изменён</h1><p>Теперь можно войти в AuroraFox с новым паролем.</p>",
        )

    return router
