# Error Envelope Contract

FastAPI validation errors still use FastAPI's default `detail` shape unless a router explicitly raises a structured detail.

Project-specific errors should use:

```json
{
  "detail": {
    "error": {
      "code": "WORD_NOT_FOUND",
      "message": "Word not found"
    }
  }
}
```

Native clients should parse in this order:

1. `detail.error.code` and `detail.error.message`
2. string `detail`
3. FastAPI validation list `detail[]`
4. fallback to HTTP status text

No client should branch only on localized `message` text.
