.PHONY: merge-templates create-volumes apply-media-config apply-media-config-dry


merge-templates:
	python scripts/merge_templates.py

create-volumes:
	python scripts/create_volumes.py

# Push stacks/media-server/config/*.json to the running apps (see scripts/apply_media_config.py for env vars)
apply-media-config:
	python scripts/apply_media_config.py

apply-media-config-dry:
	python scripts/apply_media_config.py --dry-run
