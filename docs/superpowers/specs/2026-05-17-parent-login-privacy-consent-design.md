# Parent login consent: privacy + terms checkbox

- **Date:** 2026-05-17
- **Scope:** Login page + new public Terms-of-Service page
- **Status:** Approved (operator name baked in, defaults accepted on
  governing law / forum / support email / deletion-path wording / checkbox
  copy / `/terms` URL); next step is `writing-plans`

## Goal

Add a single consent checkbox to the parent login page so users cannot start
any login or registration flow without explicitly checking it. The checkbox
links to **two** documents:

1. The existing 隐私协议 at `/privacy` (already in production).
2. A **new** 用户协议 at `/terms` (created as part of this change).

If the user tries to proceed without consent, an inline prompt asks them to
read and agree first.

Because all three native clients (HarmonyOS, iOS, Android) open the same web
shell at `/family/login`, this single login-page change covers every
platform.

## Why now

- Compliance hygiene: the parent flow is the only place where a real account
  is created, so consent must be captured at that gate.
- Parent-only audience (children never see this page), so client-side
  enforcement is sufficient and proportionate.
- The product currently ships a 隐私协议 but no 用户协议 (terms of service);
  app stores and Chinese regulatory practice expect both to be linked from
  the account-creation surface.

## Files touched

| File                                              | Change                       |
| ------------------------------------------------- | ---------------------------- |
| `server/app/templates/parent/login.html`          | Add checkbox + inline error + JS gate; both links |
| `server/app/templates/public/terms.html`          | **New** — 用户协议 page (content drafted below) |
| `server/app/routers/public_pages.py`              | Add `GET /terms` route, mirroring `/privacy` |
| `server/tests/test_public_pages.py`               | Add `/terms` to the parametrized reachability test |

No router, schema, OAuth, or `parent_auth` test changes. No `User` model
change. No new dependencies.

## In scope

1. One checkbox on `login.html`, gating all 5 entry methods on the page:
   - Email OTP `<form method="post">` → `/family/_/auth/request-code`
   - Google OAuth `<a href>` start link
   - Apple OAuth `<a href>` start link
   - WeChat OAuth `<a href>` start link
   - Alipay OAuth `<a href>` start link
2. Checkbox label text: **我已阅读并同意《用户协议》和《隐私协议》**, with
   each title rendered as an underlined link opening in a new tab.
3. Inline rose-colored error prompt when the user clicks any entry method
   while the box is unchecked.
4. New `/terms` page served by `public_pages.py`, mirroring the existing
   `/privacy` and `/support` pattern (public, no auth, App-Store-reachable).
5. Reachability test extended to assert `/terms` returns 200 with the page
   title in the body.

## Out of scope (YAGNI)

- No new `consent_at` / `terms_version` / `privacy_version` field on the
  parent `User` model.
- No server-side `consent=1` validation on `/family/_/auth/request-code` or
  on any OAuth `/start` endpoint.
- No persistence (no localStorage, no cookie). Checkbox is unchecked on
  every visit; user re-affirms consent each session.
- No backend audit log.
- No change to `/family/_/auth/verify-code` (verify page is downstream of
  consent — the user has already opted in by the time they reach it).
- No translation. Page is Chinese only, matching `/privacy` and `/support`.

## User-visible design

### Markup on `login.html` (inserted between intro `<p>` and the email `<form>`)

```html
<div class="mb-4 flex items-start gap-2">
  <input type="checkbox" id="privacy-consent"
         class="mt-1 h-4 w-4 rounded border-slate-300 text-indigo-600
                focus:ring-indigo-500" />
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
   class="hidden mb-3 px-3 py-2 bg-rose-50 border border-rose-200
          text-rose-800 rounded-md text-sm"
   role="alert" aria-live="polite">
  请先阅读并同意《用户协议》和《隐私协议》后再继续登录。
</p>
```

### Behavior (small `<script>` block at the bottom of the `<section>`)

- Selects the email `<form>` and all OAuth start `<a>` elements (anchors
  whose `href` starts with `/v1/oauth/`).
- On `submit` / `click`: if `#privacy-consent` is **unchecked**:
  - `event.preventDefault()`
  - Remove `hidden` from `#privacy-consent-error`
  - `scrollIntoView({ block: 'center' })` + `.focus()` on the checkbox
