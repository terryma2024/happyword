# Parent login privacy + terms consent — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Block all 5 entry methods on `/family/login` (email OTP + 4 OAuth providers) behind a single consent checkbox that links to a new 用户协议 page at `/terms` plus the existing 隐私协议 at `/privacy`; show an inline rose-colored prompt when the user tries to proceed without consent.

**Architecture:** Pure server-rendered template + client-side JS gate. Two changes to one Jinja template (`server/app/templates/parent/login.html`); one new public page (`server/app/templates/public/terms.html`) wired through the existing `server/app/routers/public_pages.py`. No router/schema/OAuth-flow changes, no database changes, no new dependencies. Two TDD-style HTTP content-presence tests lock the consent UI in place against future regressions.

**Tech Stack:** FastAPI + Jinja2 + Tailwind utility classes (already on every page via `_base.html`), vanilla JS (no framework), pytest + httpx for tests.

**Spec:** `docs/superpowers/specs/2026-05-17-parent-login-privacy-consent-design.md`

---

## File Structure

| File | Status | Responsibility |
| --- | --- | --- |
| `server/app/templates/public/terms.html` | **new** | 用户协议 page body, 13 sections, Chinese, operator: 个人开发者 马天一. Static. |
| `server/app/routers/public_pages.py` | modify | Add `GET /terms` mirroring `GET /privacy` (5 lines). |
| `server/app/templates/parent/login.html` | modify | Insert consent checkbox + inline error `<p>` above email form; add small `<script>` at end of `<section>` to gate form submit + OAuth link clicks. |
| `server/tests/test_public_pages.py` | modify | Extend parametrize with `("/terms", "魔法背单词用户协议")` (1 line). |
| `server/tests/test_parent_login_page.py` | **new** | `GET /family/login` content-presence test: checkbox id, both links, error text, script marker. |

No other files. No model migrations. `parent_auth`, OAuth, OTP, OAuth-handoff tests all unchanged.

---

## Task 1: Create `/terms` page (TDD)

**Files:**
- Modify: `server/tests/test_public_pages.py`
- Create: `server/app/templates/public/terms.html`
- Modify: `server/app/routers/public_pages.py`

- [ ] **Step 1.1: Extend the parametrize with the failing `/terms` row**

Edit `server/tests/test_public_pages.py`:

```python
from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("path", "expected"),
    [
        ("/privacy", "魔法背单词隐私政策"),
        ("/terms", "魔法背单词用户协议"),
        ("/support", "魔法背单词支持"),
    ],
)
async def test_public_store_pages_are_reachable_without_login(
    client: AsyncClient, path: str, expected: str
) -> None:
    response = await client.get(path)

    assert response.status_code == 200
    assert expected in response.text
    assert "退出登录" not in response.text
```

- [ ] **Step 1.2: Run the test and confirm the `/terms` row fails**

```bash
cd server && uv run pytest tests/test_public_pages.py -v
```

Expected: the `[/privacy-...]` and `[/support-...]` rows pass; the `[/terms-...]` row fails with `assert 200 == 404` (route not yet defined).

- [ ] **Step 1.3: Create the `/terms` template**

Create `server/app/templates/public/terms.html` with the full ToS body from the approved spec. Use Tailwind utility classes that match `public/privacy.html` exactly:

