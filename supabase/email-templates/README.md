# Supabase email templates (popup)

Paste these into the Supabase dashboard so signup mail matches the app.

## Confirm signup

1. Dashboard → **Authentication** → **Email Templates** → **Confirm signup**
2. Subject: `Confirm your popup campus email`
3. Paste the HTML from `confirm-signup.html`
4. Keep the `{{ .ConfirmationURL }}` link — Supabase fills it in

## Redirect URL (required)

Authentication → **URL Configuration** → **Redirect URLs** must include:

```
popup://auth-callback
```

Also keep your hosted bridge if you use one, e.g. `https://YOUR-HOST/auth/verified.html`.

Site URL can stay as the bridge page; the email button uses `ConfirmationURL`, which respects the `emailRedirectTo` the app sends (`popup://auth-callback`).

## Confirm email must be ON

Authentication → **Providers** → **Email** → **Confirm email** = enabled.

If this is off, students get a session without clicking the email and the app will block them with an error.
