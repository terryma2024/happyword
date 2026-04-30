"""Admin Category CRUD endpoints (V0.5.5)."""

from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status

from app.deps import current_admin_user
from app.models.category import Category
from app.models.user import User
from app.models.word import Word
from app.schemas.admin_category import (
    CategoryCreateIn,
    CategoryListOut,
    CategoryOut,
    CategoryUpdateIn,
)

router = APIRouter(prefix="/api/v1/admin/categories", tags=["admin-categories"])


def _err(http_status: int, code: str, message: str) -> HTTPException:
    return HTTPException(
        status_code=http_status, detail={"error": {"code": code, "message": message}}
    )


def _to_out(c: Category) -> CategoryOut:
    return CategoryOut(
        id=c.id,
        label_en=c.label_en,
        label_zh=c.label_zh,
        story_zh=c.story_zh,
        source_image_url=c.source_image_url,
        source=c.source,
        created_at=c.created_at,
        updated_at=c.updated_at,
    )


@router.get("", response_model=CategoryListOut)
async def list_categories(_admin: User = Depends(current_admin_user)) -> CategoryListOut:
    rows = await Category.find_all().sort("+id").to_list()
    return CategoryListOut(items=[_to_out(c) for c in rows], total=len(rows))


@router.get("/{category_id}", response_model=CategoryOut)
async def get_category(category_id: str, _admin: User = Depends(current_admin_user)) -> CategoryOut:
    c = await Category.find_one(Category.id == category_id)
    if c is None:
        raise _err(
            status.HTTP_404_NOT_FOUND,
            "CATEGORY_NOT_FOUND",
            f"No category with id={category_id!r}",
        )
    return _to_out(c)


@router.post("", response_model=CategoryOut, status_code=status.HTTP_201_CREATED)
async def create_category(
    body: CategoryCreateIn, _admin: User = Depends(current_admin_user)
) -> CategoryOut:
    existing = await Category.find_one(Category.id == body.id)
    if existing is not None:
        raise _err(
            status.HTTP_409_CONFLICT,
            "DUPLICATE_ID",
            f"Category {body.id!r} already exists",
        )
    now = datetime.now(tz=UTC)
    c = Category(
        id=body.id,
        label_en=body.label_en,
        label_zh=body.label_zh,
        story_zh=body.story_zh,
        source="manual",
        created_at=now,
        updated_at=now,
    )
    await c.insert()
    return _to_out(c)


@router.put("/{category_id}", response_model=CategoryOut)
async def update_category(
    category_id: str,
    body: CategoryUpdateIn,
    _admin: User = Depends(current_admin_user),
) -> CategoryOut:
    c = await Category.find_one(Category.id == category_id)
    if c is None:
        raise _err(
            status.HTTP_404_NOT_FOUND,
            "CATEGORY_NOT_FOUND",
            f"No category with id={category_id!r}",
        )
    patch = body.model_dump(exclude_unset=True, by_alias=False)
    for k, v in patch.items():
        setattr(c, k, v)
    c.updated_at = datetime.now(tz=UTC)
    await c.save()
    return _to_out(c)


@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_category(category_id: str, _admin: User = Depends(current_admin_user)) -> None:
    c = await Category.find_one(Category.id == category_id)
    if c is None:
        raise _err(
            status.HTTP_404_NOT_FOUND,
            "CATEGORY_NOT_FOUND",
            f"No category with id={category_id!r}",
        )
    in_use_count = await Word.find({"category": category_id, "deleted_at": None}).count()
    if in_use_count > 0:
        raise _err(
            status.HTTP_409_CONFLICT,
            "CATEGORY_IN_USE",
            f"Category {category_id!r} is referenced by {in_use_count} active word(s)",
        )
    await c.delete()