```html
{% extends "_base.html" %}
{% block title %}用户协议{% endblock %}
{% block content %}
<article class="bg-white border border-slate-200 rounded-lg shadow-sm p-6 space-y-6">
  <header class="space-y-2">
    <p class="text-sm text-slate-500">最后更新：2026-05-17</p>
    <h1 class="text-2xl font-semibold text-slate-900">魔法背单词用户协议</h1>
    <p class="text-sm text-slate-700">
      本协议是您（"家长用户"或"您"）与魔法背单词运营方（个人开发者 马天一，
      以下简称"我们"）之间的有效合同，约定您注册、使用魔法背单词应用与家长后台时的
      权利义务。请您在使用前认真阅读，勾选"我已阅读并同意"并完成登录即视为接受
      本协议全部内容。
    </p>
  </header>

  <section class="space-y-2">
    <h2 class="text-lg font-semibold text-slate-900">一、服务说明</h2>
    <p class="text-sm text-slate-700">
      魔法背单词是一款面向儿童英语练习与家长词库管理的应用，包含 HarmonyOS、iOS、
      Android 客户端以及家长 Web 后台。我们通过这些服务为您提供：单词练习与同步、
      家长词库导入与维护、教材图片识别为可复核的词条草稿、孩子档案与设备绑定管理、
      愿望清单与兑换、家长账号与数据管理等功能。
    </p>
  </section>

  <section class="space-y-2">
    <h2 class="text-lg font-semibold text-slate-900">二、账号注册与登录</h2>
    <ul class="list-disc pl-5 text-sm text-slate-700 space-y-1">
      <li>家长账号通过邮箱一次性验证码、Google、Apple、微信或支付宝任一方式登录与注册，首次登录即创建账号。</li>
      <li>您应保证注册信息真实有效，妥善保管登录邮箱、第三方账号与家长 PIN，账号下的所有行为由账号持有人负责。</li>
      <li>账号不得转让、出租或共享给未取得监护人同意的第三方使用。</li>
    </ul>
  </section>

  <section class="space-y-2">
    <h2 class="text-lg font-semibold text-slate-900">三、儿童与家长责任</h2>
    <ul class="list-disc pl-5 text-sm text-slate-700 space-y-1">
      <li>本服务为儿童学习设计，孩子档案、设备绑定与练习均由家长账号创建和管理。</li>
      <li>家长应在孩子使用本服务时给予适度陪伴和监督，确保使用时长与内容适合孩子年龄。</li>
      <li>家长 PIN 用于保护设备解绑、兑换审批等敏感操作，请勿告知孩子或他人。</li>
    </ul>
  </section>

  <section class="space-y-2">
    <h2 class="text-lg font-semibold text-slate-900">四、用户行为规范</h2>
    <p class="text-sm text-slate-700">您承诺不会利用本服务从事下列行为：</p>
    <ul class="list-disc pl-5 text-sm text-slate-700 space-y-1">
      <li>上传、传播违反法律法规、公共秩序或善良风俗的内容；</li>
      <li>侵犯他人知识产权、隐私权、名誉权或其他合法权益；</li>
      <li>对服务进行反向工程、批量爬取、自动化脚本调用、滥用接口或绕过安全机制；</li>
      <li>提交虚假或欺骗性的兑换、愿望或反馈请求；</li>
      <li>以任何方式干扰、攻击或破坏本服务以及其他用户的正常使用。</li>
    </ul>
  </section>

  <section class="space-y-2">
    <h2 class="text-lg font-semibold text-slate-900">五、用户内容</h2>
    <ul class="list-disc pl-5 text-sm text-slate-700 space-y-1">
      <li>您在使用过程中可能上传教材图片、自建词包内容、愿望清单与反馈内容（以下统称"用户内容"）。</li>
      <li>您应保证对上传的用户内容拥有合法权利，或已经取得相关权利人的合法授权。</li>
      <li>您授予我们为提供和优化本服务所必须的范围内使用、复制、处理、传输和存储您上传的用户内容的非独占许可。</li>
      <li>对违反法律或本协议的用户内容，我们有权下架、删除或拒绝处理。</li>
    </ul>
  </section>

  <section class="space-y-2">
    <h2 class="text-lg font-semibold text-slate-900">六、知识产权</h2>
    <p class="text-sm text-slate-700">
      除用户内容外，本服务的客户端软件、Web 后台、界面设计、内置词库、图标、动画、文字、
      商标、Logo 等知识产权归我们或相应权利人所有。未经授权，您不得复制、修改、发布、出售
      或以其他方式商业化使用本服务的任何内容。
    </p>
  </section>

  <section class="space-y-2">
    <h2 class="text-lg font-semibold text-slate-900">七、第三方服务</h2>
    <p class="text-sm text-slate-700">
      本服务可能集成 Google、Apple、微信、支付宝等第三方登录，以及 Vercel 托管与对象存储、
      MongoDB 数据库、邮件服务、OpenAI 视觉能力等第三方技术。使用相应功能时，您还需遵守对应
      第三方的用户协议与服务条款。第三方服务的可用性、稳定性和服务范围由第三方决定，
      我们不对其单独承担责任。
    </p>
  </section>

  <section class="space-y-2">
    <h2 class="text-lg font-semibold text-slate-900">八、服务变更、暂停与终止</h2>
    <ul class="list-disc pl-5 text-sm text-slate-700 space-y-1">
      <li>我们可能根据产品发展、合规要求或技术原因，对服务进行更新、调整、暂停或终止。</li>
      <li>如发生重大变更，我们会通过应用内通知、邮件或官网公告方式提前告知。</li>
      <li>如您严重违反本协议，我们有权暂停或终止您对全部或部分服务的使用，并保留追究法律责任的权利。</li>
    </ul>
  </section>

  <section class="space-y-2">
    <h2 class="text-lg font-semibold text-slate-900">九、账号注销</h2>
    <p class="text-sm text-slate-700">
      您可以在客户端"游戏配置 → 孩子档案 → 账号与数据管理"页面发起账号删除。删除请求设有
      宽限期，宽限期内您可以撤销；宽限期结束后，相关账号和数据将按隐私政策约定处理。详见
      <a class="text-sky-600 hover:underline" href="/privacy">隐私政策</a>。
    </p>
  </section>

  <section class="space-y-2">
    <h2 class="text-lg font-semibold text-slate-900">十、免责声明</h2>
    <ul class="list-disc pl-5 text-sm text-slate-700 space-y-1">
      <li>本服务按"现状"提供，我们在法律允许的最大范围内不对不间断、无错误或满足特定目的作出明示或默示保证。</li>
      <li>因不可抗力、网络异常、第三方服务故障、设备或系统问题导致的服务中断或数据延迟，我们在尽合理努力后不承担责任。</li>
      <li>儿童的学习效果取决于多种因素，本服务不对具体学习成绩或考试结果作出承诺。</li>
    </ul>
  </section>

  <section class="space-y-2">
    <h2 class="text-lg font-semibold text-slate-900">十一、协议变更</h2>
    <p class="text-sm text-slate-700">
      我们可能根据法律法规或业务发展不时修订本协议。修订后的协议将在本页面发布并更新"最后更新"
      日期。如有重大调整，会通过显著方式提示您。继续使用本服务即视为接受变更后的协议；
      如不同意变更，请停止使用并按上述方式注销账号。
    </p>
  </section>

  <section class="space-y-2">
    <h2 class="text-lg font-semibold text-slate-900">十二、法律适用与争议解决</h2>
    <p class="text-sm text-slate-700">
      本协议的订立、生效、解释和争议解决均适用中华人民共和国大陆地区法律（不含冲突法）。
      因本协议产生的任何争议，双方应首先友好协商解决；协商不成的，任何一方均可向我们运营方
      住所地有管辖权的人民法院提起诉讼。
    </p>
  </section>

  <section class="space-y-2">
    <h2 class="text-lg font-semibold text-slate-900">十三、联系我们</h2>
    <p class="text-sm text-slate-700">
      如对本协议有任何疑问，请通过 <a class="text-sky-600 hover:underline" href="/support">支持页面</a>
      或邮箱 <a class="text-sky-600 hover:underline" href="mailto:support@happyword.cool">support@happyword.cool</a>
      与我们联系。
    </p>
  </section>
</article>
{% endblock %}
```

