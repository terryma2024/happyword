"""One-shot CLI to create or reset an admin user. Idempotent on username.

Usage:
    cd server
    uv run python scripts/create_admin_user.py <username> <password>

If the user exists, the password is RESET (this is intentional — it's a recovery tool).
"""

import asyncio
import sys
from datetime import UTC, datetime

from beanie import init_beanie
from motor.motor_asyncio import AsyncIOMotorClient

from app.config import get_settings
from app.models.user import User, UserRole
from app.services.auth_service import hash_password


async def main(username: str, password: str) -> None:
    settings = get_settings()
    client: AsyncIOMotorClient = AsyncIOMotorClient(settings.mongo_uri)
    try:
        await init_beanie(
            database=client[settings.mongo_db_name],
            document_models=[User],
        )
        existing = await User.find_one(User.username == username)
        if existing is None:
            await User(
                username=username,
                password_hash=hash_password(password),
                role=UserRole.ADMIN,
                created_at=datetime.now(tz=UTC),
            ).insert()
            print(f"Created admin user '{username}'.")
        else:
            existing.password_hash = hash_password(password)
            await existing.save()
            print(f"Reset password for existing admin user '{username}'.")
    finally:
        client.close()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.stderr.write("Usage: create_admin_user.py <username> <password>\n")
        sys.exit(2)
    asyncio.run(main(sys.argv[1], sys.argv[2]))
