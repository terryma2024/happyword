from app.services.auth_service import hash_password, verify_password


def test_hash_password_returns_distinct_hash_for_same_input() -> None:
    h1 = hash_password("s3cret")
    h2 = hash_password("s3cret")
    assert h1 != h2  # bcrypt salts differ
    assert verify_password("s3cret", h1)
    assert verify_password("s3cret", h2)


def test_verify_password_rejects_wrong() -> None:
    h = hash_password("right")
    assert not verify_password("wrong", h)