- [ ] **Step 1.4: Add the `GET /terms` route**

Edit `server/app/routers/public_pages.py` — insert a new handler between `get_privacy` and `get_support`:

```python
"""Public legal/support pages for store review.

These pages must stay reachable without a parent session because App Store
Connect and reviewers validate the URLs before logging into the product.
"""

from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

router = APIRouter(tags=["public-pages"])
templates = Jinja2Templates(directory="app/templates")


@router.get("/privacy", response_class=HTMLResponse)
async def get_privacy(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "public/privacy.html",
        {"user": None},
    )


@router.get("/terms", response_class=HTMLResponse)
async def get_terms(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "public/terms.html",
        {"user": None},
    )


@router.get("/support", response_class=HTMLResponse)
async def get_support(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "public/support.html",
        {"user": None},
    )


__all__ = ["router"]
```

- [ ] **Step 1.5: Run the parametrized test and confirm all rows pass**

```bash
cd server && uv run pytest tests/test_public_pages.py -v
```

Expected: 3 passed (`/privacy`, `/terms`, `/support`), 0 failed.

- [ ] **Step 1.6: Full regression — pytest must be 0 errors / 0 warnings**

```bash
cd server && uv run pytest
```

Expected: all green; **zero warnings** (project enforces `filterwarnings = ["error", ...]`). If a new warning appears, do not whitelist it — fix the root cause.

