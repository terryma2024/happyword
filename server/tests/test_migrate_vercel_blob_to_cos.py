from scripts import migrate_vercel_blob_to_cos as migration


def test_is_vercel_blob_url_matches_only_vercel_blob_hosts() -> None:
    assert migration.is_vercel_blob_url(
        "https://happyword.public.blob.vercel-storage.com/illustrations/apple.png"
    )
    assert migration.is_vercel_blob_url("https://blob.vercel-storage.com/lessons/a.jpeg")
    assert not migration.is_vercel_blob_url("https://assets.example.test/lessons/a.jpeg")
    assert not migration.is_vercel_blob_url("stub://lessons/a.jpeg")


def test_cos_path_from_blob_url_preserves_known_asset_directory_and_filename() -> None:
    assert (
        migration.cos_path_from_blob_url(
            "https://happyword.public.blob.vercel-storage.com/illustrations/apple-1234.png"
        )
        == "illustrations/apple-1234.png"
    )
    assert (
        migration.cos_path_from_blob_url(
            "https://happyword.public.blob.vercel-storage.com/preview/preview-urls.json"
        )
        == "migrated-vercel-blob/preview/preview-urls.json"
    )


def test_find_nested_vercel_blob_urls_in_pack_snapshots() -> None:
    doc = {
        "_id": 7,
        "words": [
            {
                "word": "apple",
                "illustrationUrl": "https://happyword.public.blob.vercel-storage.com/illustrations/apple.png",
                "audioUrl": "https://assets.example.test/audio/apple.mp3",
            }
        ],
        "categories": [
            {
                "source_image_url": "https://happyword.public.blob.vercel-storage.com/lessons/page.jpeg"
            }
        ],
    }

    refs = migration.find_url_refs(
        "word_packs",
        doc,
        candidate_paths=("words.*.illustrationUrl", "words.*.audioUrl", "categories.*.source_image_url"),
    )

    assert [(ref.path, ref.url) for ref in refs] == [
        (
            "words.0.illustrationUrl",
            "https://happyword.public.blob.vercel-storage.com/illustrations/apple.png",
        ),
        (
            "categories.0.source_image_url",
            "https://happyword.public.blob.vercel-storage.com/lessons/page.jpeg",
        ),
    ]