- If **checked**: the form posts / the link follows normally.
- On `change` of the checkbox: if it becomes checked, re-hide the error.

### Layout / styling

- Position: above the email form (top of section, below the intro paragraph)
  so the requirement is visible before the user picks a method.
- Error style: matches the existing `/verify` error pattern
  (`bg-rose-50 border-rose-200 text-rose-800`) for visual consistency.
- Button state: stays visually enabled (button does **not** gray out) —
  clicking it teaches the user about the consent requirement via the
  inline prompt, rather than a silent disabled state.
- The 隐私协议 link still resolves to the existing page titled “魔法背单词
  隐私政策”; the slight label/page-title difference (协议 vs 政策) is
  standard and matches mainstream Chinese-app practice.

### Router change

```python
# server/app/routers/public_pages.py
@router.get("/terms", response_class=HTMLResponse)
async def get_terms(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "public/terms.html",
        {"user": None},
    )
```

### Test change

```python
# server/tests/test_public_pages.py — parametrize add one row
("/terms", "魔法背单词用户协议"),
```

## Why client-side enforcement only

- The parent flow is operator-controlled UX, not a security boundary.
  Bypassing the checkbox via DevTools / `curl` is technically possible but
  does not yield any benefit to the user, nor does it expose new attack
  surface.
- Server-side enforcement would touch 5 routers + schemas + tests for no
  meaningful compliance gain in the parent-only flow.
- If future regulation requires a logged consent record (e.g., a
  `consent_at` timestamp on `User`), that becomes a separate follow-up spec
  and reuses the same UI.

## Risks / non-risks

- **Non-risk: existing OTP / OAuth tests.** No request shapes change, so
  `server/tests/test_parent_auth*.py` and `test_oauth_*.py` continue to
  pass without modification.
- **Non-risk: store-review reachability of `/privacy` and the new `/terms`.**
  Both use the same `public_pages.py` pattern — no auth, App Store
  reviewers can hit them with a bare URL.
- **Risk: JS disabled.** A user with JavaScript disabled could click email
  OTP without ticking the box. Acceptable: the page already relies on a
  modern browser stack (Tailwind utility classes, OAuth redirects), and the
  three native clients all use full-featured webviews.
- **Risk: legal wording in 用户协议.** The draft below is a sensible default
  grounded in what the app does, but specific clauses (governing law,
  dispute resolution forum, content licensing scope) often vary by
  operator preference. Treat the draft as a starting point for human
  review.

## Verification (covered in the implementation plan)

- `GET /terms` returns 200 and contains "魔法背单词用户协议" — covered by
  the extended `test_public_store_pages_are_reachable_without_login`.
- `GET /privacy` and `GET /support` keep returning 200 (regression).
- Render `/family/login` and confirm checkbox + both links are visible.
- Click 发送验证码 with empty email — browser-native `required` validation
  fires (no change to existing UX).
- Click 发送验证码 with valid email and **unchecked** consent — POST is
  blocked, rose error appears, checkbox is focused. Tick the box and click
  again — POST proceeds.
- For each enabled OAuth provider link: click with **unchecked** consent —
  navigation blocked, error appears. Tick + click — navigation proceeds to
  `/v1/oauth/<provider>/start`.
- Click 《用户协议》 with consent unchecked — opens `/terms` in a new tab;
  the parent login page is untouched.
- Click 《隐私协议》 with consent unchecked — opens `/privacy` in a new
  tab; the parent login page is untouched.
- `uv run pytest` in `server/` finishes with 0 errors / 0 warnings.

---

## 用户协议 content draft

This is the proposed body of `server/app/templates/public/terms.html`,
embedded here for review before any file is created. Tone, structure, and
Tailwind utility classes mirror the existing `public/privacy.html` and
`public/support.html`. Sections are grounded in what the app actually
does today (parent web login via email OTP + 4 OAuth providers, parent
backend for family wordpacks / children / devices / wishlist / redemptions,
HarmonyOS / iOS / Android clients, OpenAI vision for textbook-photo word
extraction, Vercel + MongoDB + email provider for infrastructure, parent
PIN, account-delete grace period).

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