- [ ] **Step 1.7: Lint touched files**

```bash
cd server && uv run ruff check app/routers/public_pages.py app/templates/public/terms.html tests/test_public_pages.py
```

(Ruff will skip the HTML file silently — that's expected; we just want it to pass on the Python files.)

Expected: no new findings on the files we just touched. Pre-existing findings elsewhere are out of scope (per AGENTS.md: "only fix the ones in files you actually touch").

- [ ] **Step 1.8: Commit Task 1**

```bash
cd /Users/bytedance/.cursor/worktrees/happyword/yjcf
git add server/app/templates/public/terms.html \
        server/app/routers/public_pages.py \
        server/tests/test_public_pages.py
git commit -m "feat(server): add public /terms 用户协议 page

Mirror /privacy and /support pattern: static Jinja template under
public/, route in public_pages.py, reachability covered by the existing
parametrized test_public_pages.py.

Operator: 个人开发者 马天一. PRC governing law, operator-domicile court.
13 sections grounded in current app features (parent OTP + 4 OAuth
providers, family wordpacks/devices/wishlist, OpenAI textbook OCR).

Refs docs/superpowers/specs/2026-05-17-parent-login-privacy-consent-design.md"
```

---

## Task 2: Consent checkbox + JS gate on `/family/login` (TDD)

**Files:**
- Create: `server/tests/test_parent_login_page.py`
- Modify: `server/app/templates/parent/login.html`

- [ ] **Step 2.1: Write the failing content-presence test**

Create `server/tests/test_parent_login_page.py` (new file). It hits `GET /family/login` and asserts every required UI element is present in the rendered HTML — the checkbox id, both legal-doc links, the error text, and a marker proving the JS gate was injected.

```python
"""Content-presence regression for the parent login page consent UI.

Locks the privacy + terms consent checkbox in place against future
template refactors. Does not depend on any OAuth env var: the consent
markup is unconditional, so the test passes with all OAuth providers
disabled (the default in conftest.py).
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_login_page_renders_privacy_consent_checkbox(
    client: AsyncClient,
) -> None:
    response = await client.get("/family/login")

    assert response.status_code == 200
    body = response.text

    # Checkbox element (id used by the JS gate and the label `for=`).
    assert 'id="privacy-consent"' in body
    assert 'type="checkbox"' in body

    # Both legal docs are linked, opening in a new tab.
    assert 'href="/terms"' in body
    assert 'href="/privacy"' in body
    assert 'target="_blank"' in body
    assert 'rel="noopener noreferrer"' in body

    # Label copy uses the approved Chinese wording with 《》 punctuation.
    assert "我已阅读并同意" in body
    assert "《用户协议》" in body
    assert "《隐私协议》" in body

    # Inline error <p> is present (initially hidden) with the required
    # ARIA live attribute and the approved prompt text.
    assert 'id="privacy-consent-error"' in body
    assert 'role="alert"' in body
    assert 'aria-live="polite"' in body
    assert "请先阅读并同意《用户协议》和《隐私协议》后再继续登录。" in body

    # JS gate marker: the script must reference the checkbox id so we know
    # the interception logic is wired, not just dead markup.
    assert "privacy-consent" in body
    assert "preventDefault" in body
    # OAuth links are targeted by selector even when no provider is
    # enabled in this env, so the prefix string must appear in the script.
    assert "/v1/oauth/" in body
```

- [ ] **Step 2.2: Run the test and confirm it fails**

```bash
cd server && uv run pytest tests/test_parent_login_page.py -v
```

Expected: 1 failed — first failing assertion will be `assert 'id="privacy-consent"' in body` (the current login.html has no consent markup).

- [ ] **Step 2.3: Add the consent markup + JS gate to `login.html`**

Replace the contents of `server/app/templates/parent/login.html` with:

```html
{% extends "_base.html" %}
{% block title %}登录{% endblock %}
{% block content %}
<section class="bg-white rounded-lg shadow-sm border border-slate-200 p-6 max-w-md mx-auto">
  <h1 class="text-2xl font-semibold text-slate-900 mb-2">家长登录</h1>
  <p class="text-sm text-slate-600 mb-6">输入您的邮箱地址，我们会发送一个 6 位验证码到您的邮箱。</p>

  <div class="mb-4 flex items-start gap-2">
    <input type="checkbox" id="privacy-consent"
           class="mt-1 h-4 w-4 rounded border-slate-300 text-indigo-600 focus:ring-indigo-500" />
    <label for="privacy-consent" class="text-sm text-slate-700">
      我已阅读并同意
      <a href="/terms" target="_blank" rel="noopener noreferrer"
         class="text-indigo-600 underline">《用户协议》</a>
      和
      <a href="/privacy" target="_blank" rel="noopener noreferrer"
         class="text-indigo-600 underline">《隐私协议》</a>
    </label>
  </div>
  <p id="privacy-consent-error"
     class="hidden mb-3 px-3 py-2 bg-rose-50 border border-rose-200 text-rose-800 rounded-md text-sm"
     role="alert" aria-live="polite">
    请先阅读并同意《用户协议》和《隐私协议》后再继续登录。
  </p>

  <form method="post" action="/family/_/auth/request-code" class="space-y-4" id="parent-otp-form">
    <label class="block">
      <span class="block text-sm font-medium text-slate-700 mb-1">邮箱地址</span>
      <input type="email" name="email" required autocomplete="email"
             class="w-full px-3 py-2 border border-slate-300 rounded-md focus:outline-none focus:ring-2 focus:ring-indigo-500"
             placeholder="parent@example.com" />
    </label>
    <button type="submit"
            class="w-full bg-indigo-600 text-white py-2 rounded-md hover:bg-indigo-700 transition">
      发送验证码
    </button>
  </form>
  <p class="text-xs text-slate-400 mt-4">
    如果未在收件箱看到邮件，请检查垃圾邮件文件夹。
  </p>
  {% if google_oauth_enabled and google_start_url %}
  <p class="text-center text-sm text-slate-400 my-6">或</p>
  <a href="{{ google_start_url }}"
     class="w-full inline-flex justify-center items-center gap-3 border border-slate-300 rounded-md py-2.5 px-3 text-sm font-medium text-slate-800 bg-white hover:bg-slate-50 transition">
    <svg class="h-5 w-5 shrink-0" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
      <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
      <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
      <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
    </svg>
    Continue with Google
  </a>
  {% endif %}
  {% if apple_oauth_enabled and apple_start_url %}
  <a href="{{ apple_start_url }}"
     class="w-full inline-flex justify-center items-center gap-3 border border-slate-300 rounded-md py-2.5 px-3 text-sm font-medium text-slate-800 bg-white hover:bg-slate-50 transition mt-3">
    <svg class="h-5 w-5 shrink-0" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="currentColor" d="M17.05 20.28c-.98.95-2.05 1.88-3.51 1.9-1.48.02-1.95-.87-3.63-.87-1.68 0-2.2.85-3.64.89-1.46.04-2.57-1.47-3.55-2.42C2.44 16.2 1.03 12.45 2.94 9.11c1.36-2.37 3.94-3.86 6.7-3.9 1.56-.03 3.03 1.04 3.98 1.04.95 0 2.75-1.28 4.65-1.09.79.03 3.01.32 4.43 2.41-3.8 2.07-3.18 7.46.76 9.11-.65 1.9-1.55 3.77-2.51 5.7zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z"/>
    </svg>
    Continue with Apple
  </a>
  {% endif %}
  {% if wechat_oauth_enabled and wechat_start_url %}
  <a href="{{ wechat_start_url }}"
     class="w-full inline-flex justify-center items-center gap-3 border border-slate-300 rounded-md py-2.5 px-3 text-sm font-medium text-slate-800 bg-white hover:bg-slate-50 transition mt-3">
    <span class="h-5 w-5 shrink-0 rounded-full bg-emerald-500 text-white text-xs font-bold inline-flex items-center justify-center">微</span>
    Continue with WeChat
  </a>
  {% endif %}
  {% if alipay_oauth_enabled and alipay_start_url %}
  <a href="{{ alipay_start_url }}"
     class="w-full inline-flex justify-center items-center gap-3 border border-slate-300 rounded-md py-2.5 px-3 text-sm font-medium text-slate-800 bg-white hover:bg-slate-50 transition mt-3">
    <span class="h-5 w-5 shrink-0 rounded-full bg-sky-500 text-white text-xs font-bold inline-flex items-center justify-center">支</span>
    Continue with Alipay
  </a>
  {% endif %}
  {% if oauth_error_message %}
  <p class="text-sm text-red-600 mt-4" role="alert">{{ oauth_error_message }}</p>
  {% endif %}

  <script>
    (function () {
      var consent = document.getElementById('privacy-consent');
      var errorEl = document.getElementById('privacy-consent-error');
      if (!consent || !errorEl) return;

      function showError() {
        errorEl.classList.remove('hidden');
        consent.scrollIntoView({ block: 'center', behavior: 'smooth' });
        consent.focus();
      }

      function hideError() {
        errorEl.classList.add('hidden');
      }

      consent.addEventListener('change', function () {
        if (consent.checked) hideError();
      });

      var form = document.getElementById('parent-otp-form');
      if (form) {
        form.addEventListener('submit', function (event) {
          if (!consent.checked) {
            event.preventDefault();
            showError();
          }
        });
      }

      var oauthLinks = document.querySelectorAll('a[href^="/v1/oauth/"]');
      oauthLinks.forEach(function (link) {
        link.addEventListener('click', function (event) {
          if (!consent.checked) {
            event.preventDefault();
            showError();
          }
        });
      });
    })();
  </script>
</section>
{% endblock %}
```

Key edits versus the original template:

1. New `<div>` + `<p id="privacy-consent-error">` block inserted between the intro `<p>` and the email `<form>`.
2. Added `id="parent-otp-form"` to the existing `<form>` so the JS can target it deterministically (no behavior change for the form itself).
3. Added a `<script>` block immediately before `</section>` that wires the change/submit/click listeners. IIFE keeps the global namespace clean.

- [ ] **Step 2.4: Run the new test and confirm it passes**

```bash
cd server && uv run pytest tests/test_parent_login_page.py -v
```

Expected: 1 passed.

- [ ] **Step 2.5: Full regression — pytest must be 0 errors / 0 warnings**

```bash
cd server && uv run pytest
```

Expected: all green, zero warnings. In particular `test_parent_otp.py`, `test_oauth_google_routes.py`, `test_oauth_apple_routes.py`, `test_oauth_return_origin.py`, `test_account_deletion.py`, `test_parent_packs_pages.py`, and `tests/e2e/test_root_redirect_e2e.py` continue to pass unchanged — none of them inspect login HTML body, only status codes / redirect locations.

- [ ] **Step 2.6: Lint the touched Python file**

```bash
cd server && uv run ruff check tests/test_parent_login_page.py
```

Expected: no findings.

- [ ] **Step 2.7: Manual smoke test against a live uvicorn**

Start a dev server in one terminal:

```bash
cd server && uv run uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

(This requires `server/.env.local` with `MONGODB_URI`, `MONGO_DB_NAME`, `JWT_SECRET`, `ADMIN_BOOTSTRAP_USER`, `ADMIN_BOOTSTRAP_PASS` set per AGENTS.md "Running the server locally" — plus a running `mongod` on `127.0.0.1:27017`.)

Then in a browser, hit `http://127.0.0.1:8000/family/login` and verify:

| # | Action | Expected |
| - | --- | --- |
| 1 | Page loads | Checkbox visible at top, both link labels render as `《用户协议》` and `《隐私协议》` and are underlined indigo |
| 2 | Click `《用户协议》` | Opens `/terms` in a new tab; original tab unchanged |
| 3 | Click `《隐私协议》` | Opens `/privacy` in a new tab; original tab unchanged |
| 4 | Type valid email + click 发送验证码 with checkbox **unchecked** | Form submit blocked, rose error appears, checkbox is focused/scrolled into view |
| 5 | Check the box → error hides → click 发送验证码 again | Form POST proceeds; you should land on `/family/_/auth/verify-code` (or the verify HTML page) |
| 6 | If any OAuth provider is enabled in `.env.local`, click that provider button with checkbox **unchecked** | Navigation blocked, rose error reappears |
| 7 | Check the box → click the OAuth provider | Navigation proceeds to `/v1/oauth/<provider>/start` |
| 8 | Reload the page | Checkbox is unchecked again (no persistence — by design) |

If any step fails, stop and diagnose before committing.

- [ ] **Step 2.8: Commit Task 2**

```bash
cd /Users/bytedance/.cursor/worktrees/happyword/yjcf
git add server/app/templates/parent/login.html \
        server/tests/test_parent_login_page.py
git commit -m "feat(server): gate /family/login behind privacy + terms consent

Adds a single checkbox above the email form linking to /terms and
/privacy in new tabs. Vanilla JS IIFE intercepts both the email OTP
form submit and all /v1/oauth/* anchor clicks; when the checkbox is
unchecked, the action is preventDefault'd and a rose-colored inline
error (role=alert, aria-live=polite) prompts the user to read and
agree. Checking the box hides the error.

No server-side enforcement, no persistence, no audit log — parent-only
flow, UX gate sufficient per design.

Content-presence test in test_parent_login_page.py locks the consent
UI in against future template refactors; runs without any OAuth env
var because the consent markup is unconditional.

Refs docs/superpowers/specs/2026-05-17-parent-login-privacy-consent-design.md"
```

---

## Task 3: Final verification + branch readiness

**Files:** none modified.

- [ ] **Step 3.1: Final full pytest sweep**

```bash
cd server && uv run pytest
```

Expected: every existing suite green, 2 new tests counted in the passed total (`test_public_pages.py::...[/terms-...]` and `test_parent_login_page.py::test_login_page_renders_privacy_consent_checkbox`), zero warnings.

- [ ] **Step 3.2: Lint sweep on changed files**

```bash
cd server && uv run ruff check \
  app/routers/public_pages.py \
  tests/test_public_pages.py \
  tests/test_parent_login_page.py
```

Expected: no findings.

- [ ] **Step 3.3: Type-check on changed files**

```bash
cd server && uv run mypy \
  app/routers/public_pages.py \
  tests/test_public_pages.py \
  tests/test_parent_login_page.py
```

Expected: no new findings. (Pre-existing repo-wide mypy findings are out of scope per AGENTS.md.)

- [ ] **Step 3.4: Confirm branch + commit log**

```bash
cd /Users/bytedance/.cursor/worktrees/happyword/yjcf
git log --oneline -5
git branch --show-current
```

Expected: branch is `feat/server-parent-login-privacy-consent`; top three commits are the spec, Task 1 (`/terms` page), Task 2 (consent gate).

- [ ] **Step 3.5: Hand back to user (no auto-push, no auto-PR)**

Per AGENTS.md: do not push or open a PR unless explicitly requested. Report:

- Branch name
- Commit SHAs (spec / Task 1 / Task 2)
- Confirmation that `uv run pytest` finished with 0 errors / 0 warnings
- Note on what is **not** done: server-side consent enforcement, audit log, persistence (all explicitly out of scope per spec)
- Reminder that the live preview deployment will rebuild automatically on Vercel once the branch is pushed (operator's decision when to push)

---

## Self-review

**1. Spec coverage:** Walked through every section of the spec.

- 5 entry methods gated → Task 2 Step 2.3 (`form submit` listener + `a[href^="/v1/oauth/"]` selector covers Google/Apple/WeChat/Alipay).
- Checkbox label "我已阅读并同意《用户协议》和《隐私协议》" → Task 2 Step 2.3 markup + Task 2 Step 2.1 test assertion.
- Inline error prompt → Task 2 Step 2.3 markup + Task 2 Step 2.1 test assertion.
- New `/terms` page → Task 1 Steps 1.3–1.4 + Task 1 Step 1.1 test.
- Reachability regression on `/terms` → Task 1 Step 1.1 parametrize row.
- "Files touched" table in spec matches Task 1+2 files exactly.
- "No persistence" → Task 2 Step 2.3 script has no `localStorage`/`cookie` calls; Step 2.7 row 8 manually verifies.
- "Button stays enabled" → markup keeps original button classes unchanged; JS only `preventDefault`s on click.
- "Operator: 个人开发者 马天一" → Task 1 Step 1.3 header paragraph baked in.
- Verification list → mapped 1:1 to Task 2 Step 2.7 manual table + Task 3 pytest sweep.

No spec section without a task.

**2. Placeholder scan:** No "TBD", "TODO", "implement later", "Add appropriate error handling", or "Similar to Task N" patterns. Every step shows the full code or command.

**3. Type / name consistency:**

- `id="privacy-consent"` appears in markup (Task 2 Step 2.3), test assertion (Step 2.1), and `document.getElementById('privacy-consent')` (Step 2.3 script) — all match.
- `id="privacy-consent-error"` matches across markup, test, and script.
- `id="parent-otp-form"` matches between markup and `document.getElementById('parent-otp-form')` in script.
- `a[href^="/v1/oauth/"]` selector matches both the OAuth URL prefix used by `build_google_start_url` / `build_apple_start_url` / `build_wechat_start_url` / `build_alipay_start_url` (verified during brainstorming) and the test assertion `"/v1/oauth/" in body`.
- Test parametrize string `"魔法背单词用户协议"` matches the `<h1>` text in `terms.html`.
- Commit messages reference the same spec path `docs/superpowers/specs/2026-05-17-parent-login-privacy-consent-design.md` consistently.

No mismatches.
